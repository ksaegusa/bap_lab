# Chaos Engineering Lab

## Overview

このディレクトリでは、Containerlab上のネットワーク環境に対して障害を注入し、BFD / BGP / SNMP Trap / Zabbix がどのように反応するかを検証する。

目的は、単純な障害再現だけでなく、以下を一連のChaos Experimentとして扱うこと。

- 正常状態の確認
- 障害注入
- 障害検知
- Routing Protocolの収束確認
- Zabbixによる障害検知
- Rollback
- 復旧確認

---

## Architecture

```text
Chaos Toolkit
    |
    | Experiment
    v
Containerlab / Pumba
    |
    | Fault Injection
    v
Containerlab Network
    |
    +--> BFD
    |
    +--> BGP
    |
    +--> SNMP Trap
            |
            v
         Zabbix
```

役割は以下。

```text
Containerlab
  ネットワークトポロジの構築

Chaos Toolkit
  Chaos Experimentの定義・実行・結果記録

Containerlab netem
  ネットワーク障害注入

Pumba
  将来的な周期障害・ランダム障害・Container障害注入

Zabbix
  外部からの障害・復旧監視
```

---

## Directory Structure

```text
chaos/
├── .venv/
├── requirements.txt
├── README.md
├── experiments/
│   └── r2-r4-link-loss.json
└── journals/
```

### `.venv`

Chaos Toolkit実行用のPython Virtual Environment。

### `requirements.txt`

Chaos Toolkitなど、このラボで利用するPythonパッケージを管理する。

### `experiments/`

Chaos ToolkitのExperiment定義を配置する。

### `journals/`

Chaos Experiment実行結果を保存する。

---

## Python Environment

Virtual Environmentを有効化する。

```bash
cd ~/labs/chaos

source .venv/bin/activate
```

確認:

```bash
chaos --version
```

依存パッケージを再インストールする場合:

```bash
python -m pip install -r requirements.txt
```

---

## Current Network Topology

対象ラボ:

```text
                        AS65003
                         r5-srl
                           |
                     10.0.4.0/31
                           |
AS65001                                      AS65002
r1-gobgp -------- r2-frr -------- r4-frr -------- r3-gobgp
```

R2-R4間:

```text
r2-frr:eth2
10.0.2.0/31
     |
     |
10.0.2.1/31
r4-frr:eth1
```

Management Network:

```text
172.20.20.0/24
```

---

## BFD

R2-R4間ではBFDを有効化している。

目的は、BGP Hold Timerを待たず高速に経路障害を検知すること。

設定例:

```text
Transmit Interval : 300ms
Receive Interval  : 300ms
Detect Multiplier : 3
```

確認:

```bash
docker exec clab-bgp-chaos-r2-frr \
  vtysh -c 'show bfd peers'
```

正常時:

```text
Status: up
```

R4側:

```bash
docker exec clab-bgp-chaos-r4-frr \
  vtysh -c 'show bfd peers'
```

---

## BGP

BGP状態確認:

```bash
docker exec clab-bgp-chaos-r2-frr \
  vtysh -c 'show bgp summary'
```

R2-R4 Neighbor:

```text
R2 -> 10.0.2.1
R4 -> 10.0.2.0
```

正常時はEstablishedであること。

---

## SNMP Trap

BGP状態変化はSNMP TrapとしてZabbixへ送信される。

### BGP Established

```text
OID:
1.3.6.1.2.1.15.0.1
```

現在のTrap表示:

```text
mib-2.15.0.1
```

### BGP Backward Transition

```text
OID:
1.3.6.1.2.1.15.0.2
```

現在のTrap表示:

```text
mib-2.15.0.2
```

Trap確認:

```bash
docker exec zabbix-snmptraps \
  tail -f /var/lib/zabbix/snmptraps/snmptraps.log
```

---

## Zabbix Monitoring

現在のBGP Trap Item:

```text
Name:
BGP state trap

Type:
SNMP trap

Key:
snmptrap["mib-2\.15\.0\.[12]"]

Type of information:
Log
```

Trigger例:

```text
find(/r2-frr/snmptrap["mib-2\.15\.0\.[12]"],,"like","mib-2.15.0.2")=1
```

動作:

```text
mib-2.15.0.2
↓
BGP Down
↓
PROBLEM
```

復旧:

```text
mib-2.15.0.1
↓
Trigger condition becomes false
↓
RECOVERY
```

---

# Experiment 01: R2-R4 Link Loss

## Objective

R2-R4間の通信を完全に遮断し、以下を確認する。

```text
Network Loss
↓
BFD Down
↓
BGP Down
↓
SNMP Trap
↓
Zabbix Problem
↓
Network Recovery
↓
BFD Up
↓
BGP Established
↓
SNMP Trap
↓
Zabbix Recovery
```

---

## Failure Injection

対象:

```text
Container:
clab-bgp-chaos-r2-frr

Interface:
eth2
```

障害:

```text
Packet Loss:
100%
```

Containerlab単体で実行する場合:

```bash
containerlab tools netem set \
  -n clab-bgp-chaos-r2-frr \
  -i eth2 \
  --loss 100
```

解除:

```bash
containerlab tools netem reset \
  -n clab-bgp-chaos-r2-frr \
  -i eth2
```

---

## Chaos Toolkit Experiment

Experiment file:

```text
experiments/r2-r4-link-loss.json
```

実行前にVirtual Environmentを有効化する。

```bash
cd ~/labs/chaos

source .venv/bin/activate
```

Experiment実行:

```bash
chaos run \
  --rollback-strategy=always \
  --journal-path journals/r2-r4-link-loss.json \
  experiments/r2-r4-link-loss.json
```

---

## Expected Flow

### 1. Steady State

Experiment開始前に以下を確認する。

```text
BFD = Up
BGP = Established
```

### 2. Fault Injection

R2 eth2へ100% Packet Lossを適用する。

```text
R2 eth2
   |
   X 100% loss
   |
R4 eth1
```

### 3. Failure Detection

期待結果:

```text
BFD Down
↓
BGP Down
```

BFDが有効なため、BGP Hold Timerを待たず高速に検知される。

### 4. Monitoring

SNMP Trap:

```text
mib-2.15.0.2
```

Zabbix:

```text
PROBLEM
```

### 5. Rollback

Containerlab netemを解除する。

```text
Packet Loss 100%
↓
Packet Loss 0%
```

### 6. Recovery

期待結果:

```text
BFD Up
↓
BGP Established
↓
mib-2.15.0.1
↓
Zabbix RECOVERY
```

---

# Experiment Journals

Chaos Toolkitの実行結果は`journals/`へ保存する。

例:

```text
journals/r2-r4-link-loss.json
```

確認:

```bash
python3 -m json.tool \
  journals/r2-r4-link-loss.json
```

Journalから以下を確認できる。

- Experiment開始時刻
- Probe結果
- Action結果
- Failure発生
- Rollback実行
- Steady State再確認
- Experiment全体の成功 / 失敗

---

# Chaos Engineering Policy

単純に障害を発生させるだけではなく、Experimentごとに以下を定義する。

```text
1. Steady State
2. Fault
3. Expected Failure
4. Monitoring Result
5. Rollback
6. Expected Recovery
```

例えば:

```text
Steady State:
BFD Up
BGP Established

Fault:
R2 eth2 packet loss 100%

Expected Failure:
BFD Down
BGP Down

External Observation:
Zabbix Problem

Rollback:
Remove packet loss

Expected Recovery:
BFD Up
BGP Established
Zabbix Recovery
```

---

# Future Experiments

## Packet Loss

```text
10%
30%
50%
70%
100%
```

目的:

- BFD stability
- BGP stability
- packet loss耐性確認

---

## Network Delay

例:

```text
100ms
500ms
1s
3s
```

確認対象:

- BFD
- BGP
- ICMP RTT
- Zabbix

---

## Jitter

WAN品質劣化を模擬する。

```text
delay + jitter
```

---

## Random Link Failure

複数リンクからランダムに障害対象を選択する。

例:

```text
R1-R2
R2-R4
R4-R3
R2-R5
```

---

## Periodic Failure

例:

```text
60秒正常
↓
20秒障害
↓
60秒正常
↓
20秒障害
```

周期的なBGP flappingを発生させる。

Pumbaの利用を想定する。

---

## Router Restart

対象Routerコンテナをrestartし、

```text
Device Down
↓
BGP Down
↓
SNMP / ICMP monitoring
↓
Container restart
↓
Routing convergence
```

を確認する。

---

## CPU / Memory Stress

Routing daemonが高負荷になった場合の挙動を確認する。

確認対象:

- BFD
- BGP
- Routing convergence
- Zabbix monitoring

---

# Monitoring Improvements

現在は主にBGP Trapを監視している。

今後以下を追加する。

```text
ICMP Reachability

Interface
  ifOperStatus
  ifAdminStatus
  ifInErrors
  ifOutErrors
  ifInDiscards
  ifOutDiscards

BGP
  Trap
  Peer State polling

BFD

Interface Traffic

Packet Loss

Latency
```

最終的には、

```text
Chaos Injection
↓
Network Failure
↓
Protocol Failure
↓
Monitoring Detection
↓
Recovery
```

を一つのExperimentとして評価できる環境を目指す。

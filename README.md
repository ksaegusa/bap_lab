# BGP Chaos Lab

Containerlab上にGoBGP / FRRouting / Nokia SR Linuxを使ったBGP検証環境を構築し、BGP・BFD・SNMP・Zabbix監視・Chaos Engineeringをまとめて検証するためのラボです。

主な用途は以下です。

- BGPのiBGP / eBGP動作確認
- GoBGP / FRR / SR Linux間の相互接続
- BGP経路Advertise / Withdraw
- Linux FIBへの経路反映
- BFDによる高速障害検知
- SNMP Polling / SNMP Trap監視
- Zabbixによる障害検知・復旧確認
- Interface / Packet Loss等の障害注入
- Chaos Toolkitによる障害シナリオ実行
- 障害発生から監視検知までの時系列確認

---

# Architecture

```text
                              +------------------+
                              |      Zabbix      |
                              |------------------|
                              | SNMP Polling     |
                              | SNMP Trap        |
                              | ICMP             |
                              +--------+---------+
                                       |
                                       |
                                  Management
                                       |
                                       |
        +------------------------------+------------------------------+
        |                                                             |
        |                     Containerlab                             |
        |                                                             |
        |                     AS65003                                 |
        |                      r5-srl                                  |
        |                        |                                     |
        |                   10.0.4.0/31                               |
        |                        |                                     |
        |                                                             |
        | AS65001                                    AS65002           |
        |                                                             |
        | r1-gobgp ---- r2-frr -------- r4-frr ---- r3-gobgp          |
        |             iBGP        eBGP          iBGP                    |
        |                                                             |
        +-------------------------------------------------------------+

                              |
                              |
                       Chaos Toolkit
                              |
                  Containerlab netem / Docker
```

---

# Topology

```text
                        AS65003
                         r5-srl
                           |
                     10.0.4.0/31
                           |
AS65001                                      AS65002

r1-gobgp -------- r2-frr -------- r4-frr -------- r3-gobgp
    iBGP             eBGP             iBGP
```

BGP Session:

| Local | Remote | Type |
|---|---|---|
| R1 GoBGP | R2 FRR | iBGP |
| R2 FRR | R4 FRR | eBGP |
| R4 FRR | R3 GoBGP | iBGP |
| R2 FRR | R5 SR Linux | eBGP |

---

# Addressing

## Management Network

```text
172.20.20.0/24
```

| Node | Management IP |
|---|---|
| r1-gobgp | 172.20.20.11 |
| r2-frr | 172.20.20.12 |
| r3-gobgp | 172.20.20.21 |
| r4-frr | 172.20.20.22 |
| r5-srl | 172.20.20.31 |

Docker Host側:

```text
172.20.20.1
```

---

## Point-to-Point Links

| Link | Network | Side A | Side B |
|---|---|---|---|
| R1 - R2 | 10.0.1.0/31 | R1: 10.0.1.0 | R2: 10.0.1.1 |
| R2 - R4 | 10.0.2.0/31 | R2: 10.0.2.0 | R4: 10.0.2.1 |
| R4 - R3 | 10.0.3.0/31 | R4: 10.0.3.0 | R3: 10.0.3.1 |
| R2 - R5 | 10.0.4.0/31 | R2: 10.0.4.0 | R5: 10.0.4.1 |

---

## Service Prefix

```text
R1: 10.100.1.1/32
R3: 10.100.3.1/32
```

これらをGoBGPから広告し、End-to-Endのデータプレーン確認に使用します。

---

# Requirements

このラボでは以下を使用します。

- Linux
- Docker
- Containerlab
- Git
- Python 3
- Python venv
- Chaos Toolkit
- Zabbix 7.0 LTS
- PostgreSQL
- Net-SNMP

ARM64環境でも利用可能です。

現在の検証環境はRaspberry Pi / Ubuntu / Dockerです。

---

# Repository Layout

想定するディレクトリ構成:

```text
bgp_lab/
├── bgp-chaos.clab.yml
│
├── configs/
│   ├── r1-gobgp/
│   │   └── gobgpd.yaml
│   │
│   ├── r2-frr/
│   │   ├── daemons
│   │   ├── frr.conf
│   │   ├── vtysh.conf
│   │   └── snmpd.conf
│   │
│   ├── r3-gobgp/
│   │   └── gobgpd.yaml
│   │
│   ├── r4-frr/
│   │   ├── daemons
│   │   ├── frr.conf
│   │   ├── vtysh.conf
│   │   └── snmpd.conf
│   │
│   └── r5-srl/
│       └── config.cli
│
├── images/
│   ├── gobgp/
│   │   └── Dockerfile
│   │
│   └── frr/
│       └── Dockerfile
│
├── zabbix/
│   ├── compose.yaml
│   ├── .env
│   └── ...
│
├── chaos/
│   ├── requirements.txt
│   └── experiments/
│
└── README.md
```

---

# 1. Install Containerlab

Containerlabをインストールします。

インストール後:

```bash
containerlab version
```

Dockerも利用可能であることを確認します。

```bash
docker version
```

---

# 2. Build Custom Images

このラボではGoBGP用とFRR用のカスタムImageを使用します。

## GoBGP

使用Image:

```text
gobgp-lab:v4.7.0
```

ビルド例:

```bash
cd images/gobgp

docker build \
  -t gobgp-lab:v4.7.0 \
  .
```

---

## FRR

使用Image:

```text
frr-lab:10.7.0-snmp-netconf
```

このImageには主に以下を追加しています。

- FRR
- SNMP support
- AgentX
- Net-SNMP
- Sysrepo
- libnetconf2
- Netopeer2

ビルド例:

```bash
cd images/frr

docker build \
  -t frr-lab:10.7.0-snmp-netconf \
  .
```

現状、NETCONF関連コンポーネントもImageに含まれていますが、現在のラボでは主にBGP / BFD / SNMPを使用しています。

---

# 3. Deploy Containerlab

Topologyを起動:

```bash
containerlab deploy
```

状態確認:

```bash
containerlab inspect 
```

Docker側:

```bash
docker ps
```

以下のNodeが起動していることを確認します。

```text
clab-bgp-chaos-r1-gobgp
clab-bgp-chaos-r2-frr
clab-bgp-chaos-r3-gobgp
clab-bgp-chaos-r4-frr
clab-bgp-chaos-r5-srl
```

---

# 4. Verify BGP

## R2

```bash
docker exec clab-bgp-chaos-r2-frr \
  vtysh -c 'show bgp summary'
```

## R4

```bash
docker exec clab-bgp-chaos-r4-frr \
  vtysh -c 'show bgp summary'
```

正常時は以下のSessionがEstablishedになります。

```text
R1 - R2
R2 - R4
R4 - R3
R2 - R5
```

---

# 5. Verify BFD

BFDはR2-R4間で有効です。

R2:

```bash
docker exec clab-bgp-chaos-r2-frr \
  vtysh -c 'show bfd peers'
```

R4:

```bash
docker exec clab-bgp-chaos-r4-frr \
  vtysh -c 'show bfd peers'
```

正常時:

```text
Status: up
```

BFD設定:

```text
detect-multiplier 3
receive-interval 300 ms
transmit-interval 300 ms
```

---

# 6. Verify End-to-End Routing

R1からR3:

```bash
docker exec clab-bgp-chaos-r1-gobgp \
  ping -I 10.100.1.1 10.100.3.1
```

R3からR1:

```bash
docker exec clab-bgp-chaos-r3-gobgp \
  ping -I 10.100.3.1 10.100.1.1
```

サービスPrefixをSource IPとして指定します。

---

# 7. Verify SNMP

FRR NodeではNet-SNMPとAgentXを使用します。

構成:

```text
FRR bgpd / zebra
       |
       | AgentX
       v
     snmpd
       |
       +-- SNMP Polling
       |
       +-- SNMP Trap
```

R2のBGP4-MIB確認:

```bash
docker exec clab-bgp-chaos-r2-frr \
  snmpwalk \
  -v2c \
  -c public \
  -On \
  127.0.0.1 \
  .1.3.6.1.2.1.15
```

Interface一覧:

```bash
docker exec clab-bgp-chaos-r2-frr \
  snmpwalk \
  -v2c \
  -c public \
  -On \
  127.0.0.1 \
  .1.3.6.1.2.1.2.2.1.2
```

---

# 8. Setup Zabbix

Zabbix 7.0 LTSをDocker Composeで起動します。

```bash
cd zabbix
```

.envを修正

起動:

```bash
docker compose up -d
```

状態確認:

```bash
docker compose ps
```

構成:

```text
PostgreSQL
Zabbix Server
Zabbix Web
Zabbix SNMP Trap Receiver
```

Zabbix Web UIは現在以下を使用します。

```text
http://<Docker-Host>:8080
```

---

# Zabbix Network Access

ZabbixからContainerlab Management Networkへ到達できる必要があります。

Containerlab Management Network:

```text
172.20.20.0/24
```

対象:

```text
R2 172.20.20.12
R4 172.20.20.22
```

SNMP:

```text
UDP/161
```

SNMP Trap Receiver:

```text
UDP/1162
```

FRR側は以下へTrapを送ります。

```text
172.20.20.1:1162
```

---

# 9. Add Zabbix Hosts

## R2

Host:

```text
r2-frr
```

SNMP Interface:

```text
172.20.20.12
UDP/161
```

Community:

```text
public
```

## R4

Host:

```text
r4-frr
```

SNMP Interface:

```text
172.20.20.22
UDP/161
```

Community:

```text
public
```

---

# 10. Apply Zabbix SNMP Template

R2 / R4には以下の標準Templateをリンクします。

```text
Network Generic Device by SNMP
```

このTemplateにはSNMP Low-Level Discoveryが含まれます。

```text
Network interfaces discovery
```

Discoveryにより以下がInterfaceごとに自動生成されます。

- Interface Operational Status
- Traffic In
- Traffic Out
- Error
- Discard
- その他IF-MIB情報

---

# 11. Configure BGP Trap Monitoring

BGP Trap Item:

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

BGP Established:

```text
1.3.6.1.2.1.15.0.1
```

BGP Down:

```text
1.3.6.1.2.1.15.0.2
```

R2 Trigger:

```text
find(/r2-frr/snmptrap["mib-2\.15\.0\.[12]"],,"like","mib-2.15.0.2")=1
```

R4 Trigger:

```text
find(/r4-frr/snmptrap["mib-2\.15\.0\.[12]"],,"like","mib-2.15.0.2")=1
```

---

# 12. ICMP Monitoring

必要に応じてSimple Checkを追加します。

```text
Type:
Simple check

Key:
icmpping
```

またはIPを明示:

```text
icmpping[172.20.20.12]
```

戻り値:

```text
1 = reachable
0 = unreachable
```

---

# 13. Test Interface Failure

R2-R4間のR2側Interfaceは `eth2` です。

Down:

```bash
docker exec clab-bgp-chaos-r2-frr \
  ip link set dev eth2 down
```

状態確認:

```bash
docker exec clab-bgp-chaos-r2-frr \
  ip link show eth2
```

復旧:

```bash
docker exec clab-bgp-chaos-r2-frr \
  ip link set dev eth2 up
```

期待される状態:

```text
Interface Down
↓
BFD Down
↓
BGP Down
↓
Zabbix Problem
```

復旧時:

```text
Interface Up
↓
BFD Up
↓
BGP Established
↓
Zabbix Recovery
```

---

# 14. Test Packet Loss

Containerlab netemを利用します。

R2からR4方向へ100% Packet Loss:

```bash
containerlab tools netem set \
  -n clab-bgp-chaos-r2-frr \
  -i eth2 \
  --loss 100
```

状態確認:

```bash
containerlab tools netem show
```

解除:

```bash
containerlab tools netem reset \
  -n clab-bgp-chaos-r2-frr \
  -i eth2
```

この障害ではInterface自体はDownしません。

```text
ifOperStatus = up
BFD = down
BGP = down
```

Interface Down試験との違いを確認できます。

---

# 15. Setup Chaos Toolkit

Chaos ToolkitはPython Virtual Environmentにインストールします。

```bash
cd chaos
```

Virtual Environment作成:

```bash
python3 -m venv .venv
```

有効化:

```bash
source .venv/bin/activate
```

インストール:

```bash
pip install -r requirements.txt
```

`requirements.txt`:

```text
chaostoolkit
```

確認:

```bash
chaos --version
```

---

# Chaos Experiment Layout

```text
chaos/
├── .venv/
├── requirements.txt
└── experiments/
    ├── r2-r4-packet-loss/
    │   └── experiment.yaml
    │
    ├── r2-interface-flap-1min/
    │   └── experiment.yaml
    │
    └── ...
```

Experiment実行:

```bash
cd chaos/experiments/<experiment-name>

chaos run experiment.yaml
```

---

# Example Chaos Cases

現在検討・実装している障害ケース:

```text
Interface Down
Interface Flapping

100% Packet Loss
Partial Packet Loss
Delay
Jitter

BGP daemon Stop
BFD daemon Stop
Container Stop

TCP/179 Drop

Prefix Withdraw
Route Policy Change
Local Preference Change
MED Change
AS-PATH Prepend
```

---

# Monitoring Differences by Failure Type

| Failure | ICMP | Interface | BFD | BGP |
|---|---|---|---|---|
| Interface Down | Up | Down | Down | Down |
| 100% Packet Loss | Up | Up | Down | Down |
| BGP daemon Stop | Up | Up | 状況依存 | Down |
| Container Stop | Down | 取得不可 | Down | Down |
| Delay | Up | Up | 条件次第 | 条件次第 |
| Partial Loss | Up | Up | 条件次第 | 条件次第 |

障害の種類によって監視結果が異なる点を確認できます。

---

# Useful Commands

## Containerlab

Topology確認:

```bash
containerlab inspect \
  -t bgp-chaos.clab.yml
```

Topology削除:

```bash
sudo containerlab destroy \
  -t bgp-chaos.clab.yml
```

再作成:

```bash
sudo containerlab deploy \
  -t bgp-chaos.clab.yml
```

---

## FRR

R2 CLI:

```bash
docker exec -it clab-bgp-chaos-r2-frr \
  vtysh
```

R4 CLI:

```bash
docker exec -it clab-bgp-chaos-r4-frr \
  vtysh
```

BGP:

```bash
docker exec clab-bgp-chaos-r2-frr \
  vtysh -c 'show bgp summary'
```

BFD:

```bash
docker exec clab-bgp-chaos-r2-frr \
  vtysh -c 'show bfd peers'
```

Route:

```bash
docker exec clab-bgp-chaos-r2-frr \
  vtysh -c 'show ip route'
```

---

## Linux FIB

```bash
docker exec clab-bgp-chaos-r1-gobgp \
  ip route
```

```bash
docker exec clab-bgp-chaos-r3-gobgp \
  ip route
```

---

## SNMP

BGP4-MIB:

```bash
docker exec clab-bgp-chaos-r2-frr \
  snmpwalk \
  -v2c \
  -c public \
  -On \
  127.0.0.1 \
  .1.3.6.1.2.1.15
```

Interface:

```bash
docker exec clab-bgp-chaos-r2-frr \
  snmpwalk \
  -v2c \
  -c public \
  -On \
  127.0.0.1 \
  .1.3.6.1.2.1.2.2.1.2
```

---

# Troubleshooting

## BGPがEstablishedしない

R2:

```bash
docker exec clab-bgp-chaos-r2-frr \
  vtysh -c 'show bgp summary'
```

Interface確認:

```bash
docker exec clab-bgp-chaos-r2-frr \
  ip addr
```

---

## BFDがUpしない

R2 / R4双方で `bfdd` が起動していることを確認します。

```bash
docker exec clab-bgp-chaos-r2-frr \
  ps aux | grep '[b]fdd'
```

```bash
docker exec clab-bgp-chaos-r4-frr \
  ps aux | grep '[b]fdd'
```

FRR `daemons`:

```text
bfdd=yes
```

---

## SNMPが取得できない

```bash
docker exec clab-bgp-chaos-r2-frr \
  snmpwalk \
  -v2c \
  -c public \
  127.0.0.1 \
  system
```

snmpd確認:

```bash
docker exec clab-bgp-chaos-r2-frr \
  ps aux | grep '[s]nmpd'
```

---

## BGP TrapがZabbixに届かない

FRR `snmpd.conf`:

```text
trap2sink 172.20.20.1 public 1162
```

Zabbix SNMP Trap ReceiverがUDP/1162をListenしていることを確認します。

Trap Source IPがR2/R4のManagement IPになっていることも確認します。

```text
R2: 172.20.20.12
R4: 172.20.20.22
```
---

# Next Steps

```text
1. Zabbix Monitoring

   - ICMP
   - Interface Status
   - Traffic
   - Errors
   - Discards

2. Chaos Scenarios

   - Interface Flap
   - Packet Loss
   - Delay
   - Process Failure
   - Container Failure

3. Route-level Chaos

   - Prefix Withdraw
   - Policy Change
   - MED
   - Local Preference
   - AS-PATH

4. Monitoring Correlation

   - Interface
   - BFD
   - BGP
   - Data Plane
   - Zabbix Alert

5. Redundant Topology

   - Failover
   - Alternate Path
   - Convergence
```

---

# Cleanup

Containerlab環境を削除:

```bash
sudo containerlab destroy \
  -t bgp-chaos.clab.yml
```

Zabbix停止:

```bash
cd zabbix

docker compose down
```

Chaos Toolkit Virtual Environment終了:

```bash
deactivate
```

---

# Notes

このラボでは、単にBGP SessionがEstablishedになることだけを目的としていません。

```text
Failure Injection
       ↓
Interface / Network State
       ↓
BFD
       ↓
BGP
       ↓
RIB / FIB
       ↓
Data Plane
       ↓
Zabbix Detection
       ↓
Recovery
```

まで一連の動きを観測することを目的としています。

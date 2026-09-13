# BGP Chaos Lab

GoBGP、FRRouting（FRR）、Nokia SR Linuxを使用してBGPネットワークを構築し、経路制御、データプレーン、監視、障害注入、障害検知、経路収束を観測するための検証環境です。

現在は Raspberry Pi / Docker / Containerlab 上で以下の5ノード構成を動作させています。

```text
                         AS65003
                          R5 SR Linux
                              |
                         10.0.4.0/31
                              |
                              |
AS65001                      R2 FRR -------- R4 FRR                      AS65002
R1 GoBGP --------------------/                 \-------------------- R3 GoBGP
```

より正確には以下の構成です。

```text
                        AS65003
                         r5-srl
                           |
                     10.0.4.0/31
                           |
AS65001                                      AS65002

r1-gobgp -------- r2-frr -------- r4-frr -------- r3-gobgp

          iBGP          eBGP          iBGP
```

GoBGPノードではBGP Control Planeだけでなく、FRR Zebraを利用して学習経路をLinux FIBへ反映します。

```text
BGP Update
    ↓
GoBGP RIB
    ↓
FRR Zebra
    ↓
Linux FIB
    ↓
Packet Forwarding
```

FRRノードではBGP、BFD、SNMP / AgentXを使用し、ZabbixからSNMP PollingおよびSNMP Trapによる監視を行います。

障害注入には主に以下を利用します。

```text
Containerlab netem
Docker / ip link
Chaos Toolkit
```

最終的には、ネットワーク障害ごとにControl Plane、Data Plane、Monitoring Planeがどのように反応するかを観測できる環境を目指します。

---

# Goals

主な目的は以下です。

- GoBGP / FRR / SR Linux間でのBGP相互接続
- iBGP / eBGP双方の動作確認
- BGP経路Advertise / Withdrawの観測
- GoBGP RIBとLinux FIBの連携確認
- 実際のデータプレーン到達性確認
- BFDによる高速障害検知
- BGP収束動作の観測
- SNMP Pollingによるネットワーク監視
- SNMP TrapによるBGP障害監視
- Zabbixによる障害検知・復旧監視
- SNMP Interface DiscoveryによるInterface監視
- Packet Loss / Delay等の障害注入
- Interface Down / Upによるリンク障害試験
- Chaos Toolkitによる障害シナリオ実行
- 障害内容ごとの監視結果比較
- 実験結果の時系列観測

---

# Current Topology

```text
                               AS65003

                              ┌──────────┐
                              │  R5 SRL  │
                              │ AS65003  │
                              └────┬─────┘
                                   │
                              10.0.4.0/31
                                   │
                                   │ eBGP
                                   │

            AS65001                                 AS65002

┌──────────────┐      iBGP      ┌──────────┐
│  R1 GoBGP    │────────────────│  R2 FRR  │
│   AS65001    │                │ AS65001  │
└──────────────┘                └────┬─────┘
                                    │
                                    │ eBGP
                                    │
                               ┌────┴─────┐
                               │  R4 FRR  │
                               │ AS65002  │
                               └────┬─────┘
                                    │
                                    │ iBGP
                                    │
                            ┌───────┴───────┐
                            │   R3 GoBGP    │
                            │    AS65002    │
                            └───────────────┘
```

BGP Session:

```text
R1 GoBGP ── iBGP ── R2 FRR
R2 FRR   ── eBGP ── R4 FRR
R4 FRR   ── iBGP ── R3 GoBGP
R2 FRR   ── eBGP ── R5 SR Linux
```

---

# AS Design

```text
AS65001
├── R1 GoBGP
└── R2 FRR

AS65002
├── R3 GoBGP
└── R4 FRR

AS65003
└── R5 SR Linux
```

使用ASN:

```text
65001
65002
65003
```

---

# Node Roles

## R1 / R3: GoBGP + Zebra

R1とR3はGoBGPをBGP Control Planeとして使用します。

主な用途:

- テスト用PrefixのAdvertise
- Prefix Withdraw
- BGP経路学習
- Community
- MED
- AS-PATH操作
- 大量Prefix注入
- API経由のBGP操作
- Chaos試験の対象

GoBGPが選択した経路はFRR Zebra経由でLinux Kernelへ反映します。

```text
gobgpd
   |
   | ZAPI
   v
FRR Zebra
   |
   v
Linux Kernel FIB
```

BGP処理を担当するのはGoBGPです。

FRR bgpdはGoBGPノードでは使用しません。

---

## R2 / R4: FRRouting

R2とR4はLinux RouterとしてFRRを使用します。

```text
FRR bgpd
   |
   +── BFD
   |
   +── SNMP module
   |
   v
FRR Zebra
   |
   v
Linux Kernel FIB
```

主な観測対象:

- iBGP
- eBGP
- BFD
- BGP best path
- RIB
- FIB
- Next-Hop
- Interface
- SNMP
- SNMP Trap
- 障害発生時の状態遷移

---

## R5: Nokia SR Linux

R5はAS65003の外部ルータとして使用します。

```text
R2 FRR
   |
   | eBGP
   |
R5 SR Linux
```

主な用途:

- 異種NOSとのBGP相互接続
- FRRとのeBGP検証
- 将来的なMulti-AS障害試験

---

# Naming Convention

Node ID:

```text
r1-gobgp
r2-frr
r3-gobgp
r4-frr
r5-srl
```

Containerlab Container Name:

```text
clab-bgp-chaos-r1-gobgp
clab-bgp-chaos-r2-frr
clab-bgp-chaos-r3-gobgp
clab-bgp-chaos-r4-frr
clab-bgp-chaos-r5-srl
```

---

# Management Network

Management Network:

```text
172.20.20.0/24
```

Management IP:

| Node | Management IP |
|---|---|
| R1 | 172.20.20.11 |
| R2 | 172.20.20.12 |
| R3 | 172.20.20.21 |
| R4 | 172.20.20.22 |
| R5 | 172.20.20.31 |

Docker Bridge / Host側:

```text
172.20.20.1
```

Management Networkは以下に利用します。

- Container管理
- SNMP
- SNMP Trap
- Monitoring
- SR Linux Management
- 将来的なTelemetry接続

---

# Router ID

| Node | Router ID |
|---|---|
| R1 | 10.255.0.1 |
| R2 | 10.255.0.2 |
| R3 | 10.255.0.3 |
| R4 | 10.255.0.4 |
| R5 | 10.255.0.5 |

R2 / R4ではLoopbackにRouter ID用アドレスを設定します。

```text
R2 lo  10.255.0.2/32
R4 lo  10.255.0.4/32
```

R5ではSR Linuxのsystem0を使用します。

```text
R5 system0  10.255.0.5/32
```

---

# Point-to-Point Address Design

Point-to-Point Linkには `/31` を使用します。

## R1 - R2

```text
Network 10.0.1.0/31

R1  10.0.1.0
R2  10.0.1.1
```

## R2 - R4

```text
Network 10.0.2.0/31

R2  10.0.2.0
R4  10.0.2.1
```

## R4 - R3

```text
Network 10.0.3.0/31

R4  10.0.3.0
R3  10.0.3.1
```

## R2 - R5

```text
Network 10.0.4.0/31

R2  10.0.4.0
R5  10.0.4.1
```

---

# Service Prefix

GoBGPノードから試験用Service Prefixを広告します。

```text
R1
  10.100.1.1/32

R3
  10.100.3.1/32
```

Linux Loopbackにも同じアドレスを設定します。

```bash
# R1
ip addr add 10.100.1.1/32 dev lo

# R3
ip addr add 10.100.3.1/32 dev lo
```

これにより、BGP RIBだけでなく実際のEnd-to-End Packet Forwardingを確認できます。

---

# Address Summary

| Node | Implementation | ASN | Router ID | Management | Link Address | Service Prefix |
|---|---|---:|---|---|---|---|
| R1 | GoBGP + Zebra | 65001 | 10.255.0.1 | 172.20.20.11 | 10.0.1.0/31 | 10.100.1.1/32 |
| R2 | FRR | 65001 | 10.255.0.2 | 172.20.20.12 | 10.0.1.1/31, 10.0.2.0/31, 10.0.4.0/31 | - |
| R3 | GoBGP + Zebra | 65002 | 10.255.0.3 | 172.20.20.21 | 10.0.3.1/31 | 10.100.3.1/32 |
| R4 | FRR | 65002 | 10.255.0.4 | 172.20.20.22 | 10.0.2.1/31, 10.0.3.0/31 | - |
| R5 | SR Linux | 65003 | 10.255.0.5 | 172.20.20.31 | 10.0.4.1/31 | - |

---

# Containerlab Topology

現在の主な構成:

```yaml
name: bgp-chaos

mgmt:
  network: bgp-chaos-mgmt
  ipv4-subnet: 172.20.20.0/24

topology:
  nodes:
    r1-gobgp:
      kind: linux
      image: gobgp-lab:v4.7.0
      mgmt-ipv4: 172.20.20.11
      binds:
        - ./configs/r1-gobgp/gobgpd.yaml:/etc/gobgp/gobgpd.yaml:ro
      exec:
        - ip addr add 10.0.1.0/31 dev eth1
        - ip addr add 10.100.1.1/32 dev lo
        - sh -c 'until gobgp global rib add 10.100.1.1/32; do sleep 1; done'

    r2-frr:
      kind: linux
      image: frr-lab:10.7.0-snmp-netconf
      mgmt-ipv4: 172.20.20.12
      binds:
        - ./configs/r2-frr/daemons:/etc/frr/daemons:ro
        - ./configs/r2-frr/frr.conf:/etc/frr/frr.conf:ro
        - ./configs/r2-frr/vtysh.conf:/etc/frr/vtysh.conf:ro
        - ./configs/r2-frr/snmpd.conf:/etc/snmp/snmpd.conf:ro
      exec:
        - snmpd

    r3-gobgp:
      kind: linux
      image: gobgp-lab:v4.7.0
      mgmt-ipv4: 172.20.20.21
      binds:
        - ./configs/r3-gobgp/gobgpd.yaml:/etc/gobgp/gobgpd.yaml:ro
      exec:
        - ip addr add 10.0.3.1/31 dev eth1
        - ip addr add 10.100.3.1/32 dev lo
        - sh -c 'until gobgp global rib add 10.100.3.1/32; do sleep 1; done'

    r4-frr:
      kind: linux
      image: frr-lab:10.7.0-snmp-netconf
      mgmt-ipv4: 172.20.20.22
      binds:
        - ./configs/r4-frr/daemons:/etc/frr/daemons:ro
        - ./configs/r4-frr/frr.conf:/etc/frr/frr.conf:ro
        - ./configs/r4-frr/vtysh.conf:/etc/frr/vtysh.conf:ro
        - ./configs/r4-frr/snmpd.conf:/etc/snmp/snmpd.conf:ro
      exec:
        - snmpd

    r5-srl:
      kind: nokia_srlinux
      type: ixr-d3
      image: ghcr.io/nokia/srlinux:26.7.1-554
      mgmt-ipv4: 172.20.20.31
      startup-config: ./configs/r5-srl/config.cli

  links:
    - endpoints: ["r1-gobgp:eth1", "r2-frr:eth1"]
    - endpoints: ["r2-frr:eth2", "r4-frr:eth1"]
    - endpoints: ["r4-frr:eth2", "r3-gobgp:eth1"]
    - endpoints: ["r2-frr:eth3", "r5-srl:e1-1"]
```

---

# GoBGP Configuration

## R1

```yaml
global:
  config:
    as: 65001
    router-id: 10.255.0.1

zebra:
  config:
    enabled: true
    url: "unix:/run/frr/zserv.api"
    version: 6

neighbors:
  - config:
      neighbor-address: 10.0.1.1
      peer-as: 65001
    afi-safis:
      - config:
          afi-safi-name: ipv4-unicast
```

## R3

```yaml
global:
  config:
    as: 65002
    router-id: 10.255.0.3

zebra:
  config:
    enabled: true
    url: "unix:/run/frr/zserv.api"
    version: 6

neighbors:
  - config:
      neighbor-address: 10.0.3.0
      peer-as: 65002
    afi-safis:
      - config:
          afi-safi-name: ipv4-unicast
```

---

# GoBGP Prefix Operation

R1:

```bash
gobgp global rib add 10.100.1.1/32
```

Withdraw:

```bash
gobgp global rib del 10.100.1.1/32
```

R3:

```bash
gobgp global rib add 10.100.3.1/32
```

Withdraw:

```bash
gobgp global rib del 10.100.3.1/32
```

---

# FRR Configuration

## R2

```text
frr defaults traditional
hostname r2-frr
agentx
!
interface lo
 ip address 10.255.0.2/32
!
interface eth1
 description to-r1-gobgp
 ip address 10.0.1.1/31
!
interface eth2
 description to-r4-frr
 ip address 10.0.2.0/31
!
interface eth3
 description to-r5-srl
 ip address 10.0.4.0/31
!
bfd
 peer 10.0.2.1 interface eth2
  detect-multiplier 3
  receive-interval 300
  transmit-interval 300
  no shutdown
 !
!
router bgp 65001
 bgp router-id 10.255.0.2
 no bgp ebgp-requires-policy
 neighbor 10.0.1.0 remote-as 65001
 neighbor 10.0.2.1 remote-as 65002
 neighbor 10.0.2.1 bfd
 neighbor 10.0.4.1 remote-as 65003
 !
 address-family ipv4 unicast
  neighbor 10.0.1.0 activate
  neighbor 10.0.1.0 next-hop-self
  neighbor 10.0.2.1 activate
  neighbor 10.0.4.1 activate
 exit-address-family
!
line vty
!
```

`vtysh.conf`:

```text
service integrated-vtysh-config
```

---

## R4

```text
frr defaults traditional
hostname r4-frr
agentx
!
interface lo
 ip address 10.255.0.4/32
!
interface eth1
 description to-r2-frr
 ip address 10.0.2.1/31
!
interface eth2
 description to-r3-gobgp
 ip address 10.0.3.0/31
!
bfd
 peer 10.0.2.0 interface eth1
  detect-multiplier 3
  receive-interval 300
  transmit-interval 300
  no shutdown
 !
!
router bgp 65002
 bgp router-id 10.255.0.4
 no bgp ebgp-requires-policy
 neighbor 10.0.2.0 remote-as 65001
 neighbor 10.0.2.0 bfd
 neighbor 10.0.3.1 remote-as 65002
 !
 address-family ipv4 unicast
  neighbor 10.0.2.0 activate
  neighbor 10.0.3.1 activate
  neighbor 10.0.3.1 next-hop-self
 exit-address-family
!
line vty
!
```

`vtysh.conf`:

```text
service integrated-vtysh-config
```

---

# BFD

BFDは現在R2-R4間で有効化しています。

```text
R2 eth2                         R4 eth1
10.0.2.0 ---------------------- 10.0.2.1
              BFD
```

設定:

```text
detect-multiplier 3
receive-interval 300 ms
transmit-interval 300 ms
```

FRR daemon設定ではR2 / R4双方で以下が必要です。

```text
bfdd=yes
```

状態確認:

```bash
docker exec clab-bgp-chaos-r2-frr \
  vtysh -c 'show bfd peers'
```

```bash
docker exec clab-bgp-chaos-r4-frr \
  vtysh -c 'show bfd peers'
```

正常時:

```text
Status: up
```

BFDにより、BGPのHold Timerを待たずにR2-R4間の障害を高速検知できます。

---

# End-to-End Data Plane

Service PrefixをSource IPとして指定したEnd-to-End Pingが両方向で成功することを確認済みです。

R1 → R3:

```bash
ping -I 10.100.1.1 10.100.3.1
```

R3 → R1:

```bash
ping -I 10.100.3.1 10.100.1.1
```

通信経路:

```text
10.100.1.1
    |
R1 GoBGP
    |
R2 FRR
    |
R4 FRR
    |
R3 GoBGP
    |
10.100.3.1
```

---

# FRR SNMP Architecture

FRR自身がSNMP Master Agentになるわけではありません。

```text
FRR bgpd / zebra
       |
       | AgentX
       v
     snmpd
       |
       +── SNMP GET / WALK
       |
       └── SNMP Trap
```

FRR daemonではSNMP moduleを有効化します。

```text
zebra_options="-M snmp"
bgpd_options="-M snmp"
```

FRR設定:

```text
agentx
```

AgentX Socket:

```text
/var/agentx/master
```

---

# SNMP Configuration

R2 / R4ではNet-SNMP `snmpd` を使用しています。

`snmpd.conf`:

```conf
master agentx
agentXSocket /var/agentx/master
agentXPerms 0777 0755

agentAddress udp:161
rocommunity public

trap2sink 172.20.20.1 public 1162
```

SNMP TrapはDocker Host側の以下へ送信します。

```text
172.20.20.1:1162/UDP
```

Zabbix SNMP Trap Receiverはhost networkで動作させることで、Trapの送信元IPを維持します。

---

# SNMP BGP Monitoring

FRR BGP4-MIBはSNMP WALKできることを確認済みです。

```bash
docker exec clab-bgp-chaos-r2-frr \
  snmpwalk -v2c -c public -On \
  127.0.0.1 .1.3.6.1.2.1.15
```

例:

```text
.1.3.6.1.2.1.15.2.0 = INTEGER: 65001
.1.3.6.1.2.1.15.4.0 = IpAddress: 10.255.0.2
```

BGP Trap:

```text
BGP Established
1.3.6.1.2.1.15.0.1

BGP Backward Transition
1.3.6.1.2.1.15.0.2
```

---

# Zabbix Architecture

Zabbix 7.0 LTSをDocker Composeで動作させています。

```text
FRR R2 / R4
    |
    | SNMP UDP/161
    |
    +-----------------------> Zabbix Server

FRR R2 / R4
    |
    | SNMP Trap UDP/1162
    v
172.20.20.1
    |
    v
zabbix-snmptraps
    |
    v
Trap File
    |
    v
Zabbix Server
```

構成要素:

```text
PostgreSQL 16 Alpine
Zabbix Server
Zabbix Web
Zabbix SNMP Traps
```

Web UI:

```text
TCP/8080
```

Zabbix Server:

```text
TCP/10051
```

SNMP Trap Receiver:

```text
UDP/1162
```

---

# Zabbix BGP Trap Monitoring

R2:

```text
SNMP Interface
172.20.20.12:161
```

R4:

```text
SNMP Interface
172.20.20.22:161
```

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

R2 Trigger:

```text
find(/r2-frr/snmptrap["mib-2\.15\.0\.[12]"],,"like","mib-2.15.0.2")=1
```

R4 Trigger:

```text
find(/r4-frr/snmptrap["mib-2\.15\.0\.[12]"],,"like","mib-2.15.0.2")=1
```

BGP Session Down:

```text
mib-2.15.0.2
→ Problem
```

BGP Session Established:

```text
mib-2.15.0.1
→ Recovery
```

R2 / R4双方からTrapが送信され、障害検知と復旧をZabbix上で確認済みです。

---

# Zabbix Interface Monitoring

R2 / R4には以下の標準テンプレートを利用します。

```text
Network Generic Device by SNMP
```

このテンプレートのLow-Level Discoveryによって、SNMPからInterfaceを自動検出します。

```text
Network interfaces discovery
    |
    +── eth0
    +── eth1
    +── eth2
    +── eth3
```

各Interfaceについて自動的に以下が生成されます。

```text
Operational Status
Traffic In
Traffic Out
Errors
Discards
その他IF-MIB情報
```

R2で確認されたifIndex:

| Interface | ifIndex |
|---|---:|
| lo | 1 |
| eth0 | 2 |
| eth3 | 173 |
| eth1 | 175 |
| eth2 | 177 |

R2-R4 LinkはR2側 `eth2` です。

```text
ifIndex 177
```

Interface Down試験:

```bash
docker exec clab-bgp-chaos-r2-frr \
  ip link set dev eth2 down
```

復旧:

```bash
docker exec clab-bgp-chaos-r2-frr \
  ip link set dev eth2 up
```

この方法では実際に`ifOperStatus`がDownするため、Interface監視試験に使用できます。

---

# ICMP Monitoring

ホスト死活監視にはZabbix Simple Checkを使用できます。

```text
Type:
Simple check

Key:
icmpping
```

Zabbix Server側からICMP Echoを送信します。

例:

```text
1 = reachable
0 = unreachable
```

必要に応じて対象IPを明示できます。

```text
icmpping[172.20.20.12]
```

---

# Monitoring Layers

## Host

```text
ICMP Reachability
SNMP Reachability
```

## Interface

```text
ifAdminStatus
ifOperStatus
Traffic
Errors
Discards
```

## BFD

```text
Up
Down
```

## BGP

```text
Established
Backward Transition
Route Advertise
Route Withdraw
```

## Routing

```text
RIB
FIB
Next-Hop
Best Path
Prefix
```

## Data Plane

```text
Ping
Packet Loss
RTT
Actual Traffic
```

---

# Monitoring Characteristics

監視方式によって障害検知タイミングは異なります。

```text
SNMP Trap
  イベント発生時に即時送信

SNMP Polling
  ZabbixのPolling Intervalに依存
```

例えばInterface Down時:

```text
eth2 DOWN
   |
   +── ifOperStatus = down
   |
   +── BFD Down
          |
          v
       BGP Down
          |
          v
       BGP Trap
```

BGP Trapはイベント駆動のため、SNMP PollingによるInterface Down表示より先にZabbixでProblemになる場合があります。

---

# Chaos Engineering

Chaos Engineeringでは、監視の検証そのものよりもまず「障害を確実に発生させる」ことを重視します。

現在利用している主な手段:

```text
Containerlab netem
Docker exec
Linux ip link
Chaos Toolkit
```

---

# Containerlab Netem

R2-R4間に100% Packet Lossを発生:

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

状態確認:

```bash
containerlab tools netem show
```

この障害ではInterface自体はUPのままです。

```text
ifOperStatus = up
BFD = down
BGP = down
```

そのためInterface Downとは異なる障害パターンとして利用できます。

---

# Interface Down Failure

InterfaceそのものをDown:

```bash
docker exec clab-bgp-chaos-r2-frr \
  ip link set dev eth2 down
```

復旧:

```bash
docker exec clab-bgp-chaos-r2-frr \
  ip link set dev eth2 up
```

期待される状態:

```text
ifOperStatus = down
BFD = down
BGP = down
```

---

# Chaos Toolkit

Chaos ToolkitはPython Virtual Environment上に導入しています。

Directory:

```text
~/labs/chaos/
```

構成例:

```text
chaos/
├── .venv/
├── requirements.txt
├── README.md
└── experiments/
```

`requirements.txt`:

```text
chaostoolkit
```

Virtual Environment:

```bash
cd ~/labs/chaos

source .venv/bin/activate
```

ExperimentはYAML形式で管理します。

```text
experiments/
├── r2-r4-link-flap/
│   └── experiment.yaml
│
├── r2-interface-flap-1min/
│   └── experiment.yaml
│
├── r2-r4-packet-loss/
│   └── experiment.yaml
│
└── ...
```

実行:

```bash
chaos run experiment.yaml
```

Chaos Toolkit Journalは実験の実行履歴として利用できます。

```text
journal.json
```

現在はJournal管理を複雑にしすぎず、Experiment単位のディレクトリで扱う方針とします。

---

# Chaos Scenario: Packet Loss Flapping

R2-R4間でPacket Lossを繰り返します。

例:

```text
100% loss
↓
20秒
↓
reset
↓
40秒正常
↓
再度100% loss
```

この場合:

```text
Interface = UP
BFD = DOWN
BGP = DOWN
```

となります。

InterfaceそのものはDownしません。

---

# Chaos Scenario: Interface Flapping

R2 `eth2` をDown / Upさせます。

1分間の例:

```text
00秒  eth2 DOWN
10秒  eth2 UP

20秒  eth2 DOWN
30秒  eth2 UP

40秒  eth2 DOWN
50秒  eth2 UP

60秒  終了
```

この試験では:

```text
Interface Down
↓
BFD Down
↓
BGP Down

Interface Up
↓
BFD Up
↓
BGP Established
```

というフラッピングを発生させます。

---

# Failure Pattern Comparison

| Failure | ICMP | IF Oper | BFD | BGP |
|---|---|---|---|---|
| Interface Down | Up | Down | Down | Down |
| 100% Packet Loss on R2-R4 | Up | Up | Down | Down |
| BGP daemon Down | Up | Up | 状況依存 | Down |
| Container Stop | Down | 取得不可 | Down | Down |
| Delay | Up | Up | 条件次第 | 条件次第 |
| Partial Loss | Up | Up | 条件次第 | 条件次第 |

障害の種類ごとに監視結果が異なる点を利用し、原因切り分けの検証を行います。

---

# Planned Chaos Cases

```text
Interface Down
Interface Flap
100% Packet Loss
Partial Packet Loss
Delay
Jitter
Packet Reorder
Packet Duplication
Packet Corruption
Bandwidth Limitation

BGP Daemon Stop
BFD Daemon Stop
Container Stop

TCP/179 Drop

Prefix Withdraw
Route Policy Change
Local Preference Change
MED Change
AS-PATH Prepend
Route Leak

CPU Pressure
Memory Pressure
```

---

# Observation Timeline

障害試験では以下の時間軸を観測します。

```text
T0  Failure Injected

T1  Interface / BFD State Change

T2  BGP Session Down

T3  Route Withdrawn

T4  FIB Changed

T5  Data Plane Impact

T6  Monitoring Problem

T7  Failure Removed

T8  BFD / BGP Recovery

T9  Monitoring Recovery
```

主な評価指標:

```text
Failure Detection Time
BFD Detection Time
BGP Failure Detection Time
Routing Convergence Time
Data Plane Outage Time
Monitoring Detection Time
Recovery Time
```

---

# Zabbix Backup

Zabbixの設定情報は主にPostgreSQL Databaseに保存されます。

バックアップ対象:

```text
PostgreSQL Database
Docker Compose configuration
.env
SNMP Trap configuration
その他の外部設定ファイル
```

例:

```bash
mkdir -p ~/labs/zabbix/backups
```

PostgreSQL dump:

```bash
docker exec zabbix-postgres \
  pg_dump -U zabbix -Fc zabbix \
  > ~/labs/zabbix/backups/zabbix-$(date +%Y%m%d-%H%M%S).dump
```

Container名は環境によって異なるため、事前に確認します。

```bash
docker compose ps
```

Gitで管理するもの:

```text
compose.yaml
.env.example
snmptrapd.conf
その他の設定ファイル
```

Database Dumpには以下のようなGUI設定も含まれます。

```text
Hosts
Items
Triggers
Templates
Template Links
Users
Actions
その他Zabbix設定
```

---

# FRR Container Image

FRR Nodeでは以下のカスタムImageを使用しています。

```text
frr-lab:10.7.0-snmp-netconf
```

このTag名は10.7.0ですが、現在のBuild元ではFRR 10.7.1を使用しています。

主な追加機能:

```text
SNMP
AgentX
Sysrepo
libnetconf2
Netopeer2
```

ビルドには以下も含まれています。

```text
libyang
sysrepo
libnetconf2
netopeer2
FRR
```

現在Image Sizeが大きい主因は、SNMP / NETCONF Runtimeそのものではなく、Build ToolchainとSource / Build Directoryを最終Imageに残しているためです。

将来的にはMulti-stage Buildによる軽量化を検討します。

---

# NETCONF Status

NETCONF / Sysrepo / Netopeer2関連コンポーネントはCustom FRR Imageに含まれています。

ただし現在の検証優先順位は、

```text
BGP
BFD
SNMP
Zabbix
Chaos Engineering
```

です。

NETCONFの詳細な切り分けは現在停止しています。

---

# Current Status

現在確認済み:

```text
[OK] R1-R2 iBGP Established
[OK] R2-R4 eBGP Established
[OK] R4-R3 iBGP Established
[OK] R2-R5 eBGP Established

[OK] R1 10.100.1.1/32 Advertise
[OK] R3 10.100.3.1/32 Advertise

[OK] R1 → R3 BGP Route Propagation
[OK] R3 → R1 BGP Route Propagation

[OK] GoBGP RIB → Zebra → Linux FIB

[OK] R1 → R3 Service IP Ping
[OK] R3 → R1 Service IP Ping

[OK] FRR SNMP Module
[OK] FRR AgentX
[OK] R2 SNMP WALK
[OK] R4 SNMP WALK

[OK] R2 BGP Trap
[OK] R4 BGP Trap

[OK] Zabbix SNMP Trap Receiver
[OK] Trap Source IP Preservation
[OK] Zabbix BGP Problem Detection
[OK] Zabbix BGP Recovery

[OK] R2-R4 BFD
[OK] BFDによる高速BGP Down

[OK] Zabbix Network Generic Device by SNMP
[OK] SNMP Interface Discovery
[OK] Interface Status Monitoring

[OK] R2 eth2 Interface Down Test
[OK] Interface Up Recovery

[OK] Containerlab netem 100% Packet Loss
[OK] netem Reset

[OK] Chaos Toolkit Installation
[OK] YAML Experiment Format
[OK] Repeated Packet Loss Scenario

[WIP] Interface Flap Chaos Scenario
[WIP] ICMP Monitoring Expansion
[WIP] Interface Monitoring Expansion
[WIP] Additional Chaos Scenarios
```

---

# Current Monitoring Scope

現在の監視対象:

```text
Host
└── ICMP

Interface
├── Status
├── Traffic
├── Error
└── Discard

BFD
└── BFD State

BGP
├── BGP Down Trap
└── BGP Established Trap

Routing
├── RIB
└── FIB

Data Plane
└── End-to-End Ping
```

---

# Next Steps

現在の優先順位:

```text
1. Zabbix監視拡張

   - R4へNetwork Generic Device by SNMP適用
   - ICMP監視
   - Interface監視
   - Traffic
   - Error
   - Discard

2. Chaos Scenario追加

   - Interface Flap
   - Packet Loss
   - Partial Loss
   - Delay
   - Container Stop
   - BGP daemon Stop
   - BFD daemon Stop

3. ZabbixとChaosの時系列比較

   - 障害発生
   - Interface状態
   - BFD
   - BGP
   - Zabbix Problem
   - Recovery

4. Prefix / Route系Chaos

   - Prefix Withdraw
   - Policy Change
   - MED
   - Local Preference
   - AS-PATH

5. 冗長経路追加

6. 必要に応じてPrometheus / Grafana / BMPを追加
```

---

# Future Redundant Topology

現在は障害の影響を追いやすくするため基本的に直列構成です。

将来的には冗長経路を追加します。

```text
R1 ───── R2
│         │
│         │
R3 ───── R4
```

検証項目:

```text
Best Path
Failover
Local Preference
MED
AS-PATH
ECMP
Convergence
```

---

# Platform

現在の実行環境:

```text
Raspberry Pi
ARM64
Ubuntu Linux
Docker
Containerlab
```

Containerlabは以下を担当します。

```text
Topology
Container Deployment
Virtual Links
Network Impairment
```

Routing機能:

```text
GoBGP
FRR
Nokia SR Linux
Linux Kernel
```

Monitoring:

```text
Zabbix 7.0 LTS
Net-SNMP
SNMP Trap
```

Chaos:

```text
Containerlab netem
Linux ip link
Docker
Chaos Toolkit
```

---

# Useful Commands

R2 FRR CLI:

```bash
docker exec -it clab-bgp-chaos-r2-frr vtysh
```

R4 FRR CLI:

```bash
docker exec -it clab-bgp-chaos-r4-frr vtysh
```

BGP Summary:

```bash
docker exec clab-bgp-chaos-r2-frr \
  vtysh -c 'show bgp summary'
```

BFD:

```bash
docker exec clab-bgp-chaos-r2-frr \
  vtysh -c 'show bfd peers'
```

SNMP BGP4-MIB:

```bash
docker exec clab-bgp-chaos-r2-frr \
  snmpwalk -v2c -c public -On \
  127.0.0.1 .1.3.6.1.2.1.15
```

Interface Discovery確認:

```bash
docker exec clab-bgp-chaos-r2-frr \
  snmpwalk -v2c -c public -On \
  127.0.0.1 .1.3.6.1.2.1.2.2.1.2
```

R2 eth2 Down:

```bash
docker exec clab-bgp-chaos-r2-frr \
  ip link set dev eth2 down
```

R2 eth2 Up:

```bash
docker exec clab-bgp-chaos-r2-frr \
  ip link set dev eth2 up
```

R2-R4 100% Loss:

```bash
containerlab tools netem set \
  -n clab-bgp-chaos-r2-frr \
  -i eth2 \
  --loss 100
```

Netem Reset:

```bash
containerlab tools netem reset \
  -n clab-bgp-chaos-r2-frr \
  -i eth2
```

Chaos Toolkit:

```bash
cd ~/labs/chaos
source .venv/bin/activate
```

Experiment実行:

```bash
chaos run experiment.yaml
```

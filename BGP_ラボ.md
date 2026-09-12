# BGP Chaos Lab

GoBGP と FRRouting（FRR）を使用してBGPネットワークを構築し、経路制御、データプレーン、監視、障害注入、経路収束を観測するための検証環境です。

現在は Raspberry Pi / Docker / Containerlab 上で以下の4ノード構成を動作させています。

```text
R1 GoBGP ── R2 FRR ── R4 FRR ── R3 GoBGP
```

GoBGPノードではBGP Control Planeだけでなく、FRR Zebraを利用して学習経路をLinux FIBへ反映しています。

これにより、

```text
BGP Update
    ↓
GoBGP RIB
    ↓
Zebra
    ↓
Linux FIB
    ↓
実際のPacket Forwarding
```

まで一連の動作を確認できます。

最終的には、リンク障害、BGPセッション断、Prefix Withdraw、パケットロス、遅延、ルーティングポリシー変更などを意図的に発生させ、Control Plane、Data Plane、監視システムがどのように反応するかを時系列で評価できる環境を目指します。

---

## Goals

主な目的は以下です。

* GoBGP / FRR間でのBGP相互接続
* iBGP / eBGP双方の動作確認
* BGP経路のAdvertise / Withdrawの観測
* GoBGP RIBとLinux FIBの連携確認
* 実際のデータプレーン到達性確認
* BGP収束時間の計測
* SNMP / SNMP Trapによる監視
* NETCONF / YANGベースの管理
* BMP等によるBGP状態の観測
* Prometheus / Grafana等による監視
* `tc netem` 等を利用した障害注入
* Chaos Engineering的なネットワーク障害試験
* 実験結果の時系列記録

---

# Current Topology

現在は以下の直列構成です。

```text
                         AS65001

     R1                                     R2
 ┌──────────┐       iBGP             ┌────────────┐
 │  GoBGP   │────────────────────────│    FRR     │
 │ + Zebra  │                        │            │
 └──────────┘                        └─────┬──────┘
                                         │
                                         │ eBGP
                                         │
                                   ┌─────┴──────┐
                                   │    FRR     │
                                   │     R4     │
                                   └─────┬──────┘
                                         │
                                         │ iBGP
                                         │
                                   ┌─────┴──────┐
                                   │   GoBGP    │
                                   │  + Zebra   │
                                   │     R3     │
                                   └────────────┘

                         AS65002
```

経路伝播は以下です。

```text
R1 GoBGP
   ↓ iBGP
R2 FRR
   ↓ eBGP
R4 FRR
   ↓ iBGP
R3 GoBGP
```

逆方向も同様です。

---

# AS Design

```text
AS65001
├── R1 GoBGP
└── R2 FRR

AS65002
├── R3 GoBGP
└── R4 FRR
```

Private ASNを使用します。

```text
AS65001
AS65002
```

---

# Node Roles

## R1 / R3: GoBGP + Zebra

R1とR3はGoBGPをBGP Control Planeとして使用します。

主な用途は以下です。

* テスト用PrefixのAdvertise
* Prefix Withdraw
* BGP経路学習
* Community付与
* MED変更
* AS-PATH操作
* 大量Prefix注入
* API経由でのBGP操作
* Chaos試験のトリガー

GoBGP単体では、BGP RIBに存在する経路がLinux Kernel FIBへ自動的に反映されません。

そのため現在はFRR Zebraを同一コンテナ内で動作させています。

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

FRRの `bgpd` は使用していません。

ZebraはGoBGPが選択した経路をLinux Kernelへ反映するために使用します。

---

## R2 / R4: FRRouting

R2とR4は通常のLinuxルータとしてFRRを使用します。

基本構成は以下です。

```text
FRR bgpd
   |
   v
FRR Zebra
   |
   v
Linux Kernel FIB
```

主な観測対象は以下です。

* iBGP
* eBGP
* BGP best path
* RIB
* FIB
* Next-Hop
* Route Policy
* 障害発生時の経路変化
* SNMP
* NETCONF / YANG

---

# Naming Convention

Node IDは以下で固定しています。

```text
r1-gobgp
r2-frr
r3-gobgp
r4-frr
```

ASNはNode名に含めません。

Containerlab上のコンテナ名は以下です。

```text
clab-bgp-chaos-r1-gobgp
clab-bgp-chaos-r2-frr
clab-bgp-chaos-r3-gobgp
clab-bgp-chaos-r4-frr
```

---

# Management Network

Management Networkは以下です。

```text
172.20.20.0/24
```

現在のManagement IPは以下です。

```text
R1  172.20.20.11
R2  172.20.20.12
R3  172.20.20.21
R4  172.20.20.22
```

Management Networkは以下に使用します。

* Container管理
* SNMP
* NETCONF
* Telemetry
* Monitoring
* 将来的なCollector接続

---

# Router ID

Router IDは以下です。

```text
R1  10.255.0.1
R2  10.255.0.2
R3  10.255.0.3
R4  10.255.0.4
```

R2 / R4ではLoopbackにもRouter ID用アドレスを設定しています。

```text
R2 lo  10.255.0.2/32
R4 lo  10.255.0.4/32
```

R1 / R3ではGoBGP設定上のRouter IDとして使用しています。

---

# Point-to-Point Address Design

Point-to-Pointリンクには `/31` を使用しています。

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

---

# Service Prefix

GoBGPノードから試験用サービスPrefixを広告します。

```text
R1
  10.100.1.1/32

R3
  10.100.3.1/32
```

Linux Loopbackにも同じIPを設定しています。

```bash
# R1
ip addr add 10.100.1.1/32 dev lo

# R3
ip addr add 10.100.3.1/32 dev lo
```

これにより、単なるBGP RIB確認だけでなく、実際にサービスIP同士のEnd-to-End通信を確認できます。

---

# Address Summary

| Node | Implementation |   ASN | Router ID  | Management   | Link Address             | Service Prefix |
| ---- | -------------- | ----: | ---------- | ------------ | ------------------------ | -------------- |
| R1   | GoBGP + Zebra  | 65001 | 10.255.0.1 | 172.20.20.11 | 10.0.1.0/31              | 10.100.1.1/32  |
| R2   | FRR            | 65001 | 10.255.0.2 | 172.20.20.12 | 10.0.1.1/31, 10.0.2.0/31 | -              |
| R3   | GoBGP + Zebra  | 65002 | 10.255.0.3 | 172.20.20.21 | 10.0.3.1/31              | 10.100.3.1/32  |
| R4   | FRR            | 65002 | 10.255.0.4 | 172.20.20.22 | 10.0.2.1/31, 10.0.3.0/31 | -              |

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

R1からサービスPrefixを広告します。

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

# GoBGP and Zebra

現在のGoBGPコンテナでは、GoBGPとFRR Zebraを同じコンテナ内で動かしています。

現在使用しているZebraはFRR 8.4.4です。

```text
GoBGP 4.7.0
    |
    | ZAPI v6
    v
FRR Zebra 8.4.4
    |
    v
Linux Kernel
```

実際にIPv4 Unicast RouteのFIB反映が動作することを確認済みです。

R1では、

```text
10.100.3.1 via 10.0.1.1 dev eth1 proto bgp
```

R3では、

```text
10.100.1.1 via 10.0.3.0 dev eth1 proto bgp
```

がLinux Routing Tableへ登録されます。

---

# FRR Configuration

## R2

```text
frr defaults traditional
hostname r2-frr
service integrated-vtysh-config
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
router bgp 65001
 bgp router-id 10.255.0.2
 no bgp ebgp-requires-policy
 neighbor 10.0.1.0 remote-as 65001
 neighbor 10.0.2.1 remote-as 65002
 !
 address-family ipv4 unicast
  neighbor 10.0.1.0 activate
  neighbor 10.0.1.0 next-hop-self
  neighbor 10.0.2.1 activate
 exit-address-family
!
line vty
!
```

## R4

```text
frr defaults traditional
hostname r4-frr
service integrated-vtysh-config
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
router bgp 65002
 bgp router-id 10.255.0.4
 no bgp ebgp-requires-policy
 neighbor 10.0.2.0 remote-as 65001
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

---

# Current BGP State

現在、以下のBGP SessionはすべてEstablishedになることを確認済みです。

```text
R1 GoBGP ── iBGP ── R2 FRR
R2 FRR   ── eBGP ── R4 FRR
R4 FRR   ── iBGP ── R3 GoBGP
```

サービスPrefixも両方向に伝播します。

R1:

```text
10.100.1.1/32 local
10.100.3.1/32 via 10.0.1.1 AS_PATH 65002
```

R3:

```text
10.100.1.1/32 via 10.0.3.0 AS_PATH 65001
10.100.3.1/32 local
```

---

# End-to-End Data Plane

サービスPrefixをSource IPとして指定したEnd-to-End Pingが両方向で成功することを確認済みです。

R1 → R3:

```bash
ping -I 10.100.1.1 10.100.3.1
```

R3 → R1:

```bash
ping -I 10.100.3.1 10.100.1.1
```

経路は以下のように流れます。

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

送信元IPを指定しないPingでは、LinuxがPoint-to-Point InterfaceのIPをSourceとして選択する場合があります。

そのPrefixはBGP広告していないため、戻り経路が存在せず失敗する場合があります。

そのためサービス到達性試験では `-I` でService Prefixを明示します。

---

# FRR Management Extensions

FRRノードでは、通常のBGP機能に加えてManagement Planeの検証を進めています。

現在の公式FRR 10.7.0コンテナイメージには、SNMP / Sysrepo機能が含まれていません。

そのため以下を有効化したカスタムイメージを作成しています。

```text
frr-lab:10.7.0-snmp-netconf
```

FRR Build Option:

```text
--enable-snmp
--enable-sysrepo
```

追加コンポーネント:

```text
Net-SNMP
Sysrepo
libnetconf2
Netopeer2
```

---

# Current FRR Management Test

現在はR2のみカスタムFRRイメージへ変更し、Management機能を検証しています。

R2では以下のmoduleがロードできることを確認済みです。

```text
zebra -M snmp -M sysrepo
bgpd -M snmp -M sysrepo
staticd -M sysrepo
```

FRR moduleも存在します。

```text
bgpd_snmp.so
zebra_snmp.so
sysrepo.so
```

R4は現時点では通常のFRR 10.7.0イメージを使用しています。

R2で動作確認後、必要に応じてR4にも同じManagement機能を追加します。

---

# SNMP Architecture

FRR自身がSNMP Master Agentになるわけではありません。

構成は以下です。

```text
FRR bgpd / zebra
       |
       | AgentX
       v
    Net-SNMP
      snmpd
       |
       +── SNMP GET / WALK
       |
       └── SNMP Trap
```

FRR側ではSNMP moduleをロードします。

```text
bgpd_options="-M snmp -M sysrepo"
zebra_options="-M snmp -M sysrepo"
staticd_options="-M sysrepo"
```

FRR設定にはAgentXを有効化します。

```text
agentx
```

---

# SNMP Configuration

`snmpd.conf` はFRR設定とは別です。

これはNet-SNMPの `snmpd` 用設定ファイルです。

```text
/etc/snmp/snmpd.conf
```

基本設定:

```conf
master agentx
agentAddress udp:161
rocommunity public
```

Trap Receiverを設定する場合は以下を追加します。

```conf
trap2sink 172.20.20.100 public
```

構成:

```text
FRR
 ↓ AgentX
snmpd
 ↓ UDP/162
Trap Receiver
```

Trap ReceiverのIPは環境ごとに変わるため、`snmpd.conf` はDocker Imageへ固定で埋め込まず、Containerlabからbind mountして管理する方針とします。

```yaml
binds:
  - ./configs/r2-frr/snmpd.conf:/etc/snmp/snmpd.conf:ro
```

`snmpd` はFRRとは別processなので、明示的に起動する必要があります。

```yaml
exec:
  - snmpd
```

---

# NETCONF Architecture

NETCONFは以下の構成を使用します。

```text
NETCONF Client
      |
      | SSH / NETCONF
      v
Netopeer2
      |
      v
Sysrepo
      |
      v
FRR Sysrepo Plugin
      |
      v
FRR
```

役割は以下です。

```text
Netopeer2
  NETCONF Server

Sysrepo
  YANG Datastore

FRR sysrepo module
  FRRとSysrepoの連携
```

FRR側では、

```text
-M sysrepo
```

を指定してSysrepo moduleをロードします。

NETCONF runtimeの起動・YANG module登録については現在検証中です。

---

# Container Images

## GoBGP

```text
gobgp-lab:v4.7.0
```

内容:

```text
GoBGP 4.7.0
FRR Zebra 8.4.4
iproute2
ping
tcpdump
その他検証用ツール
```

## FRR Standard

```text
quay.io/frrouting/frr:10.7.0
```

現在R4で使用しています。

## FRR Management Extended

```text
frr-lab:10.7.0-snmp-netconf
```

現在R2で検証しています。

内容:

```text
FRR 10.7.0
SNMP module
Sysrepo module
Net-SNMP
Sysrepo
libnetconf2
Netopeer2
```

---

# Monitoring Architecture

今後は以下の監視構成を追加します。

```text
                 Monitoring / Management

          ┌──────────────────────────┐
          │ SNMP / Trap Receiver     │
          │ NETCONF Client           │
          │ Prometheus               │
          │ Grafana                  │
          │ BMP Collector            │
          │ Packet Capture           │
          └────────────▲─────────────┘
                       │
        SNMP / NETCONF / Metrics / BMP
                       │

GoBGP ───── FRR ───── FRR ───── GoBGP
```

---

# Observation Layers

## Link

```text
Interface Up / Down
Packet Count
Packet Loss
Latency
Drop
```

## BGP Session

```text
Idle
Connect
Active
OpenSent
OpenConfirm
Established
```

## Routing

```text
Prefix Received
Prefix Advertised
Best Path
Withdraw
Next-Hop
RIB
FIB
```

## Data Plane

```text
Ping
Packet Loss
RTT
Actual Traffic
```

## Management

```text
SNMP GET
SNMP WALK
SNMP Trap
NETCONF
YANG
```

## System

```text
CPU
Memory
Process
Container
```

---

# Chaos Engineering

障害注入は監視システムから独立した仕組みとします。

候補:

```text
Interface Down
Link Down
Container Stop
BGP Daemon Kill
TCP/179 Drop
Packet Loss
Latency
Packet Reorder
Packet Duplication
Packet Corruption
Bandwidth Limitation
CPU Pressure
Memory Pressure
MTU Mismatch
Route Policy Change
Prefix Withdraw
Route Leak
Local Preference Change
MED Change
AS-PATH Prepend
```

Linuxの `tc netem` を利用します。

Packet Loss:

```bash
tc qdisc add dev eth1 root netem loss 20%
```

Delay:

```bash
tc qdisc add dev eth1 root netem delay 500ms
```

解除:

```bash
tc qdisc del dev eth1 root
```

---

# BGP Withdraw Experiment

現在の構成では、R3のService PrefixをWithdrawすると、

```text
R3 GoBGP
  10.100.3.1/32 Withdraw
        |
        v
R4 FRR
        |
        v
R2 FRR
        |
        v
R1 GoBGP RIB
        |
        v
Zebra
        |
        v
R1 Linux FIB
```

という流れで経路が消えることを観測できます。

期待する観測点:

```text
T0  Prefix Withdraw

T1  R4 BGP RIBから削除

T2  R2 BGP RIBから削除

T3  R1 GoBGP RIBから削除

T4  R1 Linux FIBから削除

T5  End-to-End Ping停止
```

再Advertiseすると逆方向に復旧します。

---

# Experiment Naming

各障害試験にはIDを付与します。

```text
exp-001-r2-r4-linkdown
exp-002-r2-r4-loss20
exp-003-r4-bgpd-kill
exp-004-r1-prefix-withdraw
exp-005-r2-r4-delay500ms
```

Telemetryやログにも同じExperiment IDを付与できる構成を目指します。

```text
experiment="exp-002"
node="r2-frr"
peer="r4-frr"
link="r2-r4"
asn="65001"
```

---

# Metrics to Measure

障害発生からの時間を計測します。

```text
T0  Failure Injected

T1  Packet Loss Detected

T2  BGP Session Down

T3  Route Withdrawn

T4  Alternate Route Selected

T5  Data Plane Recovered

T6  Monitoring Alert Fired
```

主な評価指標:

```text
BGP Failure Detection Time
Routing Convergence Time
Data Plane Outage Time
Monitoring Detection Time
Alert Delay
```

---

# Current Status

現在確認済み:

```text
[OK] R1-R2 iBGP Established
[OK] R2-R4 eBGP Established
[OK] R4-R3 iBGP Established

[OK] R1 10.100.1.1/32 Advertise
[OK] R3 10.100.3.1/32 Advertise

[OK] R1 → R3 BGP経路伝播
[OK] R3 → R1 BGP経路伝播

[OK] GoBGP RIB → Zebra → Linux FIB
[OK] R1 → R3 Service IP Ping
[OK] R3 → R1 Service IP Ping

[OK] FRR SNMP module build
[OK] FRR Sysrepo module build
[OK] R2でSNMP/Sysrepo module load

[WIP] snmpdの起動・外部設定化
[WIP] SNMP Trap Receiver連携
[WIP] Sysrepo / Netopeer2 runtime integration
[WIP] NETCONF接続確認
```

---

# Next Steps

現在の優先順位は以下です。

```text
1. R2 SNMP動作確認
   - snmpd起動
   - UDP/161
   - SNMP WALK

2. SNMP Trap
   - trap2sink
   - BGP Peer Down / Up Trap確認

3. NETCONF
   - Sysrepo初期化
   - FRR YANG登録
   - Netopeer2起動
   - TCP/830
   - NETCONF hello / get確認

4. R4へ同一Management機能展開

5. BGP Withdraw / Session Downを使ったChaos試験

6. Prometheus / Grafana / BMP等の監視追加

7. 冗長経路追加
```

---

# Future Redundant Topology

現在は経路変化を追いやすくするため直列構成ですが、将来的には冗長経路を追加します。

```text
R1 ───── R2
│         │
│         │
R3 ───── R4
```

これにより以下を検証します。

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
Linux
Docker
Containerlab
```

ContainerlabはTopology、仮想リンク、Container配置の管理に使用しています。

Routing機能そのものは、

```text
GoBGP
FRR
Linux Kernel
```

が担当します。

今後も実験内容に応じて実行基盤は変更可能とします。

---
```
docker exec -it clab-bgp-chaos-r2-frr vtysh
```

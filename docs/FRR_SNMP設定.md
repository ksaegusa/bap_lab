# Containerlab上のFRRでSNMPを有効化し、BGP Trapを確認する手順

## 1. 目的

Containerlab 上で動かす FRR ノードに対して、以下を有効化する。

- SNMP GET/WALK
- FRR の BGP4-MIB 取得
- BGP peer の状態変化による SNMP Trap
- Trap receiver 側で UDP/162 を確認

構成:

```text
Containerlab
  │
  └─ FRR container
       │
       ├─ bgpd / zebra
       │    │
       │    │ AgentX
       │    ▼
       │  /var/agentx/master
       │    │
       │    ▼
       │  snmpd
       │    │
       │    ├─ UDP/161 SNMP GET/WALK
       │    └─ UDP/162 SNMP Trap
       │
       └─ management network
```

BGP Trap の流れ:

```text
BGP peer state change
        │
        ▼
      bgpd
        │
        │ AgentX
        ▼
      snmpd
        │
        │ trap2sink
        ▼
   Trap receiver
```

---

# 2. 設定する場所

設定場所は4種類に分かれる。

| 場所 | 例 | 役割 |
|---|---|---|
| Containerlab YAML | `lab.clab.yml` | FRR image、bind、snmpd起動 |
| FRR設定 | `frr.conf` | BGP設定、AgentX有効化 |
| FRR daemon設定 | `daemons` | `-M snmp` でSNMP moduleをロード |
| Net-SNMP設定 | `snmpd.conf` | AgentX master、UDP/161、Trap送信 |
| Containerlabホスト | `/etc/apparmor.d/bgpd` | bgpdのAgentX socketアクセス許可 |

重要:

```text
Containerlab YAML
FRR設定
Net-SNMP設定
ホストOS設定
```

は別物として管理する。

---

# 3. ディレクトリ構成例

```text
lab/
├── lab.clab.yml
└── configs/
    ├── snmpd.conf
    ├── router1/
    │   ├── frr.conf
    │   └── daemons
    └── router2/
        ├── frr.conf
        └── daemons
```

`snmpd.conf` は複数FRRノードで共通化できる。

---

# 4. Containerlab YAML

FRRノードは `kind: linux` で起動する。

例:

```yaml
name: frr-snmp-lab

topology:
  nodes:
    router1:
      kind: linux
      image: frr-lab:10.7.0-snmp-netconf
      binds:
        - ./configs/router1/frr.conf:/etc/frr/frr.conf
        - ./configs/router1/daemons:/etc/frr/daemons
        - ./configs/snmpd.conf:/etc/snmp/snmpd.conf
      exec:
        - snmpd

    router2:
      kind: linux
      image: frr-lab:10.7.0-snmp-netconf
      binds:
        - ./configs/router2/frr.conf:/etc/frr/frr.conf
        - ./configs/router2/daemons:/etc/frr/daemons
        - ./configs/snmpd.conf:/etc/snmp/snmpd.conf
      exec:
        - snmpd
```

Containerlab YAML で行うこと:

```text
FRR imageを指定
frr.confをbind
daemonsをbind
snmpd.confをbind
snmpdを起動
```

通常運用では、deploy後に各コンテナへ入って `snmpd` を手動起動しない。

---

# 5. FRR imageの条件

FRRはSNMP対応でビルドされている必要がある。

configure option:

```text
--enable-snmp
```

SNMP moduleの存在確認:

```bash
find /usr/lib/frr -name '*_snmp.so'
```

例:

```text
/usr/lib/frr/modules/bgpd_snmp.so
/usr/lib/frr/modules/zebra_snmp.so
```

---

# 6. `daemons`

各FRRノードの `/etc/frr/daemons` へ bind する。

最低限:

```text
zebra=yes
bgpd=yes
staticd=yes

vtysh_enable=yes

zebra_options="-M snmp"
bgpd_options="-M snmp"
staticd_options=""
```

重要:

```text
zebra_options="-M snmp"
bgpd_options="-M snmp"
```

これによりFRRのSNMP moduleがロードされる。

確認:

```bash
docker exec <FRR_CONTAINER> \
  vtysh -c 'show modules'
```

期待:

```text
zebra_snmp
bgpd_snmp
```

---

# 7. `frr.conf`

FRR側ではグローバル設定に:

```text
agentx
```

を入れる。

例:

```text
frr defaults traditional
hostname router
service integrated-vtysh-config
agentx
!
interface lo
 ip address 10.255.0.1/32
!
router bgp 65000
 bgp router-id 10.255.0.1
 no bgp ebgp-requires-policy
 neighbor 10.0.0.2 remote-as 65001
 !
 address-family ipv4 unicast
  neighbor 10.0.0.2 activate
 exit-address-family
!
line vty
!
```

確認:

```bash
docker exec <FRR_CONTAINER> \
  vtysh -c 'show running-config' | grep -i agentx
```

期待:

```text
agentx
```

---

# 8. BGP Trap設定について

RFC4273のBGP TrapはFRRではデフォルト有効なので、今回の構成では明示設定不要。

次を `router bgp` 配下へ入れない。

```text
router bgp 65000
 bgp snmp traps rfc4273
```

この位置に入れると設定読み込みに失敗する。

例:

```text
Configuration file[/etc/frr/frr.conf] processing failure
```

その結果:

```text
% No BGP neighbors found in VRF default
```

となり、BGP Trap以前にBGP自体が動かなくなる。

---

# 9. 共通 `snmpd.conf`

Containerlab YAMLで各FRRノードへ bind する。

```conf
master agentx

agentXSocket /var/agentx/master
agentXPerms 0777 0755

agentAddress udp:161

rocommunity public

trap2sink <TRAP_RECEIVER_IP> public
```

例:

```conf
master agentx

agentXSocket /var/agentx/master
agentXPerms 0777 0755

agentAddress udp:161

rocommunity public

trap2sink 172.20.20.1 public
```

意味:

```text
master agentx
    snmpdをAgentX masterにする

agentXSocket /var/agentx/master
    FRRが接続するAgentX socket

agentXPerms 0777 0755
    socket=0777
    directory=0755

agentAddress udp:161
    SNMP GET/WALK受信用

rocommunity public
    SNMPv2c community

trap2sink <IP> public
    Trap送信先
```

Containerlab側では:

```yaml
exec:
  - snmpd
```

として起動する。

---

# 10. Containerlabホスト側のAppArmor設定

UbuntuホストでAppArmorがFRR `bgpd` に適用されている場合、AgentX socket接続が拒否されることがある。

確認:

```bash
sudo aa-status | grep -A5 -B5 bgpd
```

またはコンテナ内から:

```bash
docker exec <FRR_CONTAINER> sh -c '
PID=$(pidof bgpd)
cat /proc/$PID/attr/current
'
```

例:

```text
bgpd (enforce)
```

ホストkernel log:

```bash
sudo journalctl -k --since "10 minutes ago" | \
  grep -iE 'apparmor|DENIED|bgpd'
```

拒否例:

```text
apparmor="DENIED"
operation="connect"
profile="bgpd"
name="/var/agentx/master"
requested_mask="wr"
denied_mask="wr"
```

この場合、Containerlabホスト側の:

```text
/etc/apparmor.d/bgpd
```

に追加する。

```text
/var/agentx/ r,
/var/agentx/master rw,
```

反映:

```bash
sudo apparmor_parser -r /etc/apparmor.d/bgpd
```

これはContainerlabコンテナごとではなく、ホストOS側で行う。

---

# 11. ラボをdeployする

設定後:

```bash
sudo containerlab deploy \
  --topo lab.clab.yml
```

設定変更後にcleanな状態から確認したい場合:

```bash
sudo containerlab destroy \
  --topo lab.clab.yml \
  --cleanup
```

再deploy:

```bash
sudo containerlab deploy \
  --topo lab.clab.yml
```

---

# 12. snmpd起動確認

対象FRRコンテナ:

```bash
docker exec <FRR_CONTAINER> \
  ps aux | grep '[s]nmpd'
```

UDP/161:

```bash
docker exec <FRR_CONTAINER> \
  ss -lunp | grep ':161'
```

AgentX socket:

```bash
docker exec <FRR_CONTAINER> \
  ss -xap | grep agentx
```

期待:

```text
/var/agentx/master
```

---

# 13. AgentX permission確認

```bash
docker exec <FRR_CONTAINER> sh -c '
stat -c "%A %a %U:%G %n" \
  /var/agentx \
  /var/agentx/master
'
```

期待:

```text
drwxr-xr-x 755 ... /var/agentx
srwxrwxrwx 777 ... /var/agentx/master
```

複数FRRノードをまとめて確認する場合:

```bash
for c in $(docker ps --format '{{.Names}}' | grep frr); do
  echo "===== $c ====="
  docker exec "$c" sh -c '
    stat -c "%A %a %U:%G %n" \
      /var/agentx \
      /var/agentx/master
  '
done
```

ここで差が出ても、通常運用では個別 `chmod` で終わらせない。

`snmpd.conf`、起動状態、AppArmorを確認する。

---

# 14. SNMP agent確認

```bash
docker exec <FRR_CONTAINER> \
  snmpget -v2c -c public -On \
  127.0.0.1 .1.3.6.1.2.1.1.3.0
```

正常:

```text
.1.3.6.1.2.1.1.3.0 = Timeticks: ...
```

ここで確認できるもの:

```text
snmpd
UDP/161
community
```

AgentX確認にはならない。

---

# 15. BGP4-MIB確認

```bash
docker exec <FRR_CONTAINER> \
  snmpwalk -v2c -c public -On \
  127.0.0.1 .1.3.6.1.2.1.15
```

AgentXが動いていない場合:

```text
.1.3.6.1.2.1.15 = No Such Object available on this agent at this OID
```

正常例:

```text
.1.3.6.1.2.1.15.2.0 = INTEGER: 65000
.1.3.6.1.2.1.15.4.0 = IpAddress: 10.255.0.1
```

ここまで取れれば:

```text
bgpd
  ↓ AgentX
snmpd
```

は正常。

---

# 16. BGP状態確認

Trap試験前に対象peerが `Established` している必要がある。

```bash
docker exec <FRR_CONTAINER> \
  vtysh -c 'show bgp summary'
```

対象neighborが存在し、Establishedしていることを確認する。

もし:

```text
% No BGP neighbors found
```

なら、SNMP TrapではなくFRR設定の問題。

---

# 17. Trap receiver側でtcpdump

ContainerlabホストまたはTrap receiverで:

```bash
sudo tcpdump -ni any udp port 162 -vvv
```

送信元を対象FRRノードに限定する場合:

```bash
sudo tcpdump -ni any \
  'udp port 162 and src host <FRR_MGMT_IP>' \
  -vvv
```

Docker bridgeを指定できる場合:

```bash
sudo tcpdump -ni <CONTAINERLAB_BRIDGE> \
  'udp port 162 and src host <FRR_MGMT_IP>' \
  -vvv
```

`-i any` はvethとbridgeの両方で同じパケットを表示することがある。

---

# 18. BGP Trapを発生させる

対象peerが使用しているinterfaceを確認:

```bash
docker exec <FRR_CONTAINER> \
  ip -br addr
```

対象peerがEstablishedしている状態で:

```bash
docker exec <FRR_CONTAINER> \
  ip link set <INTERFACE> down
```

BGP状態確認:

```bash
docker exec <FRR_CONTAINER> \
  vtysh -c 'show bgp summary'
```

対象peerがEstablishedから外れたことを確認する。

戻す:

```bash
docker exec <FRR_CONTAINER> \
  ip link set <INTERFACE> up
```

再度:

```bash
docker exec <FRR_CONTAINER> \
  vtysh -c 'show bgp summary'
```

Establishedへ戻ることを確認する。

---

# 19. tcpdumpでBGP Trapを確認する

BGP Established Trap:

```text
snmpTrapOID.0 = .1.3.6.1.2.1.15.0.1
```

これは `bgpEstablished`。

Trap内にはpeer情報も入る。

例:

```text
.1.3.6.1.2.1.15.3.1.7.<index> = <peer-address>
```

state:

```text
.1.3.6.1.2.1.15.3.1.2.<index> = 6
```

`6 = Established`。

正常経路:

```text
BGP state change
      ↓
    bgpd
      ↓ AgentX
    snmpd
      ↓ UDP/162
Trap receiver
```

---

# 20. coldStart Trapとの違い

`snmpd` 起動時に:

```text
snmpTrapOID.0 = .1.3.6.1.6.3.1.1.5.1
```

が送られることがある。

これは `coldStart`。

BGP Trapではない。

```text
coldStart
snmpd
  ↓
Trap receiver
```

BGP Trap:

```text
bgpd
  ↓ AgentX
snmpd
  ↓
Trap receiver
```

Trap判別では必ず:

```text
snmpTrapOID.0
```

を見る。

---

# 21. `No Such Object` の場合

確認順序:

## 21.1 FRR SNMP module

```bash
docker exec <FRR_CONTAINER> \
  vtysh -c 'show modules'
```

確認:

```text
bgpd_snmp
```

---

## 21.2 AgentX設定

```bash
docker exec <FRR_CONTAINER> \
  vtysh -c 'show running-config' | grep -i agentx
```

期待:

```text
agentx
```

---

## 21.3 AgentX master

```bash
docker exec <FRR_CONTAINER> \
  ss -xap | grep agentx
```

---

## 21.4 socket permission

```bash
docker exec <FRR_CONTAINER> sh -c '
stat -c "%A %a %U:%G %n" \
  /var/agentx \
  /var/agentx/master
'
```

---

## 21.5 AppArmor

Containerlabホスト:

```bash
sudo journalctl -k --since "10 minutes ago" | \
  grep -iE 'apparmor|DENIED|bgpd'
```

---

# 22. `strace`でAgentX接続を確認する

障害調査時のみ。

Alpine系FRR image:

```bash
docker exec -u 0 <FRR_CONTAINER> \
  apk add --no-cache strace
```

attach:

```bash
docker exec -it -u 0 <FRR_CONTAINER> \
  strace -f -e trace=connect \
  -p $(docker exec <FRR_CONTAINER> pidof bgpd)
```

AppArmor拒否時の例:

```text
connect(... "/var/agentx/master" ...) = -1 EACCES
```

この場合は:

```text
Unix permission
AppArmor
```

を確認する。

---

# 23. snmpdをforeground debugするとき

障害調査時のみ。

既存snmpd確認:

```bash
docker exec <FRR_CONTAINER> sh -c '
ps aux | grep "[s]nmpd" || true
ss -lunp | grep ":161" || true
'
```

停止:

```bash
docker exec <FRR_CONTAINER> \
  pkill snmpd || true
```

停止確認:

```bash
docker exec <FRR_CONTAINER> sh -c '
ps aux | grep "[s]nmpd" || true
ss -lunp | grep ":161" || true
'
```

UDP/161 listenerが消えてから:

```bash
docker exec -it <FRR_CONTAINER> \
  snmpd -f -Lo -Dagentx
```

正常:

```text
Turning on AgentX master support.
agentx/config: port spec: /var/agentx/master
agentx/config: socket permissions: 777
agentx/config: directory permissions: 755
agentx/master: initializing... DONE
```

もし:

```text
Error opening specified endpoint "...:161"
```

ならAgentXではなくUDP/161競合。

---

# 24. Containerlabでの最短手順

## 1. FRR image

SNMP有効ビルド:

```text
--enable-snmp
```

---

## 2. `daemons`

```text
zebra_options="-M snmp"
bgpd_options="-M snmp"
```

---

## 3. `frr.conf`

```text
agentx
```

---

## 4. 共通 `snmpd.conf`

```conf
master agentx
agentXSocket /var/agentx/master
agentXPerms 0777 0755

agentAddress udp:161
rocommunity public

trap2sink <TRAP_RECEIVER_IP> public
```

---

## 5. Containerlab YAML

```yaml
binds:
  - ./configs/<router>/frr.conf:/etc/frr/frr.conf
  - ./configs/<router>/daemons:/etc/frr/daemons
  - ./configs/snmpd.conf:/etc/snmp/snmpd.conf

exec:
  - snmpd
```

---

## 6. AppArmorが有効ならホストで1回

`/etc/apparmor.d/bgpd`:

```text
/var/agentx/ r,
/var/agentx/master rw,
```

反映:

```bash
sudo apparmor_parser -r /etc/apparmor.d/bgpd
```

---

## 7. deploy

```bash
sudo containerlab deploy \
  --topo lab.clab.yml
```

---

## 8. SNMP確認

```bash
docker exec <FRR_CONTAINER> \
  snmpget -v2c -c public -On \
  127.0.0.1 .1.3.6.1.2.1.1.3.0
```

---

## 9. BGP4-MIB確認

```bash
docker exec <FRR_CONTAINER> \
  snmpwalk -v2c -c public -On \
  127.0.0.1 .1.3.6.1.2.1.15
```

---

## 10. BGP確認

```bash
docker exec <FRR_CONTAINER> \
  vtysh -c 'show bgp summary'
```

---

## 11. Trap受信

```bash
sudo tcpdump -ni any udp port 162 -vvv
```

---

## 12. BGPイベント発生

```bash
docker exec <FRR_CONTAINER> \
  ip link set <INTERFACE> down

docker exec <FRR_CONTAINER> \
  ip link set <INTERFACE> up
```

---

## 13. Trap確認

期待:

```text
snmpTrapOID.0 = .1.3.6.1.2.1.15.0.1
```

これが確認できれば、Containerlab上のFRRで:

```text
SNMP
AgentX
BGP4-MIB
BGP Trap
UDP/162受信
```

まで正常。

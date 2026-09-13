# Zabbixでネットワーク機器のSNMP Trapを監視する方法

## 1. 概要

Zabbixでネットワーク機器のSNMP Trapを監視する場合、大きく以下の2パターンがあります。

1. **Zabbix Serverで直接SNMP Trapを受信する**
2. **Zabbix Proxy経由でSNMP Trapを受信する**

SNMP Trapでは通常、ネットワーク機器から監視側へ **UDP/162** で通知されます。

```text
Network Device
    |
    | UDP/162
    v
SNMP Trap Receiver
    |
    v
Zabbix
```

SNMP pollingで使用するUDP/161とは方向と用途が異なります。

```text
SNMP polling:
Zabbix → Device : UDP/161

SNMP Trap:
Device → Zabbix : UDP/162
```

---

# 2. パターン1: Zabbix Serverで直接Trapを受信する

## 2.1 構成

Zabbix Serverがネットワーク機器から直接SNMP Trapを受信できる場合の構成です。

```text
Router / Switch / Firewall
          |
          | UDP/162
          v
+-------------------------+
| Zabbix環境              |
|                         |
| zabbix-snmptraps        |
|        |                |
|        | trap file      |
|        v                |
| zabbix-server           |
|        |                |
|        v                |
| PostgreSQL              |
|                         |
| zabbix-web              |
+-------------------------+
```

今回のDocker構成では、SNMP Trap receiverをhost networkで動作させています。

```text
Network Device
172.20.20.12
      |
      | UDP/1162
      v
Host
172.20.20.1
      |
      v
zabbix-snmptraps
      |
      | shared volume
      v
zabbix-server
```

Trap receiverのログでは、送信元IPが以下のように維持される必要があります。

```text
ZBXTRAP 172.20.20.12
```

---

## 2.2 送信元IPについて

ZabbixのSNMP Trap監視では、Trapの送信元IPを使ってZabbix Hostを特定します。

例えば、

```text
ZBXTRAP 172.20.20.12
```

というTrapを受信した場合、ZabbixはSNMP Interfaceが

```text
172.20.20.12
```

になっているHostを探します。

そのため、Docker NATなどによって

```text
ZBXTRAP 172.18.0.1
```

のように送信元IPが変換されると、正しいHostにTrapを紐付けられません。

### 推奨

Trap receiverは以下のいずれかにします。

- host network
- 監視ネットワークに直接接続
- NATされず送信元IPを保持できる構成

---

# 3. Zabbix Host設定

例としてR2を登録します。

```text
Host name:
r2-frr

SNMP interface:
172.20.20.12

Port:
161
```

Trap監視だけの場合でも、SNMP Interfaceは必要です。

Zabbixは、

```text
ZBXTRAP 172.20.20.12
```

と

```text
SNMP Interface = 172.20.20.12
```

を照合してHostを特定します。

R4の場合は、

```text
Host name:
r4-frr

SNMP interface:
172.20.20.22

Port:
161
```

とします。

---

# 4. BGP Trap用Item

今回FRRから受信しているBGP Trapは以下です。

```text
1.3.6.1.2.1.15.0.1
BGP Established
```

```text
1.3.6.1.2.1.15.0.2
BGP Backward Transition
```

実際のTrapログでは、

```text
SNMPv2-SMI::mib-2.15.0.1
```

または

```text
SNMPv2-SMI::mib-2.15.0.2
```

として出力されています。

そのため、Zabbix Itemを以下のように設定します。

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

この正規表現は、

```text
mib-2.15.0.1
mib-2.15.0.2
```

の両方にマッチします。

---

# 5. Trigger設定

R2の場合:

```text
find(/r2-frr/snmptrap["mib-2\.15\.0\.[12]"],,"like","mib-2.15.0.2")=1
```

R4の場合:

```text
find(/r4-frr/snmptrap["mib-2\.15\.0\.[12]"],,"like","mib-2.15.0.2")=1
```

動作は以下です。

```text
mib-2.15.0.2
      |
      v
BGP Down
      |
      v
Trigger TRUE
      |
      v
PROBLEM
```

復旧時には、

```text
mib-2.15.0.1
      |
      v
BGP Established
      |
      v
Down条件がFALSE
      |
      v
RECOVERY
```

となります。

Recovery expressionを別途設定しなくても、Problem expressionがFALSEになれば通常は自動復旧します。

---

# 6. 直接受信パターンの全体像

```text
R2
172.20.20.12
      |
      | UDP/162
      v
+----------------------------+
| Zabbix Server側            |
|                            |
| snmptrapd                  |
|      |                     |
|      v                     |
| snmptraps.log              |
|      |                     |
|      v                     |
| zabbix-server              |
|      |                     |
|      v                     |
| Item                       |
| BGP state trap             |
|      |                     |
|      v                     |
| Trigger                    |
|      |                     |
|      +---- .0.2 → PROBLEM  |
|      |                     |
|      +---- .0.1 → RECOVERY |
+----------------------------+
```

---

# 7. パターン2: Zabbix Proxy経由でTrapを受信する

## 7.1 用途

以下のような環境ではZabbix Proxyを使用します。

- Zabbix ServerがOKD/Kubernetes内部にある
- ネットワーク機器からPodへUDP/162を直接到達させにくい
- FWやネットワークセグメントが分離されている
- SNMP監視対象が複数拠点に存在する
- SNMP Trapの送信元IPを保持したい

---

# 8. Proxy構成

例えばZabbix ServerをOKD上に配置し、ネットワーク管理セグメントにProxyを配置します。

```text
Network Devices
 Router
 Switch
 Firewall
     |
     | UDP/162
     v
+------------------------+
| Proxy VM / Host        |
|                        |
| zabbix-snmptraps       |
|        |               |
|        | shared volume |
|        v               |
| zabbix-proxy           |
+-----------+------------+
            |
            | TCP/10051
            v
+------------------------+
| OKD                    |
|                        |
| Zabbix Server          |
| PostgreSQL             |
| Zabbix Web             |
+------------------------+
```

重要なのは、**Zabbix ServerがProxy上のtrapファイルを直接読むわけではない**という点です。

処理は以下です。

```text
Network Device
      |
      | UDP/162
      v
snmptrapd
      |
      v
snmptraps.log
      |
      v
Zabbix Proxy
      |
      | Zabbix protocol
      | TCP/10051
      v
Zabbix Server
```

---

# 9. Zabbix Proxyの役割

Proxy側では以下を行います。

```text
SNMP Trap受信
SNMP polling
Item値の収集
一時保存
Zabbix Serverへの転送
```

Zabbix Server側では以下を行います。

```text
Trigger評価
Problem生成
Recovery生成
Action実行
通知
履歴管理
```

つまり、

```text
Proxy = データ収集担当
Server = 判定・管理担当
```

です。

---

# 10. Proxyのコンテナ構成

Zabbix Proxyはコンテナでも利用できます。

例えばZabbix 7.0では、

```text
zabbix/zabbix-proxy-sqlite3:alpine-7.0-latest
```

を使用できます。

SNMP Trap receiverには、

```text
zabbix/zabbix-snmptraps:alpine-7.0-latest
```

を使用できます。

概念的には、

```text
zabbix-snmptraps
       |
       | /var/lib/zabbix/snmptraps
       v
zabbix-proxy
```

としてTrapファイル用Volumeを共有します。

Trap receiverについては、送信元IPを保持するため、

```text
network_mode: host
```

などの構成が候補になります。

---

# 11. Active Proxy

OKDなどと組み合わせる場合はActive Proxyが扱いやすい構成です。

通信方向は、

```text
Zabbix Proxy
      |
      | TCP/10051
      v
Zabbix Server
```

です。

ネットワーク的には、

```text
Network Device → Proxy
UDP/162

Proxy → Zabbix Server
TCP/10051
```

を許可すればよくなります。

Zabbix ServerからProxyへ接続する必要がないため、FW越しでも構成しやすくなります。

---

# 12. ProxyのZabbix登録

Zabbix UIでProxyを登録します。

```text
Administration
→ Proxies
→ Create proxy
```

例:

```text
Proxy name:
proxy-net01

Mode:
Active
```

Proxyコンテナ側のHostnameも、

```text
proxy-net01
```

に一致させます。

---

# 13. Proxy配下のHost設定

R2の場合:

```text
Host name:
r2-frr

Monitored by:
Proxy

Proxy:
proxy-net01

SNMP interface:
172.20.20.12

Port:
161
```

R4の場合:

```text
Host name:
r4-frr

Monitored by:
Proxy

Proxy:
proxy-net01

SNMP interface:
172.20.20.22

Port:
161
```

直接受信との大きな違いは、

```text
Monitored by:
Proxy
```

を設定する点です。

---

# 14. Proxy利用時のItem

Item自体は直接受信時と同じです。

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

ProxyだからItem keyを変更する必要はありません。

---

# 15. Proxy利用時のTrigger

Triggerも同じです。

R2:

```text
find(/r2-frr/snmptrap["mib-2\.15\.0\.[12]"],,"like","mib-2.15.0.2")=1
```

R4:

```text
find(/r4-frr/snmptrap["mib-2\.15\.0\.[12]"],,"like","mib-2.15.0.2")=1
```

動作も同じです。

```text
.15.0.2
↓
PROBLEM

.15.0.1
↓
RECOVERY
```

---

# 16. Proxy利用時の送信元IP

Proxyを使用する場合でも、Trap送信元IPは非常に重要です。

正常:

```text
ZBXTRAP 172.20.20.12
```

NG例:

```text
ZBXTRAP 172.18.0.1
```

後者ではDocker/KubernetesなどのNATによって送信元IPが変換されています。

Zabbixは、

```text
Trap source IP
```

と

```text
Host SNMP interface IP
```

を照合するため、送信元IPが変わるとHostを特定できません。

---

# 17. Proxy構成の全体像

```text
                     Management Network

R2 172.20.20.12 --------+
                        |
R4 172.20.20.22 --------+--- UDP/162
                        |
Router / Switch --------+
                        |
                        v
              +--------------------+
              | Proxy VM / Host    |
              |                    |
              | zabbix-snmptraps   |
              |        |           |
              |        v           |
              | zabbix-proxy       |
              +---------+----------+
                        |
                        | TCP/10051
                        v
              +--------------------+
              | OKD                |
              |                    |
              | Zabbix Server      |
              | PostgreSQL         |
              | Zabbix Web         |
              +--------------------+
```

---

# 18. 直接受信とProxy方式の比較

| 項目 | 直接受信 | Proxy |
|---|---|---|
| 構成 | シンプル | 少し複雑 |
| UDP/162受信 | Zabbix Server側 | Proxy側 |
| OKD/K8sとの相性 | ネットワーク次第 | 良い |
| 拠点分離 | 不向き | 向いている |
| FW越し | 構成しにくい場合あり | Active Proxyが便利 |
| Trap source IP保持 | 必須 | 必須 |
| Item | Server側設定 | 同じ |
| Trigger | Server側設定 | 同じ |
| Trigger判定 | Server | Server |
| Problem/Recovery | Server | Server |
| 通知 | Server | Server |

---

# 19. 使い分け

## Zabbix Serverで直接受信

以下なら直接構成がシンプルです。

```text
Network Device
    |
    | UDP/162
    v
Zabbix Server
```

向いているケース:

- 小規模環境
- 同一ネットワーク
- Zabbix ServerへUDP/162を直接到達可能
- NATが入らない

---

## Zabbix Proxy経由

以下ならProxy方式が適しています。

```text
Network Device
    |
    | UDP/162
    v
Zabbix Proxy
    |
    | TCP/10051
    v
Zabbix Server
```

向いているケース:

- Zabbix ServerがOKD/Kubernetes内部
- ネットワーク管理セグメントが分離
- FW越し
- 複数拠点
- SNMP Trapを中央Serverへ直接到達させたくない
- SNMP pollingもProxy側から実施したい

---

# 20. 今回のBGP監視

今回のBGP監視では以下を使用しています。

```text
BGP Established:
1.3.6.1.2.1.15.0.1
```

```text
BGP Backward Transition:
1.3.6.1.2.1.15.0.2
```

Item:

```text
snmptrap["mib-2\.15\.0\.[12]"]
```

Trigger:

```text
find(/r2-frr/snmptrap["mib-2\.15\.0\.[12]"],,"like","mib-2.15.0.2")=1
```

処理:

```text
BGP Neighbor Down
↓
.15.0.2
↓
PROBLEM

BGP Neighbor Established
↓
.15.0.1
↓
RECOVERY
```

---

# 21. 今後の改善点

現在のTriggerはHost単位で最新のBGP Trapを見ています。

複数BGP Neighborが存在する場合、

```text
Neighbor A Down
↓
.15.0.2
↓
PROBLEM

Neighbor B Established
↓
.15.0.1
↓
誤ってRECOVERY
```

となる可能性があります。

実運用では、Trapに含まれるPeer IPも利用して、

```text
OID + BGP Peer IP
```

でNeighbor単位に障害を管理する構成へ発展させるのが望ましいです。

最終的には、

```text
R2 → 10.0.1.0
R2 → 10.0.2.1
R2 → 10.0.4.1
```

をそれぞれ独立してProblem / Recovery管理できる構成が理想です。

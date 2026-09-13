#!/bin/sh

section() {
    echo
    echo "============================================================"
    echo " $1"
    echo "============================================================"
}

run() {
    echo "+ $*"
    "$@"
}

R1="clab-bgp-chaos-r1-gobgp"
R2="clab-bgp-chaos-r2-frr"
R3="clab-bgp-chaos-r3-gobgp"
R4="clab-bgp-chaos-r4-frr"
R5="clab-bgp-chaos-r5-srl"

section "1. Container status"

docker ps \
    --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' \
    --filter "name=clab-bgp-chaos-"

section "2. Interface / IP"

for NODE in "$R1" "$R2" "$R4" "$R3"; do
    echo
    echo "--- $NODE ---"
    run docker exec "$NODE" ip -br addr
done

echo
echo "--- $R5 ---"
run docker exec "$R5" sr_cli \
    "show interface ethernet-1/1"

echo
echo "--- $R5 system0 ---"
run docker exec "$R5" sr_cli \
    "show interface system0"

section "3. Direct-link ping"

echo "--- R1 -> R2 ---"
run docker exec "$R1" \
    ping -c 2 -W 1 10.0.1.1

echo
echo "--- R2 -> R1 ---"
run docker exec "$R2" \
    ping -c 2 -W 1 10.0.1.0

echo
echo "--- R2 -> R4 ---"
run docker exec "$R2" \
    ping -c 2 -W 1 10.0.2.1

echo
echo "--- R4 -> R2 ---"
run docker exec "$R4" \
    ping -c 2 -W 1 10.0.2.0

echo
echo "--- R4 -> R3 ---"
run docker exec "$R4" \
    ping -c 2 -W 1 10.0.3.1

echo
echo "--- R3 -> R4 ---"
run docker exec "$R3" \
    ping -c 2 -W 1 10.0.3.0

echo
echo "--- R2 -> R5 ---"
run docker exec "$R2" \
    ping -c 2 -W 1 10.0.4.1

echo
echo "--- R5 -> R2 ---"
run docker exec "$R5" sr_cli \
    "ping 10.0.4.0 network-instance default -c 2"

section "4. BGP neighbors"

echo "--- R1 GoBGP ---"
run docker exec "$R1" \
    gobgp neighbor

echo
echo "--- R2 FRR ---"
run docker exec "$R2" \
    vtysh -c "show bgp summary"

echo
echo "--- R4 FRR ---"
run docker exec "$R4" \
    vtysh -c "show bgp summary"

echo
echo "--- R3 GoBGP ---"
run docker exec "$R3" \
    gobgp neighbor

echo
echo "--- R5 SR Linux ---"
run docker exec "$R5" sr_cli \
    "show network-instance default protocols bgp summary"

echo
echo "--- R5 -> R2 BGP neighbor detail ---"
run docker exec "$R5" sr_cli \
    "show network-instance default protocols bgp neighbor 10.0.4.0 detail"

section "5. BGP RIB"

echo "--- R1 GoBGP ---"
run docker exec "$R1" \
    gobgp global rib

echo
echo "--- R2 FRR ---"
run docker exec "$R2" \
    vtysh -c "show bgp ipv4 unicast"

echo
echo "--- R4 FRR ---"
run docker exec "$R4" \
    vtysh -c "show bgp ipv4 unicast"

echo
echo "--- R3 GoBGP ---"
run docker exec "$R3" \
    gobgp global rib

echo
echo "--- R5 SR Linux BGP IPv4 RIB ---"
run docker exec "$R5" sr_cli \
    "show network-instance default protocols bgp routes ipv4"

section "6. Routing tables"

for NODE in "$R1" "$R2" "$R4" "$R3"; do
    echo
    echo "--- $NODE ---"
    run docker exec "$NODE" ip route
done

echo
echo "--- $R5 route summary ---"
run docker exec "$R5" sr_cli \
    "show network-instance default route-table summary"

section "7. End-to-end service ping"

echo "--- R1 service -> R3 service ---"
run docker exec "$R1" \
    ping -I 10.100.1.1 -c 3 -W 1 10.100.3.1

echo
echo "--- R3 service -> R1 service ---"
run docker exec "$R3" \
    ping -I 10.100.3.1 -c 3 -W 1 10.100.1.1

section "8. SR Linux reachability"

echo "--- R5 -> R1 service ---"
run docker exec "$R5" sr_cli \
    "ping 10.100.1.1 network-instance default -c 3"

echo
echo "--- R5 -> R3 service ---"
run docker exec "$R5" sr_cli \
    "ping 10.100.3.1 network-instance default -c 3"

echo
echo "--- R1 service -> R5 system0 ---"
run docker exec "$R1" \
    ping -I 10.100.1.1 -c 3 -W 1 10.255.0.5

echo
echo "--- R3 service -> R5 system0 ---"
run docker exec "$R3" \
    ping -I 10.100.3.1 -c 3 -W 1 10.255.0.5

section "9. SR Linux management protocols"

echo "--- R5 listening ports ---"
run docker exec "$R5" sh -c \
    "ss -lnt 2>/dev/null | grep -E ':(22|830|57400|50053)[[:space:]]' || true"

section "Done"

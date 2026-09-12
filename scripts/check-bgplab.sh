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

section "3. Direct-link ping"

echo "--- R1 -> R2 ---"
run docker exec "$R1" ping -c 2 -W 1 10.0.1.1

echo "--- R2 -> R1 ---"
run docker exec "$R2" ping -c 2 -W 1 10.0.1.0

echo "--- R2 -> R4 ---"
run docker exec "$R2" ping -c 2 -W 1 10.0.2.1

echo "--- R4 -> R2 ---"
run docker exec "$R4" ping -c 2 -W 1 10.0.2.0

echo "--- R4 -> R3 ---"
run docker exec "$R4" ping -c 2 -W 1 10.0.3.1

echo "--- R3 -> R4 ---"
run docker exec "$R3" ping -c 2 -W 1 10.0.3.0

section "4. BGP neighbors"

echo "--- R1 GoBGP ---"
run docker exec "$R1" gobgp neighbor

echo
echo "--- R2 FRR ---"
run docker exec "$R2" vtysh -c "show bgp summary"

echo
echo "--- R4 FRR ---"
run docker exec "$R4" vtysh -c "show bgp summary"

echo
echo "--- R3 GoBGP ---"
run docker exec "$R3" gobgp neighbor

section "5. BGP RIB"

echo "--- R1 GoBGP ---"
run docker exec "$R1" gobgp global rib

echo
echo "--- R2 FRR ---"
run docker exec "$R2" vtysh -c "show bgp ipv4 unicast"

echo
echo "--- R4 FRR ---"
run docker exec "$R4" vtysh -c "show bgp ipv4 unicast"

echo
echo "--- R3 GoBGP ---"
run docker exec "$R3" gobgp global rib

section "6. Linux routing tables"

for NODE in "$R1" "$R2" "$R4" "$R3"; do
    echo
    echo "--- $NODE ---"
    run docker exec "$NODE" ip route
done

section "7. End-to-end service ping"

echo "--- R1 service -> R3 service ---"
run docker exec "$R1" \
    ping -I 10.100.1.1 -c 3 -W 1 10.100.3.1

echo
echo "--- R3 service -> R1 service ---"
run docker exec "$R3" \
    ping -I 10.100.3.1 -c 3 -W 1 10.100.1.1

echo
echo "--- R3 -> R1 service ---"
run docker exec "$R3" \
    ping -c 3 -W 1 10.100.1.1

section "Done"

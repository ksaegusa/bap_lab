docker exec clab-bgp-chaos-r2-frr sh -c '
echo "=== BUILD ==="
/usr/lib/frr/bgpd --version

echo
echo "=== MODULES ==="
ls -1 /usr/lib/frr/modules/ 2>/dev/null || true

echo
echo "=== DAEMONS CONFIG ==="
cat /etc/frr/daemons 2>/dev/null || true

echo
echo "=== RUNNING ==="
ps aux

echo
echo "=== LISTEN ==="
ss -lntup 2>/dev/null || true
'

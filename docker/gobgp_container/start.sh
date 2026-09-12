#!/bin/sh
# 1. zebra起動
# 2. zserv.apiができるまで待つ
# 3. gobgpd起動
set -eu

mkdir -p /run/frr
chown frr:frr /run/frr

echo "[startup] starting FRR zebra"
/usr/lib/frr/zebra \
  -d \
  -f /etc/frr/zebra.conf

echo "[startup] waiting for /run/frr/zserv.api"
while [ ! -S /run/frr/zserv.api ]; do
  sleep 0.1
done

echo "[startup] starting GoBGP"
exec /usr/local/bin/gobgpd \
  -f /etc/gobgp/gobgpd.yaml

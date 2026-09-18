#!/bin/sh
# Entrypoint wrapper for AdGuard Home on Railway (https://railway.app).
#
# Railway terminates TLS at its edge proxy and forwards plain HTTP to the
# container. To serve DNS-over-HTTPS (and keep real client IPs) in that
# setup, AdGuard Home needs two config tweaks that its first-run wizard and
# web API do not expose:
#
#   1. http.doh.insecure_enabled: true
#      Serve the /dns-query DoH endpoint over plain HTTP behind the proxy.
#   2. dns.trusted_proxies: RFC1918 ranges
#      Honor X-Forwarded-For from Railway's edge proxy so query logs show
#      real client IPs instead of the proxy's internal address.
#
# This wrapper applies both automatically (idempotently) whenever the config
# exists. On the very first boot there is no config: AdGuard Home serves its
# setup wizard on port 3000, and the wrapper watches for the config file the
# wizard writes, applies the tweaks, and restarts once so DoH works
# immediately after setup - no manual edits, no redeploy.
#
# Config, filters, query log, and stats live under /data, which is the
# mount point of the template's persistent Railway volume.

CONF=/data/conf/AdGuardHome.yaml
BIN=/opt/adguardhome/AdGuardHome
WORK=/data/work
ARGS="--no-check-update -c $CONF -w $WORK"

mkdir -p /data/conf /data/work

apply_proxy_settings() {
    [ -f "$CONF" ] || return 0
    # 0. Keep the admin UI on port 3000: Railway's proxy targets 3000, but
    #    the setup wizard defaults the port field to 80. Clamp any :80.
    sed -i 's|^\(  address: .*\):80$|\1:3000|' "$CONF"
    # 1. Plain-HTTP DoH behind Railway's TLS-terminating proxy.
    sed -i 's/insecure_enabled: false/insecure_enabled: true/' "$CONF"
    # 2. Trust Railway's internal proxy networks for X-Forwarded-For.
    #    Replaces the loopback-only default entry, idempotently.
    sed -i 's|    - 127.0.0.0/8$|    - 127.0.0.0/8\n    - 10.0.0.0/8\n    - 172.16.0.0/12\n    - 192.168.0.0/16|' "$CONF"
}

apply_proxy_settings

if [ ! -f "$CONF" ]; then
    # First boot: run the setup wizard, then watch for the config file that
    # the wizard writes when setup completes.
    "$BIN" $ARGS "$@" &
    AGPID=$!
    while [ ! -f "$CONF" ]; do
        sleep 2
    done
    # Give the wizard a moment to finish writing, then apply the proxy
    # settings and restart once. The admin UI blips for a second; refreshing
    # the browser is enough.
    sleep 8
    kill "$AGPID" 2>/dev/null
    wait "$AGPID" 2>/dev/null
    apply_proxy_settings
fi

exec "$BIN" $ARGS "$@"

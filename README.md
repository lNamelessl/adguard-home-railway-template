# AdGuard Home (DoH) — Railway Template

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.app/new?github_url=https://github.com/lNamelessl/adguard-home-railway-template)

**Your own ad-blocking DNS-over-HTTPS (DoH) server on Railway — encrypted DNS for your phone, laptop, and browsers, from anywhere.**

> **Honest scope, up front:** Railway has no public UDP. This template is **not** a LAN DNS server
> (no plain DNS on port 53, no DHCP, no DoT out of the box). It runs [AdGuard Home](https://github.com/AdguardTeam/AdGuardHome)
> as an **encrypted DoH endpoint** behind Railway's TLS proxy: your devices query
> `https://your-app.up.railway.app/dns-query`, answers get filtered through AdGuard's blocklists,
> and the admin UI lives on the same URL. If you need LAN DNS:53, run AdGuard Home at home — this
> template is for protecting devices on the go.

## What you get

- One service: the official `adguard/adguardhome` image (pinned to `v0.107.79`) plus a tiny
  entrypoint wrapper that wires it for Railway
- First boot opens AdGuard Home's **setup wizard** — you create your own admin account (no default
  credentials are ever shipped)
- After setup the same domain serves the **admin UI** and the **`/dns-query` DoH endpoint**
- One persistent volume at `/data` — config, blocklists, query log, and stats survive redeploys
- The wrapper auto-injects `http.doh.insecure_enabled: true` (serve DoH over plain HTTP behind
  Railway's TLS-terminating proxy) and `dns.trusted_proxies` (internal proxy ranges incl. CGNAT, so query logs show
  real client IPs from `X-Forwarded-For` instead of the proxy's address)
- The wrapper clamps the admin UI back to port 3000 if the wizard's port field (which defaults to
  80) is submitted as-is — Railway's proxy targets 3000

## Deploy

1. Click the button above (or deploy from the Railway template page).
2. When the deploy is live, open your Railway domain — AdGuard Home's setup wizard appears.
3. Create your admin username/password. Leave the DNS settings as offered.
   *(Ignore the "Web admin interface port" field — the wrapper pins it to 3000 either way.)*
4. ~10 seconds after you finish the wizard the service restarts itself once to activate DoH and
   client-IP handling. If the page blips, refresh it — that's the activation, not a crash.
5. Start filtering: point devices at `https://<your-domain>/dns-query` (below).

## Point devices at your DoH server

Any client that speaks DNS-over-HTTPS (RFC 8484) works. Your URL is
`https://<your-domain>/dns-query` (per-device IDs like `/dns-query/myphone` also work after setup).

- **Firefox** (any OS): Settings → Privacy & Security → DNS over HTTPS → Max Protection →
  Custom provider → `https://<your-domain>/dns-query`
- **Chrome / Edge / Brave**: Settings → Privacy and security → Security → Use secure DNS →
  With: Custom → `https://<your-domain>/dns-query`
- **iOS / iPadOS 14+**: install a DNS profile with your URL — easiest via the free
  [DNSecure](https://apps.apple.com/app/id1539698502) app (or Apple Configurator):
  DoH server URL `https://<your-domain>/dns-query`, then enable it in
  Settings → General → VPN, NAT & Network (or DNS) management
- **Android 9+**: Settings → Private DNS speaks DoT (not DoH), so use an app that supports custom
  DoH URLs — e.g. [Rethink: DNS + Firewall](https://play.google.com/store/apps/details?id=com.celzero.bravedns)
  or the AdGuard app → add `https://<your-domain>/dns-query` as the DoH upstream
- **Windows 11** (system-wide): `netsh dns add encryption` with your endpoint, then set the
  adapter's DNS to "Encrypted only":
  ```powershell
  netsh dns add encryption server=<your-domain-ip> dohtemplate=https://<your-domain>/dns-query autoupgrade=yes udpfallback=no
  ```
  (Set `<your-domain-ip>` to an IP your domain currently resolves to; Railway edge IPs can change,
  so the browser-level setups above are simpler.)

## Verify it works

AdGuard Home speaks RFC 8484 wire format (`?dns=` + base64url, `application/dns-message`). From any machine:

```bash
# example.com A record — expect HTTP 200 and a valid DNS answer
curl -s "https://<your-domain>/dns-query?dns=q80BAAABAAAAAAAAB2V4YW1wbGUDY29tAAABAAE" \
     -H "Accept: application/dns-message" -o answer.bin
```

Ad-blocking check: in the admin UI add a blocking rule (Filters → Custom filtering rules), e.g.
`||doubleclick.net^`, then query it — the answer is `0.0.0.0`:

```bash
curl -s "https://<your-domain>/dns-query?dns=q80BAAABAAAAAAAAC2RvdWJsZWNsaWNrA25ldAAAAQAB" \
     -H "Accept: application/dns-message" -o blocked.bin
```

(`?name=example.com&type=A` JSON APIs like Google's are a different DoH dialect — AdGuard Home
serves the standard wire format all OSes and browsers use.)

## Settings the template manages

The entrypoint (`entrypoint.sh`) runs on every boot and idempotently enforces, in `/data/conf/AdGuardHome.yaml`:

| Setting | Value | Why |
|---|---|---|
| `http.address` | `:3000` (clamped from 80) | Railway's proxy targets port 3000 |
| `http.doh.insecure_enabled` | `true` | Serve `/dns-query` over plain HTTP behind Railway's TLS edge |
| `dns.trusted_proxies` | loopback + RFC1918 + `100.64.0.0/10` (CGNAT, where Railway edge proxies originate) | Honor `X-Forwarded-For` from Railway's proxy so logs/stats show real client IPs |

Railway does not publish fixed ingress CIDRs for its edge proxy, so the template trusts the
internal RFC1918 ranges (which is where the proxy connections originate). Only services inside your
own Railway project share those private networks. Remove/replace entries in `entrypoint.sh` if your
security posture needs stricter handling — note the admin API/UI does not expose `trusted_proxies`,
which is exactly why the wrapper injects it.

## Using your own domain (and real TLS at AdGuard)

The default setup terminates TLS at Railway (fine for DoH — the DoH payload's security does not
depend on the last hop). If you want AdGuard Home to terminate TLS itself (custom domain, DoT on
853 via a Railway TCP proxy, HTTP/3):

1. Attach a custom domain in Railway and point DNS at it.
2. In the admin UI → Settings → Encryption settings: paste your certificate + key (or paths in the
   config under `tls:`), set `server_name` to your domain.
3. Then also set `tls.port_dns_over_tls: 853` and expose it with a Railway TCP proxy for DoT.

## Cost

One small service + one volume: typically **a few dollars per month** on Railway's usage-based
pricing (AdGuard Home idles at ~50-100 MB RAM; query log/stats growth is modest). Estimate before
deploying with Railway's pricing calculator; set usage limits in your workspace if you're cost-cautious.

## Troubleshooting

- **Deploy is stuck/unhealthy**: the healthcheck hits `/install.html`, which answers 200 in both the
  wizard and post-setup phases. If the deploy fails, check the service logs for the wrapper's output.
- **Wizard finished but the domain shows a gateway error**: you likely submitted port 80 in the
  wizard — wait ~10 seconds; the wrapper clamps it back to 3000 and restarts the service.
- **DoH answers 404**: you queried before the post-setup restart completed; try again after the
  self-restart (~10 s after the wizard).
- **Query logs show a 100.64.x or 10.x/172.x client IP**: a proxy range is missing from `trusted_proxies` —
  extend the list in `entrypoint.sh` and redeploy.
- **Everything disappeared after a redeploy**: the volume must be mounted at `/data` (the template
  sets this up). If you recreated the service manually, add the volume and set its mount path to
  `/data`.

## Files

- `Dockerfile` — official `adguard/adguardhome:v0.107.79` + entrypoint wrapper
- `entrypoint.sh` — proxy-mode config injection, wizard-port clamp, first-run watcher
- `railway.json` — Dockerfile builder, healthcheck on `/install.html`, restart policy

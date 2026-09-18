# AdGuard Home as a private DNS-over-HTTPS server — ad-blocking encrypted DNS for your devices, anywhere

**Read this first — honest scope:** Railway has no public UDP networking, so this template does **not** give you a classic LAN DNS server. There is no plain DNS on port 53, no DHCP, and no DNS-over-TLS out of the box. What you get instead is [AdGuard Home](https://github.com/AdguardTeam/AdGuardHome) running as a **private DNS-over-HTTPS (DoH) endpoint**: every device you own can send its DNS through `https://your-app.up.railway.app/dns-query`, encrypted over HTTPS, filtered through AdGuard's blocklists, from your phone on cellular data or your laptop on hotel Wi-Fi — not just at home.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.app/new?github_url=https://github.com/lNamelessl/adguard-home-railway-template)

## What this template deploys

- **One service**: the official `adguard/adguardhome` Docker image, pinned to `v0.107.79`, wrapped by a small entrypoint script that adapts it to Railway:
  - serves DoH (`/dns-query`) over plain HTTP behind Railway's TLS-terminating proxy (`http.doh.insecure_enabled: true`)
  - pre-configures `dns.trusted_proxies` with the proxy networks Railway uses, so query logs and per-client stats show **real client IPs** instead of the proxy's internal address
  - keeps the admin UI on port 3000 where Railway's proxy expects it (even if you accept the setup wizard's default port of 80)
- **One persistent volume** mounted at `/data`: your config, blocklists, query log, and statistics survive restarts and redeploys
- **A public domain** on the same port that serves both the admin UI and the DoH endpoint

## First-run setup (one minute)

1. Open your new Railway domain. AdGuard Home's setup wizard appears — create **your own admin username and password** (nothing is pre-configured; there are no default credentials).
2. About 10 seconds after you finish, the service restarts itself once to activate DoH and client-IP handling. If the page blips, refresh.
3. Point devices at `https://your-app.up.railway.app/dns-query`.

## Configure your devices (DoH)

- **Firefox**: Settings → Privacy & Security → DNS over HTTPS → Max Protection → Custom provider → your `/dns-query` URL
- **Chrome/Edge/Brave**: Settings → Privacy and security → Security → Use secure DNS → Custom → your `/dns-query` URL
- **iOS/iPadOS 14+**: add the URL as a DoH server in the free DNSecure app (or a .mobileconfig DNS profile)
- **Android 9+**: Android's "Private DNS" setting is DoT-only; use an app with custom DoH support (Rethink: DNS + Firewall, AdGuard app) and add your `/dns-query` URL
- **Windows 11**: `netsh dns add encryption server=<ip> dohtemplate=https://<your-domain>/dns-query autoupgrade=yes udpfallback=no`, then set the adapter to "Encrypted only"

## Verify

RFC 8484 wire-format check (works from any machine with curl):

```bash
curl -s "https://<your-domain>/dns-query?dns=q80BAAABAAAAAAAAB2V4YW1wbGUDY29tAAABAAE" \
     -H "Accept: application/dns-message" -o answer.bin   # example.com -> HTTP 200
```

To confirm ad blocking: add `||doubleclick.net^` under Filters → Custom filtering rules in the admin UI, re-query, and the answer resolves to `0.0.0.0`.

## Cost

A single lightweight service plus a small volume: AdGuard Home idles at ~50-100 MB of RAM, so light personal use typically lands in the low single-digit dollars per month on Railway's usage-based pricing.

# Deploy and Host

## About Hosting

Deploying this template provisions one Railway service built from the pinned `adguard/adguardhome:v0.107.79` image plus the template's entrypoint wrapper, and one persistent volume mounted at `/data` (AdGuard Home's config directory `/data/conf` and working data `/data/work` both live there, so filters, query log, and statistics persist across deploys). The service exposes a single HTTP port (3000) behind a Railway-generated public domain: the admin UI and the DoH endpoint share that one HTTPS URL, with TLS terminated by Railway's proxy. The healthcheck targets `/install.html`, which answers 200 both before setup (wizard) and after, so a fresh deploy is healthy immediately while you complete the wizard. No external databases or third-party services are involved.

## Why Deploy

Running AdGuard Home on Railway gives you a globally reachable, HTTPS-encrypted, ad-blocking DNS resolver without a home server, a VPS, or a static IP: one click provisions it, Railway's proxy handles TLS certificates for you, and the volume keeps your blocklists and logs persistent. Compared to rolling it yourself, the template already solves the platform-specific glue that AdGuard Home's wizard and web API do not expose — unencrypted-DoH-behind-proxy mode, trusted proxy ranges for correct client IPs, and the admin port wiring — and it self-applies those settings on every boot, so a redeploy never breaks your DoH endpoint. Upgrades stay one-click too: bump the pinned image tag and redeploy; your data survives on the volume.

## Common Use Cases

- Block ads, trackers, and malware domains on phones and laptops outside your home network — on cellular, hotel, and campus Wi-Fi — with encrypted DNS that neither the local network nor your ISP sees in the clear
- A private, password-protected DoH resolver for browsers (Firefox/Chrome custom secure-DNS URL) for a family or small team, with per-device client IDs (`/dns-query/<device>`) and per-client statistics
- Central custom DNS rules: pin your own domains, rewrite records, or block specific services across every device that uses the endpoint
- A filtered DNS endpoint for kids' devices (SafeSearch, YouTube restricted mode, adult-site blocklists) that works wherever the device goes

## Dependencies for

### Deployment Dependencies

None beyond Railway itself. The template provisions a single service (Docker image `adguard/adguardhome:v0.107.79` — no external database or API keys) and one persistent volume mounted at `/data`. TLS certificates for the default `*.up.railway.app` domain are issued automatically by Railway; clients only need an app or OS that speaks DNS-over-HTTPS (RFC 8484).

# SELF-HOST SERVER DEPLOYMENT, HARDENING & NETWORK TROUBLESHOOTING GUIDE

## 1. Network Architecture (Direct P2P + Relay Fallback)

`DAUVERSE REMOTE DESKTOP V1.0` prioritizes **Direct P2P** connections (LAN local discovery or STUN/NAT hole-punching over UDP) to achieve `<20 ms` LAN latency and `30–80 ms` Internet latency. When corporate firewalls or symmetric NATs block UDP hole-punching, traffic seamlessly falls back to an encrypted **Relay (`hbbr`)** without exposing plaintext frames (end-to-end encryption remains between Boss's client and Home PC).

---

## 2. Self-Hosted Rendezvous (`hbbs`) & Relay (`hbbr`) Deployment

Configuration is provided in [`deploy/self-host/docker-compose.yml`](../deploy/self-host/docker-compose.yml), pinned to `rustdesk/rustdesk-server:1.1.16`.

### Required Ports (Firewall Allowlist Only)
- `21115/tcp` — NAT type test
- `21116/tcp` & `21116/udp` — ID registration, heartbeat, and UDP hole punching (`hbbs`)
- `21117/tcp` — Encrypted Relay stream (`hbbr`)

### Deployment Steps (On an Authorized Host/LAN Server)
```bash
cd deploy/self-host
mkdir -p data
docker compose up -d
cat data/id_ed25519.pub
```
Copy the Ed25519 public key (`id_ed25519.pub`) into **DAUVERSE Remote -> Network Settings -> Key** on both Boss's Office client and Home AI workstation.

---

## 3. Server Security Hardening Checklist

1. **Enforce Mandatory Key Verification (`-k _`):** Already enabled in `docker-compose.yml` for both `hbbs` and `hbbr` so unauthorized clients without your `id_ed25519.pub` cannot register or relay.
2. **Keep `id_ed25519` Private Key Offline/Protected:** `chmod 600 data/id_ed25519`; never commit `data/` to Git.
3. **Restrict Management Access:** Do not expose SSH or container management ports to `0.0.0.0/0`; restrict via VPN/Tailscale or IP allowlist.
4. **Never Modify Corporate Firewalls Without Authorization:** Use standard outbound HTTPS/TCP relay compatibility when operating on corporate networks in compliance with company IT policy.

---

## 4. Network Troubleshooting Guide

| Symptom | Root Cause | Resolution |
|---|---|---|
| Status shows `Relay Fallback` on same LAN | Direct IP access disabled or Windows Firewall blocking UDP | Enable LAN Direct IP in Settings and verify Windows Firewall allows `DAUVERSE_REMOTE.exe` on Private network |
| Connection fails with `Key Mismatch` | `hbbs` generated a new `id_ed25519.pub` or client key field is empty | Ensure identical `id_ed25519.pub` string is configured on both Home and Office endpoints |
| High latency (`>100 ms`) during video playback | Relay path or ISP congestion | Switch Performance Mode to `Auto Adaptive` or `Low Bandwidth`, or verify UDP `21116` reachability |
| Host unreachable after power blink | Router DHCP lease changed or NIC WoL sleep state | Assign DHCP reservation on home router and verify NIC `Wake on Magic Packet` in Windows Device Manager |

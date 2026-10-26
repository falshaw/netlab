# EDGE DEFENCE CHEAT SHEET — CDN / WAF / DDoS

## What this is & why it matters
This is the "front door" of a regulated, high-traffic web platform. Such a service is a permanent DDoS target
(peak-event traffic spikes + extortion attacks) and is globally distributed (latency = lost users). So the edge
stack — **CDN** (speed + absorb), **WAF** (app-layer attacks), **DDoS scrubbing** (volumetric) — is where most
of the edge network engineering happens. This sheet is concept + the routing/BGP
mechanics behind it.

---

## 1. CDN (Content Delivery Network) — speed + first layer of absorption
- **What:** geographically distributed caches/PoPs serving content close to the user. Cuts latency, offloads origin, absorbs spikes.
- **How users reach the nearest PoP:**
  - **Anycast** — same IP advertised by **BGP** from every PoP; the internet routes each user to the topologically nearest.
  - **DNS-based GSLB** — DNS returns the best PoP per user (geo/latency).
- **Caching:** TTLs, cache-control headers, origin shield, cache-key design; static vs dynamic (ESI, dynamic acceleration).
- **TLS termination** at the edge; **origin pull** vs push.
- Vendors: Cloudflare, Akamai, Fastly, CloudFront.
> **Summary:** CDNs use BGP anycast plus DNS GSLB to pull users to the nearest PoP — that's both the latency optimisation and the first tier of DDoS absorption, because attack traffic is spread across every PoP instead of hitting one origin.

## 2. WAF (Web Application Firewall) — L7 application defence
- **What:** inspects **HTTP/HTTPS** for app-layer attacks the network firewall can't see.
- **Covers OWASP Top 10:** SQLi, XSS, CSRF, path traversal, RCE, etc.
- **Models:** **negative** (signatures/blocklist — OWASP CRS) + **positive** (allowlist/learned schema). Plus **rate-limiting**, **bot management**, **geo-blocking**, **virtual patching** (block an exploit before the app is patched).
- **Deploy:** reverse-proxy / cloud (Cloudflare, AWS WAF, F5 ASM, Imperva, ModSecurity+CRS).
- **Tuning:** start in **detection/log mode** → baseline → move to **block**; manage false positives per rule.
> **Summary:** a WAF is L7 — it sees the HTTP payload, so it stops SQLi/XSS/bot abuse and can virtual-patch a vuln before the developers ship a fix. Run new rules in detection mode first to bound false positives, then enforce.

## 3. DDoS mitigation
### Attack types
- **Volumetric** (Gbps/Tbps): UDP/ICMP floods, **reflection/amplification** (DNS, NTP, memcached, SSDP). Goal: saturate the pipe.
- **Protocol/state** (pps): **SYN flood**, ACK flood, fragment attacks. Goal: exhaust device state tables.
- **Application (L7)**: HTTP GET/POST floods, Slowloris, cache-busting. Low bandwidth, hard to spot.

### Mitigation mechanics (the routing parts)
- **Always-on cloud scrubbing** (Cloudflare Magic Transit, Akamai Prolexic, AWS Shield, Arbor): your prefixes are advertised/diverted to the scrubbing centre, clean traffic returned via **GRE/tunnel**.
- **BGP diversion**: on attack, **announce the targeted prefix to the scrubber** (more-specific /24) → traffic detours through scrubbing → clean traffic back over a tunnel.
- **RTBH (Remote-Triggered Black Hole)** — BGP community tags a victim /32 → `next-hop Null0` at every edge → drop the victim's traffic to save everything else (sacrifice one host). *(Full config in CHEATSHEET-BGP §9.)*
- **FlowSpec** — distribute an L3/L4 filter (match proto/port/rate, drop/rate-limit) fleet-wide via BGP instead of touching every box.
- **uRPF** — drop spoofed sources (`ip verify unicast source reachable-via rx`).
- **SYN cookies / connection limits / first-packet drop** for state attacks.
- **Anycast** spreads volumetric load across PoPs automatically.

### The trade-off
- **RTBH = you complete the DoS for one IP** (drop all its traffic) to protect the rest — blunt but instant.
- **Scrubbing = surgical** (filters bad, keeps good) but costs and adds a slight detour.
> **Summary:** layered — anycast + CDN absorb and spread, cloud scrubbing handles volumetric via BGP diversion and GRE return, FlowSpec pushes surgical L3/L4 filters fleet-wide, and RTBH is the last-resort blackhole when saving the platform means sacrificing one target IP. uRPF and SYN cookies handle spoofing and state exhaustion.

## 4. Putting it together: a reference edge design
User → **Anycast CDN PoP** (TLS, cache, absorb) → **WAF** (L7/OWASP/bot) → **DDoS scrubbing** (volumetric/state) →
origin behind a firewall, with **RTBH + FlowSpec** ready at the border and **monitoring/alerting** (NetFlow/sFlow → detection) feeding it. Tie to non-functionals: telemetry, runbooks, on-call.

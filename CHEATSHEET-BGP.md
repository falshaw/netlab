# BGP CHEAT SHEET (FRR / vtysh — Cisco notes inline)

## What this is & why it matters
BGP is **the** protocol of the internet — the path-vector protocol that exchanges reachability between
**autonomous systems (AS)**. A large online platform is **multihomed** to multiple ISPs and must **engineer**
which links carry which traffic, stay up when a link dies, and **defend** itself (RTBH/FlowSpec are BGP).
BGP best-path selection and why iBGP needs next-hop-self are the two things to know cold.

> Memorise top-to-bottom. Syntax is FRR (what the labs run); Cisco IOS differences noted as `[IOS: ...]`.
> Everything is inside `configure terminal` unless it's a `show`.

---

## 0. The one thing they WILL ask: best-path algorithm (in order)
**Weight → Local-Pref → Locally-originated → AS-path (shortest) → Origin (IGP<EGP<?) → MED (lowest) → eBGP>iBGP → lowest IGP metric to next-hop → oldest eBGP → lowest router-id → lowest neighbor IP**

Mnemonic: **W**eight **L**ocal **O**riginate **A**S **O**rigin **M**ED e**B**GP **I**GP **R**outer-id.
- **Weight** = Cisco/FRR local-only, higher wins, never advertised.
- **Local-Pref** = AS-wide, higher wins → your **OUTBOUND** lever.
- **AS-path prepend** = make a path look longer → your **INBOUND** lever.
- **MED** = hint to a neighbour AS, lower wins, only compared between paths from the *same* AS.

---

## 1. Turn on BGP + neighbours
```
router bgp 65000
 bgp router-id 1.1.1.1
 no bgp ebgp-requires-policy          ! FRR/RFC-8212: without a policy eBGP sends/accepts 0 prefixes
 neighbor 10.0.13.2 remote-as 65100   ! eBGP (different AS)
 neighbor 10.0.12.2 remote-as 65000   ! iBGP (same AS)
 neighbor 10.0.12.2 next-hop-self     ! iBGP: rewrite next-hop to me, else 'inaccessible'
 neighbor 10.0.12.2 update-source lo  ! peer off loopback (resilient, needs IGP)
 neighbor 2.2.2.2 description R2-iBGP
 network 192.0.2.0/24                 ! advertise a prefix you have a route for (needs matching RIB/Null0 route)
```
Peer-group / template (scale):
```
 neighbor UPSTREAM peer-group
 neighbor UPSTREAM remote-as external
 neighbor 10.0.13.2 peer-group UPSTREAM
```

## 2. Show / verify (live the most)
```
show ip bgp summary                 ! neighbours + state. Established+number = good. Active/Idle/Connect = broken
show ip bgp                         ! the BGP table (all paths). > = best, *=valid, i=internal
show ip bgp 8.8.8.0/24              ! all paths for one prefix + why best (next-hop, as-path, localpref, med)
show ip route bgp                   ! what BGP actually installed (B routes)
show ip bgp neighbors 10.0.13.2     ! full neighbour detail (timers, caps, counters)
show ip bgp neighbors 10.0.13.2 advertised-routes   ! what I send them
show ip bgp neighbors 10.0.13.2 received-routes      ! what they send (needs soft-reconfig inbound)
show bgp community 65100:120
show ip bgp regexp _65100$          ! path filtering by regex
```
Refresh after a policy change (NO session drop):
```
clear ip bgp * soft                 ! [IOS: clear ip bgp * soft]
clear ip bgp 10.0.13.2 soft in
```

## 3. OUTBOUND traffic engineering — Local Preference (higher wins, AS-wide)
Apply where routes ENTER your AS (inbound from the upstream you prefer):
```
route-map PREFER_ISPA permit 10
 set local-preference 200
!
router bgp 65000
 neighbor 10.0.13.2 route-map PREFER_ISPA in
```
> Result: every router in AS 65000 prefers exiting via that upstream. Beats eBGP>iBGP.

## 4. INBOUND traffic engineering — AS-path prepend (longer = less preferred)
Apply OUTBOUND toward the link you DON'T want inbound traffic on:
```
route-map PREPEND_OUT permit 10
 set as-path prepend 65000 65000     ! your own prefix now looks 2 hops longer to that ISP
!
router bgp 65000
 neighbor 10.0.24.2 route-map PREPEND_OUT out
```
Other inbound levers: **MED** (`set metric 50` out — same-AS only), **communities** the ISP publishes, more-specifics.

## 5. Communities (tag once, act anywhere) — the SP self-service TE menu
```
 neighbor 10.0.13.2 send-community            ! MUST enable to send them
!
bgp community-list standard CUST permit 65100:120
route-map FROM_ISPA permit 5
 match community CUST
 set local-preference 80                       ! act on a tag the ISP set
route-map FROM_ISPA permit 10
 set community 65000:100 additive              ! set your own tag (additive = keep existing)
```
Well-known: `no-export` (don't leave AS), `no-advertise` (don't tell any peer), `local-as`. `set community no-export`.

## 6. Filtering — prefix-list + route-map (the "don't be transit" rule)
A multihomed customer advertises ONLY its own prefixes outbound — else you're free transit between your ISPs.
```
ip prefix-list OWN seq 5 permit 192.0.2.0/24
ip prefix-list OWN seq 10 deny 0.0.0.0/0 le 32      ! deny the rest
route-map ONLY_OWN permit 10
 match ip address prefix-list OWN
!
router bgp 65000
 neighbor 10.0.13.2 route-map ONLY_OWN out
 neighbor 10.0.24.2 route-map ONLY_OWN out
```
Prefix-list range match: `permit 10.0.0.0/8 le 24` = 10/8 through /24. `ge`/`le` = range bounds.
AS-path filter: `bgp as-path access-list NOTRANSIT permit ^$` (^$ = locally originated only), apply `filter-list NOTRANSIT out`.
Max-prefix safety: `neighbor 10.0.13.2 maximum-prefix 100000 restart 5`.

## 7. iBGP scaling — Route Reflector (vs full mesh n(n-1)/2)
```
router bgp 65000
 neighbor 10.0.12.2 route-reflector-client     ! RR reflects routes between its clients
```
RR adds **Originator-ID** + **Cluster-list** for loop prevention (AS-path can't grow in-AS).
Alternative: **confederations** (split AS into sub-ASNs). Know both exist; RR is the common one.

## 8. Resilience
```
 neighbor 10.0.13.2 bfd                         ! sub-second failure detection
 bgp bestpath as-path multipath-relax           ! ECMP across equal-cost eBGP paths (diff AS)
 maximum-paths 4                                 ! install up to 4 (eBGP)  [iBGP: maximum-paths ibgp 4]
 neighbor 10.0.13.2 timers 3 9                   ! keepalive/hold (default 60/180)
 bgp graceful-restart
```

## 9. Security / DDoS via BGP (front-line defence)
**RTBH (Remote-Triggered Black Hole)** — drop a victim /32 network-wide via a community:
```
ip route 198.51.100.66/32 Null0 tag 666         ! trigger router: blackhole + tag
route-map RTBH permit 10
 match tag 666
 set community 65000:666                          ! edge matches this community -> set next-hop to a Null0 discard
 set ip next-hop 192.0.2.1
```
Edge: route-map on ingress matches `65000:666` → `set ip next-hop <discard>` (statically routed to Null0). Traffic to victim dropped at every edge, attack absorbed at the border.
**uRPF** (anti-spoof): `ip verify unicast source reachable-via rx`.
**FlowSpec**: push an L3/L4 filter (match proto/port/rate-limit/drop) via BGP AFI/SAFI 1/133 — like a fleet-wide ACL distributed by BGP. Know the concept + that it beats per-box ACLs.
**Peer hardening**: `neighbor X password <secret>` (TCP-MD5), GTSM `neighbor X ttl-security hops 1`.

## 10. Troubleshooting ladder (work in this order)
1. `show ip bgp summary` → state. **Idle** = no TCP/admin down; **Active** = trying TCP, can't (L3/ACL/wrong IP); **Connect** = TCP handshaking; **Established** = good.
2. `ping <neighbor>` → L3 reachability (the /30 far end).
3. TCP/179 reachable? ACL/MD5/GTSM mismatch?
4. AS number match? (`remote-as` both ends)
5. `Established` but 0 prefixes → **RFC-8212** (`no bgp ebgp-requires-policy` or a policy), or `network`/redistribute missing, or your filters.
6. Route in `show ip bgp` but not `show ip route` → **next-hop inaccessible** (need `next-hop-self` or an IGP).
7. Wrong path chosen → walk the best-path algorithm (section 0).

## Soundbites
- *"Outbound I steer with local-pref; inbound with AS-path prepend, since I can't set knobs in someone else's AS. MED only between paths from the same neighbour AS."*
- *"As a multihomed customer I filter outbound to my own prefixes so I never become unintentional transit."*
- *"iBGP is non-transitive — full-mesh or route reflectors; RRs stamp Originator-ID and Cluster-list."*
- *"For DDoS I trigger RTBH by community to blackhole the victim at every edge, and FlowSpec to distribute an L3/L4 filter fleet-wide via BGP instead of touching every box."*

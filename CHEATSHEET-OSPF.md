# OSPF CHEAT SHEET (FRR / vtysh — Cisco notes inline)

## What this is & why it matters
OSPF is the most common **IGP** (Interior Gateway Protocol) — it routes *inside* one organisation/AS, where
BGP routes *between* them. It's link-state: every router shares LSAs, builds an identical map, and runs SPF
(Dijkstra). It's the **foundation under iBGP**: without an IGP carrying your
links and loopbacks, your internal BGP next-hops won't resolve (the `inaccessible` trap). The core topics are
areas, LSA types, DR/BDR, and the classic troubleshooting case (adjacency stuck in ExStart = MTU).

> OSPFv2 (IPv4). Link-state, Dijkstra/SPF, AD 110, metric = cost = 10^8 / bandwidth(bps).
> FRR uses `interface` config for most knobs; IOS often uses `network` under the process.

---

## 0. Core facts
- **Link-state**: every router floods LSAs, builds an identical LSDB, runs **SPF (Dijkstra)** to get its own tree.
- **Areas**: hierarchy to limit flooding. **Area 0 = backbone**; every other area must touch it (or use a virtual-link). ABR = between areas, ASBR = injects external routes.
- **Adjacency states**: Down → Init → 2-Way → ExStart → Exchange → Loading → **Full**. Stuck in **ExStart** = MTU mismatch. Stuck in **2-Way** on LAN = normal between two DROthers.
- **DR/BDR** on broadcast/multi-access: elected by highest **priority** then highest **router-id**; cuts adjacencies from n² to n. Priority 0 = never DR. Point-to-point = no DR.
- **Cost** = 10^8/bw → 10G,40G,100G all = 1 unless you raise the reference bandwidth (`auto-cost reference-bandwidth 100000`). Set it the same everywhere.
- **Timers**: hello 10s / dead 40s (broadcast); must match or no adjacency.
- **Metrics compared**: O (intra-area) < O IA (inter-area) < E1 (ext, cost accumulates) < E2 (ext, fixed = default).

## 1. Turn on OSPF (FRR style — per interface)
```
router ospf
 ospf router-id 1.1.1.1
!
interface eth1
 ip ospf area 0                        ! FRR: put the interface in area 0
 ip ospf network point-to-point        ! /30 link: skip DR/BDR, faster
!
interface lo
 ip ospf area 0
 ip ospf passive                       ! FRR: advertise the loopback, send no hellos out of it
```
FRR sets passive per interface (`ip ospf passive`); the IOS-style `passive-interface <ifname>` under `router ospf` is not in current FRR. `passive-interface default` under `router ospf` still exists (see section 6).
IOS equivalent:
```
router ospf 1
 router-id 1.1.1.1
 network 10.0.12.0 0.0.0.3 area 0      ! wildcard mask!
 passive-interface Loopback0
```

## 2. Show / verify (live these)
```
show ip ospf neighbor                  ! must reach FULL (or 2-WAY between DROthers). State + DR/BDR
show ip ospf interface brief           ! area, cost, state, #nbrs per interface
show ip ospf interface eth1            ! timers, network type, DR/BDR, MTU
show ip route ospf                     ! O = intra, O IA = inter-area, O E2 = external
show ip ospf database                  ! the LSDB (all LSAs)
show ip ospf database router           ! Type-1 LSAs
show ip ospf rib
show ip ospf                           ! process, areas, SPF stats, reference-bw
```

## 3. Tuning the path (cost = the lever)
```
interface eth1
 ip ospf cost 50                       ! lower cost = preferred path
!
router ospf
 auto-cost reference-bandwidth 100000  ! 100G ref so 10G/40G/100G differ. Set EVERYWHERE the same
 timers throttle spf 0 50 5000         ! faster SPF on change
```

## 4. Area types (reduce LSAs into stub areas)
```
router ospf
 area 1 stub                           ! blocks Type-5 externals; ABR injects default
 area 1 stub no-summary                ! totally stubby: also blocks Type-3 inter-area (default only)
 area 2 nssa                           ! stub but CAN originate externals (Type-7 -> Type-5 at ABR)
 area 0.0.0.5 range 10.5.0.0/16        ! ABR summarisation of intra-area routes
```
LSA types: **1** Router, **2** Network (DR), **3** Summary (inter-area, by ABR), **4** ASBR-summary, **5** External (by ASBR), **7** NSSA-external.

## 5. Inject routes / default
```
router ospf
 redistribute connected                ! becomes E2 externals (ASBR)
 redistribute bgp route-map FROM_BGP
 default-information originate          ! advertise a default; add 'always' to originate even without one
```

## 6. Security
```
interface eth1
 ip ospf authentication message-digest
 ip ospf message-digest-key 1 md5 <secret>
!
router ospf
 passive-interface default             ! safest: passive everywhere...
!
interface eth1
 no ip ospf passive                    ! ...then turn OSPF back on for the real links (per-interface wins)
```

## 7. The OSPF↔BGP link (why this lab matters)
iBGP next-hops are only reachable if an IGP carries the internal links + loopbacks.
- Run OSPF on all internal links + loopbacks → loopbacks now reachable AS-wide.
- Peer iBGP on loopbacks (`update-source lo`) → sessions survive a link failure.
- BGP next-hop now resolves via OSPF → that `inaccessible` route from day1b turns valid.
> **Summary:** OSPF is the IGP under iBGP — it advertises the loopbacks and links so BGP next-hops resolve; peering iBGP on loopbacks means a single link drop doesn't tear the session.

## 8. Troubleshooting ladder
1. `show ip ospf neighbor` → not FULL?
2. **Stuck ExStart/Exchange** → **MTU mismatch** (most common) → fix MTU or `ip ospf mtu-ignore`.
3. **No neighbour at all** → hello/dead timer mismatch, area mismatch, subnet/mask mismatch, auth mismatch, or the link is passive (`ip ospf passive` / `passive-interface default`).
4. **2-WAY and won't go FULL** on a LAN → both are DROthers (normal); only DR/BDR go full with everyone.
5. **Adjacency up but no routes** → check `network`/`ip ospf area`, area type blocking LSAs, or distribute-list.
6. Wrong path → check `ip ospf cost` / reference-bandwidth consistency.

## IS-IS (60-second bridge from OSPF)
Same idea (link-state, SPF) but runs **directly on L2 (CLNS/NET address)**, not IP — so it's protocol-agnostic and a carrier favourite.
- **Levels** not areas: **L1** = intra-area, **L2** = backbone (between areas). A router can be L1, L2, or L1/L2.
- **NET address** = area + system-id + NSEL, e.g. `49.0001.1921.6800.1001.00`.
- Adjacency = hellos (IIH); metric is just "narrow (0-63)/wide (0-16M)" — use **wide-metrics** always.
- FRR: `router isis <tag>` + `net <NET>`, then `interface eth1 / ip router isis <tag> / isis circuit-type level-2-only` (same tag).
- Show: `show isis neighbor`, `show isis database`.
> **Summary:** IS-IS is link-state like OSPF but runs on CLNS, not IP, uses levels instead of areas, and scales well in big SP cores — that's why carriers favour it. The OSPF concepts map across directly.

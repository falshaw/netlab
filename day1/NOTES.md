# Day 1 — BGP — NOTES (memorise this)

## The big idea (say it in one breath)
**BGP connects separate networks.** Each network is an **Autonomous System (AS)** with a number. Inside one network you use OSPF (you trust it all); **between** different networks you use BGP (scale + policy + control). r1=AS65001, r2=AS65002, r3=AS65003 → three separate networks → BGP between them.

BGP has **no auto-discovery** — you hand-name every peer. And **peering shares nothing** until you `network`-advertise your routes.

---

## THE UNIVERSAL PATTERN (memorise — every BGP router is these 4 steps)
1. **Turn on BGP** → `router bgp <your-AS>`
2. **Name yourself** → `bgp router-id <your-loopback>`
3. **List your peers** → `neighbor <their-IP> remote-as <their-AS>`  (one line per peer)
4. **Announce your routes** → `network <your-prefix>`

> Turn on → name → peer → announce.

---

## The line-by-line meaning (quick reference)
| Command | What it's for |
|---|---|
| `configure terminal` | enter EDIT mode (read-only → editable) |
| `router bgp 65002` | switch BGP on; this router IS network AS 65002 |
| `bgp router-id 2.2.2.2` | this router's unique BGP name = its loopback (never goes down) |
| `neighbor <IP> remote-as <AS>` | open a BGP session to a peer at that IP, in that AS (eBGP if AS differs from yours) |
| `network 2.2.2.2/32` | advertise this prefix: "reach 2.2.2.2 through me" |
| `end` | leave edit mode (config is already live) |
| `write memory` | NOT needed here — config is live instantly; saving fails on the bind-mounted frr.conf (harmless) |

---

## The full lab — all 3 routers (the triangle)
Loopbacks: r1=1.1.1.1, r2=2.2.2.2, r3=3.3.3.3.
Links: r1–r2 = 10.0.12.0/30 · r1–r3 = 10.0.13.0/30 · r2–r3 = 10.0.23.0/30.

**r1 (AS65001):**
```
configure terminal
router bgp 65001                        ! BGP on; r1 = AS 65001
 bgp router-id 1.1.1.1                  ! r1's name = its loopback
 neighbor 10.0.12.2 remote-as 65002     ! peer with r2 (link 1)
 neighbor 10.0.13.2 remote-as 65003     ! peer with r3 (link 2)
 network 1.1.1.1/32                     ! advertise my loopback
end
```

**r2 (AS65002):**
```
configure terminal
router bgp 65002                        ! BGP on; r2 = AS 65002
 bgp router-id 2.2.2.2                  ! r2's name = its loopback
 neighbor 10.0.12.1 remote-as 65001     ! peer with r1 (link 1)
 neighbor 10.0.23.2 remote-as 65003     ! peer with r3 (link 3)
 network 2.2.2.2/32                     ! advertise my loopback
end
```

**r3 (AS65003):**
```
configure terminal
router bgp 65003                        ! BGP on; r3 = AS 65003
 bgp router-id 3.3.3.3                  ! r3's name = its loopback
 neighbor 10.0.13.1 remote-as 65001     ! peer with r1 (link 2)
 neighbor 10.0.23.1 remote-as 65002     ! peer with r2 (link 3)
 network 3.3.3.3/32                     ! advertise my loopback
end
```

---

## Verify (after all 3 are configured)
```
show ip bgp summary     ! peers should be "Established" (a number under PfxRcd, not Active/Idle)
show ip bgp             ! the BGP table; ">" marks the chosen best path
show ip route bgp       ! BGP-learned routes installed (flagged "B")
ping 3.3.3.3            ! from r1 — prove reachability to r3's loopback
```
On r1 you'll learn 3.3.3.3 **two ways** — direct from r3, and via r2 — and BGP picks the **shorter AS-path** (direct). See it: `show ip bgp 3.3.3.3`.

---

## The TWO levers that run 90% of real BGP (memorise)
- **Local-preference → steers traffic OUTBOUND** (higher wins). Set it on routes coming IN, to choose how YOU exit.
- **AS-path prepend → steers traffic INBOUND** (longer path looks worse). Pad your AS on routes going OUT, to make others avoid you.

> *"Local-pref out, AS-path in."*

## Best-path order (the levers first, then the full list)
weight → **local-pref** → locally-originated → **AS-path** → origin → MED → eBGP>iBGP → lowest IGP metric → oldest → lowest router-id.
> In practice the lever attributes decide it — local-pref outbound, AS-path inbound. For the full order, check `show ip bgp <prefix>`, which names the deciding attribute, or `CHEATSHEET-BGP.md` §0.

## Summary (BGP)
> BGP is the routing protocol of the internet and the cloud edge — how you peer with ISPs and run private connectivity into a cloud provider. Local-pref steers traffic outbound, AS-path or communities inbound. The big idea for an always-on platform is anycast — the same prefix advertised from many sites: users hit the nearest for low latency, and a volumetric DDoS spreads across all of them instead of hitting one.

---

## ⚠ GOTCHA proven in the lab — RFC 8212 (secure-by-default)
Modern BGP (FRR 8+) passes **no routes** on an eBGP session until you attach a policy. Sessions go `Established` but you see `0 accepted prefixes` + "discarded due to missing policy".
- **Production fix:** attach a route-map per neighbor (explicit allow).
- **Lab fix:** `no bgp ebgp-requires-policy` under `router bgp`, then `clear ip bgp *`.
> **Summary:** modern BGP is secure-by-default per RFC 8212 — an eBGP peer exchanges nothing until you attach an explicit policy. Old IOS passed everything by default.

## Reading `show ip bgp <prefix>` (the best-path detail view)
FRR shows every path AND names the winner + WHY: `best (Local Pref)`, `best (Shorter AS-path)`, etc. Each path lists its AS-path, localpref, next-hop, and `from <peer> (<router-id>)`. Use this to *prove* which attribute decided.

## STEER with local-preference — PROVEN (the #1 BGP skill)
Force r2 to reach r1 via r3 (the LONGER path) by raising local-pref on routes from r3:
```
configure terminal
route-map PREFER-R3 permit 10            ! a named policy
 set local-preference 200                ! higher than default 100 = wins
exit
router bgp 65002
 neighbor 10.0.23.2 route-map PREFER-R3 in    ! apply to routes coming IN from r3
end
clear ip bgp * soft                      ! re-evaluate, no session drop
```
Result: `show ip bgp 1.1.1.1` → best path flips to the r3 path (`best (Local Pref)`) **even though its AS-path is longer** — because local-pref is checked BEFORE AS-path.
> **THE lesson:** local-pref OVERRIDES AS-path. *Local-pref out, AS-path in.*

## Verify / break (resilience — try next time)
- `clear ip bgp *` = hard reset a session · `clear ip bgp * soft` = re-apply policy without dropping it.
- Break test: on a router `interface eth1` → `shutdown`; on a peer `show ip bgp summary` shows it drop to Active and routes reroute the other way; `no shutdown` recovers. That's BGP resilience, live.

# Day 1b — BGP DEEP DIVE — iBGP, next-hop-self, Route Reflectors (+ communities)

This is the **architect** half of BGP. Day 1 was eBGP between strangers. Today is what happens
**inside** one network, and it's the stuff any serious BGP design discussion digs into: *"explain iBGP
full-mesh and why route reflectors exist."* If you can paste this and narrate it, you own that question.

---

## The story (say it in one breath)
We are **AS 65000**. We peer with **the internet (AS 65100, = r4)** at our **border router r1**.
Behind r1 sit two internal routers **r2 and r3** — same AS, so the sessions between them are **iBGP**.
r2 and r3 are deliberately **not** cabled to each other: that missing wire is the whole reason
**route reflectors** exist.

```
        AS65100  r4 (lo 4.4.4.4)   advertises 203.0.113.0/24 ("the internet")
                    | eBGP  10.0.14.0/30
        AS65000  r1 (lo 1.1.1.1)   border router + Route Reflector
                  /                 \   iBGP
          10.0.12.0/30          10.0.13.0/30
              /                      \
        r2 (lo 2.2.2.2)        r3 (lo 3.3.3.3)   (no wire between them — that's the point)
```

## eBGP vs iBGP — the only table that matters here
| | **eBGP** (r1↔r4) | **iBGP** (r1↔r2, r1↔r3) |
|---|---|---|
| Neighbour AS | **different** (65000 vs 65100) | **same** (65000 both ends) |
| AS-path | prepends your AS | **unchanged** inside the AS |
| Next-hop | set to self automatically | **kept as-is → you must `next-hop-self`** |
| Admin distance | **20** | **200** |
| Re-advertise? | freely | **never iBGP→iBGP** (split-horizon) → full-mesh **or** route reflector |

> *"eBGP is one hop between strangers; iBGP glues my own routers together — same AS, AS-path untouched,
> and it never relays an iBGP route to another iBGP peer, so I either full-mesh them or use a route reflector."*

---

## Bring it up (3 lines)
```
git pull
cd day1b
sudo containerlab deploy
```
You now have **r1 r2 r3 r4**, wired, IP'd, **no BGP yet**. Enter a router with:
```
sudo docker exec -it clab-day1b-r1 vtysh      # swap r1 for r2 / r3 / r4
```
Open **four terminals** (one per router) so you can watch them at once — or just hop with the line above.

---

# STAGE A — eBGP to the internet (r1 ↔ r4)

### On **r4** (= the internet, AS 65100):
```
configure terminal
ip route 203.0.113.0/24 Null0            ! invent a "public" prefix so we have something to advertise
router bgp 65100                         ! BGP on; r4 = AS 65100
 bgp router-id 4.4.4.4                   ! r4's name = its loopback
 no bgp ebgp-requires-policy             ! LAB ONLY: turn off RFC-8212 default-deny (Day 1 gotcha)
 neighbor 10.0.14.1 remote-as 65000      ! eBGP peer = r1 (different AS = eBGP)
 network 203.0.113.0/24                  ! announce the public prefix into BGP
end
```
**Plain English:** r4 pretends to be the internet. `ip route ... Null0` makes the prefix *exist* so the
`network` line has something real to advertise. `no bgp ebgp-requires-policy` is the lab shortcut for the
RFC-8212 "Established but 0 prefixes" trap you hit on Day 1.

### On **r1** (our border, AS 65000):
```
configure terminal
router bgp 65000                         ! BGP on; r1 = our AS 65000
 bgp router-id 1.1.1.1                   ! r1's name = its loopback
 no bgp ebgp-requires-policy             ! LAB ONLY: RFC-8212 off on the eBGP side too
 neighbor 10.0.14.2 remote-as 65100      ! eBGP peer = r4 (different AS)
end
```

### Verify on r1:
```
show ip bgp summary                      ! r4 should be Established (a NUMBER under PfxRcd, not Active/Idle)
show ip bgp                              ! 203.0.113.0/24 should be here, next-hop 10.0.14.2, marked ">"
show ip route bgp                        ! installed as "B" — r1 can reach the internet prefix
```
✅ **Stage A done when** r1 shows `203.0.113.0/24` as a best path. r1 learned the internet. Now push it inside.

---

# STAGE B — iBGP + the next-hop trap (r1 ↔ r2, r1 ↔ r3)

### On **r2** (internal, AS 65000):
```
configure terminal
router bgp 65000                         ! SAME AS as r1 → this session is iBGP
 bgp router-id 2.2.2.2                   ! r2's name
 neighbor 10.0.12.1 remote-as 65000      ! iBGP peer = r1 (same AS 65000)
 network 2.2.2.2/32                      ! advertise my loopback into our AS
end
```

### On **r3** (internal, AS 65000):
```
configure terminal
router bgp 65000                         ! SAME AS again → iBGP
 bgp router-id 3.3.3.3                   ! r3's name
 neighbor 10.0.13.1 remote-as 65000      ! iBGP peer = r1
 network 3.3.3.3/32                      ! advertise my loopback
end
```

### On **r1** — add the two iBGP neighbours:
```
configure terminal
router bgp 65000
 neighbor 10.0.12.2 remote-as 65000      ! iBGP to r2 (same AS)
 neighbor 10.0.13.2 remote-as 65000      ! iBGP to r3 (same AS)
end
```

### 🔴 SEE IT BROKEN FIRST — on **r2**:
```
show ip bgp                              ! 203.0.113.0/24 IS in the table...
show ip route bgp                        ! ...but it is NOT installed in the routing table
show ip bgp 203.0.113.0/24               ! look: next hop 10.0.14.2 "(inaccessible)"
```
**Why:** iBGP did **not** rewrite the next-hop. r2 was told "to reach the internet, go to 10.0.14.2"
— but 10.0.14.2 is the r1↔r4 link, which r2 has no route to. BGP refuses to use a next-hop it can't reach,
so the route sits in the BGP table unused. **This is the #1 iBGP gotcha.**

### 🟢 FIX IT — on **r1**:
```
configure terminal
router bgp 65000
 neighbor 10.0.12.2 next-hop-self        ! tell r2: "for these routes, the next hop is ME"
 neighbor 10.0.13.2 next-hop-self        ! same for r3
end
clear ip bgp * soft                      ! re-send updates, no session drop
```
**Plain English:** `next-hop-self` makes the border router rewrite the next-hop to its own address
(10.0.12.1 toward r2), which r2 *is* directly connected to → reachable → route installs.

### Re-check on **r2**:
```
show ip bgp 203.0.113.0/24               ! next hop now 10.0.12.1, no "(inaccessible)"
show ip route bgp                        ! 203.0.113.0/24 now installed as "B"  ✅
```
✅ **Stage B done when** the internet route is installed on r2 **and** r3 after next-hop-self.

> **Interview line:** *"iBGP doesn't change the next-hop, so an internal router inherits the eBGP peer's
> address and can't reach it. On the border router I run `next-hop-self` so my internal routers resolve
> external routes through me."*

---

# STAGE C — the full-mesh problem → Route Reflector (the architect moment)

r1 learned **2.2.2.2/32 from r2** and **3.3.3.3/32 from r3** — both over **iBGP**.
Question: does **r3 know about r2's loopback**?

### 🔴 SEE IT BROKEN — on **r3**:
```
show ip bgp 2.2.2.2/32                    ! "Network not in table" — r3 has NEVER heard of r2's loopback
```
**Why:** the iBGP split-horizon rule — *a router never relays an iBGP-learned route to another iBGP peer.*
r1 heard 2.2.2.2/32 from iBGP peer r2, so it will **not** pass it to iBGP peer r3. In a real network you'd
fix this by **full-meshing** every router to every other (n·(n-1)/2 sessions — explodes at scale), **or**
by promoting one router to a **Route Reflector**.

### 🟢 FIX IT — make **r1** a Route Reflector:
```
configure terminal
router bgp 65000
 neighbor 10.0.12.2 route-reflector-client   ! r2 is now an RR client of r1
 neighbor 10.0.13.2 route-reflector-client   ! r3 is now an RR client of r1
end
clear ip bgp * soft                          ! re-advertise with reflection on
```
**Plain English:** an RR is *allowed* to break the split-horizon rule and reflect routes **between its
clients**. Now r1 relays r2↔r3 for you — two sessions instead of a full mesh.

### Re-check on **r3**:
```
show ip bgp 2.2.2.2/32                    ! it APPEARS now — reflection works ✅
                                          ! note "Originator: 2.2.2.2, Cluster list: 1.1.1.1"
```
`Originator` + `Cluster list` are the loop-prevention stamps an RR adds in place of the AS-path
(AS-path can't grow inside one AS, so RRs use these instead).

> ⚠️ **Honest detail (and a great thing to say):** on r3 that reflected route may still show next-hop
> **inaccessible** — because r2's next-hop (10.0.12.2) isn't reachable from r3 without an **IGP**. That is
> exactly *why real iBGP runs over OSPF/IS-IS and peers on loopbacks* — the IGP resolves BGP next-hops and
> carries the loopbacks. That's **Day 4 (OSPF)**. Today's win is proving the **reflection** itself: the
> route now reaches r3 at all, which without the RR it never did.

> **Interview line:** *"iBGP is non-transitive — it won't relay a route between internal peers, so you
> either full-mesh (which scales as n-squared) or use route reflectors. The RR reflects between clients and
> stamps Originator-ID and Cluster-list for loop prevention. Underneath it you run an IGP so the BGP
> next-hops actually resolve."*

✅ **Stage C done when** r3 can *see* 2.2.2.2/32 in `show ip bgp` (and r2 can see 3.3.3.3/32). That's the architect lesson.

---

# STAGE D — communities (stretch — the SP traffic-engineering tool)

Communities are **tags** you attach to routes; other routers **match the tag** and act on it. They're how
providers and customers signal policy without custom config per prefix. Two flavours to know:
**well-known** (`no-export`, `no-advertise`) and **custom** (`AS:value`, e.g. `65100:100`).

### Tag the internet prefix at the source — on **r4**:
```
configure terminal
route-map TAG-OUT permit 10              ! a named policy
 set community 65100:100                 ! stamp every matched route with this tag
exit
router bgp 65100
 neighbor 10.0.14.1 route-map TAG-OUT out   ! apply on the way OUT to r1
 neighbor 10.0.14.1 send-community           ! actually include communities in updates
end
clear ip bgp * soft
```

### See the tag — on **r1**:
```
show ip bgp 203.0.113.0/24               ! look for "Community: 65100:100"
```

### Act on the tag — on **r1** (customer-signaled local-pref, a real SP pattern):
```
configure terminal
bgp community-list standard CUST-100 permit 65100:100   ! a matcher for that tag
route-map FROM-NET permit 10                            ! policy on routes coming in from r4
 match community CUST-100                                ! if tagged 65100:100...
 set local-preference 200                                ! ...prefer this path (default is 100)
exit
router bgp 65000
 neighbor 10.0.14.2 route-map FROM-NET in                ! apply inbound from r4
end
clear ip bgp * soft
```
```
show ip bgp 203.0.113.0/24               ! localpref now 200, "best (Local Pref)"
```
> **Interview line:** *"Communities are route tags — `no-export` keeps a prefix inside the AS, and custom
> communities let a customer signal 'prefer this' or 'blackhole this' so the provider acts on the tag
> instead of editing policy per prefix. RTBH triggering is literally a community."*

---

## Tear down when done
```
sudo containerlab destroy
```

---

## The 4 lines that win the iBGP question
1. *"eBGP between strangers, iBGP inside my AS — same AS, AS-path untouched."*
2. *"iBGP doesn't rewrite the next-hop → `next-hop-self` on the border router."*
3. *"iBGP never relays to another iBGP peer → full-mesh **or** route reflectors."*
4. *"Run an IGP under iBGP so the next-hops resolve and you peer on loopbacks."*

## Quick command reference
| Command | Shows |
|---|---|
| `show ip bgp summary` | every peer + state + prefixes received |
| `show ip bgp` | the whole BGP table, `>` = best path |
| `show ip bgp <prefix>` | one route in detail: next-hop, accessible?, community, originator, why-best |
| `show ip route bgp` | BGP routes actually **installed** (flag `B`) |
| `clear ip bgp * soft` | re-apply policy / re-send updates, **no session drop** |

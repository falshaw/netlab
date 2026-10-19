# STUDY — the week (containerlab + FRR)

**Rhythm:** ~2–3h/session. Deploy the day's lab, type the commands, then **break it and fix it** — that's where the learning sticks. Destroy/redeploy is free (`sudo containerlab destroy` / `deploy`), so you can never get "stuck" — just redeploy clean.

**Enter a router:** `sudo docker exec -it clab-<lab>-<node> vtysh` → you're at `r1#`. FRR CLI ≈ Cisco IOS.

**Vendor note:** the topics here are vendor-neutral (multi-vendor, SP-flavoured). FRR's Cisco-style syntax transfers to any box. For the deep items FRR can't fully show in the cloud (real MPLS dataplane), concept-level understanding is the goal.

---

## Day 1 — eBGP fundamentals ✅ (ready now: `day1-bgp/`)

**Topology:** 3 routers, 3 autonomous systems, full triangle. Each advertises its loopback.
```
 r1(AS65001 1.1.1.1) ── r2(AS65002 2.2.2.2)
        \                  /
         r3(AS65003 3.3.3.3)
```

**Deploy + look around:**
```bash
cd day1-bgp && sudo containerlab deploy
sudo docker exec -it clab-day1-bgp-r1 vtysh
```
Inside r1:
```
show ip bgp summary        # neighbors -> want "Established" (a number under PfxRcd, not Idle/Active)
show ip bgp                # the BGP table; ">" = the chosen best path
show ip route bgp          # BGP routes installed (flagged "B")
show bgp neighbors 10.0.12.2 advertised-routes
ping 3.3.3.3 source 1.1.1.1
```
r1 learns 3.3.3.3 two ways — direct from r3, and via r2. It picks the **shorter AS-path** (direct). See it: `show ip bgp 3.3.3.3`.

**Make it talk — the two levers that matter (do this in config mode on r1):**
```
configure terminal
 ! prefer the r2 path for everything by raising its local-preference
 route-map PREFER-R2 permit 10
  set local-preference 200
 router bgp 65001
  neighbor 10.0.12.2 route-map PREFER-R2 in
 end
clear bgp *           # re-evaluate (or "clear ip bgp *")
show ip bgp 3.3.3.3   # best path should now point via r2 (10.0.12.2)
```
Then on r3, make r1 *avoid* r3 inbound by padding AS-path:
```
configure terminal
 route-map LONGER permit 10
  set as-path prepend 65003 65003 65003
 router bgp 65003
  neighbor 10.0.13.1 route-map LONGER out
 end
```
Watch r1's best path move. **That's it — local-pref steers traffic *out*, AS-path steers traffic *in*.**

**Break & fix:** on r2, `interface eth1` → `shutdown`. On r1, `show ip bgp summary` shows the peer drop to Active; routes reroute via r3. `no shutdown` → recovers. That's BGP resilience, live.

> **Summary line:** *"I peer with neighbor + network statements, confirm `show ip bgp summary` is Established, and steer with local-pref outbound / AS-path inbound. Anycast — same prefix from many sites — gives low latency and DDoS spread; that's the big BGP idea for an always-on platform."*

---

## Day 2 — Anycast + multihoming (the internet edge)

**Goal:** advertise the **same prefix (e.g. 100.64.0.1/32) from two "PoP" routers**; a client reaches whichever is closer; kill one PoP and traffic shifts to the other with no address change. Multihome an edge router to two upstream "ISPs" and steer with communities/local-pref.

**Key commands:** `show ip bgp 100.64.0.1` (two paths, one prefix), `traceroute` from the client to see which PoP it hits, BGP `maximum-prefix` and prefix-lists for edge hardening.

> **Why it matters:** anycast is *the* answer to "low latency globally **and** DDoS resilience" — a volumetric flood spreads across all PoPs instead of hitting one. (Topology added to `day2/`.)

---

## Day 3 — DDoS defence: RTBH + BGP FlowSpec (hands-on)

**Goal:** trigger **Remote-Triggered Black Hole** (community-tagged /32 → next-hop discard, propagated by BGP) and a **FlowSpec** rule (drop a specific 5-tuple) — the surgical vs blunt DDoS tools. Optional: an nginx container with `limit_req` to *feel* L7 rate-limiting.

**Key commands:** FRR `bgp flowspec`, `show bgp ipv4 flowspec detail`, RTBH via `route-map` setting community + a static discard route on the trigger.

> **Summary line:** *"RTBH is the blunt kill-switch for a sacrificial IP; FlowSpec is surgical — drop just the attack 5-tuple and keep the service IP alive. Volumetric you solve with anycast + scrubbing scale; L7 you solve with WAF + rate-limit + behavioural scoring, because a legitimate traffic surge can look like an HTTP flood."* (Topology → `day3/`.)

---

## Day 4 — IGP: OSPF refresh + IS-IS

**Goal:** OSPF multi-area first (familiar), then **IS-IS L1/L2** on the same topology so you can *speak to the difference*. FRR runs both.

**Key commands:** `show ip ospf neighbor`, `show isis neighbor`, `show isis database`, `show ip route isis`.

> **Summary line:** *"Both link-state. OSPF I've run as the enterprise IGP; IS-IS is the SP favourite — runs at L2 not in IP, TLV-extensible so IPv6 and segment-routing slot in with one instance. I've run OSPF hands-on; IS-IS I now know the config and would ramp on."* (→ `day4/`.)

---

## Day 5 — MPLS L3VPN + Segment Routing

**Goal:** build an MPLS core with **L3VPN** (VRF, RD/RT, MP-BGP VPNv4) and see **Segment Routing** labels. FRR does the *control plane* fully (LDP, VPNv4, SR) — you'll read the labels and VRF tables.

> ⚠️ **Cloud caveat (honest):** Codespaces can't load kernel MPLS modules, so packets may not *forward* through labels — but you'll see the full control-plane config, label bindings, and VRF separation, which is what an interview probes. For real MPLS *dataplane*, use **Juniper vLabs** (free hosted) — the one place to see it actually switch labels.

**Key commands:** `show mpls table`, `show bgp ipv4 vpn`, `show ip route vrf CUST-A`, `show isis segment-routing prefix-sids`.

> **Summary line:** *"MPLS decouples forwarding from routing — label once at the edge, swap in the core. RSVP-TE engineers paths + sub-50ms FRR; the modern direction is Segment Routing — path in the packet header, stateless core, TI-LFA protection. Config I'd ramp on; the architecture I'm solid on."* (→ `day5/`.)

**Also today (read, can't lab):** SS7/SIP — `CHEATSHEET-SIGNALING-SIP-SS7.md`. Kafka/K8s networking — `CHEATSHEET-KAFKA-K8S.md` (advertised-listeners, CNI, Ingress, netpol).

---

## Day 6 — Resilience + SD-WAN/SDN concepts

**Goal:** **BFD** for sub-second failover ("don't wait on default BGP timers", made real), **ECMP** active/active, and a VXLAN/IPsec overlay over an underlay to *feel* the control-plane/forwarding-plane split that SD-WAN/SDN is built on.

**Key commands:** `show bfd peers`, watch failover timing with/without BFD, `show ip route` ECMP entries.

> **Summary line:** *"Private circuit primary + VPN backup, BGP choosing, **BFD for sub-second detection** so traffic shifts before users notice. SDN/SD-WAN = pull the control plane out, central controller pushes app-aware policy, edges forward — controller out of the data path so a controller failure doesn't drop traffic. SD-WAN overlays MPLS, doesn't replace it."* (→ `day6/`.)

---

## Day 7 — Capstone + live-design rehearsal

**Goal:** assemble a **"mini internet edge"** — anycast front, multihomed BGP, RTBH ready, IGP core, a VRF, BFD failover — the whole picture in one topology. Then practice the **whiteboard answer out loud**: *"design a resilient, low-latency, DDoS-hardened edge for an always-on online platform."*

Use this as the proof you can hold a real network end-to-end. Pair with `CHEATSHEET-EDGE-DEFENCE.md` section 4 (the whiteboard answer).

---

### Quick command reference (FRR)
```
configure terminal / end / do show ...     # config nav (IOS-style)
show ip interface brief                     # interfaces up/up
show ip route                               # routing table (C/S/O/B/i)
show ip bgp summary | show ip bgp           # BGP peers / table
show ip ospf neighbor | show isis neighbor  # IGP adjacencies
show bfd peers                              # sub-second failover state
clear bgp *                                 # re-apply BGP policy
write memory                                # save
```

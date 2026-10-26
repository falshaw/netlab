# MPLS / RSVP-TE / L3VPN / SEGMENT ROUTING CHEAT SHEET

## What this is & why it matters
MPLS is how carriers and large WANs move traffic: instead of an IP lookup at every hop, packets are
**label-switched** along pre-built paths (LSPs). It underpins **L3VPN** (multi-tenant private WANs),
**traffic engineering** (RSVP-TE / Segment Routing), and is the "legacy construct" SD-WAN overlays. The goal
here is **concept-correct** understanding rather than config depth. Know the model, the three label-distribution
methods, and L3VPN's RD/RT cold.

> FRR has MPLS/LDP/SR; RSVP-TE is IOS-XR/Junos territory and is not implemented in FRR (concept-level here).

---

## 0. The mental model
MPLS = **label switching**. Instead of every router doing a longest-prefix IP lookup, the **ingress (PE/LER)**
classifies the packet once into a **FEC** (Forwarding Equivalence Class), pushes a **label** (a 20-bit shim
between L2 and L3), and the **core (P/LSR)** routers swap labels at line rate without looking at the IP. The
**egress** pops the label and does the final IP lookup. The path the labels follow = an **LSP** (Label-Switched Path).

- **Label stack** (32-bit shim): 20-bit **label** | 3-bit **EXP/TC** (QoS) | 1-bit **BoS** (bottom-of-stack) | 8-bit **TTL**.
- **PHP** (Penultimate Hop Popping): the second-to-last router pops the label (label 3 = implicit-null) so the egress only does one lookup.
- **Roles:** **PE** = Provider Edge (customer-facing, LER), **P** = Provider core (LSR), **CE** = Customer Edge.

## 1. How labels get distributed (3 ways — know all three)
| Mechanism | What it does | When |
|---|---|---|
| **LDP** | auto-assigns labels following the IGP's best path | simple "MPLS everywhere", no TE |
| **RSVP-TE** | signals an **explicit, bandwidth-reserved** LSP along a chosen path | traffic engineering, guaranteed BW, FRR fast-reroute |
| **Segment Routing (SR-MPLS / SRv6)** | source puts the **whole path as a label/segment stack**; NO LDP/RSVP state in the core | modern replacement — stateless, scales |

## 2. LDP (FRR)
```
mpls ldp
 router-id 1.1.1.1
 address-family ipv4
  discovery transport-address 1.1.1.1
  interface eth1
  interface eth2
!
interface eth1
 mpls enable                 ! [IOS: mpls ip]
```
Show:
```
show mpls ldp neighbor
show mpls ldp binding        ! label <-> FEC bindings
show mpls table              ! the LFIB (in-label -> out-label/action: swap/pop/push)
show mpls interface
```
IOS: `mpls ip`, `mpls label protocol ldp`, `show mpls ldp neighbor`, `show mpls forwarding-table`.

## 3. RSVP-TE (concept + IOS-XR/Junos flavour — concept-level is enough)
- Builds an **explicit LSP** with **bandwidth reservation** + admission control (CSPF picks a path meeting constraints).
- Enables **FRR (Fast ReRoute)**: pre-computed backup LSP, **<50 ms** failover (link/node protection).
- **Affinities/colours** + admin-groups steer LSPs away from/onto specific links.
- Tunnel knobs: `bandwidth`, `priority` (setup/hold), `path-option explicit`, `fast-reroute`.
IOS-XR idea:
```
interface tunnel-te1
 ipv4 unnumbered Loopback0
 destination 9.9.9.9
 path-option 1 explicit name VIA-CORE
 signalled-bandwidth 1000000
 fast-reroute
```
> **Summary:** RSVP-TE = explicit, bandwidth-reserved LSPs chosen by CSPF, with sub-50ms FRR link/node protection. FRR does not implement it, so it stays conceptual in these labs; the industry is moving to Segment Routing, which removes the per-LSP soft state.

## 4. L3VPN (MPLS VPN — the carrier bread-and-butter)
Carries many customers' overlapping IP space across one shared core, isolated.
- **VRF** = per-customer routing table on the PE (`vrf CUSTA`).
- **RD** (Route Distinguisher) = makes overlapping prefixes globally unique (`RD 65000:100` → prefix becomes a **VPNv4** route).
- **RT** (Route Target) = an extended community controlling import/export between VRFs (this is what builds the VPN topology: hub-spoke, any-to-any).
- **MP-BGP (VPNv4 AF)** carries the VPN routes PE→PE; a **2-label stack**: outer = transport LSP to egress PE, inner = VPN/VRF label.
FRR sketch. FRR does not create Linux VRFs, so create the kernel VRF device first (container shell) and put the customer-facing interface in it:
```bash
ip link add CUSTA type vrf table 100
ip link set CUSTA up
ip link set eth3 master CUSTA          # the CE-facing interface
```
Then in vtysh:
```
router bgp 65000
 address-family ipv4 vpn
  neighbor 2.2.2.2 activate
 exit-address-family
!
router bgp 65000 vrf CUSTA
 address-family ipv4 unicast
  rd vpn export 65000:100
  rt vpn both 65000:100
  label vpn export auto
  export vpn
  import vpn
```
Show: `show ip route vrf CUSTA`, `show bgp ipv4 vpn`, `show mpls table`.
> **Summary:** L3VPN = VRF per customer, RD to disambiguate overlapping prefixes into VPNv4, RT extended-communities to control which VRFs import which routes, all carried by MP-BGP over a two-label stack — transport label to the egress PE, VPN label to pick the VRF.

## 5. Segment Routing (the modern approach)
- Source-routing: ingress encodes the path as a stack of **segments** (SIDs). Core just follows labels — **no LDP, no RSVP soft-state**.
- **Prefix-SID** (global, per-node, advertised by IGP) + **Adjacency-SID** (local, per-link).
- IGP (**IS-IS or OSPF**) carries SIDs via extensions → SR rides your existing IGP, no extra protocol.
- **SR-TE** = traffic engineering with a segment list (replaces RSVP-TE). **TI-LFA** = sub-50ms protection, simpler than RSVP-FRR.
- **SRv6** = same idea using IPv6 addresses as SIDs (no MPLS shim at all).
FRR (SR-MPLS on IS-IS; the process tag `CORE` must match on every interface):
```
interface lo
 ip router isis CORE
!
interface eth1
 ip router isis CORE
!
router isis CORE
 net 49.0001.0000.0000.0001.00
 metric-style wide
 segment-routing on
 segment-routing global-block 16000 23999
 segment-routing prefix 1.1.1.1/32 index 100
```
SR-TE policies (`segment-routing` / `traffic-eng`) are handled by **pathd**, which is **off** in `common/daemons` (`pathd=no`). To try them, set `pathd=yes` there and redeploy. Example from the FRR docs:
```
segment-routing
 traffic-eng
  segment-list SL1
   index 10 mpls label 16001
   index 20 mpls label 16002
  !
  policy color 1 endpoint 192.0.2.4
   name example1
   binding-sid 1111
   candidate-path preference 100 name CP1 explicit segment-list SL1
```
> **Summary:** SR pushes path state to the edge as a SID stack, so the core is stateless — you keep TE and sub-50ms TI-LFA protection without RSVP's per-LSP signalling. It rides IS-IS/OSPF, and SRv6 drops the MPLS shim entirely.

## 6. Troubleshooting MPLS
1. Is the IGP up? (MPLS LSPs follow the IGP / loopbacks must be /32 and reachable.)
2. `show mpls ldp neighbor` → LDP adjacency up? (needs IGP + `mpls enable` per interface).
3. `show mpls table` → are in/out labels programmed (swap/pop)?
4. L3VPN missing routes → check RD set, RT import/export match, VPNv4 AF activated on the iBGP/RR session, and the transport LSP exists end-to-end.
5. `traceroute` shows MPLS labels (TTL copy) — label stack visible hop by hop.

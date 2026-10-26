# SD-WAN / SDN CHEAT SHEET (CP/FP abstraction)

## What this is & why it matters
SDN/SD-WAN **separates the control plane (the routing brain) from the forwarding plane (line-rate packet
movement)** and centralises control. SD-WAN applies this to the WAN: it bonds MPLS + broadband + LTE into one
policy-driven overlay and steers each app to the best path by measured loss/latency/jitter. The practical frame
for integrating it with **legacy constructs** is "overlay on existing MPLS, don't rip it out".

## 0. The one idea: separate the Control Plane from the Forwarding Plane
- **Control Plane (CP)** = decides where traffic goes (routing brain, policy). **Centralised** in SDN/SD-WAN.
- **Forwarding/Data Plane (FP)** = actually moves packets (line-rate). Stays **distributed** on the devices.
- **Management Plane** = config/telemetry/orchestration.
Traditional routers = CP+FP **on every box**. SDN/SD-WAN = **lift the CP out**, program the FP centrally.
> **Summary:** CP/FP abstraction means the forwarding plane stays distributed at line rate, but the control plane is centralised, so intent is expressed once and the controller programs every device — that's the core of both SDN and SD-WAN.

## 1. SDN (data-centre / campus)
- **Controller** (ODL, ONOS, Cisco APIC/ACI, vendor) holds the CP; talks **southbound** to devices, **northbound** to apps.
- **Southbound APIs:** **OpenFlow** (program flow tables directly), **NETCONF/YANG**, **gNMI/gRPC**, OVSDB, P4.
- **Northbound APIs:** REST to apps/orchestrators (intent in).
- **Overlay:** **VXLAN** (L2 over L3, 24-bit VNI = 16M segments) with **EVPN** (BGP) as the control plane = modern DC fabric (spine-leaf).
- **ACI** = Cisco's intent/policy SDN (APIC controller, endpoint groups/contracts).

## 2. SD-WAN (the WAN version)
Abstracts **multiple transports** (MPLS + broadband + LTE/5G) into **one policy-driven overlay**.
### Components (Viptela/Cisco naming, concepts are universal)
- **vManage** = management/orchestration (single pane).
- **vSmart** = the **control plane** controller (distributes policy + routes via **OMP**).
- **vBond** = orchestrator (onboarding/NAT traversal, zero-touch provisioning).
- **vEdge/cEdge** = the **forwarding plane** CPE at each site (builds the overlay tunnels).
- **OMP** (Overlay Management Protocol) = SD-WAN's BGP-like control protocol between edges and vSmart.
### How it works
- Edges build **IPsec tunnels** across every transport → a **fabric overlay**.
- **App-aware routing**: classify apps (DPI), measure each path's **loss/latency/jitter** (BFD probes), steer per-app to the best path against an **SLA** (e.g. voice → lowest jitter; bulk → broadband).
- **Dynamic path selection / failover**, **FEC/packet duplication** for loss, local internet **breakout** (don't backhaul SaaS).
- **Security:** segmentation (VPNs/segments), integrated NGFW/IPS, **SASE** (SD-WAN + cloud security: SWG/CASB/ZTNA).

### "Integration across legacy constructs"
> *"You overlay SD-WAN on top of the existing MPLS L3VPN rather than ripping it out — MPLS becomes just one transport in the fabric alongside internet and LTE. Sites migrate gradually; the overlay gives app-aware steering and central policy while the legacy WAN still carries what it always did. CP/FP split means the edges keep forwarding at line rate while vSmart centralises the routing/policy decisions."*

## 3. SD-WAN vs MPLS
| | MPLS L3VPN | SD-WAN |
|---|---|---|
| Path | single provider circuit | many transports bonded |
| Control | distributed (PE/P) | centralised (vSmart/controller) |
| App awareness | no (QoS only) | yes (DPI, per-app SLA steering) |
| Cost | high $/Mbps | cheap broadband + LTE |
| SLA | hard guarantee | measured/steered, best-effort transports |
| Provisioning | weeks | zero-touch, minutes |

## 4. Key points
- SD-WAN is CP/FP abstraction applied to the WAN: vSmart centralises control via OMP, the edges keep forwarding, and policy steers each app across MPLS/broadband/LTE by measured loss/latency/jitter against an SLA.
- MPLS becomes one transport in the overlay, not the enemy — integrate, don't rip-and-replace.
- SASE = SD-WAN fabric plus cloud-delivered security (SWG, CASB, ZTNA, FWaaS) — security and the WAN converge at the edge.

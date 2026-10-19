# QoS CHEAT SHEET

## What this is & why it matters
QoS (Quality of Service) decides **which traffic wins when a link is congested**. On a real-time platform, live
price feeds, trading and voice are latency/jitter-sensitive — they must be prioritised over bulk/replication
traffic, especially across the WAN edge. Know the pipeline (classify → mark → queue → police/shape → drop), the
DSCP values, and the police-vs-shape distinction cold.

> Enterprise/SP QoS = classify → mark → queue → drop/shape.

## 0. The model (say this)
**Classify** traffic → **mark** it (so everyone trusts the mark) → **queue/schedule** at congestion points →
**police/shape** to rates → **drop intelligently** before tail-drop. You only need QoS where there's contention (WAN edge, uplinks).

## 1. Marking values (memorise the table)
| Layer | Field | Notes |
|---|---|---|
| L2 | **CoS** (802.1p) | 3 bits in the 802.1Q tag, 0–7 |
| L3 | **DSCP** (DiffServ) | 6 bits in IP ToS byte, 0–63 |
| MPLS | **EXP/TC** | 3 bits in the label |

**Key DSCP names:** `EF` (46) = voice; `CS6/CS7` (48/56) = network control; `AF4x` (34/36/38) = video/interactive;
`AF3x/AF2x/AF1x` = business tiers; `BE/default` (0) = best-effort/scavenger. **PHB** = per-hop behaviour the mark triggers.
- **EF** → low-latency priority queue. **AF** = 4 classes × 3 drop precedences (AF*1* low drop, AF*3* high drop). **CS** = class selector (legacy IP-precedence compatible).

## 2. Mechanisms (know what each does)
- **Classification**: by ACL, DSCP, interface, NBAR/app-id.
- **Marking**: set DSCP/CoS at the trust boundary (mark once at the edge, trust in the core).
- **Policing**: enforce a rate, **drop or re-mark** excess (token bucket: CIR, Bc, Be). Hard, no buffering.
- **Shaping**: **buffer** excess to a rate (smooths bursts, adds delay). Used outbound toward a slower link.
- **Queuing/Scheduling**: **LLQ** (strict priority for EF/voice) + **CBWFQ** (weighted bandwidth per class). **WRR/DWRR/WFQ**.
- **Congestion avoidance**: **WRED** (drop lower-priority/AF-high-drop early to avoid TCP global sync & tail-drop).
- **Trust boundary**: where you start believing CoS/DSCP — push it to the access edge; police what customers send.

## 3. Cisco MQC (the canonical config pattern — memorise the 3 steps)
```
! 1) CLASSIFY
class-map match-any VOICE
 match dscp ef
class-map match-any BUSINESS
 match dscp af31 af32
!
! 2) POLICY (mark / queue / shape / drop)
policy-map WAN-EDGE
 class VOICE
  priority percent 30            ! LLQ - strict priority, policed
 class BUSINESS
  bandwidth percent 40           ! CBWFQ guaranteed share
  random-detect dscp-based       ! WRED
 class class-default
  fair-queue
!
! 3) ATTACH
interface GigabitEthernet0/1
 service-policy output WAN-EDGE
```
Police example:
```
 police cir 10000000 bc 1500000 conform-action transmit exceed-action set-dscp-transmit af11 violate-action drop
```
Shape example: `shape average 50000000`.

## 4. SP / MPLS QoS
- Map DSCP → MPLS **EXP** at ingress PE; core queues on EXP (3 bits = 8 classes).
- **Uniform vs Pipe vs Short-pipe** tunnelling models = how DSCP/EXP is copied in/out of the MPLS domain.

## 5. Soundbites
- *"Mark at the trust boundary, trust in the core. EF gets a strict-priority LLQ for voice, AF classes get CBWFQ with WRED, everything else is best-effort."*
- *"Policing drops or re-marks and adds no delay; shaping buffers and smooths — so I police inbound/ingress and shape outbound toward a slower circuit."*
- *"WRED prevents TCP global synchronisation by dropping selectively before the queue tail-drops."*
- *"Latency-sensitive flows (live price feeds, trading) map to EF/AF4; bulk/replication to scavenger."*

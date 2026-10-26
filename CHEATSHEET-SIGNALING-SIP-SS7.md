# SIGNALING CHEAT SHEET — SIP + SS7 (Diameter)

> Telco signaling territory. Goal: understand the role, the key messages, and the network-engineer angle
> (ports, transport, security).

---

# SIP (Session Initiation Protocol) — VoIP call signaling
- **What it is:** an **application-layer signaling** protocol (RFC 3261) that **sets up, modifies, tears down** media sessions (voice/video). SIP only signals; **media rides RTP/SRTP** separately. Session described by **SDP** (codecs, IPs, ports).
- **Transport/ports:** **5060** (UDP/TCP, cleartext), **5061** (TLS = SIPS). Media RTP = high UDP range.
- **Looks like HTTP:** text, request/response, methods + status codes.

### Components
**UAC/UAS** (user agents = phones/softphones) · **Proxy** (routes requests) · **Registrar** (location, `REGISTER`) ·
**Redirect server** · **SBC** (Session Border Controller — the security/NAT/interworking edge between networks).

### Methods (memorise)
`INVITE` (start) · `ACK` · `BYE` (hang up) · `CANCEL` · `REGISTER` (bind contact) · `OPTIONS` (capabilities/keepalive) · `SUBSCRIBE/NOTIFY` (events) · `REFER` (transfer).
### Responses (HTTP-like)
**1xx** provisional (100 Trying, 180 Ringing) · **2xx** success (200 OK) · **3xx** redirect · **4xx** client (401/407 auth, 404, 486 Busy) · **5xx** server · **6xx** global (603 Decline).
### Call flow (one breath)
`INVITE → 100 Trying → 180 Ringing → 200 OK → ACK` … RTP media flows … `BYE → 200 OK`.

### Network-engineer angle
- **NAT traversal** is the classic pain (SDP carries private IPs) → **SBC**, STUN/TURN/ICE, or ALG.
- **Security:** SIP over **TLS (5061)** + **SRTP** for media; SBC for topology hiding, DoS protection, toll-fraud.
- **QoS:** mark signaling CS3, voice media **EF (DSCP 46)** → LLQ.
- **Troubleshoot:** SIP ladder diagram (`sngrep`/Wireshark), one-way audio = RTP/NAT/firewall, 401/407 = auth, 488 = codec mismatch.

> **Summary:** SIP is the call-control layer — INVITE/180/200/ACK/BYE, SDP for media negotiation, RTP/SRTP carrying the actual voice, and SBCs at the edge for NAT, security and interworking. The network side is transport, TLS/SRTP, QoS marking and NAT traversal.

---

# SS7 (Signaling System 7) — legacy PSTN/telco signaling
- **What it is:** the **out-of-band signaling** network behind traditional **PSTN/PLMN** — call setup, SMS, roaming, number translation. **Separate from the voice path** (out-of-band = signaling on its own network).
- **Why it still matters:** mobile interconnect, **roaming**, SMS, and a notorious **security** story (SS7 attacks = location tracking, SMS/2FA interception) — relevant to any platform doing SMS OTP.

### Stack (rough OSI-ish)
- **MTP1/2/3** = transport (physical/data-link/network).
- **SCCP** = enhanced routing (global title translation, GTT).
- **TCAP** = transaction layer for queries.
- **Application parts:** **ISUP** (trunk call setup/teardown), **MAP** (mobile: roaming, SMS, auth), **INAP/CAP** (intelligent network / prepaid), **CAMEL**.
- **SIGTRAN** = SS7 over IP (**M3UA/SUA over SCTP**) — how legacy SS7 rides modern IP cores.

### Modern successor
- **Diameter** (RFC 6733, over **SCTP/TCP**) replaced RADIUS in LTE/IMS for AAA + policy (Gx/Gy/S6a). **5G** moves to **HTTP/2 + REST (SBA)**. Know the evolution: **SS7 → Diameter → 5G HTTP/2**.

### Network-engineer angle
- **SIGTRAN runs on SCTP** (multi-homed, multi-streamed — know SCTP exists and why: resilience for signaling).
- **Security:** SS7 has weak native auth → **SS7 firewalls / GTT screening / Diameter Edge Agents** at interconnect borders. A classic network-security topic.

> **Summary:** SS7 is the out-of-band PSTN/mobile signaling network — MTP/SCCP/TCAP with ISUP for trunks and MAP for mobile/roaming/SMS — now carried over IP via SIGTRAN (M3UA over SCTP), and being replaced by Diameter in LTE and HTTP/2 service-based interfaces in 5G. The network-engineer angle is SCTP, SIGTRAN and SS7/Diameter signaling firewalls.

---

## One-line summary
SIP = modern IP call control (text, HTTP-like, media over RTP, secured with TLS/SRTP and SBCs). SS7 = legacy out-of-band telco signaling (ISUP/MAP) now over IP via SIGTRAN/SCTP, succeeded by Diameter and 5G HTTP/2. For a network engineer the focus is the transport, security and QoS around them.

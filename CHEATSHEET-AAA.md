# AAA CHEAT SHEET (RADIUS / TACACS+ / 802.1X)

## What this is & why it matters
AAA = **Authentication** (who are you), **Authorization** (what may you do), **Accounting** (what did you do).
It's how network devices and network access (admin logins, VPN, Wi-Fi, 802.1X NAC) are controlled and audited
— core to any regulated operator's security and compliance. The classic question is **RADIUS vs TACACS+** — know that table.

> AAA = Authentication (who), Authorization (what you can do), Accounting (what you did).

## 0. RADIUS vs TACACS+ (the table they want)
| | **RADIUS** | **TACACS+** |
|---|---|---|
| Body | IETF (RFC 2865/2866) | Cisco (now open draft) |
| Transport | **UDP** 1812 auth / 1813 acct (old 1645/1646) | **TCP** 49 |
| Encryption | only the **password** | **entire payload** |
| AuthN/AuthZ | **combined** | **separated** (granular command authz) |
| Use case | **network access** (802.1X, VPN, Wi-Fi, NAC) | **device admin** (per-command control on routers/switches) |
| Multivendor | universal | Cisco-leaning but widely supported |

Mnemonic: **TACACS+ = TCP, Total encryption, device admin; RADIUS = UDP, access (dot1x/VPN).**

## 1. Cisco AAA config pattern
```
aaa new-model
!
radius server PSN1
 address ipv4 10.1.1.10 auth-port 1812 acct-port 1813
 key <secret>
tacacs server TAC1
 address ipv4 10.1.1.20
 key <secret>
!
aaa group server tacacs+ ADMIN
 server name TAC1
!
! login auth: try TACACS+, fall back to local
aaa authentication login default group ADMIN local
aaa authorization exec default group ADMIN local
aaa authorization commands 15 default group ADMIN local   ! per-command authz (TACACS+ strength)
aaa accounting commands 15 default start-stop group ADMIN
aaa accounting exec default start-stop group ADMIN
!
line vty 0 4
 login authentication default
```
Always keep a **local fallback** (`local`) so you're not locked out if the AAA server dies.

## 2. 802.1X (port-based NAC — RADIUS)
- **Supplicant** (endpoint) ↔ **Authenticator** (switch/AP) ↔ **Authentication Server** (RADIUS/ISE).
- EAP over LAN (**EAPOL**) endpoint→switch; switch wraps EAP in RADIUS to the server.
- Outcomes: dynamic **VLAN assignment**, **dACL**, SGT. **MAB** (MAC Auth Bypass) for printers; **WebAuth** for guests.
```
dot1x system-auth-control
interface Gi0/5
 authentication port-control auto
 dot1x pae authenticator
 mab
 authentication host-mode multi-auth
```
EAP methods: **EAP-TLS** (cert both sides, strongest), **PEAP/EAP-MSCHAPv2** (server cert + user pw), **EAP-FAST**.

## 3. Verify / troubleshoot
```
show aaa servers
test aaa group ADMIN <user> <pw> legacy
debug radius / debug tacacs
show authentication sessions interface Gi0/5
show dot1x all
```
- Auth fails everywhere → shared **key** mismatch, wrong port/UDP-vs-TCP, ACS/ISE policy, or NAS-IP not registered.
- Locked out → console + local fallback.

## 4. Soundbites
- *"TACACS+ separates authN/authZ and encrypts the whole payload over TCP — that's why it's for device admin with per-command authorization. RADIUS is UDP, combines authN/authZ, encrypts only the password, and is the standard for network access — 802.1X, VPN, Wi-Fi."*
- *"For NAC I run 802.1X with EAP-TLS, MAB for headless devices, dynamic VLAN/dACL on success, and a quarantine VLAN on failure — always with a local fallback so a dead AAA server doesn't lock the fleet out."*

# Day 2 — BGP Multihoming & Traffic Engineering (YOU build it)

This is the lab that proves you can run a real edge. You own **AS 65000** (r1 + r2), dual-homed to
two ISPs. The ISPs (r3 = ISP-A, r4 = ISP-B) come up working — **you build everything inside AS 65000.**
Each task: **do it → predict the result → verify → only then read the answer key at the bottom.**

```
  AS 65100 (ISP-A)  r3                       AS 65200 (ISP-B)  r4
  adv 8.8.8.0/24, 100.64.0.0/24              adv 8.8.8.0/24, 203.0.113.0/24
        | 10.0.13.0/30  eBGP                       | 10.0.24.0/30  eBGP
        | (r3=.2)                                  | (r4=.2)
   r1 (1.1.1.1) .1 ---- iBGP 10.0.12.0/30 ---- .2 (2.2.2.2) r2
   eth1->ISP-A   eth2                          eth2   eth1->ISP-B
        \________________ AS 65000 ________________/
                  we originate 192.0.2.0/24
```

**8.8.8.0/24 is advertised by BOTH ISPs** → you will have two ways out. That choice is the whole lab.

Done for you at deploy: all interface IPs, and `ip route 192.0.2.0/24 Null0` on r1 and r2.
You must paste **only `router bgp ...` config** — never touch interfaces or ISPs.

Enter a router: `sudo docker exec -it clab-day2-te-r1 vtysh`  (swap r1/r2)

---

## The BGP best-path algorithm (the most-tested BGP topic)
When two paths to the same prefix exist, BGP walks this list **top-down, first tiebreak wins**:

1. **Weight** (Cisco/FRR local-only, higher wins) — never leaves the router
2. **Local Preference** (higher wins) — your AS-wide *outbound* policy knob
3. Locally originated (network/redistribute) wins
4. **Shortest AS-path** (fewer hops wins) — the lever AS-path *prepend* pulls
5. Lowest **Origin** (IGP < EGP < incomplete)
6. Lowest **MED** (a *hint to your neighbour* about your preferred inbound link)
7. **eBGP over iBGP**
8. Lowest IGP metric to the next-hop
9. Oldest / lowest router-id … (final tiebreakers)

> Memorise the mnemonic: **W**e **L**ove **O**ranges **A**S **O**ranges **M**ean **P**ure **R**efreshment
> (Weight, LocalPref, Originate, AS-path, Origin, MED, Paths/eBGP, Router-id).

---

# TASK 1 — Bring up the three BGP sessions (recap of day1b)
Build on **r1**: eBGP to ISP-A (10.0.13.2, AS65100), iBGP to r2 (10.0.12.2, AS65000),
`next-hop-self` toward r2, and originate `network 192.0.2.0/24`.
Then the mirror on **r2**: eBGP to ISP-B (10.0.24.2, AS65200), iBGP to r1, next-hop-self, originate 192.0.2.0/24.

**Predict:** how many neighbours Established on each? Does r1 see 8.8.8.0/24 from one ISP or two?
**Verify:**
```
show ip bgp summary
show ip bgp 8.8.8.0/24
```
> Hint: r1 learns 8.8.8.0/24 directly from ISP-A (eBGP) AND from r2 over iBGP (ISP-B's copy).
> Two paths. Which is best, and **why** — read the algorithm above. (It'll be the eBGP one. Which rule?)

✅ Done when both routers are Established to their ISP + each other, and `show ip bgp 8.8.8.0/24` shows **2 paths** with one `>`.

---

# TASK 2 — OUTBOUND traffic engineering with Local Preference
Goal: **all traffic leaving AS 65000 should exit via ISP-A (r1)**, even from r2.
Local-pref is AS-wide and higher wins (rule 2) — set it where the route *enters* your AS (on r1, inbound from ISP-A).

**Your task:** on r1, apply local-pref 200 to routes learned from ISP-A, and re-advertise.
**Predict:** what does r2's best path to 8.8.8.0/24 become — its own eBGP link to ISP-B, or across to r1?
**Verify on r2:**
```
show ip bgp 8.8.8.0/24
show ip route 8.8.8.0/24
```
> Hint: you need a **route-map** that `set local-preference 200`, applied to the r1↔ISP-A neighbour
> `in`. Local-pref is carried over iBGP, so r2 will see 200 and prefer the path via r1.
> Watch rule 2 beat rule 7 (eBGP>iBGP) — that's the lesson: local-pref outranks the eBGP preference.

✅ Done when **r2's** best path to 8.8.8.0/24 points across the iBGP link to r1, not out its own ISP-B link.

---

# TASK 3 — INBOUND traffic engineering (the hard direction)
Goal: make the **internet prefer ISP-A to reach our 192.0.2.0/24**. You can't set local-pref in
someone else's AS — so you influence what *they* see. Two tools:

**3a) AS-path prepend (the blunt, reliable hammer):** on r2, prepend your own AS a few times when
advertising 192.0.2.0/24 *out to ISP-B*. ISP-B's path now looks longer (rule 4) so the outside world
prefers ISP-A.
**3b) MED (the polite hint):** only works toward the *same* neighbour AS; lower MED = preferred. With two
different ISPs it usually won't decide anything — understand *why* (different ASes don't compare MED by default).

**Predict:** after prepending on r2, what does r3 (ISP-A) and r4 (ISP-B) show for 192.0.2.0/24's AS-path?
**Verify (peek at the ISPs — read-only):**
```
sudo docker exec clab-day2-te-r3 vtysh -c "show ip bgp 192.0.2.0/24"
sudo docker exec clab-day2-te-r4 vtysh -c "show ip bgp 192.0.2.0/24"
```
> Hint: route-map with `set as-path prepend 65000 65000`, applied to the ISP-B neighbour **out**.
> r4 will see AS-path `65000 65000 65000`; r3 still sees `65000`. Shorter wins → inbound favours ISP-A.

✅ Done when r4's view of 192.0.2.0/24 has a longer AS-path than r3's.

---

# TASK 4 — Communities (tag once, act anywhere)
Goal: let ISP-A tag certain routes so *you* auto-deprioritise them. Real ISPs publish "if you tag a
route 65100:120 we set local-pref 120" menus — you'll consume one.

**Your task:** on r1, match a community on routes from ISP-A and set local-pref from it; enable
`neighbor ... send-community`. (Stretch: have r1 *set* a community on 192.0.2.0/24 outbound.)
**Verify:**
```
show ip bgp 8.8.8.0/24          # look for the Community line
show bgp community              # all community-tagged routes
```
> Hint: `bgp community-list`, then a route-map matching it. `set community 65000:100 additive` to tag.
> Interview line: "communities are route tags — I tag at ingress and act on them anywhere in my AS,
> which is how ISPs offer customers self-service traffic engineering."

---

# TASK 5 — Don't become a transit AS (the filter that saves your job)
Right now, are you re-advertising ISP-A's routes to ISP-B? If so, you're offering **free transit** —
the internet could route through your little AS. A multihomed customer must announce **only its own
prefixes** outbound.

**Predict first:** on r4 (ISP-B), can you see 100.64.0.0/24 (which only ISP-A originates)? If yes, you're transit.
```
sudo docker exec clab-day2-te-r4 vtysh -c "show ip bgp"
```
**Your task:** apply an outbound filter on **both** r1 and r2 so you advertise **only 192.0.2.0/24** to the ISPs.
**Verify:** r4 should now see 192.0.2.0/24 from you but **not** 100.64.0.0/24.
> Hint: `ip prefix-list OWN permit 192.0.2.0/24`, route-map `match ip address prefix-list OWN`, apply `out`
> to each ISP neighbour. This is the single most important real-world eBGP edge policy.

✅ Done when neither ISP can reach the other ISP's prefixes through you.

---

# Interview soundbites to lock in
- *"Outbound I steer with local-pref (AS-wide, higher wins); inbound I steer with AS-path prepend, and
  MED only between links to the same neighbour AS."*
- *"Best path is weight, local-pref, locally-originated, AS-path, origin, MED, eBGP-over-iBGP, then IGP
  metric and router-id."*
- *"As a multihomed customer I filter outbound to my own prefixes only — otherwise I'd be unintentional
  transit between my two upstreams."*
- *"Communities are tags: set once at ingress, match anywhere — the basis of ISP self-service TE menus."*

---
---

# 🔑 ANSWER KEY — only after you've tried each task

### Task 1
r1:
```
configure terminal
router bgp 65000
 bgp router-id 1.1.1.1
 no bgp ebgp-requires-policy
 neighbor 10.0.13.2 remote-as 65100
 neighbor 10.0.12.2 remote-as 65000
 neighbor 10.0.12.2 next-hop-self
 network 192.0.2.0/24
end
```
r2:
```
configure terminal
router bgp 65000
 bgp router-id 2.2.2.2
 no bgp ebgp-requires-policy
 neighbor 10.0.24.2 remote-as 65200
 neighbor 10.0.12.1 remote-as 65000
 neighbor 10.0.12.1 next-hop-self
 network 192.0.2.0/24
end
```
Best path to 8.8.8.0/24 = the eBGP one (rule 7, eBGP > iBGP) — until Task 2 changes it.

### Task 2 (on r1)
```
configure terminal
route-map FROM_ISPA permit 10
 set local-preference 200
exit
router bgp 65000
 neighbor 10.0.13.2 route-map FROM_ISPA in
end
clear ip bgp * soft
```
Now r2 prefers the path via r1 (local-pref 200 > default 100), proving rule 2 beats rule 7.

### Task 3 (on r2)
```
configure terminal
route-map PREPEND_OUT permit 10
 set as-path prepend 65000 65000
exit
router bgp 65000
 neighbor 10.0.24.2 route-map PREPEND_OUT out
end
clear ip bgp * soft
```
r4 sees `65000 65000 65000`; r3 sees `65000`. Inbound now favours ISP-A.

### Task 4 (on r1) — consume an ISP community
```
configure terminal
bgp community-list standard ISPA_LOWPREF permit 65100:120
route-map FROM_ISPA permit 5
 match community ISPA_LOWPREF
 set local-preference 80
route-map FROM_ISPA permit 10
 set local-preference 200
exit
router bgp 65000
 neighbor 10.0.13.2 send-community
end
clear ip bgp * soft
```
(Set a community outbound: `route-map ... permit 10 / set community 65000:100 additive`.)

### Task 5 (on BOTH r1 and r2)
```
configure terminal
ip prefix-list OWN seq 5 permit 192.0.2.0/24
route-map ONLY_OWN permit 10
 match ip address prefix-list OWN
exit
router bgp 65000
 neighbor <ISP-neighbor-ip> route-map ONLY_OWN out
end
clear ip bgp * soft
```
r1's ISP neighbour = 10.0.13.2, r2's = 10.0.24.2. After this, neither ISP sees the other's prefixes via you.

# Beginner Networking — Lesson 1 (for firewall engineers)

**Who this is for:** engineers with a firewall/security background who want to get comfortable with service-provider style routing. The course bridges **from what you already know (firewalls) to dynamic routing and the internet edge.** Plain English, worked examples, every lesson tied to a real command in the lab and a one-line summary.

**What is here:** Lesson 1 is written in full below. The course arc lists the planned lessons 2–10 as an outline; until they are written, the matching material is in [STUDY.md](STUDY.md) and the [cheat sheets](CHEATSHEETS.md).

**How to use:** read the lesson, run the example in the Codespace lab, then check you can restate the summary in your own words. The lab is `github.com/falshaw/netlab` (open a Codespace → `cd day1-bgp && sudo containerlab deploy`).

**The one mindset shift:** a firewall, you *hand-feed* routes (static routes + default gateway). A router can also **learn routes automatically by talking to other routers** — that's "dynamic routing" (OSPF, BGP, IS-IS). That single idea is 80% of what makes you "a networker." Everything else you basically already do.

---

## Topics, decoded

| Topic | What it really means | Lesson |
|---|---|---|
| BGP, OSPF, IS-IS | routers auto-sharing routes (inside a company, and between companies) | 3,4,5 |
| MPLS (RSVP-TE) | how big carriers label & steer traffic | 6 |
| AAA, SIP, SS7 | login/auth + telco phone signalling | 10 |
| hybrid & cloud, private connectivity | linking a DC to Azure/AWS privately + failover | 7,9 |
| resilience / failover | keeping it up when a link dies | 7 |
| monitoring, logging, automation | see problems + script the boring stuff | (woven in) |
| SD-WAN / SDN, CP/FP abstraction | modern WAN, "brain vs muscle" split | 9 |
| Kafka, Kubernetes | message bus + container orchestration networking | 10 |
| **CDN, WAF, DDoS — front-line defence** | protecting the internet edge | 8 |
| IETF / IEEE / NANOG | who writes the standards | 10 |

---

## Course arc (outline — only Lesson 1 is written so far)

1. **Firewall vs router — interfaces, IPs, the routing table** *(understand the setup you built)* ← start here
2. **Static routes & the default gateway** → and *why dynamic routing has to exist*
3. **OSPF** — routers auto-share routes *inside one company*
4. **BGP** — routers share routes *between companies / the internet* (you tasted this Day 1)
5. **IS-IS** — OSPF's service-provider cousin (enough to talk about it)
6. **MPLS & labels** — how carriers move traffic fast (concept)
7. **Resilience & failover** — keeping it up (redundant paths, sub-second detection)
8. **The edge: CDN / WAF / DDoS / anycast** — firewall-world concepts, in networking words
9. **SD-WAN / SDN + cloud connectivity** — modern WAN + hybrid cloud
10. **The "just be aware" list** — AAA, SS7/SIP, Kafka/K8s, standards bodies

---

# Lesson 1 — Firewall vs router: interfaces, IPs, and the routing table

### A. The mindset bridge (you already know this)

| On a firewall you have… | On a router it's… |
|---|---|
| Interfaces (eth1, eth2) with IPs, in zones | Interfaces (eth1, eth2) with IPs — **same**, just no zones |
| A routing table / static routes / default gateway | A routing table (`show ip route`) — **identical idea** |
| Security policy / rules | ACLs (`access-list`) — same idea, simpler |
| NAT | NAT — **same** |
| An HA pair that fails over | Routing protocols + BFD do the failover |
| **You type in the routes the firewall should use** | **Routers can also learn routes from each other automatically** ← the new bit |

So: a router = the forwarding engine you already understand, whose *only* job is moving packets between networks. A firewall is a router that *also* enforces policy. You're not starting from zero — you're filling in the "routers talk to each other" gap.

### B. Understand the setup you built today (Day 1)

You started three routers wired in a triangle:

```
        r1 (AS 65001, "me" = 1.1.1.1)
       /  \
 eth1 /    \ eth2
     /      \
   r2 ------ r3
 (AS 65002) (AS 65003)
  2.2.2.2    3.3.3.3
```

- **Each router is a separate "company" / network** — that's what an **AS (Autonomous System) number** means (65001, 65002, 65003). Think of three different ISPs, or your company + two partners.
- **The links** (e.g. `10.0.12.0/30`) are like a cable between two firewalls. `/30` = a tiny subnet with exactly **2 usable IPs** — one for each end (`10.0.12.1` = r1, `10.0.12.2` = r2). You use /30 for point-to-point links so you don't waste addresses.
- **The loopback** (`lo`, e.g. `1.1.1.1/32`) = a "this is me" identity IP. It's not on a physical wire, so it never goes down — routers use it as their stable name/ID. (You've seen loopbacks on firewalls for management.)

### C. Example — read the routing table (run this)

Make sure the lab is up, then get into r1 and look at its routing table:
```bash
# if the routers aren't running:  cd day1-bgp && sudo containerlab deploy
sudo docker exec -it clab-day1-bgp-r1 vtysh
show ip route
```

You'll see lines flagged with a **letter** — that letter is *how r1 learned the route*:

| Code | Means | Firewall parallel |
|---|---|---|
| `C` | **Connected** — a network directly on r1's own interface | the networks on your firewall's interfaces |
| `B` | **BGP** — a network another router *told* r1 about | **the new idea — r1 didn't know this until r2/r3 announced it** |
| `O` | OSPF-learned (Lesson 3) | — |
| `S` | Static — you typed it in | a static route on a firewall |

**The lightbulb:** r1 knows `2.2.2.2` and `3.3.3.3` *even though they're not on its interfaces* — because r2 and r3 **announced them over BGP**. On a firewall you'd have hand-typed those routes. Here the routers shared them automatically. **That is "being a networker."**

### D. Summary (Lesson 1)
> Coming from firewalls, the routing table and static routes are already familiar — `show ip route`, connected vs static, next-hops. The new part is routers *advertising* routes to each other dynamically — OSPF inside a domain, BGP between them — instead of an engineer hand-feeding every route.

---

*Lessons 2–10 are not written yet; see the course arc above for where each topic is covered in STUDY.md and the cheat sheets.*

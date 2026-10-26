# netlab — zero-setup network lab (containerlab + FRR)

A hands-on routing lab for learning BGP, OSPF, IS-IS, MPLS, DDoS edge defence and resilience. It runs in **GitHub Codespaces**: nothing to install locally, no VMs, no nested virtualisation. You open a Codespace and you are typing real router commands.

The routers are **FRRouting (FRR)** containers — free, open source, with a Cisco-like CLI (`router bgp`, `show ip bgp`, `show ip route`). No licensed images are needed.

## Why

Vendor router images (IOS-XR, Junos) need nested virtualisation, licences and a beefy host. FRR plus [containerlab](https://containerlab.dev) gives a disposable multi-router topology in about 30 seconds, in the browser. Breaking a lab costs nothing: destroy and redeploy.

## How it works

- `.devcontainer/devcontainer.json` uses the containerlab docker-in-docker devcontainer image (4 CPU / 8 GB), installs the containerlab VS Code extension and pre-pulls `quay.io/frrouting/frr:10.7.1` and `ghcr.io/srl-labs/network-multitool`.
- Each lab folder holds a `*.clab.yml` topology, one `rN.conf` FRR config per router and a `.drawio` diagram.
- `common/daemons` is mounted into every node as `/etc/frr/daemons` (enables bgpd, ospfd, ospf6d, isisd, ldpd, bfdd).

## Start (one time, ~2 min)

1. On the GitHub page of `github.com/falshaw/netlab` click **Code → Codespaces → Create codespace on main**.
2. Wait until the terminal prints `READY. Start Day 1`.
3. Deploy the first lab:
   ```bash
   cd day1-bgp
   sudo containerlab deploy
   ```
4. Enter a router:
   ```bash
   sudo docker exec -it clab-day1-bgp-r1 vtysh
   ```
   Then try `show ip bgp summary`, `show ip route`, `show running-config`. Leave with `exit`.

Reset a lab with `sudo containerlab destroy --cleanup` then `sudo containerlab deploy`. Do not `docker restart` a lab node — that removes its veth links; always destroy and redeploy.

## Labs

| Folder | Topic | State at deploy |
|---|---|---|
| `day1-bgp/` | eBGP triangle, 3 ASes, loopbacks advertised | fully configured (reference) |
| `day1/` | BGP fundamentals | empty canvas: wiring + IPs, no routing |
| `day1b/` | iBGP, next-hop-self, route reflectors, communities (4 routers) | empty canvas: wiring + IPs, no BGP |
| `day2/` | Anycast + multihoming | empty canvas |
| `day2-te/` | BGP multihoming & traffic engineering (AS 65000 dual-homed to two ISPs) | ISPs pre-configured, you build AS 65000 |
| `day3/` | DDoS defence: RTBH + FlowSpec | empty canvas |
| `day4/` | OSPF, then IS-IS | empty canvas |
| `day5/` | MPLS L3VPN + Segment Routing (control plane) | empty canvas |
| `day6/` | Resilience: BFD + ECMP | empty canvas |
| `day7/` | Capstone: mini internet edge | empty canvas |
| `ospf-lab/` | OSPF on the 3-router triangle | interfaces + loopbacks only |

Labs with a `NOTES.md` (`day1`, `day1b`, `day2-te`) contain step-by-step tasks and an answer key.

## Study material

- [STUDY.md](STUDY.md) — the day-by-day plan with commands and break/fix exercises.
- [COURSE.md](COURSE.md) — a beginner course bridging from firewall concepts to dynamic routing.
- [CHEATSHEETS.md](CHEATSHEETS.md) — index of the topic cheat sheets (BGP, OSPF, MPLS, edge defence, SD-WAN, SIP/SS7, QoS, AAA, Kafka/K8s).

## Images

| Image | Role |
|---|---|
| `quay.io/frrouting/frr:10.7.1` | the routers (BGP/OSPF/IS-IS/MPLS/SR/BFD) |
| `ghcr.io/srl-labs/network-multitool` | Linux host for ping/curl tests |

The FRR image is pinned. The official FRR images are published on `quay.io/frrouting/frr`; the Docker Hub `frrouting/frr:latest` tag stopped at 8.4 (2022). The `frr version` line in every `rN.conf` matches the pinned tag. To move to a newer release, change the tag in every `*.clab.yml` and in `.devcontainer/devcontainer.json`.

## Limitations

- Codespaces cannot load kernel MPLS modules, so the MPLS labs show the control plane (labels, VRFs, VPNv4) but packets may not be label-switched.
- RSVP-TE is not implemented in FRR; it is covered conceptually in `CHEATSHEET-MPLS.md`.

## Running locally (optional)

The devcontainer is built for **GitHub Codespaces**. It runs Docker-in-Docker as a privileged container, and containerlab then creates veth links and network namespaces inside it. On a Codespaces VM that is harmless. On **Docker Desktop (Windows/macOS)** a privileged containerlab-in-Docker setup shares Docker Desktop's single utility VM and can take down that VM's networking, which stops every other container on the machine until Docker Desktop is restarted. Do not open this devcontainer locally on Docker Desktop.

To run the labs locally, use a native Linux host or a WSL2 distro with its own Docker Engine (not Docker Desktop), install containerlab (`bash -c "$(curl -sL https://get.containerlab.dev)"`) and deploy any lab folder with `sudo containerlab deploy` as above.

On Windows, clone with the repository's `.gitattributes` in effect (any recent Git does this). It forces LF line endings; a CRLF copy of `common/daemons` or an `rN.conf` breaks FRR inside the container (`$'': command not found`).

## License

MIT — see [LICENSE](LICENSE).

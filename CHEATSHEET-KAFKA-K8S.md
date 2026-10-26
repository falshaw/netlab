# KAFKA / KUBERNETES CHEAT SHEET (network angle)

## What this is & why it matters
Many high-traffic web platforms are event-driven (user events, state updates and transactions stream through **Kafka**) and
run on **Kubernetes**. As the *network* engineer you don't write the apps — you make the **networking** around them
work: how clients reach Kafka brokers, how pods talk, how traffic enters the cluster, and how you segment/secure it.
This sheet covers working knowledge from the network angle.

---

# KAFKA (distributed event/message bus)
## Concepts (one breath)
- **Producers** write **events** to **topics**; topics split into **partitions** (ordering + parallelism); **consumers** in **consumer groups** read, each partition to one consumer in the group.
- **Brokers** store partitions; **replication factor** = copies across brokers; each partition has a **leader** + **followers**.
- **Offset** = a consumer's position; retention by time/size (it's a log, not a queue — re-readable).
- **Coordination:** **KRaft** (modern, built-in Raft) replaced **ZooKeeper**.

## The classic network gotcha: `advertised.listeners`
- A broker tells clients how to reach it via **`advertised.listeners`**. If that's wrong (internal hostname/IP a client can't resolve/route), clients bootstrap then **fail to reach the actual broker** — classic Kafka networking bug.
- Multiple **listeners** for different planes (internal vs external/PLAINTEXT vs SSL vs SASL_SSL), each with its own advertised address.
- Ports: **9092** (plaintext), **9093** (TLS/SASL) commonly.
- In K8s: external access needs **per-broker** addressing (LoadBalancer/NodePort per broker, or an Ingress that does TCP) because a client must reach a **specific** partition leader, not a round-robin VIP.
> **Summary:** for Kafka the network work is `advertised.listeners` — it must hand clients an address they can actually route to, and because clients talk to specific partition leaders you can't just front brokers with one VIP — you need per-broker external addressing. Security is TLS + SASL with network policies restricting who reaches 9093.

## Security/network
- **TLS** + **SASL** (SCRAM/OAuth) for auth; **ACLs** per topic.
- **NetworkPolicy** to limit which pods reach brokers; mTLS via service mesh.

---

# KUBERNETES (orchestration — network angle)
## Core objects
- **Pod** (smallest unit, 1+ containers, shares a network namespace/IP) → **ReplicaSet** → **Deployment**.
- **Service** = stable VIP/DNS in front of pods: **ClusterIP** (internal), **NodePort** (node:port), **LoadBalancer** (cloud LB), **ExternalName**.
- **Ingress** = L7 HTTP(S) routing into the cluster (host/path → service), via an ingress controller (nginx, Traefik, Envoy). **Gateway API** = its successor.
- **Namespace** = scoping; **ConfigMap/Secret**; **DaemonSet/StatefulSet** (Kafka = StatefulSet).

## Networking model (the network engineer's part)
- **Flat model rules:** every pod gets its own IP; **all pods can reach all pods without NAT**; nodes can reach all pods.
- **CNI** plugin implements it: **Calico** (BGP/policy), **Cilium** (eBPF, policy + observability), Flannel (overlay), Weave. **Calico can speak BGP to your fabric** — a real network-engineer hook.
- **kube-proxy** programs Service VIP → pod load-balancing (iptables/IPVS/eBPF).
- **CoreDNS** = in-cluster DNS (`<service>.<namespace>.svc.cluster.local`).
- **NetworkPolicy** = the cluster firewall — default-allow until you apply one; then default-deny + explicit allows (podSelector/namespaceSelector/ports). **This is your segmentation answer.**
- **East-west security / mTLS:** service mesh (Istio/Linkerd) for mTLS, retries, traffic shifting.

## Traffic path (north-south)
Client → cloud **LB** → **Ingress controller** (L7) → **Service** (ClusterIP) → **kube-proxy** → **Pod**. DNS via CoreDNS.

## Verify / troubleshoot (working-knowledge level)
```
kubectl get pods -o wide          # pod IPs + nodes
kubectl get svc,ingress
kubectl describe svc <name>       # endpoints populated? selector match?
kubectl get networkpolicy
kubectl exec -it <pod> -- curl <svc>   # test reachability
```
- Service has no endpoints → selector/label mismatch or pods not ready.
- Can't reach a pod → NetworkPolicy default-deny, CNI issue, or DNS.
- External access fails → Ingress controller, LB, or per-broker addressing (Kafka).

## Key points
- K8s networking is flat — every pod gets a routable IP, no NAT pod-to-pod. The CNI implements it (e.g. Calico or Cilium); NetworkPolicies are the in-cluster firewall, default-deny then explicit allows, with a mesh for mTLS east-west.
- Calico can BGP-peer with the physical fabric, so pod prefixes are advertised into the network — the point where routing skills apply directly.
- For Kafka the networking is `advertised.listeners` correctness and per-broker external addressing, secured with TLS/SASL and NetworkPolicies. The network engineer's job is the transport, not the producers/consumers.

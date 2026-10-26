#!/usr/bin/env bash
# Deploy one lab, wait for the protocols to settle, then fail on a node that is
# not running, a config line FRR rejected, or a point-to-point link that does
# not answer a ping. Each router's protocol state is printed for review.
set -uo pipefail
lab="$1"
cd "$lab"
topo=$(ls *.clab.yml)
name=$(awk '/^name:/{print $2; exit}' "$topo")
sudo containerlab deploy -t "$topo" --reconfigure || exit 1
sleep 75
fail=0
for c in $(sudo docker ps --filter "label=containerlab=$name" --format '{{.Names}}' | sort); do
  echo "================ $c"
  if [ "$(sudo docker inspect -f '{{.State.Running}}' "$c")" != "true" ]; then
    echo "FAIL: not running"; fail=1; continue
  fi
  # A rejected line reads "line N: % Unknown command"; the missing vtysh.conf notice is harmless
  errs=$(sudo docker logs "$c" 2>&1 | grep -E 'line [0-9]+: %' || true)
  if [ -n "$errs" ]; then echo "FAIL: config lines rejected"; echo "$errs"; fail=1; fi
  # Ping the far end of every /30 and /31 link
  for a in $(sudo docker exec "$c" ip -o -4 addr show | awk '$2 ~ /^eth[1-9]/ && ($4 ~ /\/30$/ || $4 ~ /\/31$/) {print $4}'); do
    peer=$(python3 -c "import ipaddress,sys; i=ipaddress.ip_interface(sys.argv[1]); print([str(h) for h in (i.network.hosts() if i.network.prefixlen==30 else i.network) if h!=i.ip][0])" "$a")
    if sudo docker exec "$c" ping -c1 -W2 "$peer" >/dev/null 2>&1; then echo "link $a -> $peer ok"; else echo "FAIL: link $a -> $peer no reply"; fail=1; fi
  done
  sudo docker exec "$c" vtysh -c 'show bgp summary' -c 'show ip ospf neighbor' -c 'show isis neighbor' \
    -c 'show mpls ldp neighbor' -c 'show bfd peers brief' 2>&1 \
    | grep -v -E 'is not running|not enabled|instance not found|^$' || true
done
sudo containerlab destroy -t "$topo" --cleanup >/dev/null
exit $fail

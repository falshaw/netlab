#!/usr/bin/env bash
# Deploy one lab, wait for the protocols to settle, print each router's state and
# fail on a node that is not running or a config line FRR rejected.
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
    echo "NOT RUNNING"; fail=1; continue
  fi
  errs=$(sudo docker logs "$c" 2>&1 | grep -E '% (Unknown|Invalid|Ambiguous|Incomplete)|line [0-9]+:.*%|Error' || true)
  if [ -n "$errs" ]; then echo "CONFIG ERRORS:"; echo "$errs"; fail=1; fi
  sudo docker exec "$c" vtysh -c 'show bgp summary' -c 'show ip ospf neighbor' -c 'show isis neighbor' \
    -c 'show mpls ldp neighbor' -c 'show bfd peers brief' -c 'show ip route summary' 2>&1 \
    | grep -v -E 'is not running|^$' || fail=1
done
sudo containerlab destroy -t "$topo" --cleanup >/dev/null
exit $fail

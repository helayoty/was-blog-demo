#!/usr/bin/env bash
# Narrated inspection for each scenario in the v1.37 WAS demo.
# Usage: ./verify.sh <scenario>
#   setup | basic-job | gang-job | gang-blocking | topology | elastic | raw | standalone
set -euo pipefail
NS=was-demo

hr(){ printf '\n\033[1m%s\033[0m\n' "$*"; }

pods(){ kubectl -n "$NS" get pods -o custom-columns=\
POD:.metadata.name,PHASE:.status.phase,NODE:.spec.nodeName,\
PODGROUP:.spec.schedulingGroup.podGroupName,START:.status.startTime "$@"; }

was_objects(){
  hr "Workloads (scheduling.k8s.io/v1beta1)"
  kubectl -n "$NS" get workloads.scheduling.k8s.io -o wide 2>/dev/null || echo "(none)"
  hr "PodGroups (scheduling.k8s.io/v1beta1)"
  kubectl -n "$NS" get podgroups.scheduling.k8s.io -o wide 2>/dev/null || echo "(none)"
}

case "${1:-}" in
  setup)
    hr "Label workers into two zones for the topology demo"
    mapfile -t W < <(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o name)
    [ "${#W[@]}" -ge 3 ] || { echo "need 3 workers"; exit 1; }
    kubectl label "${W[0]}" "${W[1]}" topology.kubernetes.io/zone=zone-a --overwrite
    kubectl label "${W[2]}"                topology.kubernetes.io/zone=zone-b --overwrite
    kubectl get nodes -L topology.kubernetes.io/zone
    ;;

  basic-job)
    hr "Basic Job: pods schedule pod-by-pod, but a Basic Workload+PodGroup still exists"
    pods; was_objects
    echo; echo "-> Expect a Workload + a Basic PodGroup, both owned by the Job."
    ;;

  gang-job)
    hr "Gang Job: the controller compiled the WAS objects for you"
    was_objects
    hr "Pods — all START times should be within ~1s of each other"
    pods
    echo; echo "-> Expect: gang PodGroup with minCount=4; 4 pods bound together;"
    echo "   each pod carries .spec.schedulingGroup.podGroupName."
    ;;

  gang-blocking)
    hr "Gang blocking: quorum cannot be met, so NOTHING binds"
    pods
    hr "Scheduler events (look for gang/PreEnqueue/Permit gating)"
    kubectl -n "$NS" get events --sort-by=.lastTimestamp | tail -n 15
    echo; echo "-> Expect: all pods Pending, zero Running. The gang refuses partial placement."
    ;;

  topology)
    hr "Gang + topology + disruption: group co-located in one zone"
    pods
    hr "Which zone did the group land in?"
    for p in $(kubectl -n "$NS" get pods -l job-name=gang-topology -o name); do
      node=$(kubectl -n "$NS" get "$p" -o jsonpath='{.spec.nodeName}')
      [ -n "$node" ] && echo "$p -> $node -> zone $(kubectl get node "$node" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}')"
    done
    echo; echo "-> Expect: every pod on nodes sharing one topology.kubernetes.io/zone."
    ;;

  elastic)
    hr "Elastic gang BEFORE (minCount=3)"
    kubectl -n "$NS" get podgroups.scheduling.k8s.io -o wide; pods
    hr "Scaling gang in place -> minCount=6 (no Job recreation)"
    kubectl -n "$NS" patch job elastic-gang --type merge \
      -p '{"spec":{"parallelism":6,"completions":6,"scheduling":{"schedulingPolicy":{"gang":{"minCount":6}}}}}'
    sleep 3
    hr "Elastic gang AFTER"
    kubectl -n "$NS" get podgroups.scheduling.k8s.io -o wide; pods
    echo; echo "-> Expect: same PodGroup, resized to minCount=6; Job not recreated."
    ;;

  raw|standalone)
    was_objects; pods
    echo; echo "-> Hand-authored primitives: pods join via .spec.schedulingGroup.podGroupName."
    ;;

  *)
    echo "Usage: ./verify.sh {setup|basic-job|gang-job|gang-blocking|topology|elastic|raw|standalone}"
    exit 1
    ;;
esac

#!/usr/bin/env bash
# Inspection helpers for each scenario. Assumes kubectl is configured for
# the kind cluster from 00-kind-cluster.yaml and the ws-demo namespace exists.
set -euo pipefail

NS=ws-demo

usage() {
  cat <<EOF
Usage: $0 <scenario>

scenarios:
  basic            Layer 0 — GenericWorkload plumbing
  gang             Layer 1 — 4-pod gang (expect atomic schedule)
  gang-timeout     Layer 1 — 3-pod gang (expect Permit timeout / Unschedulable)
  gang-job         Layer 2 — Indexed Job with WorkloadWithJob (the main demo)
  non-gang-job     Contrast — same workload without gang (pods start independently)
EOF
  exit 1
}

hdr() { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }
info() { printf '\033[0;33m→ %s\033[0m\n' "$*"; }

inspect_workloads() {
  hdr "Workloads"
  kubectl -n "$NS" get workloads.scheduling.k8s.io -o wide 2>/dev/null || echo "  (none)"
}

inspect_podgroups() {
  hdr "PodGroups"
  kubectl -n "$NS" get podgroups.scheduling.k8s.io -o wide 2>/dev/null || echo "  (none)"
  hdr "PodGroup conditions"
  kubectl -n "$NS" get podgroups.scheduling.k8s.io -o json 2>/dev/null \
    | jq -r '.items[] | "\(.metadata.name)\t\(.status.conditions // [] | map("\(.type)=\(.status)/\(.reason // "-")") | join(","))"' 2>/dev/null \
    || true
}

inspect_pods() {
  hdr "Pods"
  kubectl -n "$NS" get pods -o wide 2>/dev/null || true
}

inspect_events() {
  hdr "Recent scheduling events"
  kubectl -n "$NS" get events --sort-by=.lastTimestamp 2>/dev/null | tail -n 15
}

wait_for_workload() {
  info "Waiting for the Job controller to create a Workload..."
  for i in $(seq 1 24); do
    if kubectl -n "$NS" get workloads.scheduling.k8s.io -o name 2>/dev/null | grep -q .; then
      return 0
    fi
    sleep 5
  done
  echo "  (timed out waiting for Workload)"
  return 1
}

wait_for_pods_running() {
  local label="$1"
  local count="$2"
  info "Waiting for $count pods to reach Running..."
  kubectl -n "$NS" wait --for=condition=Ready pod -l "$label" --timeout=120s 2>/dev/null || true
}

show_pod_start_times() {
  local label="$1"
  hdr "Pod start times (look for simultaneous timestamps)"
  kubectl -n "$NS" get pods -l "$label" \
    -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,START:.status.startTime,NODE:.spec.nodeName' \
    2>/dev/null || true
}

show_pod_logs() {
  local label="$1"
  hdr "Worker logs (peer discovery proves co-start)"
  for pod in $(kubectl -n "$NS" get pods -l "$label" -o name 2>/dev/null); do
    echo "--- ${pod} ---"
    kubectl -n "$NS" logs "$pod" 2>/dev/null | head -n 10
    echo ""
  done
}

case "${1:-}" in
  basic)
    inspect_workloads; inspect_podgroups; inspect_pods
    ;;

  gang)
    inspect_workloads; inspect_podgroups; inspect_pods
    hdr "Expect: all 4 pods bound in one cycle (atomic PodGroup schedule)"
    ;;

  gang-timeout)
    inspect_podgroups; inspect_pods; inspect_events
    hdr "Expect: 3 pods Pending — gang requires minCount=4 but only 3 exist"
    info "Add a 4th pod with schedulingGroup.podGroupName: gang-demo-workers to unblock."
    ;;

  non-gang-job)
    hdr "Non-gang Job (contrast)"
    info "This Job has completions(8) != parallelism(4) → does NOT qualify for WorkloadWithJob."
    kubectl -n "$NS" get job non-gang-training -o wide 2>/dev/null || true

    hdr "Workloads in namespace (should be NONE for this Job)"
    kubectl -n "$NS" get workloads.scheduling.k8s.io -o wide 2>/dev/null || echo "  (none)"

    wait_for_pods_running "app=non-gang-training" 4
    show_pod_start_times "app=non-gang-training"
    info "Notice: pods may start at different times — no gang coordination."
    ;;

  gang-job)
    hdr "Gang Job demo (WorkloadWithJob)"
    info "A plain batch/v1 Job — no Workload or PodGroup YAML needed."
    echo ""
    kubectl -n "$NS" get job gang-training -o wide 2>/dev/null || true

    wait_for_workload

    hdr "Auto-created Workload (owned by the Job)"
    kubectl -n "$NS" get workloads.scheduling.k8s.io -o wide
    echo ""
    info "Owner references:"
    kubectl -n "$NS" get workloads.scheduling.k8s.io -o json \
      | jq -r '.items[] | "  \(.metadata.name) → owned by \(.metadata.ownerReferences[0].kind)/\(.metadata.ownerReferences[0].name)"' 2>/dev/null || true

    hdr "Auto-created PodGroup (Gang policy, minCount=4)"
    kubectl -n "$NS" get podgroups.scheduling.k8s.io -o wide
    echo ""
    info "Scheduling policy:"
    kubectl -n "$NS" get podgroups.scheduling.k8s.io -o json \
      | jq -r '.items[] | "  \(.metadata.name): \(.spec.schedulingPolicy | tostring)"' 2>/dev/null || true

    wait_for_pods_running "app=gang-training" 4
    show_pod_start_times "app=gang-training"

    info "All 4 pods should show nearly identical START times — that is gang scheduling."
    echo ""

    show_pod_logs "app=gang-training"
    inspect_events
    ;;

  *) usage ;;
esac

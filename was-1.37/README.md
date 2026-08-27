# Workload-Aware Scheduling — v1.37 end-to-end examples

Companion demo for the blog post *Workload-Aware Scheduling in Kubernetes 1.37:
Building Blocks, the `workloadbuilder` Library, and Controller Integration*.

Every manifest targets the APIs shipped in **Kubernetes v1.37**:

- `scheduling.k8s.io/v1beta1` — `Workload` + `PodGroup` (**graduated to Beta** in 1.37)
- `scheduling.k8s.io/v1alpha3` — building blocks + `CompositePodGroup` (Alpha)
- Job `.spec.scheduling` integration — Alpha, behind `WorkloadWithJob`

The building-block / library surface is **alpha and off by default**.

## Prerequisites

1. `kind` ≥ v0.32 (needs `featureGates` and `runtimeConfig` at cluster level).
2. A v1.37 node image: `v1.37.0`.
3. `kubectl` v1.37+ (older clients don't know the `scheduling.k8s.io/v1beta1` types).

```bash
  kind build node-image v1.37.0
```

## Layout

| File                              | What it demonstrates                                                        |
| --------------------------------- | --------------------------------------------------------------------------- |
| `00-kind-cluster.yaml`            | kind cluster with WAS feature gates + `v1beta1`/`v1alpha3` API enabled       |
| `01-basic-job.yaml`               | Job with no `.spec.scheduling` → Basic; Workload+PodGroup still created      |
| `02-gang-job.yaml`                | **Main demo:** explicit `.spec.scheduling` gang (minCount → parallelism)     |
| `02b-gang-job-blocking.yaml`      | Gang that can't reach quorum — nothing binds (the failure mode)             |
| `03-gang-topology-disruption.yaml`| All four blocks: gang + zone co-location + group disruption                  |
| `04-elastic-gang.yaml`            | Scale `gang.minCount` in place — the one mutable scheduling field            |
| `05-raw-workload-podgroup.yaml`   | Hand-authored `Workload` + `PodGroup` + Pod (the low-level primitives)       |
| `06-standalone-podgroup.yaml`     | Standalone `PodGroup` with policy set directly (no `Workload`)              |
| `workloadbuilder-example/`        | Out-of-tree controller sketch using the `workloadbuilder` Go library         |
| `verify.sh`                       | Narrated inspection for each scenario                                        |

## Running the full demo

```bash
# 1. Bring up the cluster
kind create cluster --config 00-kind-cluster.yaml --image kindest/node:v1.37.0

# 2. Namespace + zone labels (for the topology demo)
kubectl create namespace was-demo
./verify.sh setup
```

### Demo 1 — Basic Job (baseline)

A Job without `.spec.scheduling` still produces a Workload + PodGroup, but on the
`Basic` policy its pods schedule the ordinary way.

```bash
kubectl apply -f 01-basic-job.yaml
./verify.sh basic-job
kubectl delete -f 01-basic-job.yaml
```

### Demo 2 — Gang Job (the main event)

You submit a plain `batch/v1` Job with an explicit `.spec.scheduling.schedulingPolicy.gang`.
The controller compiles the Workload + PodGroup and admits all pods atomically.

```bash
kubectl apply -f 02-gang-job.yaml
./verify.sh gang-job
kubectl delete -f 02-gang-job.yaml
```

**What to look for:**

1. A `Workload` and a gang `PodGroup` (minCount=4), both owned by the Job.
2. All pod `START` times identical (within ~1s).
3. Each pod carries `.spec.schedulingGroup.podGroupName`.

### Demo 3 — Gang blocking (failure mode)

```bash
kubectl apply -f 02b-gang-job-blocking.yaml
./verify.sh gang-blocking
kubectl delete -f 02b-gang-job-blocking.yaml
```

The gang requests more than a 3-worker cluster can place at once. Below quorum,
**nothing binds** — the group is parked rather than committing resources to a
partial placement. (Tune the `cpu` request to your machine if all six happen to fit.)

### Demo 4 — Gang + topology + disruption

```bash
kubectl apply -f 03-gang-topology-disruption.yaml
./verify.sh topology
kubectl delete -f 03-gang-topology-disruption.yaml
```

The group is co-located within a single `topology.kubernetes.io/zone` and marked
to be disrupted as a unit (`disruptionMode: all`).

### Demo 5 — Elastic gang

```bash
kubectl apply -f 04-elastic-gang.yaml
./verify.sh elastic          # scales minCount 3 -> 6 in place, no Job recreation
kubectl delete -f 04-elastic-gang.yaml
```

### Demo 6 — Raw primitives

```bash
kubectl apply -f 06-standalone-podgroup.yaml   # policy set directly on the PodGroup
./verify.sh standalone
kubectl delete -f 06-standalone-podgroup.yaml

# 05 shows the Workload + template + PodGroup split (confirm template field
# names against the v1beta1 Workload reference for your build).
```

### Out-of-tree integration (Go)

See `workloadbuilder-example/` for the `NewBuilder → Validate → BuildWorkload →
NewPodGroup` flow an external controller uses, including allow-lists, the
declarative-validation toggle, and `NewBuilderFromExistingWorkload` for child
controllers.

## Cleanup

```bash
kubectl delete namespace was-demo
kind delete cluster
```

## What changed since v1.36

| v1.36 (alpha1)                                  | v1.37                                                        |
| ----------------------------------------------- | ----------------------------------------------------------- |
| Job auto-qualified via implicit conditions      | Explicit `.spec.scheduling` block on the Job                |
| `Workload`/`PodGroup` at `v1alpha2`             | `Workload`/`PodGroup` graduated to `v1beta1` (Beta)         |
| Controllers hand-assembled objects              | Shared `workloadbuilder` library + `v1alpha3` building blocks |
| Flat `PodGroup` only                            | `CompositePodGroup` for multi-level (group-of-groups)       |

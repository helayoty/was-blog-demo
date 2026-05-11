# Workload-aware scheduling — end-to-end examples

Companion gist for the blog post. Every manifest here targets the
`scheduling.k8s.io/v1alpha2` API shipped in **Kubernetes v1.36**.

All feature gates are **alpha and off by default**.

## Prerequisites

1. kind ≥ v0.31 (needs `featureGates` and `runtimeConfig` at cluster level).
2. A v1.36 node image: `kindest/node:v1.36.0`.
3. `kubectl` v1.36+ (older clients don't know the `scheduling.k8s.io/v1alpha2`
   types).

> **Note:** If `kindest/node:v1.36.0` is not yet published, build it from source:
> ```bash
> git clone --depth 1 --branch release-1.36 https://github.com/kubernetes/kubernetes.git
> kind build node-image ./kubernetes --image kindest/node:v1.36.0
> ```
> You can also build `kubectl` from the same checkout:
> ```bash
> cd kubernetes && make kubectl && cp _output/bin/kubectl /usr/local/bin/kubectl
> ```

## Layout

| File | What it demonstrates |
|------|---------------------|
| `00-kind-cluster.yaml` | kind cluster with feature gates + v1alpha2 API enabled |
| `01-basic-workload.yaml` | Workload + PodGroup plumbing with `basic` policy (no gang) |
| `02-gang-4pods.yaml` | 4-pod gang with `minCount: 4` — atomic scheduling |
| `02b-gang-only-3pods.yaml` | Same gang, only 3 pods — demonstrates blocking behavior |
| `03-gang-job.yaml` | **Main demo:** plain Job → auto gang scheduling |
| `03a-non-gang-job.yaml` | Contrast: Job that doesn't qualify (no gang) |
| `verify.sh` | Narrated inspection for each scenario |

## Running the full demo

```bash
# 1. Bring up the cluster
kind create cluster --config 00-kind-cluster.yaml --image kindest/node:v1.36.0

# 2. Create namespace
kubectl create namespace ws-demo
```

### Demo 1: Gang scheduling basics

```bash
# All 4 pods schedule atomically — or none do.
kubectl apply -f 02-gang-4pods.yaml
./verify.sh gang

# Cleanup before next step
kubectl delete -f 02-gang-4pods.yaml
```

### Demo 2: Gang blocking (failure mode)

```bash
# Only 3 of 4 required pods — gang blocks indefinitely.
kubectl apply -f 02b-gang-only-3pods.yaml
./verify.sh gang-timeout

# Cleanup
kubectl delete -f 02b-gang-only-3pods.yaml
```

### Demo 3: Job integration (the main event)

This is the headline feature. You submit a **plain `batch/v1` Job** — no
Workload, no PodGroup, no scheduling YAML. The Job controller does everything.

```bash
# Step 1: Show the contrast — a non-qualifying Job (no gang scheduling)
kubectl apply -f 03a-non-gang-job.yaml
./verify.sh non-gang-job
# → Notice: no Workload/PodGroup created. Pods start independently.

# Step 2: Now submit the gang-eligible Job
kubectl apply -f 03-gang-job.yaml
./verify.sh gang-job
# → Notice:
#   - A Workload appears automatically (owned by the Job)
#   - A PodGroup appears with Gang policy (minCount=4)
#   - All 4 pods start at the SAME time (check timestamps)
#   - Workers discover all peers immediately via DNS
```

**What to look for in the output:**

1. `Workload` and `PodGroup` are auto-created with the Job as owner
2. All pod `START` times are identical (within 1 second)
3. Worker logs show all 4 peers reachable immediately
4. Compare with the non-gang Job where pods start at arbitrary times

## Cleanup

```bash
kubectl delete namespace ws-demo
kind delete cluster --name workload-aware
```

## What makes a Job qualify for gang scheduling?

The Job controller creates a Workload + PodGroup when ALL of these are true:

- `spec.parallelism` > 1
- `spec.completionMode` = `Indexed`
- `spec.completions` = `spec.parallelism`
- Pod template does NOT already set `spec.schedulingGroup`

Any Job that doesn't match gets standard pod-by-pod scheduling (no change).

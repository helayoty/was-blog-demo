# Workload-Aware Scheduling — blog demos

Hands-on, runnable examples for the **Workload-Aware Scheduling (WAS)** blog
series. Each directory is a self-contained set of Kubernetes manifests plus a
narrated `verify.sh` that walks through gang scheduling, topology co-location,
disruption, and Job integration on a local [kind](https://kind.sigs.k8s.io/)
cluster.

WAS introduces two core objects — `Workload` and `PodGroup` — that let the
scheduler reason about a group of pods as a single unit (all-or-nothing "gang"
scheduling) rather than one pod at a time.

## Directories

| Directory | Kubernetes | Scheduling API | Highlights |
|-----------|------------|----------------|------------|
| [`was-1.36/`](was-1.36/README.md) | v1.36 | `scheduling.k8s.io/v1alpha2` (Alpha) | Job **auto-qualifies** for gang scheduling via implicit conditions; flat `PodGroup` only |
| [`was-1.37/`](was-1.37/README.md) | v1.37 | `scheduling.k8s.io/v1beta1` (Beta) + `v1alpha3` building blocks | Explicit `.spec.scheduling` on Jobs; `workloadbuilder` library; `CompositePodGroup` |

## What changed between versions

| v1.36 (alpha) | v1.37 |
|---------------|-------|
| Job auto-qualified via implicit conditions | Explicit `.spec.scheduling` block on the Job |
| `Workload`/`PodGroup` at `v1alpha2` | `Workload`/`PodGroup` graduated to `v1beta1` (Beta) |
| Controllers hand-assembled objects | Shared `workloadbuilder` library + `v1alpha3` building blocks |
| Flat `PodGroup` only | `CompositePodGroup` for multi-level (group-of-groups) |

## Prerequisites

- [`kind`](https://kind.sigs.k8s.io/) ≥ v0.31 (v0.32 for the 1.37 demos) — needs
  cluster-level `featureGates` and `runtimeConfig`.
- A matching node image (`kindest/node:v1.36.0` or `kindest/node:v1.37.0`).
- A `kubectl` new enough to know the WAS API types (v1.36+ / v1.37+).

All WAS feature gates are **alpha/off by default**; the cluster configs in each
directory enable them. See each directory's README for build-from-source
instructions if the node image isn't published yet.

## Quick start

Pick a version, then follow its README:

```bash
cd was-1.37   # or was-1.36
kind create cluster --config 00-kind-cluster.yaml --image kindest/node:v1.37.0
kubectl create namespace was-demo
./verify.sh setup
```

Each directory's README documents the full demo sequence (basic Job, gang Job,
blocking/failure mode, topology + disruption, elastic gang, and raw primitives).

## Cleanup

```bash
kubectl delete namespace was-demo   # or ws-demo for was-1.36
kind delete cluster
```

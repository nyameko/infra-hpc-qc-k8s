# 6. Hermes Agent Fabric: Foundation and Persistent Inference

## 6.1 Purpose

This tutorial introduces Hermes as a persistent agent runtime inside the Kubernetes layer of `infra-hpc-qc-k8s`.

The learner starts with one isolated Hermes profile, one inference backend, and one persistent Cinder-backed volume. By the end of the tutorial, Hermes is deployed through Argo CD, survives pod replacement, and can use both Ollama and llama.cpp through an internal model interface.

The tutorial deliberately separates:

```text
OpenStack / Cinder
        │
        ▼
Kubernetes storage
        │
        ▼
Hermes state
```

from:

```text
Hermes
   │
   ▼
model interface
   │
   ├── Ollama
   └── llama.cpp
```

This preserves the repository's ownership rule: Kubernetes applications belong to Argo CD, persistent storage belongs to the storage layer, and model inference is a separate service from the agent runtime.

## 6.2 Learning objectives

By the end of this tutorial the learner should be able to:

* explain the distinction between an agent runtime and an inference runtime;
* deploy an isolated Hermes container using GitOps;
* provision and mount a Cinder-backed PVC;
* deploy Ollama and llama.cpp as separate services;
* connect Hermes to an OpenAI-compatible model endpoint;
* validate persistence by deleting and recreating the Hermes pod;
* identify what belongs in Git and what must remain runtime state or secret material.

## 6.3 Architecture

```text
                         Argo CD
                            │
                            ▼
                       Kubernetes
                            │
          ┌─────────────────┴─────────────────┐
          │                                   │
       Hermes                              Models
          │                                   │
      /opt/data                     ┌─────────┴─────────┐
          │                          │                   │
          ▼                        Ollama             llama.cpp
      Cinder PVC                     │                   │
          │                          └─────────┬─────────┘
          │                                    │
          └────────────────────────────────────┘
                         model API
```

The important boundary is:

```text
Hermes = agent state + tools + skills + sessions + orchestration
Model runtime = inference only
```

Hermes currently supports persistent profiles, skills, memory, cron, messaging gateways and multiple terminal backends. The current Docker deployment treats `/opt/data` as mutable state while the image remains disposable. See the upstream Hermes documentation for the current deployment contract.

## 6.4 Prerequisites

The base environment should already provide:

* a functioning Kubernetes cluster;
* Cinder CSI and a usable StorageClass;
* Argo CD;
* cluster DNS and service networking;
* an ingress path if the Hermes UI/gateway will be exposed;
* access to the `infra-hpc-qc-k8s` repository.

Verify:

```bash
kubectl get nodes
kubectl get storageclass
kubectl get applications -n argocd
```

The Cinder CSI Helm chart is responsible for provisioning Cinder-backed storage classes. Keep that component in the platform/storage layer rather than embedding cloud-specific logic in Hermes manifests.

## 6.5 Repository layout

A minimal GitOps layout is:

```text
kubernetes/
└── platform/
    ├── hermes/
    │   ├── namespace.yaml
    │   ├── pvc.yaml
    │   ├── deployment.yaml
    │   ├── service.yaml
    │   └── kustomization.yaml
    │
    ├── ollama/
    │   └── ...
    │
    └── llama-cpp/
        └── ...

argocd/
└── applications/
    ├── hermes.yaml
    ├── ollama.yaml
    └── llama-cpp.yaml
```

## 6.6 Persistent Hermes storage

Use a dedicated PVC for Hermes state.

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: hermes-data
  namespace: hermes
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: cinder
  resources:
    requests:
      storage: 10Gi
```

Mount it at:

```text
/opt/data
```

Do not store model weights in the Hermes PVC.

## 6.7 Hermes deployment

Pin the container image version rather than deploying `latest`.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hermes
  namespace: hermes
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hermes
  template:
    metadata:
      labels:
        app: hermes
    spec:
      containers:
        - name: hermes
          image: nousresearch/hermes-agent:<PINNED-VERSION>
          args:
            - gateway
            - run
          ports:
            - name: http
              containerPort: 8642
          volumeMounts:
            - name: data
              mountPath: /opt/data
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: hermes-data
```

The exact gateway invocation should be verified against the pinned Hermes release used by the deployment. Do not treat a command copied from a moving `main` branch as a stable interface.

## 6.8 Deploy through Argo CD

Create an Argo CD Application that points at the directory containing the Hermes manifests.

The expected ownership chain is:

```text
Git commit
   │
   ▼
GitHub Actions: validate
   │
   ▼
merge
   │
   ▼
Argo CD
   │
   ▼
Kubernetes
```

Do not have Hermes itself bypass this path to mutate the production manifests.

## 6.9 Validate the first agent

```bash
kubectl -n hermes get pods
kubectl -n hermes get pvc
kubectl -n hermes logs deploy/hermes
kubectl -n hermes get svc
```

Validate the PVC:

```bash
kubectl -n hermes describe pvc hermes-data
```

Validate the gateway from inside the cluster before exposing it externally.

## 6.10 Persistence test

Write a known test value into Hermes state using the supported Hermes profile/state mechanism.

Then:

```bash
kubectl -n hermes delete pod -l app=hermes
kubectl -n hermes get pods -w
```

The new pod must recover the previous state from the Cinder volume.

This is the first infrastructure contract:

```text
pod lifetime ≠ agent lifetime
```

## 6.11 Deploy Ollama

Deploy Ollama separately, ideally with a separate PVC for model data.

```text
ollama-models PVC
        │
        ▼
      Ollama
```

Keep the service internal:

```yaml
kind: Service
metadata:
  name: ollama
spec:
  type: ClusterIP
```

Ollama exposes an OpenAI-compatible API for supported operations/models, so Hermes can treat it as a model provider rather than embedding Ollama-specific logic.

## 6.12 Deploy llama.cpp

Deploy `llama-server` as a separate service. The upstream project provides an OpenAI-compatible HTTP server and container images.

```text
llama-cpp
   │
   ├── server
   └── model storage
```

Expose only an internal ClusterIP service during the tutorial.

The important teaching experiment is not "which runtime is better?" It is:

> Can the same agent runtime switch inference backends without changing the agent's identity, memory or tools?

## 6.13 Model interface

Conceptually:

```text
Hermes
  │
  ▼
OpenAI-compatible model endpoint
  │
  ├── Ollama
  └── llama.cpp
```

Use model/provider configuration supported by the pinned Hermes version. Keep credentials and provider-specific secrets outside Git.

## 6.14 GPU scheduling

Do not make Hermes responsible for GPU allocation.

```text
Hermes
   │
   ▼
model service
   │
   ▼
Kubernetes scheduler / GPU resources
   │
   ▼
GPU
```

This keeps agent orchestration independent of hardware placement.

## 6.15 Failure modes

### Pod restarts but state disappears

Check whether `/opt/data` is really mounted from the PVC.

### PVC remains Pending

Inspect:

```bash
kubectl -n hermes describe pvc hermes-data
kubectl get storageclass
kubectl get pods -n kube-system
```

The issue is likely below Hermes, in Cinder CSI, the StorageClass, or OpenStack volume provisioning.

### Hermes cannot reach Ollama

Test cluster DNS and service connectivity first:

```bash
kubectl -n hermes run netcheck --rm -it --image=curlimages/curl -- sh
curl http://ollama:11434/
```

Do not debug model configuration until network reachability is proven.

### Model works directly but not through Hermes

Inspect the model endpoint URL, API compatibility, model identifier and Hermes provider configuration.

## 6.16 Testing pyramid

The Hermes subsystem should eventually adopt the same testing philosophy as the rest of the repository:

```text
             E2E
              ▲
              │
         integration
              │
      ┌───────┴───────┐
      │               │
   runtime         storage
      │               │
      └───────┬───────┘
              │
      static / policy
```

Tests should answer different questions:

```text
static    → is the configuration valid?
integration → can components communicate?
persistence → does state survive failure?
E2E       → can a user actually converse with the agent?
```

## 6.17 Further reading

* Hermes Agent: https://github.com/NousResearch/hermes-agent
* Hermes Docker deployment: https://hermes-agent.nousresearch.com/docs/user-guide/docker
* Hermes profiles: https://hermes-agent.nousresearch.com/docs/user-guide/features/profiles/
* Cinder CSI: https://github.com/kubernetes/cloud-provider-openstack/tree/master/charts/cinder-csi-plugin
* Ollama OpenAI compatibility: https://docs.ollama.com/api/openai-compatibility
* llama.cpp server: https://github.com/ggml-org/llama.cpp
* Argo CD: https://argo-cd.readthedocs.io/

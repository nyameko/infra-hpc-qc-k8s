# 4. Kubernetes & Platform Services

## 4.1 kubeadm bootstrap

```text
CP1
 │
 ├── kubeadm init
 │
 ├──▶ CP2
 ├──▶ CP3
 │
 └──▶ workers
```

API endpoint: `10.51.0.100:6443` for the life of the cluster, regardless of what fronts it (§4.2).

```bash
ansible-playbook -i ansible/inventories/personal/hosts.yml ansible/playbooks/kubernetes.yml
```

Install on every node first: `containerd`, `kubelet`, `kubeadm`, `kubectl`, required kernel modules, sysctl
configuration. `containerd` should use the **systemd cgroup driver** — this is a common source of
hard-to-diagnose kubelet instability if missed.

Validate:

```bash
kubectl get nodes
```

All six nodes should eventually report `Ready`. Do not proceed to Cilium/Argo CD/applications before that.

**Further reading:** [kubeadm docs](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/) ·
[Container runtimes / cgroup driver](https://kubernetes.io/docs/setup/production-environment/container-runtimes/) ·
[Kubernetes releases](https://kubernetes.io/releases/) (check the current supported minor before you pin —
see `docs/08` §8.3).

## 4.2 API load balancing

```text
             10.51.0.100:6443
                    │
                 HAProxy
                /    |    \
             CP1    CP2    CP3
```

The implementation is meant to be swappable via a variable:

```text
api_lb_type = haproxy
```

...upgradeable later to an Octavia-managed load balancer **without changing the Kubernetes API endpoint**
clients connect to. See `docs/03` §3.3 for the drift between this description and the committed root
README's wording — resolve that before presenting this section to students, since it's the kind of detail
that undermines confidence in the rest of the docs if left contradictory.

**Further reading:** [HAProxy documentation](https://www.haproxy.org/) · [OpenStack Octavia (load balancer
as a service)](https://docs.openstack.org/octavia/latest/).

## 4.3 Cilium (CNI)

Cilium provides pod networking, service networking, `NetworkPolicy` enforcement, and network observability
via eBPF.

```bash
kubectl get nodes
cilium status
```

**Further reading:** [Cilium installation with
kubeadm](https://docs.cilium.io/en/latest/installation/k8s-install-kubeadm/) · [Cilium
NetworkPolicy](https://docs.cilium.io/en/stable/security/policy/) · [Hubble (Cilium's observability
layer)](https://docs.cilium.io/en/stable/observability/hubble/intro/).

## 4.4 OpenStack integration and storage

```text
Application
    │
    ▼
   PVC
    │
    ▼
   CSI
    │
    ▼
 Cinder
```

Add the OpenStack Cloud Controller Manager and Cinder CSI once the cluster is already healthy — don't bundle
this into the initial kubeadm bootstrap. Persistent storage is planned for: Wazuh indexer, Grafana,
PostgreSQL, Jupyter data, user data, application state.

**Further reading:** [OpenStack Cloud Controller
Manager](https://github.com/kubernetes/cloud-provider-openstack) · [Cinder CSI
driver](https://docs.openstack.org/cinder/latest/) · [Kubernetes storage
concepts](https://kubernetes.io/docs/concepts/storage/).

## 4.5 Argo CD (GitOps)

```text
Git
 │
 ▼
Argo CD
 │
 ▼
Kubernetes
```

Argo CD becomes the *normal* path for anything running in-cluster from this point on (see `docs/01` §1.2).
Applications include: Wazuh indexer, Wazuh dashboard, Prometheus, Grafana, ingress controller,
cert-manager, JupyterHub, Astro, research services. An "app of apps" pattern (one root Argo CD `Application`
that manages the rest as children) is worth teaching explicitly here — it's how a platform team keeps a
growing application list declarative instead of a list of manual `kubectl apply -f`s.

**Further reading:** [Argo CD docs](https://argo-cd.readthedocs.io/) · [Argo CD "app of apps"
pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/) ·
[OpenGitOps principles](https://opengitops.dev/).

## 4.6 Ingress: a decision the source docs leave open

The original documentation just says "ingress" without naming a controller. As of March 2026, that decision
matters more than it used to: **`ingress-nginx`, historically the default choice in most tutorials, was
formally retired by Kubernetes SIG Network and the Security Response Committee** — best-effort maintenance
ended and the project now receives no further releases, bug fixes, or security patches. The official
guidance is to migrate to the [Gateway API](https://gateway-api.sigs.k8s.io/) or another actively maintained
controller.

For this platform, two reasonable choices:

| Option | Why it fits | Trade-off |
|---|---|---|
| **Traefik** | Actively maintained, supports both classic `Ingress` and `Gateway API`, ships a dashboard that's genuinely useful for teaching HTTP routing concepts live | One more component to operate and secure |
| **Cilium Gateway API support** | Cilium is already the CNI (§4.3); using its built-in Gateway API implementation means one fewer moving part and one fewer thing to patch | Less separation between "networking" and "ingress" concerns, which may be pedagogically worse if you *want* students to see them as distinct layers |

Either is defensible; what matters for a teaching repo is picking one explicitly and updating every doc that
currently just says "ingress" to name it, so students don't build muscle memory around a project that no
longer receives security patches.

**Further reading:** [Kubernetes: Ingress NGINX retirement
statement](https://www.kubernetes.io/blog/2026/01/29/ingress-nginx-statement/) · [Gateway API
documentation](https://gateway-api.sigs.k8s.io/) · [Traefik documentation](https://doc.traefik.io/traefik/) ·
[Cilium Gateway API support](https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/).

## 4.7 TLS

Add `cert-manager` once ingress is settled, issuing certificates against Let's Encrypt. Given Cloudflare
manages the public DNS zone (`docs/01` §1.7), a DNS-01 challenge via the Cloudflare API is the natural
choice — it avoids needing HTTP-01's requirement that the challenge be publicly reachable before TLS is even
configured.

**Further reading:** [cert-manager documentation](https://cert-manager.io/docs/) · [cert-manager: ACME DNS01
challenges](https://cert-manager.io/docs/configuration/acme/dns01/) · [Cloudflare API
docs](https://developers.cloudflare.com/api/).

## 4.8 Observability

**Prometheus/Grafana/Loki** cover node metrics, Kubernetes metrics, Slurm metrics, application metrics,
workload telemetry, and Hermes telemetry.

**Wazuh indexer and dashboard**, deployed in Kubernetes once the base platform is healthy:

```text
Agents → Wazuh manager → Wazuh indexer → Wazuh dashboard
```

The indexer needs persistent storage (§4.4); the dashboard is the web interface. Wazuh documents the
manager, indexer, and dashboard as genuinely separate components — don't assume one Helm chart covers all
three.

**Further reading:** [Prometheus docs](https://prometheus.io/docs/) · [Grafana docs](https://grafana.com/docs/) ·
[Loki docs](https://grafana.com/docs/loki/latest/) · [Wazuh architecture](https://documentation.wazuh.com/current/getting-started/architecture.html).

## 4.9 JupyterHub

```text
Browser
   │
   ▼
Ingress
   │
   ▼
JupyterHub
   │
   ▼
JupyterLab
```

Research/teaching images can include PennyLane, Qiskit, Qiskit Aer, CUDA-Q, PyTorch, and custom builds; see
`docs/07` for the dedicated quantum-computing sandbox design built on top of this. Resource selection per
user profile can eventually include CPU, RAM, GPU, and persistent storage tiers.

**Further reading:** [JupyterHub documentation](https://jupyterhub.readthedocs.io/) · [Zero to JupyterHub on
Kubernetes](https://z2jh.jupyter.org/).

## 4.10 Astro (public website)

```text
Cloudflare
    │
    ▼
Ingress
    │
    ▼
Astro service
    │
    ▼
Astro container
```

First target: a simple hello-world page at `quantum.nyameko.com`, used to verify DNS, ingress, and
application deployment end-to-end before anything more complex ships. This is deliberately the smallest
possible "does the whole chain work" test — treat it as a milestone, not a throwaway.

**Further reading:** [Astro documentation](https://docs.astro.build/).

## 4.11 PostgreSQL

A later persistent application service, planned for user information, research portal data, JupyterHub
state, and application metadata:

```text
PostgreSQL → PVC → Cinder
```

**Further reading:** [PostgreSQL documentation](https://www.postgresql.org/docs/).

## 4.12 Local LLM inference (Ollama / llama.cpp)

Named in the deployment order (`docs/01` §1.9, phase 6) alongside the other platform services. These serve
as the local model-inference backend that Hermes (`docs/06`) can call without sending data to an external
API — relevant both for cost and for keeping infrastructure telemetry inside the trust boundary it was
collected in.

**Further reading:** [Ollama documentation](https://docs.ollama.com/) · [llama.cpp
repository](https://github.com/ggml-org/llama.cpp).

## 4.13 Per-layer validation commands

```bash
kubectl get nodes -o wide
cilium status
kubectl get storageclass
argocd app list
kubectl get certificates -A
kubectl get ingress -A          # or: kubectl get httproute -A, if using Gateway API
```

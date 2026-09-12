# Traefik Ingress — WireGuard → Pi-hole → HAProxy → Kubernetes

## 1. Objective

This tutorial establishes the Kubernetes ingress path for the initial `infra-hpc-qc-k8s` environment:

```text
Client
  │
  │ WireGuard
  ▼
EDGE
  │
  │ private DNS
  ▼
Pi-hole
  │
  │ traefik-test.quantum.nyameko.com
  │ → 10.51.0.100
  ▼
api-lb-01
  │
  │ HAProxy
  ▼
Kubernetes worker NodePorts
  │
  │ 31818 / 31924
  ▼
Traefik
  │
  ▼
Kubernetes Ingress
  │
  ▼
ingress-test Service
  │
  ▼
nginx
```

The end state is:

```text
https://traefik-test.quantum.nyameko.com
```

reaching the nginx test workload entirely through the private infrastructure path.

This tutorial deliberately separates:

- DNS
- network/load-balancer infrastructure
- Kubernetes Service networking
- Traefik
- Kubernetes Ingress
- TLS
- application routing

That separation is important for both operations and troubleshooting.

---

# 2. Architecture

The infrastructure contains three different kinds of IP address.

## 2.1 Infrastructure network

The Kubernetes node network is:

```text
10.51.0.0/24
```

For the current cluster:

```text
k8s-cp-01       10.51.0.11
k8s-cp-02       10.51.0.12
k8s-cp-03       10.51.0.13

k8s-worker-01   10.51.0.21
k8s-worker-02   10.51.0.22
k8s-worker-03   10.51.0.23

api-lb-01       10.51.0.100
```

This is the network on which HAProxy reaches Kubernetes worker nodes.

---

## 2.2 Kubernetes Pod network

Traefik Pods are assigned addresses from the Cilium Pod network:

```text
traefik Pod 1    10.0.0.24
traefik Pod 2    10.0.5.4
```

These addresses are **not** the addresses HAProxy should use.

Kubernetes owns the translation:

```text
worker node
   ↓
NodePort
   ↓
Service
   ↓
Pod
```

---

## 2.3 Kubernetes Service network

The Traefik Service has:

```text
ClusterIP: 10.97.78.229
```

This address is internal to Kubernetes.

HAProxy does not need to connect directly to the ClusterIP.

The external load-balancer path is:

```text
HAProxy
   ↓
worker-node:NodePort
   ↓
Traefik Service
   ↓
Traefik Pod
```

---

# 3. Why there are three different "load balancers"

It is important not to confuse these components.

## 3.1 `api-lb-01`

This is a real OpenStack VM created by Terraform.

It runs:

```text
HAProxy
```

It owns:

```text
10.51.0.100
```

This is the actual infrastructure load balancer.

---

## 3.2 Kubernetes `Service: type: LoadBalancer`

Traefik is exposed as:

```yaml
type: LoadBalancer
```

This is the Kubernetes abstraction.

It does not mean that Kubernetes automatically creates the OpenStack HAProxy VM.

In this environment there is no OpenStack Octavia integration providing an external address to the Kubernetes Service, so the Kubernetes Service remains:

```text
EXTERNAL-IP: <pending>
```

That is not a problem for this architecture.

The actual external load balancer is already provided by `api-lb-01`.

---

## 3.3 NodePort

The Kubernetes Service allocates NodePorts:

```text
HTTP    31818
HTTPS   31924
```

These are the backend ports HAProxy uses to reach the Kubernetes cluster.

The clients never need to know about them.

Therefore:

```text
Internet / WireGuard client
        │
        ▼
10.51.0.100:443
        │
        ▼
HAProxy
        │
        ▼
10.51.0.21:31924
10.51.0.22:31924
10.51.0.23:31924
```

is the intended path.

---

# 4. Why `ss` does not show NodePort 31818

A common mistake is to run:

```bash
sudo ss -lntp | grep 31818
```

and conclude that NodePort is not running.

That is not a reliable NodePort test.

The NodePort is implemented by the Kubernetes service datapath, currently involving:

```text
kube-proxy
Cilium
```

rather than requiring an ordinary userspace process to bind:

```text
0.0.0.0:31818
```

Therefore:

```bash
ss
```

may show nothing.

The correct test is to connect to the **node IP**, not the Pod IP:

```bash
curl http://10.51.0.21:31818/
curl http://10.51.0.22:31818/
curl http://10.51.0.23:31818/
```

The same applies to HTTPS:

```bash
curl -vk https://10.51.0.21:31924/
curl -vk https://10.51.0.22:31924/
curl -vk https://10.51.0.23:31924/
```

---

# 5. Why the first test appeared broken

The initial incorrect test used:

```text
10.0.0.24:31818
10.0.5.4:31818
```

Those addresses are Traefik Pod addresses.

NodePort belongs to the node:

```text
10.51.0.21:31818
10.51.0.22:31818
10.51.0.23:31818
```

Once the correct addresses were used, the connection succeeded.

For example:

```text
Connected to 10.51.0.21 port 31818
HTTP/1.1 404 Not Found
```

That `404` is actually evidence that the traffic successfully reached Traefik.

Likewise HTTPS successfully completed a TLS 1.3 handshake and returned Traefik's:

```text
TRAEFIK DEFAULT CERT
```

certificate.

At that point:

```text
api-lb → worker → NodePort → Traefik
```

was proven.

---

# 6. Security groups

The existing worker rule already covers the Traefik NodePorts.

The infrastructure uses:

```hcl
k8s_cidr = "10.51.0.0/24"
```

and the worker security group already permits:

```hcl
port_range_min = 30000
port_range_max = 32767
remote_ip_prefix = var.k8s_cidr
```

Therefore:

```text
31818 ∈ 30000–32767
31924 ∈ 30000–32767
```

and:

```text
10.51.0.100 ∈ 10.51.0.0/24
```

Therefore no additional OpenStack security-group rule is required just for these two NodePorts.

Do not open:

```text
31818
31924
```

to:

```text
0.0.0.0/0
```

They are internal HAProxy-to-Kubernetes plumbing.

---

# 7. Pi-hole

Pi-hole is running on the edge host.

The client reaches it through WireGuard:

```text
WireGuard client
       │
       ▼
10.60.0.1
       │
       ▼
Pi-hole :53
```

The private DNS record is:

```text
traefik-test.quantum.nyameko.com
        ↓
10.51.0.100
```

The record is managed declaratively through Ansible rather than manually through the Pi-hole GUI.

The intended variable is:

```yaml
pihole_dns_hosts:
  - "{{ kubernetes_api_endpoint.address }} traefik-test.quantum.nyameko.com"
```

where the current Kubernetes API/HAProxy VIP is:

```text
10.51.0.100
```

The Quadlet passes that to Pi-hole through:

```ini
Environment="FTLCONF_dns_hosts={{ pihole_dns_hosts | join('\n') }}"
```

---

# 8. Pi-hole persistence and SELinux

The edge host uses:

```text
/opt/pihole/etc-pihole
```

as persistent storage.

The container sees:

```text
/etc/pihole
```

through:

```ini
Volume=/opt/pihole/etc-pihole:/etc/pihole:Z
```

The `:Z` option is important on the Rocky/SELinux edge host.

Without it, SELinux labelled the directory as:

```text
unconfined_u:object_r:usr_t
```

and denied the Pi-hole container:

```text
container_t
```

from writing.

The resulting AVC denials included:

```text
avc: denied { write }
```

and Pi-hole could not create:

```text
gravity.db
pihole-FTL.db
```

With the SELinux-aware mount, the directory is correctly labelled:

```text
container_file_t
```

and Pi-hole can persist its state.

This should be treated as a reusable Podman-on-Rocky pattern for future edge services.

---

# 9. Verify private DNS

From a WireGuard-connected client:

```bash
dig @10.60.0.1 traefik-test.quantum.nyameko.com
```

The expected result is:

```text
ANSWER SECTION:

traefik-test.quantum.nyameko.com.  IN A 10.51.0.100
```

This proves:

```text
WireGuard
    ↓
edge
    ↓
Pi-hole
    ↓
private DNS
```

before Kubernetes is involved.

---

# 10. Traefik Helm deployment

Traefik is deployed through Argo CD using the official Helm chart.

The chart is pinned:

```yaml
targetRevision: 41.5.0
```

and the Traefik image is explicitly pinned:

```yaml
image:
  tag: v3.7.13
```

The current values also deploy two replicas and enable both the Kubernetes CRD and standard Kubernetes Ingress providers. The `web` and `websecure` entrypoints use ports `8000` and `8443`, exposed through Services as `80` and `443`.

The final relevant values are:

```yaml
image:
  tag: v3.7.13

deployment:
  replicas: 2

providers:
  kubernetesCRD:
    enabled: true

  kubernetesIngress:
    enabled: true

ingressClass:
  enabled: true
  isDefaultClass: true

ports:
  web:
    port: 8000
    exposedPort: 80
    nodePort: 31818

  websecure:
    port: 8443
    exposedPort: 443
    nodePort: 31924
    http:
      tls:
        enabled: true

service:
  enabled: true
  type: LoadBalancer

log:
  level: INFO

accessLog:
  enabled: true

metrics:
  prometheus:
    enabled: true
```

The explicit NodePorts make the HAProxy-to-Kubernetes contract deterministic:

```text
HTTP  → 31818
HTTPS → 31924
```

rather than relying on dynamically assigned NodePorts.

---

# 11. Why the first Traefik deployment failed

The first values file used an incorrect schema:

```yaml
ports:
  websecure:
    tls:
      enabled: true

logs:
```

Traefik chart `41.5.0` rejected those fields.

The correct structure is:

```yaml
ports:
  websecure:
    http:
      tls:
        enabled: true

log:
  level: INFO
```

Argo therefore reported:

```text
ComparisonError

values don't meet the specifications of the schema(s)
```

and:

```text
SYNC STATUS: Unknown
```

No Kubernetes namespace was created because Argo could not generate the desired manifests.

The lesson is important:

> A healthy Argo `Application` object does not mean its desired manifests can actually be rendered.

Always inspect:

```bash
kubectl -n argocd describe application traefik
```

when an Application reports:

```text
Unknown
```

rather than immediately investigating Kubernetes resources that haven't been created yet.

---

# 12. Argo CD synchronization

The Traefik Application uses:

```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true

  syncOptions:
    - CreateNamespace=true
```

Therefore Git is the source of truth and Argo creates the `traefik` namespace when the manifests render successfully.

The normal verification commands are:

```bash
kubectl -n argocd get applications
```

and:

```bash
kubectl -n argocd get application traefik \
  -o jsonpath='{.status.sync.status}{"\n"}{.status.health.status}{"\n"}'
```

A normal deployment progression is:

```text
Unknown / Healthy
        ↓
Synced / Progressing
        ↓
Synced / Healthy
```

Do not interpret the intermediate `Progressing` state as a failure.

---

# 13. Verify Traefik

Once synchronized:

```bash
kubectl -n traefik get pods -o wide
```

Expected:

```text
traefik-...   1/1   Running
traefik-...   1/1   Running
```

Then:

```bash
kubectl -n traefik get svc traefik
```

Expected:

```text
NAME      TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)
traefik   LoadBalancer   10.97.78.229    <pending>     80:31818/TCP,443:31924/TCP
```

The `<pending>` value is expected in this architecture.

It does not mean HAProxy is broken.

It means Kubernetes has no external cloud-controller responsible for populating:

```yaml
status:
  loadBalancer:
```

Your external load balancer already exists:

```text
api-lb-01
```

---

# 14. Verify the Service endpoints

Use EndpointSlices:

```bash
kubectl -n traefik get endpointslice \
  -l kubernetes.io/service-name=traefik -o wide
```

Expected:

```text
10.0.0.24
10.0.5.4
```

with ports:

```text
8000
8443
```

The Service therefore performs:

```text
worker:31818
       ↓
Traefik Service
       ↓
Pod:8000

worker:31924
       ↓
Traefik Service
       ↓
Pod:8443
```

---

# 15. Configure HAProxy

The existing `api-lb-01` VM owns:

```text
10.51.0.100
```

The Kubernetes workers are:

```text
10.51.0.21
10.51.0.22
10.51.0.23
```

HAProxy therefore targets the worker NodePorts.

Conceptually:

```text
frontend ingress_http
    bind 10.51.0.100:80
    default_backend traefik_http

backend traefik_http
    server worker01 10.51.0.21:31818 check
    server worker02 10.51.0.22:31818 check
    server worker03 10.51.0.23:31818 check
```

and:

```text
frontend ingress_https
    bind 10.51.0.100:443
    default_backend traefik_https

backend traefik_https
    server worker01 10.51.0.21:31924 check
    server worker02 10.51.0.22:31924 check
    server worker03 10.51.0.23:31924 check
```

The exact HAProxy syntax should follow the existing Ansible role/configuration in this repository rather than being copied as an independent configuration model.

The important backend contract is:

```text
api-lb → worker-01:31818
api-lb → worker-02:31818
api-lb → worker-03:31818

api-lb → worker-01:31924
api-lb → worker-02:31924
api-lb → worker-03:31924
```

---

# 16. Test the HAProxy backend before testing DNS

From `api-lb-01`:

```bash
curl -v http://10.51.0.21:31818/
curl -v http://10.51.0.22:31818/
curl -v http://10.51.0.23:31818/
```

A successful connection returning:

```text
HTTP/1.1 404 Not Found
```

from Traefik is a success at this stage.

It means:

```text
api-lb
 ↓
worker
 ↓
NodePort
 ↓
Traefik
```

is functioning.

For HTTPS:

```bash
curl -vk https://10.51.0.21:31924/
curl -vk https://10.51.0.22:31924/
curl -vk https://10.51.0.23:31924/
```

A successful TLS handshake using:

```text
TRAEFIK DEFAULT CERT
```

proves the `websecure` entrypoint is alive.

---

# 17. Why a Traefik 404 is useful

Traefik returning:

```text
404 page not found
```

does not necessarily mean Traefik is broken.

It means the request reached Traefik but Traefik did not find a router matching the request.

For example:

```bash
curl http://10.51.0.21:31818/
```

produces a Host header similar to:

```text
Host: 10.51.0.21:31818
```

but the intended route is:

```text
traefik-test.quantum.nyameko.com
```

Therefore test the hostname explicitly:

```bash
curl -v \
  -H 'Host: traefik-test.quantum.nyameko.com' \
  http://10.51.0.21:31818/
```

---

# 18. The missing piece: deploy the Ingress resource

This is the important distinction from the current repository layout.

The current test file contains:

```text
Deployment
Service
Ingress
```

and the Ingress correctly specifies:

```yaml
ingressClassName: traefik

rules:
  - host: traefik-test.quantum.nyameko.com
```

with backend:

```yaml
service:
  name: ingress-test
  port:
    number: 80
```



However, the Traefik Application currently consumes:

```text
values.yaml
```

as a Helm values source. It does not automatically deploy arbitrary YAML files next to that values file.

Therefore the current state can legitimately be:

```text
Traefik
  ✅ Running

Traefik NodePort
  ✅ Working

TLS
  ✅ Working

Ingress route
  ❌ Not installed

nginx test
  ✅ may exist
```

which produces:

```text
HTTP 404 page not found
```

from Traefik.

---

# 19. Recommended GitOps structure for the test

Do not put application manifests beside Helm values and rely on implicit behaviour.

Separate them:

```text
argocd/
├── applications/
│   ├── traefik.yml
│   └── traefik-test.yml
│
└── resources/
    ├── traefik/
    │   └── values.yaml
    │
    └── traefik-test/
        └── ingress-test.yaml
```

`traefik` owns:

```text
Helm chart
Traefik controller
Traefik Service
```

`traefik-test` owns:

```text
Deployment
Service
Ingress
```

This is a better long-term pattern because the ingress controller is infrastructure while the nginx deployment is an application/workload.

---

# 20. Example `traefik-test` Argo Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: traefik-test
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io

spec:
  project: default

  source:
    repoURL: https://github.com/nyameko/infra-hpc-qc-k8s.git
    targetRevision: main
    path: argocd/resources/traefik-test

  destination:
    server: https://kubernetes.default.svc
    namespace: default

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

Then the resource directory contains:

```text
argocd/resources/traefik-test/
└── ingress-test.yaml
```

The test manifest can remain exactly:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ingress-test
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ingress-test
  template:
    metadata:
      labels:
        app: ingress-test
    spec:
      containers:
        - name: nginx
          image: nginx:1.29-alpine
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: ingress-test
  namespace: default
spec:
  selector:
    app: ingress-test
  ports:
    - port: 80
      targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ingress-test
  namespace: default
spec:
  ingressClassName: traefik
  rules:
    - host: traefik-test.quantum.nyameko.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ingress-test
                port:
                  number: 80
```

This turns the test into a real GitOps-managed application rather than an incidental file.

---

# 21. Verify the router

After Argo deploys the test application:

```bash
kubectl get ingress ingress-test
```

Then:

```bash
kubectl get ingress ingress-test -o yaml
```

And:

```bash
kubectl get deployment ingress-test
kubectl get service ingress-test
```

You should now have:

```text
Ingress
  ↓
ingress-test Service
  ↓
nginx Pod
```

---

# 22. Test HTTP before TLS

From `api-lb-01`:

```bash
curl -v \
  -H 'Host: traefik-test.quantum.nyameko.com' \
  http://10.51.0.21:31818/
```

A successful result should now contain the nginx response rather than:

```text
404 page not found
```

Test the other workers as well.

---

# 23. Test the HAProxy VIP

Once HAProxy has been configured:

```bash
curl -v \
  -H 'Host: traefik-test.quantum.nyameko.com' \
  http://10.51.0.100/
```

The path is now:

```text
api-lb client
   ↓
10.51.0.100:80
   ↓
HAProxy
   ↓
worker NodePort 31818
   ↓
Traefik
   ↓
Ingress
   ↓
nginx
```

---

# 24. HTTPS

The Traefik `websecure` entrypoint is already configured for TLS.

The initial certificate seen during direct NodePort testing is:

```text
TRAEFIK DEFAULT CERT
```

That is expected.

It demonstrates that TLS itself is functioning, but it is not yet the certificate you want users to trust.

For the first controlled ingress test, create a TLS Secret for:

```text
traefik-test.quantum.nyameko.com
```

and add:

```yaml
spec:
  tls:
    - hosts:
        - traefik-test.quantum.nyameko.com
      secretName: traefik-test-tls

  rules:
    - host: traefik-test.quantum.nyameko.com
```

Once routing and TLS are proven, replace the manual test certificate with your production certificate automation.

---

# 25. Final end-to-end test

From a WireGuard-connected client:

```bash
dig @10.60.0.1 traefik-test.quantum.nyameko.com
```

Expected:

```text
10.51.0.100
```

Then:

```bash
curl -vk \
  --resolve traefik-test.quantum.nyameko.com:443:10.51.0.100 \
  https://traefik-test.quantum.nyameko.com/
```

Finally, because Pi-hole already resolves the real name:

```bash
curl -vk \
  https://traefik-test.quantum.nyameko.com/
```

The complete path is now:

```text
Blackmyth
   │
   │ WireGuard
   ▼
EDGE 10.60.0.1
   │
   │ Pi-hole DNS
   ▼
traefik-test.quantum.nyameko.com
   │
   │ 10.51.0.100
   ▼
api-lb-01
   │
   │ HAProxy :443
   ▼
Kubernetes workers
   │
   │ NodePort :31924
   ▼
Traefik Service
   │
   │ Service → Pod
   ▼
Traefik Pod
   │
   │ Ingress host match
   ▼
ingress-test Service
   │
   ▼
nginx
```

---

# 26. Layer-by-layer troubleshooting

This sequence is the important operational lesson from the exercise.

## DNS failure

```bash
dig @10.60.0.1 traefik-test.quantum.nyameko.com
```

Expected:

```text
10.51.0.100
```

If this fails:

```text
WireGuard / Pi-hole / DNS configuration
```

---

## NodePort failure

From `api-lb`:

```bash
curl -v http://10.51.0.21:31818/
```

If this times out:

```text
OpenStack SG
worker firewall
routing
NodePort implementation
```

If this connects and returns Traefik's `404`:

```text
NodePort path is working
```

---

## Traefik 404

```text
HTTP 404 page not found
```

means:

```text
request reached Traefik
but no router matched
```

Check:

```bash
kubectl get ingress -A
```

and:

```bash
kubectl -n traefik logs deploy/traefik
```

---

## Ingress route works but backend fails

Check:

```bash
kubectl get service ingress-test
kubectl get endpointslice \
  -l kubernetes.io/service-name=ingress-test
```

A missing EndpointSlice normally means the Service selector does not match a Ready Pod.

---

## TLS failure

Check:

```bash
kubectl get secret traefik-test-tls
```

and:

```bash
kubectl describe ingress ingress-test
```

Then inspect Traefik logs.

---

# 27. The important architectural lessons

This exercise exposed several useful principles.

### Kubernetes `LoadBalancer` does not equal your HAProxy VM

Your physical load balancer is:

```text
api-lb-01
```

Kubernetes merely describes Traefik as:

```text
Service type: LoadBalancer
```

The actual external datapath is implemented by your HAProxy infrastructure.

### NodePort is an implementation detail

NodePort does not replace HAProxy.

It provides the stable backend interface:

```text
HAProxy → worker:NodePort
```

The user sees only:

```text
10.51.0.100:443
```

### Pod IPs are not external load-balancer targets

Do not configure HAProxy against:

```text
10.0.0.24
10.0.5.4
```

Those are ephemeral Pod addresses.

Use:

```text
10.51.0.21:31924
10.51.0.22:31924
10.51.0.23:31924
```

### ClusterIP is not the external backend

Do not make HAProxy depend on:

```text
10.97.78.229
```

The ClusterIP belongs to Kubernetes service networking.

### A 404 can be evidence of success

A successful connection returning:

```text
404 page not found
```

from Traefik proves considerably more than a timeout does.

It tells us:

```text
network → NodePort → Service → Traefik
```

is alive.

The next question becomes routing, rather than networking.

---

# 28. Verification checklist

The finished exercise should be able to demonstrate every layer independently.

```text
[ ] WireGuard handshake
[ ] client reaches 10.60.0.1
[ ] dig reaches Pi-hole
[ ] private hostname resolves to 10.51.0.100

[ ] Traefik Application = Synced
[ ] Traefik Pods = Running
[ ] Traefik Service = LoadBalancer
[ ] HTTP NodePort = 31818
[ ] HTTPS NodePort = 31924
[ ] EndpointSlices contain Ready Traefik Pods

[ ] api-lb → worker:31818 works
[ ] api-lb → worker:31924 works
[ ] HAProxy :80 listener works
[ ] HAProxy :443 listener works

[ ] ingress-test Deployment = Ready
[ ] ingress-test Service has endpoints
[ ] Ingress exists
[ ] ingressClassName = traefik
[ ] hostname matches DNS name

[ ] HTTP returns nginx
[ ] HTTPS returns nginx
[ ] certificate is for traefik-test.quantum.nyameko.com
```

---

# 29. Production transition

The `traefik-test` workload is deliberately disposable.

Once it proves the complete path, remove it or move it into a dedicated test application.

The production ingress pattern becomes:

```text
grafana.quantum.nyameko.com
        ↓
10.51.0.100
        ↓
HAProxy
        ↓
Traefik
        ↓
Grafana Service
```

and:

```text
prometheus.quantum.nyameko.com
        ↓
10.51.0.100
        ↓
HAProxy
        ↓
Traefik
        ↓
Prometheus Service
```

and:

```text
jupyter.quantum.nyameko.com
        ↓
10.51.0.100
        ↓
HAProxy
        ↓
Traefik
        ↓
JupyterHub
```

The ingress infrastructure is therefore established once and reused by every subsequent application.

---

# 30. Further reading

Traefik Helm chart and installation reference:

https://doc.traefik.io/traefik/

Kubernetes Services:

https://kubernetes.io/docs/concepts/services-networking/service/

Kubernetes Ingress:

https://kubernetes.io/docs/concepts/services-networking/ingress/

Argo CD Applications:

https://argo-cd.readthedocs.io/en/stable/user-guide/application-specification/

Repository documentation/course pack:

`docs/tutorials/README.md`

The repository's course-pack structure intentionally separates architecture, networking/security, Terraform/Ansible deployment, Kubernetes platform work, secrets/variables/versioning, and later HPC/AI/quantum layers. This Traefik exercise belongs primarily at the boundary between the networking/security and Kubernetes-platform modules.
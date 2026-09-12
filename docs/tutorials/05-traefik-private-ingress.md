# Tutorial 5 — Private Kubernetes Ingress, DNS-01 TLS, and External HAProxy

## Outcome

This tutorial documents the most recent platform milestone:

> A private Kubernetes application is reachable over WireGuard/private DNS, terminates trusted Let's Encrypt TLS through Traefik, and is backed by a normal Kubernetes Service and application Pod.

The tutorial also captures the debugging lessons discovered while building the path.

---

## Architecture

The final intended path is:

```text
blackmyth / private client
        │
        │ WireGuard
        ▼
edge
10.60.0.1
        │
        │ Pi-hole split DNS
        ▼
10.51.0.100
api-lb-01 / HAProxy
        │
        ├── :80  → worker NodePort :31818
        └── :443 → worker NodePort :31924
                         │
                         ▼
                      Traefik
                         │
                         ▼
                       Ingress
                         │
                         ▼
                    nginx test app
```

Certificate issuance uses a different path:

```text
cert-manager
      │
      ├── ClusterIssuer
      │
      └── Cloudflare API token
               │
               ▼
          Cloudflare DNS-01
               │
               ▼
           Let's Encrypt
               │
               ▼
         traefik-test-tls
```

Private reachability and public certificate issuance are deliberately separate concerns.

---

## 1. Deploy Traefik with explicit NodePorts

Traefik exposes:

```text
HTTP  → NodePort 31818
HTTPS → NodePort 31924
```

The important design choice is that these are **worker-node entry points**, not Pod IPs.

Therefore:

```text
correct:
10.51.0.21:31924
10.51.0.22:31924
10.51.0.23:31924

incorrect:
10.0.0.x:31924
```

The Cilium Pod CIDR is not the NodePort listen address.

---

## 2. Prove the Kubernetes side first

Before involving DNS, WireGuard, or HAProxy, test each worker directly.

```bash
for node in 10.51.0.21 10.51.0.22 10.51.0.23; do
  echo "=== $node ==="
  curl -skv \
    --resolve traefik-test.quantum.nyameko.com:31924:$node \
    https://traefik-test.quantum.nyameko.com:31924/
done
```

The expected result is:

```text
TLS 1.3
certificate: traefik-test.quantum.nyameko.com
issuer: Let's Encrypt
HTTP/2 200
server: nginx
```

This proves:

```text
worker NodePort
    ↓
Traefik
    ↓
Ingress
    ↓
Service
    ↓
Pod
```

without involving the external load balancer.

---

## 3. Configure private DNS in Pi-hole

The private hostname is:

```text
traefik-test.quantum.nyameko.com
```

Pi-hole returns:

```text
10.51.0.100
```

Test Pi-hole directly:

```bash
dig @10.60.0.1 traefik-test.quantum.nyameko.com
```

The answer should contain:

```text
traefik-test.quantum.nyameko.com.  IN  A  10.51.0.100
```

Do not put this mapping into workstation `/etc/hosts`. DNS belongs at the private DNS layer so the same namespace can later service many infrastructure applications.

---

## 4. Configure split DNS on the WireGuard client

WireGuard provides reachability; it does not automatically change the workstation's DNS resolver.

On a system using `systemd-resolved`, a suitable test configuration is:

```bash
sudo resolvectl dns wg_infra_hpc_qc 10.60.0.1
sudo resolvectl domain wg_infra_hpc_qc '~quantum.nyameko.com'
```

Verify:

```bash
resolvectl status wg_infra_hpc_qc
```

and:

```bash
dig traefik-test.quantum.nyameko.com
```

The workstation should now send only the `quantum.nyameko.com` namespace through Pi-hole while ordinary Internet DNS continues to use the normal network resolver.

---

## 5. Install cert-manager with Argo CD

The cert-manager Helm source must use the correct OCI registry.

The working pattern is:

```yaml
source:
  repoURL: quay.io/jetstack/charts
  chart: cert-manager
  targetRevision: v1.21.1
  helm:
    values: |
      crds:
        enabled: true
```

The project initially attempted a Docker Hub OCI source and Argo returned `401 unauthorized`. The correct registry resolved the deployment problem.

Validate:

```bash
kubectl get ns cert-manager
kubectl get pods -n cert-manager
kubectl get crd | grep cert-manager
```

The CRDs should include:

```text
certificates.cert-manager.io
certificaterequests.cert-manager.io
challenges.acme.cert-manager.io
clusterissuers.cert-manager.io
issuers.cert-manager.io
orders.acme.cert-manager.io
```

---

## 6. Store the Cloudflare API token as a Sealed Secret

Create the plaintext Secret only on the operator workstation:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-api-token
  namespace: cert-manager
type: Opaque
stringData:
  api-token: YOUR_CLOUDFLARE_API_TOKEN
```

Seal it using the cluster's public Sealed Secrets certificate:

```bash
kubeseal \
  --cert inventories/private/infra-hpc-qc-k8s.cert \
  --format yaml \
  < ../secrets/cert-manager/cloudflare-api-token.yaml \
  > argocd/resources/cert-manager/cloudflare-api-token-sealed.yaml
```

Check that the result is a `SealedSecret` with encrypted data.

Then remove the plaintext working copy:

```bash
rm ../secrets/cert-manager/cloudflare-api-token.yaml
```

The secret should not be committed in plaintext.

---

## 7. Separate cert-manager from cert-manager configuration

Use two Argo Applications:

```text
cert-manager
    ↓
installs the controller + CRDs

cert-manager-config
    ↓
owns the SealedSecret + ClusterIssuer
```

The configuration Application targets:

```text
argocd/resources/cert-manager
```

and uses a later sync wave than cert-manager itself.

This avoids trying to make a Helm chart Application magically own unrelated YAML.

---

## 8. Let the Ingress request its own certificate

The application Ingress contains:

```yaml
annotations:
  cert-manager.io/cluster-issuer: letsencrypt-cloudflare
```

and:

```yaml
tls:
  - hosts:
      - traefik-test.quantum.nyameko.com
    secretName: traefik-test-tls
```

Do not create a hand-written `Certificate` resource for every application unless the application really needs that level of control.

cert-manager ingress-shim watches the Ingress and creates the Certificate automatically.

This gives the application ownership of the requested hostname while the platform owns the certificate-issuance mechanism.

---

## 9. Verify the ACME chain

Check:

```bash
kubectl get clusterissuer
kubectl get certificate -A
kubectl get certificaterequest -A
kubectl get order -A
kubectl get challenge -A
```

A successful issuance should look like:

```text
ClusterIssuer        READY=True
Certificate          READY=True
CertificateRequest   READY=True
Order                valid
Challenge            eventually cleaned up
Secret               kubernetes.io/tls
```

Do not interpret an absent `Challenge` after successful issuance as failure. Completed ACME challenges are cleaned up.

---

## 10. Verify the generated TLS Secret

```bash
kubectl -n default get secret traefik-test-tls -o yaml
```

It should be:

```text
type: kubernetes.io/tls
```

and contain:

```text
tls.crt
tls.key
```

The metadata should identify the cert-manager issuer and certificate.

---

## 11. Verify Traefik with real SNI

Use `curl --resolve` so that the TCP destination is the worker NodePort while TLS SNI remains the real hostname:

```bash
curl -vk \
  --resolve traefik-test.quantum.nyameko.com:31924:10.51.0.21 \
  https://traefik-test.quantum.nyameko.com:31924/
```

A successful response proves all of these at once:

```text
SNI hostname correct
        ↓
Traefik selected the correct certificate
        ↓
Let's Encrypt trust chain is valid
        ↓
Traefik matched the Ingress
        ↓
Service has a backend
        ↓
Application responded
```

---

## 12. Understand Argo `Progressing`

The Traefik test Application may remain `Progressing` even while the route is completely functional.

Why?

The repository intentionally uses an external HAProxy VM as the actual load balancer. Kubernetes therefore does not necessarily populate the `status.loadBalancer` field that generic Argo health checks expect.

So:

```text
Argo Progressing
        ≠
application unavailable
```

For this platform, the authoritative test is the actual network path and application response.

A later improvement is to teach Argo a custom health interpretation for this deliberate external-load-balancer architecture.

Do not introduce another load-balancer controller simply to make the UI say `Healthy`.

---

## 13. Scale the external HAProxy worker pool from inventory

The current architecture should not hard-code three workers forever.

Use the Ansible inventory / canonical worker topology as the source of truth:

```text
worker inventory
      ↓
api_lb_ingress_workers
      ↓
Jinja loop
      ↓
HAProxy
```

The HTTP backend should iterate over workers using NodePort `31818`.

The HTTPS backend should iterate over workers using NodePort `31924`.

Conceptually:

```jinja2
{% for worker in api_lb_ingress_workers %}
    server {{ worker.name }} {{ worker.address }}:{{ api_lb_ingress_http_port }} check
{% endfor %}
```

and:

```jinja2
{% for worker in api_lb_ingress_workers %}
    server {{ worker.name }} {{ worker.address }}:{{ api_lb_ingress_https_port }} check
{% endfor %}
```

This means adding a worker changes topology data once, rather than requiring an HAProxy template edit for every new node.

---

## 14. Final end-to-end validation

Once HAProxy is configured for `:80` and `:443`, test from the private client:

```bash
dig traefik-test.quantum.nyameko.com
```

Expect:

```text
10.51.0.100
```

Then:

```bash
curl -v https://traefik-test.quantum.nyameko.com/
```

The successful result should show:

```text
10.51.0.100:443
TLS certificate for traefik-test.quantum.nyameko.com
Let's Encrypt issuer
HTTP/2 200
nginx response
```

---

## Failure analysis: what this milestone taught us

### Failure 1 — Pod IP versus NodePort

Trying to contact:

```text
Pod IP:31818
```

was wrong.

NodePorts are exposed on the node addresses:

```text
worker IP:31818
```

### Failure 2 — private DNS did not imply private resolver configuration

Pi-hole returned the correct address when queried directly, but the workstation still used public/LAN DNS.

The fix was split DNS on the WireGuard interface.

### Failure 3 — cert-manager did not exist

Argo showed an Application object but the cluster had no cert-manager namespace or CRDs.

The actual error was an OCI registry authentication failure.

The fix was the correct cert-manager OCI registry.

### Failure 4 — Sealed Secret existed in Git but was not reconciled

The Secret and ClusterIssuer YAML existed in the repository, but no Argo Application owned that directory.

The fix was `cert-manager-config` as a separate GitOps Application.

### Failure 5 — manually managed Certificate was unnecessary

The application already expressed its TLS requirement in its Ingress.

The cleaner architecture was:

```text
Ingress
  ↓
cert-manager ingress-shim
  ↓
Certificate
```

### Failure 6 — Argo `Progressing` looked worse than the application actually was

Kubernetes status fields and a GitOps health assessment do not always represent the complete external architecture.

Runtime testing showed the route was healthy.

---

## Acceptance checklist

The milestone is complete when all of the following are true:

```text
[ ] Pi-hole resolves traefik-test.quantum.nyameko.com to 10.51.0.100
[ ] WireGuard client can reach edge
[ ] Worker NodePort 31924 works on every worker
[ ] cert-manager pods are healthy
[ ] ClusterIssuer READY=True
[ ] Certificate READY=True
[ ] traefik-test-tls Secret exists
[ ] Certificate is issued by Let's Encrypt
[ ] Traefik serves the correct certificate through SNI
[ ] Ingress routes to the nginx backend
[ ] external HAProxy listener exists on :443
[ ] private client reaches the final hostname through HAProxy
```

---

## Lessons to carry forward

1. Test the network path one boundary at a time.
2. Keep private DNS and public certificate issuance conceptually separate.
3. Let applications declare the certificates they need; let cert-manager own issuance.
4. Let inventory describe cluster topology and make HAProxy consume that topology.
5. Treat GitOps status as one signal, not the only operational truth.
6. Fix the ownership boundary before adding another framework.

This pattern will be reused for the next platform applications.

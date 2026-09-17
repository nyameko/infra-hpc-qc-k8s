# Phase 1: private administrative infrastructure diagnostics

This runbook accompanies the drop-in changes for agent-control-plane,
quantum-platform, quantum-workflows and .spacemacs.d. These files do not deploy
anything by being extracted. Commit the application changes yourself, publish
tested images, configure deployment values, then perform the first sync.

The slice is: private Django administrator page → authenticated task API →
PostgreSQL queue/history → fixed Prometheus tool → persistent Hermes explanation.
No Kubernetes API credential, provisioning, general shell tool or public ACP
ingress is introduced. Existing edge-only host firewall policy is unchanged.

## 1. Review and publish compatible application images

Review `agent-control-plane/docs/12-phase1.md` and `13-ade-workflow.md`. Apply the
source files to their corresponding repositories. The portal adds migration
`portal.0003_agentprincipal`; check for a migration-number conflict if other work
has landed since the documented baseline. Existing account/PI workflow code is
preserved. The new admin routes use the current allauth administrator login.

Commit the ACP and portal changes. ACP CI uses a disposable native PostgreSQL 18
service and a pinned real Hermes SDK with a local OpenAI protocol fixture. Its
image workflow publishes the exact successful main commit to:

- `ghcr.io/nyameko/agent-control-plane:sha-<full commit SHA>`
- `ghcr.io/nyameko/agent-control-plane-hermes:sha-<full commit SHA>`

The portal's existing image workflow publishes its user-api image. Confirm that
its new administrator tests and image build succeed. Record the **digest** of all
three images from the build results. The base ACP kustomization intentionally has
unconfigured image tags; do not sync it yet. Confirm the cluster can pull the
packages, either through package visibility or an appropriately scoped pull Secret.

The worker builds Hermes from commit
`a566d20d226a8e2ef0747639dc8a3fc1c43f9dba` using its supported editable installation.
It is not a floating latest Hermes gateway. It runs on CPU and uses your configured
remote inference endpoint; it requests no GPUs from Kubernetes.

## 2. Prepare and seal credentials

Use an authenticated operator machine with the intended kubeconfig and
WireGuard access. Select the context deliberately:

```sh
export KUBE_CONTEXT=YOUR_TARGET_CONTEXT
kubectl --context "$KUBE_CONTEXT" get nodes
kubectl --context "$KUBE_CONTEXT" -n monitoring get service prometheus-server
kubectl --context "$KUBE_CONTEXT" get storageclass cinder-ssd
```

Put the model endpoint's API key in a private local file. For a deliberately
unauthenticated internal model server, that file can contain an explicit local
placeholder key. Its network access still needs restriction.

From the ACP repository, with its Python dependencies installed:

```sh
python scripts/create_secrets.py \
  --output /YOUR_PRIVATE_DIRECTORY/agent-phase1-secrets \
  --model-api-key-file /YOUR_PRIVATE_DIRECTORY/model-api-key
```

The script refuses an output directory within a Git checkout and refuses to
replace an existing directory. It generates owner/app PostgreSQL passwords, an
Ed25519 key pair, and five Secret JSON files. It does not print the credentials.
Do not rerun it as a password-rotation mechanism after the database is initialized.

Seal each file for the actual target cluster/controller. Use your existing
kubeseal controller arguments if they differ from its defaults:

```sh
kubeseal --context "$KUBE_CONTEXT" --format yaml \
  < /YOUR_PRIVATE_DIRECTORY/agent-phase1-secrets/acp-db-owner.json \
  > argocd/resources/agent-control-plane/acp-db-owner-sealed.yaml
```

Repeat for `acp-db-app`, `acp-verification`, and `acp-model` into the ACP resource
directory. Seal `acp-signing.json` into
`argocd/resources/quantum-platform/acp-signing-sealed.yaml`. Names and namespaces
are already correct in the generated JSON. Add those five **sealed** files to
the corresponding kustomizations' `resources` lists. Never commit the raw JSON.
Keep an encrypted recovery copy according to your normal credential policy.

Only the portal receives the private signing key. The API receives its public
key. The migration job receives the schema-owner credential. API/worker use the
restricted `acp_app` role; the Hermes subprocess receives only its model key.

## 3. Configure images, model access and private admin integration

Select a model already served by vLLM/Ollama/llama.cpp through an OpenAI-compatible
API. Use its actual deployment model ID and base URL, including `/v1`. Phase 1
uses that explicit route; it does not select model sizes, GPUs, MIGs or VMs.

From the infra repository, with PyYAML installed, run:

```sh
python tools/configure-agent-phase1.py \
  --api-digest sha256:API_IMAGE_DIGEST \
  --hermes-digest sha256:HERMES_IMAGE_DIGEST \
  --platform-digest sha256:PORTAL_USER_API_IMAGE_DIGEST \
  --model YOUR_DEPLOYED_MODEL_ID \
  --model-base-url http://YOUR_INTERNAL_MODEL_HOST:8000/v1 \
  --model-cidr YOUR_MODEL_HOST_IP/32 \
  --model-port 8000
```

Replace every placeholder. For a Kubernetes model service, replace `--model-cidr`
with `--model-namespace YOUR_NAMESPACE --model-app YOUR_APP_LABEL`. The port must
be the destination **pod port** used after Service translation, not necessarily
its Service port. Verify endpoint labels and network-policy behavior in the actual
cluster. The IP form accepts a single host only, not a whole subnet.

This script changes Git files only. It pins ACP and portal images by digest, sets
the model configuration, opens narrow model egress, and enables the optional
`quantum-platform-agent-admin` Kustomize component. That component mounts the
portal signing Secret and configures its internal ACP URL. It does not alter
private/public ingress or existing identity registration settings.

Inspect `git diff`. The quantum-platform Argo application currently auto-syncs
main, so **do not publish its activation change before its signing Secret and
compatible application image are ready**. The portal's existing migration job
uses the same pinned user-api image and runs before deployment.

## 4. Validate and sync in order

```sh
kubectl kustomize argocd/resources/agent-control-plane > /tmp/acp-phase1.yaml
python tools/check-agent-phase1.py /tmp/acp-phase1.yaml
kubectl kustomize argocd/resources/quantum-platform > /tmp/quantum-platform-phase1.yaml
kubectl --context "$KUBE_CONTEXT" apply --dry-run=server -f /tmp/acp-phase1.yaml
```

The static checker rejects unconfigured ACP images/model access and unexpected
public ingress or RBAC. The server dry-run additionally checks API compatibility;
it may require the namespace to exist first. Before syncing, verify Sealed Secrets
has decrypted the resources. When bootstrapping, create the ACP namespace and
apply its sealed resources through your usual GitOps/bootstrap process first.
Do not print Secret data while checking availability.

Review the Prometheus Service and server pod labels/ports. The included policy
uses namespace `monitoring`, labels `app.kubernetes.io/name=prometheus` and
`app.kubernetes.io/component=server`, destination port 9090. Confirm these match
your installed chart. The HTTP Service base URL uses its default port 80. DNS
policy assumes the current kube-dns pod label. Confirm Cilium enforces these
policies without introducing host firewalls on Kubernetes nodes.

After publishing the reviewed infra configuration, register the new Application:

```sh
kubectl --context "$KUBE_CONTEXT" apply -f argocd/applications/agent-control-plane.yaml
```

Perform a **manual sync** of `agent-control-plane` in Argo CD. Waves create the
namespace/storage/network policy, PostgreSQL, the migration job, then API/worker.
The app has no automatic pruning or deletion finalizer. Then promote the private
administrator activation in quantum-platform. The existing portal application
performs its own migration/deployment sync.

Check:

```sh
kubectl --context "$KUBE_CONTEXT" -n agent-control-plane get pods,pvc
kubectl --context "$KUBE_CONTEXT" -n agent-control-plane rollout status deployment/agent-control-plane-api
kubectl --context "$KUBE_CONTEXT" -n agent-control-plane rollout status statefulset/agent-control-plane-hermes
kubectl --context "$KUBE_CONTEXT" -n quantum-platform rollout status deployment/quantum-platform-user-api
```

A blank model configuration or missing credentials should fail startup. Correct
configuration before retrying; do not weaken policy to get a green status.
Inspect failure codes and pod logs without copying credentials into public issues.
`cinder-agent-retain` creates new SSD-backed retained volumes. Existing Cinder
StorageClasses and the portal database volume are not changed.

## 5. Live acceptance

Connect WireGuard and sign into
`https://admin.quantum.nyameko.com/admin/agent-runs/` as an active staff user.
Submit the fixed pod-readiness diagnostic. Verify a queued task becomes running,
then succeeded with numeric evidence, model ID, Hermes revision, session reference
and ordered events. The narrative is interpretation; compare it to Prometheus.

Confirm that public `quantum.nyameko.com/admin/agent-runs/` cannot access the page,
nonstaff users cannot query it, and an unauthenticated internal ACP request gets
401. Check that the worker cannot contact the Kubernetes API or unrelated
services under its network policies. No service-account token should be mounted.

In a test deployment, exercise model unavailability: a completed diagnostic must
retain its evidence while the run reports a model failure. Exercise worker restart
during a run: the abandoned run becomes `worker_interrupted`, not silently retried.
Restart API, worker and database pods one at a time, preserving their claims, and
verify task history and the Hermes profile survive. Do not delete a production PVC
as a persistence test.

The delivered local tests do not replace these checks. In particular native
PostgreSQL connection/concurrency behavior, production image startup, live model
quality, network policy enforcement and Cinder recovery need the target cluster.

## Backup and rollback

This PostgreSQL StatefulSet is a single-instance Phase 1 deployment, not HA.
Before relying on it, create an encrypted off-cluster backup and perform a restore
into a separate namespace/volume. A Cinder snapshot alone does not establish
PostgreSQL-consistent backup or restore correctness.

An operator can capture a logical database backup without printing the password:

```sh
kubectl --context "$KUBE_CONTEXT" -n agent-control-plane exec \
  statefulset/agent-control-plane-postgres -- \
  pg_dump -U acp_owner -d agent_control_plane -Fc > /YOUR_PRIVATE_DIRECTORY/acp.dump
```

Back up the existing quantum-platform PostgreSQL database too: it owns the stable
user-to-AgentPrincipal mapping. Back up the Hermes profile with its worker stopped,
or use a method that correctly captures SQLite plus its WAL. Store reviewed images,
Git configuration and Sealed Secrets recovery material separately. Define an RPO,
RTO and retention policy before expanding to personal research data.

For rollback, remove the optional portal component and restore its previous image
digest through Git, then stop the ACP worker/API through reviewed desired-state
changes. Keep PostgreSQL and both retained claims. The additive AgentPrincipal
table can remain during the rollback window. Do not roll the migration backward
or delete claims to roll back an application. If removing the new namespace/app,
first inspect the retained volume lifecycle and backup status explicitly.

Password rotation requires both PostgreSQL role changes and coordinated Secret
updates; official postgres initialization scripts run only on an empty data
directory. JWT rotation requires coordinated portal/API key deployment. A future
key-ring implementation can remove the short maintenance window.

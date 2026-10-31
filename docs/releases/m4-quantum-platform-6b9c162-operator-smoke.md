# Quantum Platform M4 portal release — source 6b9c162

**Status:** GitOps promotion proposal only; no live cluster change by this PR.

## Supply-chain evidence
- Quantum Platform source commit: `6b9c162d25d493590c876b0a86c1d0e6e3dc4fea` on `main`.
- Source: https://github.com/nyameko/quantum-platform/commit/6b9c162d25d493590c876b0a86c1d0e6e3dc4fea
- Main build: https://github.com/nyameko/quantum-platform/actions/runs/41217593958 (success)
- `users`: `ghcr.io/nyameko/quantum-platform-users@sha256:44b0ef2d1ca2d265f367cfa9b4f7acc0a376cb0fedb6e71a2f06bb83a582aa54`
- `user-api`: `ghcr.io/nyameko/quantum-platform-user-api@sha256:86f5cba386f4647e70671023686cdce454909e3a52a81fcc8f6057eaaec7ce2d`
- Main CI https://github.com/nyameko/quantum-platform/actions/runs/41217593807 ; security https://github.com/nyameko/quantum-platform/actions/runs/41217593741 ; Django administrator tests https://github.com/nyameko/quantum-platform/actions/runs/41217593636 (all success).
- No `quantum-platform-blog` change; the Blog → News portal navigation is frontend-only.

## GitOps release semantics
The `quantum-platform` Application in `argocd/applications/quantum-platform.yaml` watches **infra main** and uses **automated prune + selfHeal**. Merging an application PR or publishing GHCR images is insufficient: an explicitly reviewed infrastructure digest promotion into `main` is the trigger for Argo reconciliation.

**Important:** this Application also includes `quantum-platform-migrate`, an Argo **Sync hook** in wave 1 running `python manage.py migrate --noinput` and conditional `ensure_platform_admin --apply`. The hook can run on Application synchronization **even if only image digests are modified**. Review live diff, migration plan, bootstrap configuration and a backup before promoting to infra main. Never promote with failing required checks.

A source `dev` PR is the first review gate. Promote infra `dev` → `main` with a reviewed PR; do not push directly to `main` or bypass Argo hooks through ad hoc kubectl patching without a documented operator decision.

## Validation after approved promotion (operator uses kubectl on k8s-cp-01)

```sh
kubectl -n argocd get application quantum-platform -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REV:.status.sync.revision'
kubectl -n quantum-platform rollout status deploy/quantum-platform-users --timeout=180s
kubectl -n quantum-platform rollout status deploy/quantum-platform-user-api --timeout=180s
kubectl -n quantum-platform get deployments quantum-platform-users quantum-platform-user-api -o custom-columns='NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image'
kubectl -n quantum-platform get pods -l app.kubernetes.io/name=quantum-platform-users -o jsonpath='{range .items[*]}{.metadata.name}{" "}{range .status.containerStatuses[*]}{.imageID}{"\\n"}{end}{end}'
kubectl -n quantum-platform get pods -l app.kubernetes.io/name=quantum-platform-user-api -o jsonpath='{range .items[*]}{.metadata.name}{" "}{range .status.containerStatuses[*]}{.imageID}{"\\n"}{end}{end}'
kubectl -n quantum-platform get jobs -l app.kubernetes.io/name=quantum-platform-migrate
```

Pod image IDs may be platform-manifest digests instead of OCI index digests; validate the Deployment spec immutable reference first and capture actual Pod image IDs separately. Check controller/migrate Job errors **without** publishing secrets/logged session cookies.

## Browser acceptance on a real authenticated session
1. Incognito: direct `/profile/`, `/security/`, `/programmes/`, `/agent/`, `/access/` and `/profile/index.html` redirect to `/login/` without serving private page markup; public `/`, `/login/`, `/publications/`, `/events/` and `/how-to-cite/` remain readable. With raw HTTP, protected GET status/Location must not expose static HTML.
2. Signed-in root `/`: six functional routes **Identity, Research, Security, Jupyter, Slurm, Resource Access**; old `/dashboard/` compatibility redirect to `/`.
3. Quantum Guide rail: approved personal projects/chats and approved programme folders; **no shared programme chats yet**. A session-scoped mini prompt opens the canonical `/agent/` composer as a draft (not auto-sent).
4. Full Guide: same existing projects/conversations, source-linked memory proposal/approval/correction/revocation and real cross-conversation recall; verify no cross-account data leakage.
5. News header points to existing blog; Publications/Events/How-to-Cite pages show honest verified-empty states, valid navigation, desktop/mobile layout.
6. Workbench and Slurm links route to current functioning pages; retry status and errors are understandable; no model/tools claims beyond deployed abilities.
7. Capture browser console/network failures, actual URL and timing, image SHA, smoke result and accessible-label/mobile findings. Never upload live secrets, bearer tokens or private chat content to public GitHub.

## Follow-up M4 acceptance
- M4b ACP #31: correction/revocation, cross-principal isolation, restart, source provenance.
- M4c ACP #48 / platform #83: governed shared programme conversations; today's folders are read-only navigation.
- M4d governed skills, M4e portable personas, M4f native JupyterLab Guide, M4g terminal continuity.
- Infra #28: automate *creation of reviewed digest PRs*, not direct writes to main.

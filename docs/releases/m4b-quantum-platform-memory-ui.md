# M4b Quantum Platform memory UI release gate

This change stages ONLY two Quantum Platform images from successful main build [41147974510](https://github.com/nyameko/quantum-platform/actions/runs/41147974510), source commit `7a3c3a193a168c00a7443b676b2eeb59ca99db4c`:

- `ghcr.io/nyameko/quantum-platform-users@sha256:45595a65974a7381e8f33566055d968842fef213890a4a2fe46df74fc14991d5` (memory UI)
- `ghcr.io/nyameko/quantum-platform-user-api@sha256:9c0ebcbcfa4a27b698686f50ccf0049390edc4b098f95b61cb1e60c1271cbaf9` (memory proxy)

No ACP API changes, database migrations or worker-memory feature activation are included. **Current live ACP PostgreSQL is schema 3.** The browser memory panel can be shown after this frontend rollout, but saving/approving/retrieving memories **will fail** until ACP API and schema v4 have been separately verified and activated. Label those controls unavailable rather than claiming M4b complete.

**Critical promotion hazard:** `argocd/applications/quantum-platform.yaml` auto-syncs `infra-hpc-qc-k8s/main`, and its Kustomization includes a `quantum-platform-migrate` **Sync hook** running Django migrations and `ensure_platform_admin --apply`. Do not promote the image pins to `main` or manually sync until operator has approved the resulting hook execution and confirmed a recent backup, SQL migration diff, administrator bootstrap behavior and rollback strategy. Review ArgoCD diff and resource list. Use a separate migration-free deployment-only path if this hook is not authorized. The existing SealedSecrets are not changed.

### Verification before merging
1. Kustomize render identifies exactly those two immutable image digests. Blog image remains as previously pinned/tagged.
2. CI and audit green on the **exact source SHA**; record source-to-registry mapping.
3. Capture live Quantum Platform user and user-api pod `imageID` via read-only kubectl; match or document platform-specific manifest digest.
4. Inspect sync/operation history; verify ingress `/agent` route and no frontend caching/old service worker issue. Avoid clearing unrelated browser data.
5. Operator explicitly approves the planned Quantum Platform rollout/hook policy. Only then promote and observe rollout.
6. Test that UI panel appears, source-message selection works, and the 503 disabled/unavailable response is understandable while ACP schema is still v3. Then proceed separately to ACP v4 migration/activation and actual recall.

**No cluster mutations authorized by this PR.**
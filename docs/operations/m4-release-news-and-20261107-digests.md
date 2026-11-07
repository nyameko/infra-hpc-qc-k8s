# M4 release candidate — News styling and verified image digests

**Source only, operator-promoted and observed acceptance required.**
These updates are based on the November 7, 2026 successful *main-branch*
container builds for:
- quantum-platform merge `0e40eebea9e00440934a3d2c88b8b63c846d091d`
  ([#153](https://github.com/nyameko/quantum-platform/pull/153));
- agent-control-plane merge `583de1600e540e0907e8d7a746a62884b97e3195`
  ([#93](https://github.com/nyameko/agent-control-plane/pull/93)).
These are the **currently published digests**. The follow-up newsroom/UI
feature changes from quantum-platform #154 are **not included** in the
November 7 published images; pin *its* new digests after its merge/build
and before its authorized production promotion. Do not assume the portal
signout redesign is deployed simply because this PR is merged.

| Workload | Verified GHCR manifest digest (2026-11-07 main build) |
|---|---|
| `quantum-platform-blog` | `sha256:34bdb7a491e8b0086f6c2b76e1a75ce45752b757c47ba4e2d6af65c23c7a6678` |
| `quantum-platform-users` | `sha256:37db85f9ec2f4206881b93a76d275ef934e6ceee0acfcc77f2198e4924c54556` |
| `quantum-platform-user-api` | `sha256:38ead0c6f49b6a5ec4f7401b50f36aace412c20ae1ea123a28650ce3b77b5929` |
| `agent-control-plane` (API) | `sha256:750b0ceb03fc3d09ef71063b5424716f14944df7be082485689dba6f2ff68f1c` |
| `agent-control-plane-hermes` | `sha256:6ec37a755e57ef868a2fcce6052535588d14742bc85df75ab973dae811f1bdda` |

Source: successful build-push logs for
[QP main image workflow 42410507841](https://github.com/nyameko/quantum-platform/actions/runs/42410507841)
and
[ACP main image workflow 42410603010](https://github.com/nyameko/agent-control-plane/actions/runs/42410603010).
The ACP Hermes digest is also updated in **personal-worker init container,
main container and schema PreSync hook**, which use literal images
rather than Kustomize image substitutions.

## News remains on the existing blog hostname

The **News** navigation label points to the existing public blog:
`https://blog.nyameko.com/`. The blog's Astro canonical site is the
same hostname, and Traefik continues to serve the blog using the existing
Ingress host and existing `quantum-platform-tls` certificate configuration.

There is **no new `news.quantum.nyameko.com` domain**, no new DNS,
Cloudflare or cert-manager request, and no redirect middleware. Existing
post paths stay unchanged. News keeps the same shared Quantum Platform
`@nyameko/ui` site layout, theme, and typography. The separate
wireframe sign-out control remains on the authenticated portal.

Verify the existing host only, after any separately approved deployment:

```bash
curl -IL --max-redirs 3 https://blog.nyameko.com/
```

Do not use this News styling change to trigger Cloudflare changes or
additional DNS records.

## Portal sign-out human UX

After QP #154's **new image** is promoted, sign in on
`https://quantum.nyameko.com/`. Top-right sign out should be a
theme-aware wireframe door, with a `Sign out` tooltip on pointer hover
**and keyboard focus**, keyboard-accessible and readable to assistive
technology. Confirm CSRF-protected POST logout works and failed requests
remain retryable. Test desktop/mobile and dark/light themes.
No GET logout and no change to Django's auth boundary.

## ACP release guard

* M4 human release issue [ACP #45](https://github.com/nyameko/agent-control-plane/issues/45)
  remains the release gate even after the new API/Hermes digests are
  pinned here.
* This digest promotion can launch a **schema-v8 migration** if the
  production database is still older. Before any authorized
  `dev -> main` sync, take an off-PVC PostgreSQL backup, restore to an
  isolated disposable database, inspect migrations 0005-0008 and obtain
  explicit owner production approval. A `main` merge with automated root
  sync is *not* a substitute for this review.
* Inspect the live schema, API `/ready`, personal-worker preflight,
  actual model route, memory lifecycle and two-user denial. Do not mark
  any unobserved test as completed. Paperclip pilot is a separate
  manually approved M5 service, not a blocker for the M4 portal release.

No live Kubernetes, database, DNS or Cloudflare change was performed by
authoring this document and the associated PR.

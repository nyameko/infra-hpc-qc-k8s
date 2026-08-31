# 9. Gap Analysis & Recommendations

This is the concrete output of comparing the drafted documentation against the live repository
(`github.com/nyameko/infra-hpc-qc-k8s`, reviewed 31 August 2026) — its committed `README.md`, `FILELIST.txt`,
`Makefile`, and the actual `ansible/roles/`, `ansible/playbooks/`, and `terraform/modules/` trees. None of
these are severe — this is a young, honestly-scoped POC repo — but every one of them will confuse a student
or a mentor if it isn't resolved before this material goes in front of a cohort.

## Findings

| # | Finding | Evidence | Recommendation |
|---|---|---|---|
| 1 | **Edge node naming drift.** The committed root `README.md` names the edge node `edge-admin`; the newer draft docs (this pack's source material) call it `edge`. | Compared committed `README.md` VM table against `docs/architecture.md`, `docs/EDGE_SECURITY.md`, `docs/INSTALLATION.md`. | Pick one name and propagate it into the Ansible role directory name, inventory group name, and cloud-init filename together — a partial rename is worse than no rename. |
| 2 | **API load balancer terminology drift.** Committed README describes "Kubernetes API Octavia LB"; newer drafts describe an HAProxy VM (`api-lb-01`) behind a switchable `api_lb_type` variable — and there is a real Terraform module named `api_lb`, which matches the HAProxy description, not the Octavia one. | `README.md` deployment order vs. `INSTALLATION.md` §15, `VARIABLE_MODEL.md`, `terraform/modules/api_lb/` in `FILELIST.txt`. | Standardize on the HAProxy VM description (it matches the actual module and variable names) and fix the stray "Octavia" wording in the committed README, unless the intent really is to call Octavia directly — in which case the module and variable should be renamed to match, not the other way round. |
| 3 | **Missing VM topology row.** `api-lb-01` is described in prose (`INSTALLATION.md` §1, §15) and implied by "13 VMs plus the load balancer" (`bootstrap-sequence.md`), but has no row in the VM topology table and no assigned IP. | `README.md` VM table (13 rows) vs. `bootstrap-sequence.md` "13 VMs plus the Kubernetes API load balancer." | Add an explicit `api-lb-01` row to the VM topology table with an IP once finding #2 is resolved. |
| 4 | **Makefile references playbooks that don't exist yet.** `make edge`, `make slurm`, `make hermes`, `make k8s-prereqs` point at `ansible/playbooks/edge.yml`, `slurm.yml`, `hermes.yml`, `kubernetes-prereqs.yml`. None of these appear in the committed `FILELIST.txt`, which lists only `bootstrap.yml`, `join-cluster.yml`, and `kubernetes.yml`. The older quick-start guide additionally references `playbooks/api-lb.yml`, which has **no** Makefile target at all. | Direct diff of `Makefile` targets against `FILELIST.txt` playbook entries and `QUICK_GUIDE.md`. | Not a bug to silently fix — a gap to track explicitly (see #14) and, ideally, close as course exercises (see `COURSE_OUTLINE.md` Module 10). Add a `make api-lb` target for consistency once the corresponding playbook exists. |
| 5 | **No `slurm` or `hermes` Ansible role exists yet**, despite both having dedicated design documents and Makefile targets. `ansible/roles/` currently has: `common`, `containerd`, `edge`, `kube_control_plane`, `kube_join_control_plane`, `kube_worker`, `kubernetes_prereqs`, `pihole`, `ssh`, `suricata`, `wazuh_agent`, `wireguard`. | `FILELIST.txt` role listing. | Same as #4 — track, don't hide; good candidate for guided lab work. |
| 6 | **Two overlapping READMEs** — the repo-root README (facts + quick deployment order) and this pack's documentation-index README (teaching depth) — describe the same VM topology with the naming/LB discrepancies above. Left as-is, the two will keep drifting independently. | Direct comparison of both documents' content. | Merge or clearly scope them: root README stays a terse quick-facts entry point; the `docs/` pack (this one) is the depth reference it should always defer to. |
| 7 | **Ingress controller is unspecified**, and the obvious historical default (`ingress-nginx`) was formally retired by Kubernetes SIG Network and the Security Response Committee, with best-effort maintenance ending in March 2026 and no releases, bug fixes, or security patches since. | `INSTALLATION.md` §20/§25 just say "ingress"; confirmed against Kubernetes' own retirement statement during this review. | Name a controller explicitly now — Traefik or Cilium's Gateway API support are both reasonable (`docs/04` §4.6) — rather than let students build muscle memory around an unmaintained default. |
| 8 | **Stray variable name in prose.** The committed README's deployment order reads "Kubernetes API Api\_Lb LB," which reads like a Terraform variable/module name (`api_lb`) pasted directly into a sentence rather than describing the component in words. | `README.md` §"Deployment order," item 1. | Light copyedit to "HAProxy-based Kubernetes API load balancer" (or whatever #2 resolves to). |
| 9 | **Kubernetes version guidance is right in principle, but names a specific minor that will age.** `versions.md` says "use the currently supported `1.36.x` patch... do not hard-code an old patch." As of this review, `1.37.0` is the newest stable minor (released 26 Aug 2026), with `1.36.2`/`1.35.6`/`1.34.9` also within their support windows. | Cross-checked against Kubernetes' own release page during this review. | Rephrase the rule to be self-updating: "pick the newest minor with at least one patch release and comfortable runway before its own end-of-life" (applied concretely in `docs/08` §8.3), rather than hard-coding `1.36.x` in the policy text itself. |
| 10 | **`FILELIST.txt` is hand-maintained and already stale** relative to the Makefile (finding #4). | Direct diff. | Automate it: `git ls-files > FILELIST.txt` as a Makefile target and/or pre-commit hook (`docs/03` §3.9). |
| 11 | **Minor copyediting.** The committed root README has a couple of typos in its "How to Deploy" section (e.g. "instao an installaiton guide," "adn POC servers"). | Direct read of `README.md`. | Low priority, but worth a pass before this becomes public-facing course material — first impressions on a teaching repo matter more than on an internal one. |
| 12 | **Future nonprofit domain (`omra.nyameko.com`) sits inside the technical domain plan** with no stated relationship to the platform. | `domains.md`. | No action required — just document that it's an intentionally separate concern, so a reader doesn't go looking for infrastructure that isn't there. |
| 13 | **Several drafted docs aren't committed to the repository's `docs/` folder yet.** The live `docs/` directory currently holds only `bootstrap-sequence.md`, `domains.md`, `secrets.md`, and `versions.md`; the newer `architecture.md`, `EDGE_SECURITY.md`, `hermes-federation.md`, `INSTALLATION.md`, `QUICK_GUIDE.md`, `slurm.md`, `VARIABLE_MODEL.md`, and a second `README.md` exist only as drafts. | `FILELIST.txt` vs. the full set of source documents reviewed for this pack. | Commit this pack's `docs/` directory in their place (see this pack's top-level `README.md`), rather than committing the intermediate drafts and creating a third layer of near-duplicate content. |
| 14 | **No single place shows "what's real vs. planned."** Findings #4 and #5 are each individually understandable, but a student hitting either one cold, with no map, will reasonably assume something is broken. | Synthesis of #4/#5. | Add a `STATUS.md`: one row per component, columns for Terraform / Ansible role / Playbook / Status (`done` / `in progress` / `planned`). This becomes the literal 1:1 source for lab assignments in `COURSE_OUTLINE.md` Module 10. |

## Suggested `STATUS.md` skeleton

```markdown
| Component            | Terraform | Ansible role | Playbook | Status      |
|-----------------------|:---------:|:-------------:|:--------:|-------------|
| Networking             | ✅        | —              | —        | done        |
| Compute (VMs)           | ✅        | —              | —        | done        |
| API load balancer        | ✅ (`api_lb`) | —          | —        | ⚠ naming gap (#2) |
| Edge (WireGuard/Pi-hole/nftables) | — | ✅ (`edge`)  | ✅ (`bootstrap.yml`) | done |
| Suricata               | —         | ✅             | ✅       | done        |
| Wazuh agent             | —         | ✅             | ✅       | done        |
| Wazuh manager/indexer/dashboard | — | —              | —        | planned (Argo CD, `docs/04` §4.8) |
| Kubernetes prerequisites  | —         | ✅             | ✅       | done        |
| Kubernetes control plane  | —         | ✅             | ✅       | done        |
| Slurm (controller/login/compute) | — | ❌ (missing) | ❌ (missing) | ▶ lab — see `docs/05` §5.5 |
| Hermes orchestrator       | —         | ❌ (missing)  | ❌ (missing) | ▶ lab — see `docs/06` |
| Cilium                 | —         | —              | —        | planned (`docs/04` §4.3) |
| Argo CD                | —         | —              | —        | planned (`docs/04` §4.5) |
```

## Priority order

**Quick wins (documentation only, no code change):** #1, #2, #3, #7, #8, #9, #11, #12 — all resolvable in a
single editing pass.

**Structural (small automation change):** #4 (playbook stubs or explicit status tracking), #6 (README
merge), #10 (`make filelist`), #13 (commit this pack), #14 (`STATUS.md`).

**Substantive (real implementation work — good course material):** #5 — writing the missing `slurm` and
`hermes` roles. See `COURSE_OUTLINE.md` Module 10 for how this becomes a graded capstone rather than an
unresolved TODO.

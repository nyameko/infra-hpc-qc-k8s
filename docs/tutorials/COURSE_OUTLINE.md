# Course Outline: Hybrid HPC / Cloud / AI-ML / Quantum Infrastructure

A facilitation guide for turning `infra-hpc-qc-k8s` and the `docs/` pack in this repository into a taught
course — video lectures, in-person/live workshops, and self-paced tutorials — in the format proven by
[CHPC's Student Cluster Competition](https://github.com/chpc-tech-eval/scc): daily lecture + tutorial
pairing, a checklist per tutorial, progress-weighted scoring, and a public repo the cohort checks for
updates.

## Audience & prerequisites

Undergraduate/postgraduate students or early-career engineers comfortable with a Linux shell and basic
networking (IP addressing, DNS, SSH). No prior Kubernetes, Slurm, or quantum-computing experience assumed —
Module 0 exists specifically to level the group before the stack-specific modules start.

## Learning outcomes

By the end, a participant should be able to: stand up a segmented, WireGuard-fronted OpenStack environment
from Terraform; configure it with Ansible against a documented variable model; bootstrap a highly-available
Kubernetes cluster and run applications on it via GitOps; operate a Slurm HPC partition alongside it;
articulate a layered security posture (cloud → host → cluster → application) and its threat model; explain
where an AI orchestration agent like Hermes fits, and does *not* fit, into infrastructure automation; and
run quantum circuit simulations in a JupyterHub sandbox.

## How this maps to the repo and docs pack

| Module | Docs reference | Repo paths touched |
|---|---|---|
| M0 — Orientation & Access | `docs/01` | OpenStack project, SSH keys |
| M1 — Architecture & Separation of Concerns | `docs/01` | — (design/reading module) |
| M2 — Networking, WireGuard & Edge Security | `docs/02` | `terraform/modules/{network,security}`, `ansible/roles/{wireguard,ssh}` |
| M3 — Terraform: Provisioning the Cloud | `docs/03` §3.3 | `terraform/environments/personal`, `terraform/modules/*` |
| M4 — Ansible: Configuring the Fleet | `docs/03` §3.4–3.9 | `ansible/*` |
| M5 — Kubernetes Bootstrap | `docs/04` §4.1–4.4 | `ansible/roles/{kube_control_plane,kube_worker,containerd,kubernetes_prereqs}` |
| M6 — GitOps, Ingress & Platform Services | `docs/04` §4.5–4.12 | (Argo CD applications, not yet in repo) |
| M7 — HPC with Slurm | `docs/05` | `ansible/roles/slurm` (▶ lab, doesn't exist yet) |
| M8 — Hermes: AI Agents & Security Orchestration | `docs/06` | `ansible/roles/hermes` (▶ lab, doesn't exist yet) |
| M9 — Quantum Computing Sandbox | `docs/07` | JupyterHub profile config |
| M10 — Capstone: Close the Gaps | `docs/09` | Whatever the cohort chooses from the `STATUS.md` backlog |

## Format per module

Each module below follows the same four-part structure so a facilitator can prep once and reuse the
pattern:

- **Lecture** (45–60 min, recorded for YouTube) — concept-level, diagram-driven, no live typing.
- **Workshop** (2–3 hr, in-person or live-streamed) — hands-on, instructor drives the first pass, cohort
  repeats it themselves.
- **Tutorial checklist** (self-paced, take-home) — the graded artifact; mirrors the SCC tutorials' per-item
  checkbox format so progress is easy for both student and mentor to track.
- **Deliverable** — what gets checked off / submitted.

---

## M0 — Orientation & Environment Access

**Objectives:** get every participant a working OpenStack project, SSH keypair, and a first VM they can
reach — before any platform-specific content starts.

**Lecture:** what OpenStack is and isn't; projects/quotas/flavors/images; the shape of the whole course
(show the architecture diagram from `docs/01` §1.3 once, as a "here's where we're going" map).

**Workshop:** generate an SSH keypair; authenticate to OpenStack (`openstack token issue`); launch one
throwaway VM; SSH in; tear it down.

**Tutorial checklist:**
- [ ] SSH keypair generated and added to the OpenStack project
- [ ] `openstack token issue` succeeds
- [ ] One VM launched, reached over SSH, and deleted again
- [ ] Local tooling installed and verified (`docs/03` §3.1 commands all run clean)

**Deliverable:** screenshot/terminal log of the four checklist items.

---

## M1 — Architecture & Separation of Concerns

**Objectives:** explain the Terraform/Ansible/kubeadm/Argo CD boundary from memory; explain why Slurm and
Kubernetes coexist rather than one replacing the other; locate every VM on the topology diagram without
looking it up.

**Lecture:** walk `docs/01` end to end — separation of concerns table, VM topology, hybrid HPC/K8s
rationale, the environment roadmap (personal → research → Purple Team) and why that last stage is still an
open question (`docs/01` §1.8).

**Workshop:** whiteboard exercise — given a new requirement ("add a GPU node," "add a second research
domain"), the group decides which layer(s) it touches and why, using the separation-of-concerns table as the
only reference material.

**Tutorial checklist:**
- [ ] Can redraw the VM topology table from memory, unaided
- [ ] Can state, for any given change, which of Terraform/Ansible/kubeadm/Argo CD owns it
- [ ] Has read `docs/09` findings #1–#3 (the naming/LB gaps) and can explain each in one sentence

**Deliverable:** a short written answer (2–3 sentences) to "why does this platform run both Slurm and
Kubernetes instead of just one?"

---

## M2 — Networking, WireGuard & Edge Security

**Objectives:** stand up WireGuard, understand the two independent firewall layers (OpenStack SGs vs.
nftables), and articulate the threat model in `docs/02` §2.9.

**Lecture:** `docs/02` in full — defense-in-depth diagram, canonical CIDRs, SSH identity model, WireGuard key
handling, nftables baseline, Pi-hole DNS chain, Wazuh/Suricata staged rollout, the three access-control
planes (§2.8).

**Workshop:** generate a WireGuard client keypair; connect through `edge`; verify the `bootstrap_ssh_cidr →
WireGuard` cutover by disabling the bootstrap rule and confirming access still works over the tunnel; write
and validate an `nftables` ruleset with `nft -c -f`.

**Tutorial checklist:**
- [ ] WireGuard tunnel up, client can reach `mgmt_cidr`
- [ ] Public bootstrap SSH rule removed and access re-verified over WireGuard only
- [ ] `nftables` ruleset validates with `nft -c -f` before being applied
- [ ] Pi-hole resolves an internal record and correctly refuses external queries
- [ ] Threat-model table (`docs/02` §2.9) extended with at least two new rows, with likelihood/impact and a MITRE ATT&CK technique mapped to each

**Deliverable:** the extended threat-model table.

---

## M3 — Terraform: Provisioning the Cloud

**Objectives:** run the full Terraform workflow against the OpenStack project from M0 and produce the 13(+1)
VM topology from `docs/01`.

**Lecture:** Terraform module structure (`network`, `compute`, `api_lb`, `security`), state handling, why
Terraform never touches the OS (`docs/01` §1.2).

**Workshop:** `terraform init/validate/plan/apply` against `terraform/environments/personal`; deliberately
break something (wrong flavor, missing variable) and read the `plan` output to diagnose it before applying.

**Tutorial checklist:**
- [ ] `terraform validate` and `terraform plan` both clean
- [ ] `terraform apply` produces the expected VM count
- [ ] Can explain, from the module list alone, what each of `network`/`compute`/`api_lb`/`security` is
      responsible for
- [ ] Has proposed a resolution to gap-analysis finding #2 (Octavia vs. HAProxy wording) in a short PR/patch

**Deliverable:** `terraform plan` output plus the gap-#2 patch.

---

## M4 — Ansible: Configuring the Fleet

**Objectives:** run the bootstrap sequence end-to-end and correctly diagnose inventory/variable issues using
`ansible-inventory` rather than reading YAML by eye.

**Lecture:** roles vs. playbooks, the canonical variable model (`docs/03` §3.5, `docs/08` §8.2), the
bootstrap sequence (`docs/03` §3.6), why `--flush-cache` is almost never what you actually need.

**Workshop:** run `make bootstrap`, then intentionally introduce a variable-naming drift
(`management_cidr` instead of `mgmt_cidr`) and use `rg` plus `ansible-inventory --host` to find and fix it.

**Tutorial checklist:**
- [ ] `ansible all -m ping` returns success from every host
- [ ] `chronyc tracking` reports `Leap status : Normal` on every host
- [ ] Deliberately introduced naming drift found via `rg` and fixed
- [ ] Has read gap-analysis findings #4/#5 and can explain, without help, exactly which playbooks/roles are
      missing today and why that's tracked rather than hidden

**Deliverable:** before/after diff of the drift-fix exercise.

---

## M5 — Kubernetes Bootstrap

**Objectives:** bring up a 3+3 HA Kubernetes cluster with Cilium and validate every node is `Ready`.

**Lecture:** kubeadm HA control-plane bootstrap, the API load balancer's role (`docs/04` §4.1–4.2), Cilium's
job as CNI (§4.3), the storage chain (§4.4).

**Workshop:** run `make k8s-prereqs && make k8s-init`; install Cilium; run `cilium status` and `kubectl get
nodes -o wide`; deliberately stop `haproxy` on the LB node and observe (without panic) what does and doesn't
break.

**Tutorial checklist:**
- [ ] All six nodes report `Ready`
- [ ] `cilium status` reports healthy
- [ ] Can explain what continues working, and what stops, if the API load balancer goes down mid-session
- [ ] Has resolved gap-analysis finding #3 (missing `api-lb-01` topology row) with a concrete IP proposal

**Deliverable:** `kubectl get nodes -o wide` output plus the topology-table patch.

---

## M6 — GitOps, Ingress & Platform Services

**Objectives:** deploy Argo CD, pick and justify an ingress controller, and get the `quantum.nyameko.com`
hello-world Astro site live end-to-end.

**Lecture:** Argo CD app-of-apps pattern (`docs/04` §4.5); the ingress-nginx retirement and why it changes
the default answer here (§4.6); cert-manager + DNS-01 (§4.7); the observability and Wazuh
indexer/dashboard architecture (§4.8).

**Workshop:** install Argo CD; deploy Traefik (or Cilium Gateway API) and cert-manager as the first two
Argo-managed applications; ship the Astro hello-world page and verify the full
`Cloudflare → Ingress → Astro` chain resolves publicly.

**Tutorial checklist:**
- [ ] Argo CD UI reachable and showing at least two healthy applications
- [ ] `quantum.nyameko.com` resolves and serves the hello-world page over HTTPS
- [ ] Can state, in one paragraph, why `ingress-nginx` was ruled out and what was chosen instead
- [ ] Has written the `STATUS.md` rows (gap-analysis finding #14) for every application deployed this module

**Deliverable:** working public URL + `STATUS.md` patch.

---

## M7 — HPC with Slurm

**Objectives:** submit and monitor a job on a working Slurm partition, and understand exactly what's missing
from the current repo to get there.

**Lecture:** controller/login/compute separation (`docs/05` §5.2–5.4), why the 64-CPU flavor assertion
matters as an IaC pattern, the roadmap items (§5.5).

**Workshop:** starting from the design in `docs/05`, scaffold the missing `slurm` Ansible role (controller +
login + compute variants) far enough to bring up a working single-node partition; submit the sample job from
§5.6.

**Tutorial checklist:**
- [ ] `sinfo` shows the partition `up` with at least one `idle` node
- [ ] Sample job (`docs/05` §5.6) completes and produces the expected output file
- [ ] Role includes the 64-CPU flavor assertion, tested against both a passing and a deliberately-wrong flavor
- [ ] Progress captured against the `slurm` row in `STATUS.md`

**Deliverable:** the `slurm` role (even partially complete) plus job output.

---

## M8 — Hermes: AI Agents & Security Orchestration

**Objectives:** articulate the least-privilege capability model in `docs/06` §6.3 precisely enough to design
a tool scope for a new Hermes capability, and explain the prompt-injection risk in §6.5 in your own words.

**Lecture:** federation model and why the orchestrator sits outside Kubernetes (`docs/06` §6.1–6.2); the
read-only-by-default capability model (§6.3); Hermes as a security orchestrator and its specific guardrails
(§6.4); prompt injection via attacker-controlled log content (§6.5) — this is the module most worth slowing
down for.

**Workshop:** design exercise, no code required — given a proposed new Hermes capability ("auto-draft a
firewall rule change when Suricata fires N alerts from the same source in 5 minutes"), the group specifies:
the exact read scope required, what the human-approval gate looks like, what gets logged, and where an
attacker could try to manipulate the pipeline via crafted alert content.

**Tutorial checklist:**
- [ ] Can state the difference between "propose" and "apply" as it applies to every Hermes capability
- [ ] Has completed the design exercise above in writing
- [ ] Can name at least one OWASP LLM Top 10 category and MITRE ATLAS technique relevant to a log-reading
      security agent
- [ ] Has NOT designed any capability that lets Hermes push to a protected branch or apply a change without
      the human-approval gate — mentors check this explicitly

**Deliverable:** the written capability design.

---

## M9 — Quantum Computing Sandbox

**Objectives:** run the full lab progression from `docs/07` §7.6 inside the JupyterHub sandbox, and correctly
state the qubit-count ceiling for classical simulation and why it exists.

**Lecture:** simulators vs. real hardware (`docs/07` §7.4), the toolkit comparison table (§7.3), where the
sandbox sits in the wider platform (§7.7).

**Workshop:** work through steps 1–4 of the lab progression live (single-qubit gates → Bell state →
Deutsch–Jozsa → Grover on 3 qubits); leave VQE/QAOA (steps 5–6) as the take-home.

**Tutorial checklist:**
- [ ] Steps 1–4 completed and running in the JupyterHub sandbox
- [ ] VQE (step 5) run on a toy molecule, with the resulting energy value sanity-checked
- [ ] QAOA (step 6) run on a small MaxCut instance
- [ ] Can explain, without notes, why state-vector simulation cost grows exponentially with qubit count

**Deliverable:** the notebook from steps 1–6, with brief written commentary per step.

---

## M10 — Capstone: Close the Gaps

**Objectives:** take an item straight from `docs/09`'s findings table or `STATUS.md` backlog and ship it as a
reviewed change — the same "human-approved Git/CI path" the whole platform is designed around (`docs/06`
§6.3).

**Format:** no lecture — this module is entirely project work, spread across the last week(s) of the course,
with brief daily stand-ups instead of a scheduled workshop block.

**Suggested project menu** (pick one per team, sized to the team's remaining time):

- Finish the `slurm` role (M7) end-to-end, including the backup-controller and dedicated-DB roadmap items
  from `docs/05` §5.5
- Build the `hermes` role and the read-only telemetry integration described in `docs/06` §6.4
- Resolve every "quick win" in `docs/09` (findings #1, #2, #3, #7, #8, #9, #11, #12) as a single PR
- Design and document (not necessarily implement) the Purple Team environment boundary flagged as open in
  `docs/01` §1.8
- Automate `FILELIST.txt` and add the `STATUS.md` tracker (`docs/09` finding #10/#14) as CI-enforced
  artifacts

**Deliverable:** a pull request against the course repository, reviewed against the same criteria the course
has been teaching all along — least privilege, separation of concerns, and no secrets in Git.

**Presentation:** each team presents their change (10 minutes: what gap it closed, why the approach was
chosen, what they'd do differently with more time) to the full cohort and any invited mentors.

---

## Assessment rubric

| Component | Weight |
|---|---:|
| Tutorial checklists (M0–M9) | 40% |
| Capstone PR (M10) | 35% |
| Capstone presentation | 15% |
| Participation (discussions, peer help) | 10% |

## Suggested cadence

The nine content modules (M0–M9) map naturally onto a 9–10 session course — weekly for a semester-length
offering, or daily for an intensive week in the SCC style. M10 needs unstructured project time; don't
compress it into a single session. If running in the intensive format, mirror SCC's pattern directly:
lectures in the morning, tutorial/workshop time in the afternoon, discussion channel open the whole time for
peer help.

## Facilitator notes

- **Mentors guide, they don't drive.** If running this in the SCC "hands-off" style, state that rule
  explicitly on day one: mentors help debug and explain, they do not type commands on a student's
  infrastructure.
- **The gap-analysis document is not a script bug list — treat it as real course content.** Presenting
  `docs/09` early (end of M1) sets the expectation that finding and fixing documentation/implementation
  drift is itself a skill being taught, not an embarrassing oversight to route around.
- **Keep a public discussion channel open** (GitHub Discussions, Slack, whatever the cohort already uses) —
  the SCC repos lean on this heavily, and it scales mentor time far better than 1:1 debugging.
- **Recheck `docs/08` §8.3's version table before every course run.** Software moves faster than a syllabus;
  the rule in that section is written to survive that, but someone still has to apply it each time.

## Suggested repository branching model

Reuse the pattern from `chpc-tech-eval/scc` for the course repository itself:

- `main` — stable, what the cohort is currently working from
- `stag` — staging/integration testing of new modules or material before they go live
- `dev` — active development of new course content

Participants working on M10 capstone PRs branch from `dev`, not `main`, for the same reason: it keeps
in-flight teaching material from landing in front of the cohort half-finished.

## Cheat sheet

| Command | Purpose |
|---|---|
| `openstack token issue` | Verify OpenStack authentication |
| `terraform plan` / `apply` | Preview / apply infrastructure changes |
| `ansible-inventory -i <inv> --host <host>` | Authoritative view of what a host's variables actually resolve to |
| `ansible all -i <inv> -m ping` | Verify SSH + Ansible connectivity across the fleet |
| `wg show` | WireGuard tunnel status |
| `nft -c -f <file>` | Validate an nftables ruleset before applying it |
| `kubectl get nodes -o wide` | Kubernetes node health |
| `cilium status` | CNI health |
| `argocd app list` | GitOps application sync status |
| `sinfo` | Slurm partition/node status |
| `squeue -u $USER` | Your own Slurm job queue |
| `sbatch <script>` | Submit a Slurm batch job |

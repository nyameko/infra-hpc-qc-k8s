# 6. Hermes: AI Agents & Orchestration

## 6.1 Two Hermes roles, from the start

| Role | Location | Scope |
|---|---|---|
| `hermes-orchestrator-01` | Isolated VM, outside Kubernetes | Personal/federation orchestrator and reporting point |
| `research-hermes` | Inside Kubernetes, deployed later | Research-cluster agent; reports upward to the personal Hermes |

```text
Personal Hermes
      │
      ├── Infrastructure Hermes
      ├── Research Hermes
      └── future environment agents
```

## 6.2 Why the orchestrator lives outside Kubernetes

A Kubernetes control-plane failure should not be able to take the orchestration/reporting root down with
it. Putting `hermes-orchestrator-01` on its own VM, with its own lifecycle, means the thing responsible for
observing and reasoning about the platform doesn't share a single point of failure with the platform it's
observing. This mirrors a general principle in monitoring/observability design: your monitoring plane
should degrade independently of the plane it monitors.

**Further reading:** [Site Reliability Engineering — Monitoring Distributed Systems (free online
chapter)](https://sre.google/sre-book/monitoring-distributed-systems/).

## 6.3 Capability model: least privilege, by default

The default state is **read-only**. Hermes can read logs, metrics, and infrastructure state, and it can
*generate proposed changes* — but a proposal is not the same as a change taking effect. Concretely:

- No credentials capable of directly pushing Git changes or bypassing approval.
- Read-only Git credentials only; it may create a local patch or a request for review, but it **cannot push
  protected branches**.
- No unrestricted Kubernetes or OpenStack credentials.
- Branch protection and CI are additional, independent enforcement layers *outside* the VM — the guarantee
  doesn't rely solely on Hermes behaving itself.

Every change that actually lands goes through a human-approved Git/CI path, or another mechanism that has
gone through the same explicit approval as that path. This is the load-bearing sentence in the whole design:
an agent that can *propose* infrastructure changes is extremely useful; an agent that can *apply* them
unsupervised is a very different risk profile, and this repo deliberately stays on the "propose" side of
that line for the personal/federation Hermes.

## 6.4 Hermes as a security orchestrator

This is the natural extension of §6.3, and worth treating as its own capability rather than an afterthought:
Hermes is well-positioned to consume the telemetry this environment already produces — Wazuh alerts,
Suricata events, Prometheus/Loki data — correlate it, and turn "here are forty raw alerts" into "here is one
proposed remediation, here's the evidence, here's the blast radius." That's a genuinely valuable use of an
LLM-backed agent. It's also a genuinely different risk surface than "summarise these logs," and needs its
own guardrails on top of §6.3:

- **Same approval gate as everything else.** A security-relevant proposal (a firewall rule change, an
  account lockout, a patch) is still just a proposal until it goes through the human-approved path — Hermes
  does not get an emergency-response exception to §6.3 by default. If you decide it should, that decision
  needs to be made explicitly and documented, not fall out of "well, it seemed urgent."
- **Explicit, narrow read scopes.** Hermes reading Wazuh/Suricata data should be scoped to what it needs for
  correlation, not a blanket credential across every log source in the environment.
- **A durable audit log of every agent action** — every read, every proposal generated, every approval or
  rejection — kept independently of Hermes itself, so the audit trail survives even if Hermes's own state is
  compromised.
- **Secrets never enter the agent's context.** This is the same never-commit discipline as `docs/08` §8.1,
  extended to runtime: don't let a tool call hand Hermes a live credential just because it needs to "check"
  something. Give it a narrower, read-only tool instead.

## 6.5 Prompt injection is a real, specific risk here — not a hypothetical one

A security-log-reading agent has an unusual property: **the data it's analysing is frequently attacker-
controlled.** An HTTP request logged by Suricata, a filename in a Wazuh file-integrity alert, a username in
a failed-login event — all of these can contain arbitrary attacker-chosen text, and if Hermes's log-ingestion
pipeline treats that text as anything other than untrusted data, an attacker gets a way to talk to the
orchestrator through the very alerts meant to catch them. Concretely: log content goes into the context
window as data to be analysed, never as instructions to be followed, and the pipeline should be built (and
tested) with that distinction in mind from day one — not patched in after the first incident where it
mattered.

This is a specific instance of a broader class of risk in agentic systems that consume untrusted external
content. It's worth teaching as its own topic, not folded silently into "and also be careful."

**Further reading:** [OWASP Top 10 for LLM
Applications](https://owasp.org/www-project-top-10-for-large-language-model-applications/) (see specifically
*Prompt Injection* and *Excessive Agency*) · [OWASP Agentic AI — Threats and
Mitigations](https://genai.owasp.org/resource/agentic-ai-threats-and-mitigations/) · [MITRE ATLAS (Adversarial
Threat Landscape for Artificial-Intelligence Systems)](https://atlas.mitre.org/) · [NIST AI Risk Management
Framework](https://www.nist.gov/itl/ai-risk-management-framework).

## 6.6 Research Hermes: sequencing

`research-hermes` deploys **after** the base cluster, ingress, telemetry, and security layers are already
healthy — not in parallel with them. It is scoped to research operations specifically, not given the same
(or broader) access as the personal orchestrator by default; each Hermes instance's capability set should be
justified for what that instance actually needs to do.

## 6.7 Inference backend

Ollama and llama.cpp (`docs/04` §4.12) serve as Hermes's local model-inference backend. Keeping inference
on-cluster/on-VM, rather than calling an external API, matters here for the same reason the read scopes in
§6.4 matter: infrastructure telemetry and security alert content shouldn't leave the trust boundary they
were collected in just to get a model's opinion on them.

## 6.8 Memory / "soul state"

Whatever persistent memory or state Hermes accumulates over time is explicitly on the never-commit list —
see `docs/08` §8.1. Treat it with the same handling as any other credential-adjacent artifact: it can encode
enough about the environment's internals to be useful to an attacker, even if it isn't a credential in the
literal sense.

**Further reading:** [Ansible Vault](https://docs.ansible.com/ansible/latest/vault_guide/index.html) ·
[SOPS](https://github.com/getsops/sops) · [age](https://github.com/FiloSottile/age) — all covered in full in
`docs/08`.

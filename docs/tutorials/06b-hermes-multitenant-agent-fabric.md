# 7. Hermes Agent Fabric: Profiles, Messaging, Specialists and Orchestration

## 7.1 Purpose

Tutorial 6 deployed one persistent Hermes agent. This tutorial turns that single agent into a multi-tenant Agent Fabric.

The central design change is that a Hermes profile is treated as an **agent principal** rather than merely a chat personality.

A principal may represent:

```text
person
system
research project
specialist
orchestrator
```

Each profile receives an explicit scope of memory, tools, credentials and permissions.

## 7.2 Learning objectives

The learner will:

* create isolated Hermes profiles;
* distinguish human, system, research and control agents;
* connect Discord and Telegram;
* map communication channels to institutions and research topics;
* implement a least-privilege capability model;
* create read-only infrastructure agents;
* introduce agent-to-agent requests;
* add cron and event-driven reflection without confusing these mechanisms with model training.

## 7.3 Architecture

```text
                        HERMES GATEWAY
                              │
              ┌───────────────┼───────────────┐
              │               │               │
           Discord         Telegram          API
              │               │               │
              └───────────────┼───────────────┘
                              │
                    profile resolution
                              │
          ┌───────────────────┼───────────────────┐
          │                   │                   │
        USERS            SYSTEMS            ORCHESTRATORS
          │                   │                   │
     researcher-a       hermes-k8s         hermes-platform
     student-a          hermes-openstack   hermes-research
     student-b          hermes-slurm       hermes-meta
                              │
                              ▼
                       capability policy
```

## 7.4 Profile isolation

Current Hermes documentation describes profiles as isolated configuration/state domains containing profile-specific configuration, skills, sessions and credentials. That primitive should be the foundation of the multi-tenant design.

The platform should maintain an external registry mapping:

```text
external identity
      │
      ▼
platform agent ID
      │
      ▼
Hermes profile
```

Do not infer authority from the contents of `SOUL.md`.

## 7.5 Profile classes

Use four broad classes:

```text
users/
  student-001
  researcher-001

systems/
  kubernetes
  openstack
  slurm
  haproxy
  wazuh

research/
  qrmi
  hpc
  quantum

control/
  observer
  platform
  research
  meta
```

These are logical classes, not necessarily separate Kubernetes deployments.

The default architecture remains one managed Hermes deployment containing multiple profiles unless a stronger isolation boundary requires separate deployments.

## 7.6 Cinder storage strategy

A small deployment may use one Hermes PVC.

For stronger tenancy isolation, move toward:

```text
agent-a → PVC-a
agent-b → PVC-b
agent-c → PVC-c
```

or a shared storage system with explicit filesystem isolation when operational scale makes one volume per agent impractical.

Do not place all users' private state in one unrestricted workspace.

## 7.7 Identity and capability model

Define capabilities as nouns/verbs rather than broad administrator roles.

```text
kubernetes.read
kubernetes.events.read
kubernetes.restart

openstack.read
openstack.network.modify

slurm.read
slurm.submit
slurm.cancel

git.read
git.branch
git.commit
git.push

discord.read
discord.post
telegram.send

research.read
research.propose
research.publish.internal
```

Then assign only what each profile requires.

Example:

```text
hermes-observer
  kubernetes.read
  openstack.read
  slurm.read
  research.read
```

The security boundary is implemented by credentials, RBAC, network policy and tool wrappers outside the model.

## 7.8 Read-only infrastructure agents

Create the first specialists in read-only form.

### Kubernetes

```text
hermes-kubernetes
  ├── pods
  ├── deployments
  ├── events
  ├── nodes
  └── metrics
```

### OpenStack

```text
hermes-openstack
  ├── Nova
  ├── Neutron
  ├── Cinder
  └── quotas
```

### Slurm

```text
hermes-slurm
  ├── jobs
  ├── partitions
  ├── nodes
  └── utilisation
```

Write capabilities only after the read-only workflow is proven.

## 7.9 Discord

Hermes supports Discord as a messaging surface. Discord itself uses Gateway events and scoped application permissions/intents.

Start with a dedicated bot and minimum required permissions. Avoid granting `Administrator` just to simplify development.

The server can reflect the institutional structure:

```text
Research Server
│
├── Institution-A
│   ├── #general
│   ├── #hpc
│   ├── #quantum
│   └── #ai-ml
│
├── Institution-B
│   ├── #general
│   └── #hpc
│
└── International-Collaboration
    ├── #hpc
    ├── #quantum
    └── #open-problems
```

The channel itself should become routing metadata, not an authorization shortcut.

## 7.10 Telegram

Telegram provides a useful mobile surface for direct conversations, alerts and approvals.

Keep the bot token in a Kubernetes Secret or external secret manager.

```text
Git
  X bot token

Secret store
  │
  ▼
Hermes
```

## 7.11 Conversation routing

The gateway should resolve:

```text
Discord user
  +
Discord server/channel
        │
        ▼
principal + context
        │
        ▼
Hermes profile
```

For example:

```text
Institution-A / #quantum
        │
        ▼
research context = quantum
visibility = institution
```

Do not rely solely on channel names; store explicit mappings.

## 7.12 Agent-to-agent communication

Specialists should communicate through a controlled service/API rather than mounting one another's private state.

```text
hermes-research
       │
       │ request
       ▼
hermes-qrmi
       │
       │ result
       ▼
hermes-research
```

Every request should have:

```text
requester
recipient
scope
purpose
inputs
result
timestamp
correlation ID
```

## 7.13 Orchestrators

Introduce domain orchestrators only after specialists work independently.

```text
hermes-platform
  ├── kubernetes
  ├── openstack
  └── slurm

hermes-research
  ├── qrmi
  ├── hpc
  └── literature
```

The orchestrator should request information or actions from specialists. It should not inherit their credentials.

This is a load-bearing security rule:

> Orchestration does not imply privilege inheritance.

## 7.14 Observer

A read-only observer can correlate operational state across systems.

```text
Wazuh ───────┐
Suricata ────┤
Prometheus ──┼──> observer
Loki ────────┘
```

But operational visibility is not permission to read private user memories or unpublished work.

## 7.15 Prompt injection boundary

Infrastructure telemetry is untrusted data.

A log line can contain attacker-controlled text.

Therefore:

```text
log/event content
       │
       ▼
UNTRUSTED DATA
       │
       ▼
analysis
```

never:

```text
log/event content
       │
       ▼
agent instruction
```

The same rule applies to web pages, issue comments, repository files and external research content.

## 7.16 Cron and hooks

Cron gives the agent a temporal trigger:

```text
daily → literature scan
weekly → memory consolidation
monthly → skill review
```

Hooks give it an event trigger:

```text
Slurm job completed
       ↓
agent analysis
```

These mechanisms create unattended activity. They do not modify model weights by themselves.

## 7.17 Memory consolidation

A safe memory pipeline is:

```text
sessions
   ↓
candidate memories
   ↓
reflection
   ↓
deduplication
   ↓
approved durable memory
```

Do not allow the agent to silently rewrite the core identity/purpose of a protected profile.

A useful policy split is:

```text
identity / mission     → controlled
working preferences    → mutable
project observations   → mutable
credentials            → never model-managed as memory
```

## 7.18 Validation

Test the tenancy boundary explicitly.

1. Create two profiles.
2. Add a unique memory to each.
3. Start sessions against each profile.
4. Confirm neither profile can retrieve the other's private state.
5. Restart the Hermes pod.
6. Repeat the test.

Then test permissions:

```text
hermes-kubernetes → read pod
hermes-kubernetes → attempt secret read
```

The second operation should fail because the credential/policy layer rejects it.

## 7.19 Further reading

* Hermes Agent: https://github.com/NousResearch/hermes-agent
* Hermes profiles: https://hermes-agent.nousresearch.com/docs/user-guide/features/profiles/
* Hermes memory: https://hermes-agent.nousresearch.com/docs/user-guide/features/memory/
* Hermes cron: https://hermes-agent.nousresearch.com/docs/user-guide/features/cron/
* Discord Gateway: https://docs.discord.com/developers/events/gateway
* Telegram Bot API: https://core.telegram.org/bots/api
* OWASP Agentic AI threats: https://genai.owasp.org/
* MITRE ATLAS: https://atlas.mitre.org/

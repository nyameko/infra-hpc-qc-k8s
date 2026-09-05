# 9. Hermes Research Intelligence: Hierarchical Scientific Discovery

## 9.1 Purpose

This tutorial is the capstone of the Hermes Agent Fabric.

The earlier tutorials established:

```text
persistent agent
      ↓
profiles
      ↓
specialists
      ↓
orchestrators
      ↓
harnesses
```

This tutorial adds the research intelligence layer.

The goal is not an automated paper summariser. The goal is a system that continuously relates:

```text
literature
researchers
projects
experiments
software
infrastructure
results
publications
```

and uses those relationships to propose research opportunities, experiments, collaborations and publication directions.

Human review remains the boundary for externally consequential scientific claims, publications and contact with outside researchers.

## 9.2 Learning objectives

The learner will:

* design a research knowledge graph;
* ingest literature from arXiv and other scholarly sources;
* cross-reference literature with explicitly shared user/project metadata;
* relate papers to actual computational capabilities;
* discover potential collaboration opportunities;
* schedule continuous literature and research reflection;
* connect observations from real Slurm experiments to literature;
* generate publication proposals with provenance;
* understand the research observatory as a closed-loop agent system.

## 9.3 Architecture

```text
                         HERMES RESEARCH
                                │
        ┌───────────────────────┼───────────────────────┐
        │                       │                       │
    Literature              Researchers             Projects
        │                       │                       │
      arXiv                 institutions           experiments
      OpenAlex              expertise              software
      Crossref              publications           datasets
        │                       │                       │
        └───────────────────────┼───────────────────────┘
                                │
                         Research Graph
                                │
             ┌──────────────────┼──────────────────┐
             │                  │                  │
        opportunities      collaborations     publications
             │                  │                  │
             └──────────────────┼──────────────────┘
                                │
                           experiments
                                │
                              Slurm
                                │
                              results
                                │
                                ▼
                            reflection
                                │
                                └──────────► graph
```

## 9.4 Research visibility

The research agent must not inspect every user's private memory merely because it is a research agent.

Define explicit visibility classes:

```yaml
research_visibility:
  publications: public
  research_topics: institutional
  project_metadata: institutional
  collaboration_interest: institutional
  experiments: private
  unpublished_results: private
  conversations: private
  memories: private
```

The exact policy should be encoded by the platform authorization layer.

## 9.5 Research graph

A minimal graph contains:

```text
Paper
Researcher
Student
PI
Institution
Project
Experiment
Repository
Dataset
Algorithm
Software
Hardware
ResearchQuestion
Publication
```

Example relationships:

```text
Paper ──studies──> Algorithm
Paper ──written-by──> Researcher
Researcher ──member-of──> Institution
Researcher ──works-on──> Project
Project ──uses──> Software
Project ──runs-on──> Hardware
Experiment ──produces──> Result
Result ──supports──> ResearchQuestion
```

## 9.6 Literature ingestion

A scheduled collector should retrieve metadata from approved scholarly sources.

A first implementation can focus on arXiv.

The ingestion pipeline is:

```text
source
  ↓
metadata normalization
  ↓
content extraction
  ↓
topic/method extraction
  ↓
entity resolution
  ↓
research graph
```

Do not claim that a paper proves something merely because an LLM summary says so. Store the original bibliographic source and preserve evidence links.

## 9.7 Relevance scoring

The research agent should rank papers against explicit research context.

Possible signals include:

```text
topic similarity
method overlap
software overlap
hardware compatibility
author/institution relationships
citation relationships
active project relevance
```

The output should be a small set of high-value papers rather than a daily firehose.

## 9.8 Infrastructure-aware literature analysis

This is a defining feature of the platform.

Suppose a new paper describes a GPU-accelerated distributed method.

Hermes Research asks:

```text
Does our platform have the required GPU?
Do we have the required runtime?
Do we have MPI?
Can Slurm schedule it?
Can Pyxis/Enroot reproduce the environment?
Is there already a project that could test it?
```

Then:

```text
paper
  ↓
method
  ↓
infrastructure match
  ↓
replication / extension opportunity
```

## 9.9 Researcher-aware analysis

If three active projects independently touch:

```text
quantum ML
GPU optimisation
variational algorithms
```

and a new paper combines those areas, the agent can propose an internal research discussion.

This requires explicit metadata about what users are willing to expose to the research graph.

## 9.10 Collaboration discovery

Potential collaboration can be treated as a matching problem:

```text
research interest
+
method expertise
+
data/assets
+
infrastructure
+
publication history
```

Example:

```text
Student A
  algorithm expertise

Research Group B
  experimental dataset

Platform C
  GPU/HPC capacity
```

The agent can propose a collaboration hypothesis.

It should not automatically contact the outside researcher.

The lifecycle is:

```text
candidate
  ↓
analysis
  ↓
proposal
  ↓
human review
  ↓
draft
  ↓
human approval
  ↓
send
```

## 9.11 Discord research observatory

Discord can become the human-facing research surface.

Example message:

```text
🔬 Research Intelligence

New publication: <title>

Relevance: High

Why it matters:
The paper overlaps with the current quantum/HPC work in this institution.

Infrastructure:
The reported workload appears reproducible with the available GPU + Slurm stack.

Potential extension:
The paper does not evaluate <dimension>.

Suggested research question:
<question>

Potential collaborators:
<people/groups with explicit research visibility>
```

The bot should link back to the original publication and identify which facts are sourced versus inferred.

## 9.12 Telegram research digest

Telegram is useful for concise personal or administrative notifications:

```text
3 new papers relevant to QRMI today.
1 has a likely replication path on the current cluster.
1 suggests a potential collaboration.
1 may be relevant to an existing publication draft.
```

Avoid publishing sensitive project results into broad channels.

## 9.13 Continuous reflection

The research agent needs three distinct activities.

### Literature refresh

```text
daily
  ↓
new literature
```

### Research reflection

```text
weekly
  ↓
projects + literature + experiments
  ↓
new hypotheses
```

### Strategy review

```text
monthly/quarterly
  ↓
research portfolio
  ↓
publication/collaboration opportunities
```

These are different from model training.

## 9.14 Experiment feedback loop

A failed or surprising experiment should become research context.

```text
Slurm job
   ↓
result
   ↓
analysis
   ↓
research observation
   ↓
compare literature
   ↓
hypothesis
```

Example:

```text
published benchmark: A > B

local H200 experiment: B > A

        ↓

investigate workload / implementation / hardware effects
```

That discrepancy can become a research question rather than merely a debugging issue.

## 9.15 Research memory

Separate memory classes:

```text
literature memory
research-question memory
experiment memory
collaboration memory
infrastructure memory
publication memory
```

A proper research database should eventually carry structured metadata, while Hermes filesystem memory remains useful for local agent state and procedural context.

## 9.16 Publication intelligence

The publication agent should maintain a state machine:

```text
observation
   ↓
research question
   ↓
hypothesis
   ↓
experiment proposal
   ↓
human approval
   ↓
experiment
   ↓
result
   ↓
analysis
   ↓
publication proposal
```

The agent may draft and organize evidence. It should not represent an unverified hypothesis as a scientific conclusion.

## 9.17 Research provenance

A publication proposal should be traceable to evidence:

```text
publication idea
   │
   ├── literature references
   ├── project
   ├── experiment IDs
   ├── code commits
   ├── container digests
   ├── Slurm jobs
   └── result artifacts
```

This is the research analogue of the agent coding episode in Tutorial 8.

## 9.18 Hierarchical research agents

The research stack can now be expanded:

```text
                      hermes-meta
                           │
                     hermes-research
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
  literature-agent   collaboration-agent   publication-agent
        │                  │                  │
        └──────────────────┼──────────────────┘
                           │
                       research graph
                           │
                 ┌─────────┴─────────┐
                 │                   │
             hermes-qrmi         hermes-hpc
                 │                   │
             DSH harness          Slurm
                 │                   │
                code             experiments
```

The important point is that the research orchestrator coordinates specialists; it does not become an all-powerful research superuser.

## 9.19 Research observatory loop

The final closed loop is:

```text
                     ┌───────────────┐
                     │  Literature   │
                     └───────┬───────┘
                             │
                             ▼
                     ┌───────────────┐
                     │   Discovery   │
                     └───────┬───────┘
                             │
                             ▼
                     ┌───────────────┐
                     │  Hypothesis   │
                     └───────┬───────┘
                             │
                             ▼
                     ┌───────────────┐
                     │  Experiment   │
                     └───────┬───────┘
                             │
                             ▼
                     ┌───────────────┐
                     │    Results    │
                     └───────┬───────┘
                             │
                             ▼
                     ┌───────────────┐
                     │  Reflection   │
                     └───────┬───────┘
                             │
                             ▼
                     ┌───────────────┐
                     │  Publication  │
                     └───────┬───────┘
                             │
                             └──────────► Literature
```

This is the conceptual endpoint of the four tutorials.

## 9.20 Evaluation

The platform itself can become an experiment.

Compare:

```text
A. stateless assistant
B. persistent memory
C. consolidated memory
D. memory + skills
E. memory + reflection
F. hierarchy
G. hierarchy + research intelligence
```

Measure:

```text
task success
research relevance
false positives
token use
latency
memory growth
repeated errors
human intervention
accepted collaboration suggestions
useful publication proposals
```

A particularly interesting measure is whether infrastructure-aware research intelligence identifies opportunities that a literature-only assistant would miss.

## 9.21 Security and ethics

The research observatory handles potentially sensitive unpublished work.

Therefore:

```text
research metadata ≠ private memory

operational visibility ≠ unrestricted personal visibility

proposal ≠ scientific claim

suggested collaborator ≠ authorised contact
```

Human approval remains the gate for external publication, external contact and high-impact scientific conclusions.

## 9.22 Acceptance test

The capstone acceptance test is:

```text
new paper discovered
      ↓
matched to explicit research topic
      ↓
matched to available infrastructure
      ↓
matched to active project
      ↓
potential experiment proposed
      ↓
Discord notification
      ↓
human approval
      ↓
Slurm experiment
      ↓
results recorded
      ↓
research memory updated
      ↓
future reflection revisits result
```

A second acceptance test should demonstrate a collaboration proposal without revealing any private user material that was not explicitly shared.

## 9.23 Final architecture

```text
                         USERS
                           │
             ┌─────────────┼─────────────┐
             │             │             │
          JupyterHub     Discord       Telegram
             │             │             │
             └─────────────┼─────────────┘
                           │
                           ▼
                  HERMES AGENT FABRIC
                           │
                    ┌──────┴──────┐
                    │             │
               META AGENT     POLICY/AUDIT
                    │
       ┌────────────┼───────────────┐
       │            │               │
   PLATFORM      RESEARCH         USERS
       │            │               │
    K8s/OS/      literature      profiles
    Slurm        graph
       │            │
       │       collaboration
       │       publication
       │            │
       └──────┬─────┘
              │
        SPECIALIST AGENTS
              │
        ┌─────┴─────┐
        │           │
      Hermes       DSH
                    │
                 Slurm
                    │
              Pyxis/Enroot
                    │
                 compute
                    │
                 results
                    │
                    └──────────────► Research Graph
```

The system now has three distinct loops:

```text
operational loop
  observe → diagnose → propose → approve

engineering loop
  task → code → test → benchmark → report

research loop
  discover → hypothesize → experiment → reflect → publish
```

## 9.24 Further reading

* Hermes Agent: https://github.com/NousResearch/hermes-agent
* Hermes research-ready features: https://hermes-agent.nousresearch.com/docs/
* DeepSeek Harness: https://deepseek.com/harness/en/
* DeepSeek Harness repository: https://github.com/deepseek-ai/deepseek-harness
* arXiv API: https://info.arxiv.org/help/api/index.html
* OpenAlex API: https://docs.openalex.org/
* Crossref REST API: https://api.crossref.org/
* Slurm: https://slurm.schedmd.com/
* NVIDIA Pyxis: https://github.com/NVIDIA/pyxis
* Argo CD: https://argo-cd.readthedocs.io/

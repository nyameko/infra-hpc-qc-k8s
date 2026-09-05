# 8. Hermes + DeepSeek Harness: Agent Execution and Scientific Software Engineering

## 8.1 Purpose

Tutorial 7 established a multi-profile Agent Fabric. This tutorial adds a second abstraction: the execution harness.

The key distinction is:

```text
Hermes
  = agent identity, interaction, memory, orchestration

Harness
  = environment, tools, execution loop, sandbox, session mechanics
```

DeepSeek Harness (`dsh`) is especially useful for scientific software engineering because it exposes an everything-is-a-plugin architecture in which models, tools, skills, sessions, sandboxes, storage, loops, scheduling and UI are composable.

As of the current documentation, DeepSeek Harness is explicitly a developer preview and warns that compatibility-breaking changes are expected. Therefore the platform must treat it as replaceable infrastructure behind an internal harness contract.

## 8.2 Learning objectives

The learner will:

* understand the difference between Hermes and a coding harness;
* deploy DeepSeek Harness without coupling the whole Agent Fabric to it;
* run a coding agent against a Git repository;
* place the execution environment in a Slurm allocation;
* use Pyxis and Enroot for reproducible HPC container execution;
* capture agent episode provenance;
* build a reusable QRMI coding agent;
* compose coding, testing and benchmarking harnesses.

## 8.3 Architecture

```text
                     Hermes Research
                           │
                     coding request
                           │
                           ▼
                   Harness interface
                           │
                           ▼
                  DeepSeek Harness
                           │
             ┌─────────────┼─────────────┐
             │             │             │
           model         tools         skills
             │             │             │
             └─────────────┼─────────────┘
                           │
                        sandbox
                           │
                           ▼
                         Slurm
                           │
                       Pyxis/Enroot
                           │
                           ▼
                    scientific container
                           │
                    ┌──────┼──────┐
                    │      │      │
                   Git  compiler  tests
                           │
                       benchmark
```

## 8.4 Why the harness is separate

A model can generate code without knowing:

* where the repository is;
* which compiler to invoke;
* which dependencies are installed;
* which GPU is allocated;
* how to run integration tests;
* how to preserve a reproducible execution trace.

The harness provides those environmental capabilities.

The architectural interface should therefore be:

```text
Agent
  │
  └── Harness request
          │
          ├── environment
          ├── tools
          ├── execution
          ├── verification
          └── provenance
```

## 8.5 DeepSeek Harness

The current DeepSeek Harness describes the design as "Agent = Model + Harness" and treats capabilities as plugins coordinated by the Cordis kernel. Its runs are represented by an append-only session record containing the model context and tool activity.

This aligns naturally with the Agent Fabric, but the upstream project is moving rapidly.

Pin:

```text
DSH version
container image
plugin set
model version
```

for every reproducible experiment.

## 8.6 Installation boundary

For a first deployment, keep DSH separate from Hermes:

```text
Kubernetes
├── Hermes
└── DSH
```

Then prove the protocol/interaction before moving coding sessions onto Slurm.

The initial test is:

```text
Hermes → DSH → repository → tests
```

## 8.7 Repository access

The coding agent should receive only the repository and branch scope needed for the task.

A safe workflow is:

```text
main
 │
 └── agent branch
        │
        ├── edit
        ├── build
        ├── test
        └── report
```

Protected branches remain protected by Git and CI.

The agent may propose a commit; it should not need authority to bypass branch protections.

## 8.8 Slurm execution

For scientific work, put the coding harness inside a controlled Slurm allocation.

```text
Hermes
  │
  ▼
DSH
  │
  ▼
srun / sbatch
  │
  ▼
Pyxis
  │
  ▼
Enroot
  │
  ▼
container
```

Pyxis is a Slurm SPANK plugin for running containers through Slurm, while Enroot provides the container runtime. Install and configure them on the Slurm execution layer, not as Kubernetes applications.

## 8.9 Scientific coding environment

A QRMI coding environment should contain only what the project needs:

```text
Git
compiler/toolchain
Python
MPI
numerical libraries
QRMI source
unit tests
integration tests
benchmark suite
```

The environment should be versioned as a container image.

Record:

```text
image digest
compiler version
MPI version
GPU driver/runtime
```

## 8.10 Example execution contract

```yaml
agent: hermes-qrmi
harness: dsh
repository:
  path: /workspace/qrmi
  branch: agent/<task-id>
execution:
  scheduler: slurm
  partition: gpu
  gpus: 1
verification:
  - unit
  - integration
  - benchmark
policy:
  push_protected_branch: false
```

This is a platform-level contract, not necessarily native DSH configuration.

## 8.11 Coding loop

The preferred loop is:

```text
understand
   ↓
inspect
   ↓
plan
   ↓
modify
   ↓
build
   ↓
test
   ↓
benchmark
   ↓
review
   ↓
report
```

Do not define success as "the model produced code."

Success means:

```text
code change
+
verification evidence
+ reproducible environment
+ provenance
```

## 8.12 Testing hierarchy

For scientific software, preserve the testing hierarchy already established in the repository:

```text
unit
  ↓
numerical correctness
  ↓
integration
  ↓
reference implementation
  ↓
end-to-end
  ↓
benchmarking
```

Tests answer:

```text
is it correct?
```

Benchmarks answer:

```text
how well does it perform?
```

The harness should never substitute one for the other.

## 8.13 Episode provenance

Every coding run becomes a research/engineering episode.

```yaml
episode:
  id: ...
  agent: hermes-qrmi
  harness: dsh
  model: ...
  harness_version: ...

repository:
  commit_before: ...
  commit_after: ...

compute:
  slurm_job_id: ...
  node: ...
  gpu: ...

software:
  container_digest: ...
  compiler: ...
  mpi: ...

verification:
  tests_passed: ...
  benchmarks: ...

human_intervention:
  required: ...
```

This is not just an audit log. It is a reproducibility record.

## 8.14 Harness of harnesses

Once the basic coding harness works, compose narrower harnesses:

```text
research harness
      │
      ├── coding harness
      │      ├── compiler
      │      └── tests
      │
      ├── benchmark harness
      │      ├── Slurm
      │      └── performance analysis
      │
      └── publication harness
             ├── results
             └── figures/tables
```

The top-level agent coordinates the work. Each harness remains responsible for its domain.

## 8.15 QRMI example

A research request such as:

> Implement the next circulant/diagonal operator experiment and compare it against the reference implementation.

can become:

```text
Hermes QRMI
   ↓
DSH coding harness
   ↓
branch
   ↓
implementation
   ↓
unit tests
   ↓
Slurm benchmark
   ↓
comparison
   ↓
research episode
```

A failure becomes useful state:

```text
failure
  ↓
diagnosis
  ↓
research memory
  ↓
possible new skill
```

## 8.16 Security boundary

A coding agent is a high-agency system.

Apply the same proposal/apply separation used elsewhere in the repository:

```text
agent
  │
  ├── inspect
  ├── edit branch
  ├── test
  └── propose merge
             │
             ▼
       human/CI gate
```

Never give a development agent production credentials merely because it is capable of deploying code.

## 8.17 Validation

The minimum acceptance test is:

```text
Hermes
  → creates coding request
  → launches DSH
  → allocates Slurm resources
  → runs inside Pyxis/Enroot
  → modifies a branch
  → passes tests
  → produces benchmark
  → records episode provenance
```

Then deliberately create a failing task and verify that the harness reports the failure rather than declaring success.

## 8.18 Developer-preview warning

DeepSeek Harness is currently a developer preview. Its upstream repository explicitly warns of compatibility-breaking changes.

Therefore:

```text
Agent Fabric
      │
      ▼
Harness interface
      │
 ┌────┴────┐
 │         │
 DSH     future
```

Do not make your persistent agent database, profile model or research graph depend on unstable DSH internals.

## 8.19 Further reading

* DeepSeek Harness: https://deepseek.com/harness/en/
* DSH repository: https://github.com/deepseek-ai/deepseek-harness
* Slurm: https://slurm.schedmd.com/
* NVIDIA Pyxis: https://github.com/NVIDIA/pyxis
* Enroot: https://github.com/NVIDIA/enroot
* GitHub branch protection: https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-branch-protection-rules

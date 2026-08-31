# 7. Quantum Computing Simulation Sandbox

This document is new relative to the original repo — the source docs mention Qiskit, PennyLane, Qiskit Aer,
and CUDA-Q only as a bullet list of JupyterHub images (`docs/04` §4.9). This expands that into an actual
design, since it's one of the platform's headline capabilities and deserves more than a bullet list.

## 7.1 Purpose

Give students and researchers a safe, reproducible, zero-marginal-cost environment to learn quantum
programming — circuit construction, simulation, variational algorithms — without needing real QPU
credentials, queue time, or per-shot billing on day one. Real-hardware access (§7.4) is an explicit stretch
goal layered on top, not a prerequisite.

## 7.2 Delivery mechanism

The sandbox is a JupyterHub **profile**, not a separate VM class or Kubernetes namespace of its own — it
reuses the platform already described in `docs/04` §4.9:

```text
Browser → Ingress → JupyterHub → JupyterLab (Quantum Sandbox profile)
```

## 7.3 Toolkits

| Toolkit | Role | Notes |
|---|---|---|
| [Qiskit](https://docs.quantum.ibm.com/) + [Qiskit Aer](https://qiskit.github.io/qiskit-aer/) | Circuit construction + classical simulator | IBM's ecosystem; largest tutorial/community base |
| [PennyLane](https://docs.pennylane.ai/) (+ Lightning simulator) | Differentiable quantum computing / QML | Best fit for variational algorithms and hybrid quantum-classical gradients |
| [NVIDIA CUDA-Q](https://nvidia.github.io/cuda-quantum/) | GPU-accelerated simulation, hybrid kernels | Only useful if a GPU-backed node pool exists — see §7.5 |
| [Cirq](https://quantumai.google/cirq) / [Amazon Braket SDK (local simulator mode)](https://amazon-braket-sdk-python.readthedocs.io/) | Alternatives worth offering for comparison | Optional, not required for the core lab progression |

## 7.4 Simulation vs. real hardware

Aer and Lightning are **classical simulators** — they represent quantum state as a state vector on
conventional hardware, and that representation grows exponentially with qubit count. On a modest GPU,
expect a practical ceiling somewhere around 25–30 qubits for full state-vector simulation before memory
becomes the binding constraint; this is a good, concrete number to give students so "simulation" doesn't
feel unbounded. CUDA-Q can offload that simulation to GPU workers if the platform has them, and — as a
stretch goal, not a launch requirement — can also target real QPUs through cloud providers: [IBM
Quantum](https://docs.quantum.ibm.com/), [AWS Braket](https://docs.aws.amazon.com/braket/), [Azure
Quantum](https://learn.microsoft.com/en-us/azure/quantum/). Credentials for any of those live outside the
repository, under the same never-commit policy as everything else (`docs/08` §8.1) — they are not
infrastructure secrets, but they're still secrets.

## 7.5 Resource profiles

| Profile | Backend | Storage |
|---|---|---|
| CPU-only | Qiskit Aer (CPU), PennyLane default.qubit | PVC-backed notebook storage |
| GPU-enabled | Aer-GPU, CUDA-Q, PennyLane Lightning-GPU | Same PVC pattern, larger request |

Both profiles come from the same JupyterHub deployment (`docs/04` §4.9) — this is a resource-request and
image difference, not a separate service.

## 7.6 Suggested lab progression

A concrete, gradually-harder sequence — this doubles as the tutorial checklist in `COURSE_OUTLINE.md`
Module 9:

1. Single-qubit gates and measurement (Qiskit `QuantumCircuit` basics)
2. Bell state — the first two-qubit entanglement exercise
3. Deutsch–Jozsa algorithm — smallest useful demonstration of quantum speedup over a classical oracle query
4. Grover's algorithm on 3 qubits — search, and a first taste of amplitude amplification
5. Variational Quantum Eigensolver (VQE) on a toy molecule (e.g. H₂) — bridges into PennyLane/quantum
   chemistry
6. QAOA on a small MaxCut instance — combinatorial optimisation angle
7. *(Stretch)* Submit one of the above to a real QPU via IBM Quantum, and compare noise/fidelity against the
   simulator run from steps 1–6

## 7.7 Where this fits the wider hybrid architecture

No dedicated VM class is needed for the sandbox at launch — it rides on JupyterHub. If a GPU partition is
later added to Slurm (`docs/05` §5.5), that's a natural home for **batch** quantum-simulation jobs too large
or long-running for an interactive notebook session — same toolkits, submitted via `sbatch` instead of run
interactively.

**Further reading:** [Qiskit documentation](https://docs.quantum.ibm.com/) · [Qiskit Aer
documentation](https://qiskit.github.io/qiskit-aer/) · [PennyLane documentation](https://docs.pennylane.ai/) ·
[NVIDIA CUDA-Q documentation](https://nvidia.github.io/cuda-quantum/) · [IBM Quantum
Learning](https://learning.quantum.ibm.com/) · [AWS Braket documentation](https://docs.aws.amazon.com/braket/) ·
[Azure Quantum documentation](https://learn.microsoft.com/en-us/azure/quantum/) — good background text:
*Quantum Computing: An Applied Approach* (Hidary, Springer) for the underlying algorithm math referenced
above.

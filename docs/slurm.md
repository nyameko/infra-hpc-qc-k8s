# Initial Slurm design

`slurm-controller-01` is a dedicated VM. It runs the controller and, initially, accounting services. It is not a login host.

`login1` and `login2` are redundant user entry points. Users submit directly with `sbatch`, `srun`, `salloc`, etc. Jobs are scheduled by `slurmctld` onto compute nodes.

`slurm-cpu-01` and `slurm-cpu-02` are the first pure compute resources, provisioned with exactly 64 logical CPUs each. Their Ansible role fails the deployment if the OpenStack flavor does not expose 64 CPUs.

Later additions can include:

- `slurm-controller-02` as backup controller;
- a dedicated database VM;
- `slurmrestd` on a dedicated API VM if the orchestration layer needs high-volume REST access;
- GPU partitions for H200/A100 resources.

Slurm also supports configless operation for nodes/clients pulling configuration from the controller, which we may adopt after the basic cluster is working.

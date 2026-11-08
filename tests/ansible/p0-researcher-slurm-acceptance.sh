#!/usr/bin/env bash
# Operator-observed P0 acceptance, executed by a *real* provisioned researcher
# over their own authenticated SSH login. NEVER run as admin/root/service.
# Read-only by default. --submit-hello/--submit-cancel-test explicitly schedule
# small disposable CPU test jobs and print IDs for review; no auto-cancellation.
set -euo pipefail

usage() {
  echo "Usage: $0 [--inspect|--submit-hello|--submit-cancel-test]"
  echo "  --inspect            read-only identity, Slurm and NFS checks (default)"
  echo "  --submit-hello       explicitly submit one disposable /bin/hostname CPU job"
  echo "  --submit-cancel-test explicitly submit disposable sleep job for own cancellation"
}

mode="${1:---inspect}"
case "$mode" in
  --inspect|--submit-hello|--submit-cancel-test) ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 64 ;;
esac
[[ "$#" -le 1 ]] || { usage >&2; exit 64; }

actual_user="$(id -un)"
actual_uid="$(id -u)"
actual_gid="$(id -g)"
[[ "$actual_uid" =~ ^[0-9]+$ && "$actual_uid" -ge 20000 ]] || {
  echo "REFUSE: expected a non-privileged, provisioned research UID (>=20000)" >&2
  exit 77
}
[[ -z "${SUDO_USER:-}" && -z "${PKEXEC_UID:-}" ]] || {
  echo "REFUSE: must enter through researcher's own SSH identity" >&2
  exit 77
}
[[ "$actual_user" == "${USER:-$actual_user}" ]] || {
  echo "REFUSE: environment USER differs from authenticated real user" >&2
  exit 77
}
[[ "$HOME" == "/home/research/$actual_user" ]] || {
  echo "REFUSE: unexpected research home; inspect account mapping" >&2
  exit 77
}
for command in sbatch squeue sacct sinfo; do
  command -v "$command" >/dev/null || { echo "Missing: $command" >&2; exit 69; }
done

echo "P0 researcher=$actual_user uid=$actual_uid gid=$actual_gid host=$(hostname -f)"
echo "Expected submission site: CPU Slurm cluster; no GPU requirement"
echo "--- Scheduler partitions and node states ---"
sinfo -o '%P|%G|%a|%l|%T'
echo "--- Researcher associations (read-only; may require site policy) ---"
if command -v sacctmgr >/dev/null; then
  sacctmgr -nP show association where user="$actual_user"     format=Cluster,Account,User,Partition,QOS || {
      echo "Association read blocked; operator should obtain approved read-only evidence." >&2
    }
fi
echo "--- Researcher's current Slurm jobs ---"
squeue -h -u "$actual_user" -o '%i|%u|%P|%T|%R'
echo "--- Researcher home ---"
stat -c '%U:%G %a %n' "$HOME"
[[ -d "$HOME/.quantum-platform" ]] || {
  echo "Research state directory absent. Check identity/NFS provisioning before P0 submit." >&2
  exit 69
}

if [[ "$mode" == --inspect ]]; then
  echo "READ-ONLY INSPECTION COMPLETE; this is not an end-to-end P0 PASS."
  exit 0
fi

# Actual scheduling requires an explicit user choice. Slurm's own account,
# partition/QOS limits and ownership checks are authoritative.
proof_dir="$HOME/.quantum-platform/p0-native-proof"
mkdir -p -- "$proof_dir"
chmod 0700 -- "$proof_dir"

if [[ "$mode" == --submit-hello ]]; then
  wrap="/bin/hostname"
  name="p0-native-hello"
else
  wrap="/bin/sleep 180"
  name="p0-native-cancel-test"
fi
job="$(
  sbatch --parsable --partition=cpu-small --time=00:05:00     --nodes=1 --ntasks=1 --cpus-per-task=1     --job-name="$name" --output="$proof_dir/%j.out"     --wrap="$wrap"
)"
job="${job%%;*}"
[[ "$job" =~ ^[0-9]+$ ]] || {
  echo "Scheduler did not return a numeric job ID; inspect your queue before retrying." >&2
  exit 70
}
echo "SUBMITTED as $actual_user: job=$job"
echo "Check: squeue -j $job -o '%i|%u|%T|%R'"
echo "Then:  sacct -X -nP -j $job --format=JobIDRaw,User,Account,State,ExitCode,Elapsed,AllocTRES"
echo "Output: $proof_dir/$job.out"
if [[ "$mode" == --submit-cancel-test ]]; then
  echo "For OWN job only, after confirming User=$actual_user:"
  echo "  scancel -- $job"
  echo "  sacct -X -nP -j $job --format=JobIDRaw,User,State"
  echo "No cancellation was performed automatically."
fi
echo "No PASS claim until scheduler/accounting evidence is reviewed."

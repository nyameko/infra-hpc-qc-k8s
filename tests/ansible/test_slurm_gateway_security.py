"""Source-level guard against restoring root-powered Slurm cancellation.

This is an additional invariant, NOT a substitute for negative multi-user
acceptance against the live Slurm cluster and deployed gateway.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "ansible/roles/jupyterhub_slurm_gateway/templates/jupyterhub-slurm-helper.j2"
SSH = ROOT / "ansible/roles/jupyterhub_slurm_gateway/templates/jupyterhub-slurm-ssh-entry.j2"


class SlurmGatewaySecurityTests(unittest.TestCase):
    def test_no_root_scancel_in_helper(self):
        src = HELPER.read_text()
        cancel_lines = [
            line.strip()
            for line in src.splitlines()
            if line.strip().startswith("exec ") and "/usr/bin/scancel" in line
        ]
        self.assertEqual(len(cancel_lines), 1)
        self.assertIn('runuser -u "$user" -- /usr/bin/scancel -- "$job"', cancel_lines[0])
        self.assertNotIn('exec /usr/bin/scancel "$arg"', src)

    def test_cancel_requires_authenticated_user_and_matching_uid(self):
        src = HELPER.read_text()
        self.assertIn('expected_uid="${BASH_REMATCH[2]}"', src)
        self.assertIn('actual_uid="$(id -u -- "$user")"', src)
        self.assertIn('"$actual_uid" == "$expected_uid"', src)
        self.assertIn('job_owner="$(/usr/bin/squeue', src)
        self.assertIn('"$job_owner" == "$user"', src)
        self.assertIn('jupyterhub_allowed_group', src)

    def test_ssh_gateway_does_not_offer_shell(self):
        src = SSH.read_text()
        self.assertIn('SSH_ORIGINAL_COMMAND', src)
        self.assertIn('command rejected', src)


if __name__ == "__main__":
    unittest.main()

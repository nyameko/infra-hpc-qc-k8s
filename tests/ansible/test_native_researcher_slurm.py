"""P0 source guards: researcher SSH login and standard Slurm, no UID-switch helper.

Not a substitute for operator-observed multi-user live acceptance.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
ROLE = ROOT / "ansible/roles/researcher_slurm_ssh/tasks/main.yml"
POLICY = ROOT / "ansible/playbooks/slurm-retire-shared-gateway.yml"


class ResearcherSlurmSecurityTests(unittest.TestCase):
    def test_native_ssh_uses_centralized_approved_keys_per_real_user(self):
        policy = ROLE.read_text()
        self.assertIn("researcher_slurm_keys_dir }}/%u", policy)
        self.assertIn("Match Group", policy)
        self.assertIn("AuthenticationMethods publickey", policy)
        self.assertIn("ssh_public_keys", policy)
        self.assertIn("execution_enabled", policy)
        self.assertIn("else ''", policy)
        self.assertNotIn("sudo ", policy)
        self.assertNotIn("runuser ", policy)

    def test_service_selected_uid_helper_not_deployed(self):
        root = ROOT / "ansible/roles/jupyterhub_slurm_gateway"
        self.assertFalse(root.exists(), "Remove the entire legacy helper role")
        jhub = (ROOT / "ansible/playbooks/jupyterhub-slurm.yml").read_text()
        self.assertNotIn("    - jupyterhub_slurm_gateway", jhub)
        self.assertIn("    - researcher_slurm_ssh",
                      (ROOT / "ansible/playbooks/research-identities.yml").read_text())

    def test_retirement_is_separate_confirmed_operator_action(self):
        policy = POLICY.read_text()
        self.assertIn("slurm_legacy_gateway_retirement_approved", policy)
        for p in (
            "/etc/sudoers.d/jupyterhub-slurm-gateway",
            "/usr/local/sbin/jupyterhub-slurm-helper",
            "/usr/local/sbin/jupyterhub-slurm-ssh-entry",
        ):
            self.assertIn(p, policy)
        self.assertIn("state: absent", policy)
        self.assertIn("name: jupyterhub-gateway", policy)


if __name__ == "__main__":
    unittest.main()

"""Offline contract tests for the ACP immutable-digest promoter."""

import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / "scripts/update_acp_image_digests.py"
spec = importlib.util.spec_from_file_location("acp_digest_promotion", MODULE)
promoter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(promoter)

A = "sha256:" + "a" * 64
B = "sha256:" + "b" * 64


class DigestPromotionTests(unittest.TestCase):
    def test_real_gitops_kustomization_matches_exactly_two_aliases(self):
        path = ROOT / "argocd/resources/agent-control-plane/kustomization.yaml"
        original = path.read_text()
        updated = promoter.rewrite_kustomization(original, A, B)
        self.assertIn("newName: ghcr.io/nyameko/agent-control-plane\n  digest: " + A, updated)
        self.assertIn("newName: ghcr.io/nyameko/agent-control-plane-hermes\n  digest: " + B, updated)
        self.assertEqual(promoter.rewrite_kustomization(updated, A, B), updated)

    def test_worker_pins_init_and_main_to_identical_hermes_digest(self):
        path = ROOT / "argocd/resources/agent-control-plane-personal-worker/deployment.yaml"
        original = path.read_text()
        updated = promoter.rewrite_worker(original, B)
        pinned = "ghcr.io/nyameko/agent-control-plane-hermes@" + B
        self.assertEqual(updated.count(pinned), 2)
        self.assertEqual(promoter.rewrite_worker(updated, B), updated)

    def test_rejects_untrusted_or_incomplete_digests(self):
        for wrong in ("dev", "sha256:" + "Z" * 64, "sha256:" + "a" * 63, A + ";rm -rf /"):
            with self.assertRaises(ValueError):
                promoter.valid_digest(wrong)

    def test_fails_closed_if_kustomization_layout_drifted(self):
        with self.assertRaises(ValueError):
            promoter.rewrite_kustomization("images: []\n", A, B)

    def test_fails_closed_if_worker_image_count_drifted(self):
        with self.assertRaises(ValueError):
            promoter.rewrite_worker("containers: []\n", B)


if __name__ == "__main__":
    unittest.main()

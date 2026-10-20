"""Exercise publication checks in disposable Git repositories."""

from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


class PublicationTest(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name)
        subprocess.run(["git", "init", "--quiet", str(self.root)], check=True)
        (self.root / "scripts").mkdir()
        shutil.copy2(
            Path(__file__).with_name("check_publication.py"),
            self.root / "scripts/check_publication.py",
        )
        (self.root / ".gitignore").write_text(".env\ndocs/*\n!docs/README.md\n")

    def check_publication(self):
        return subprocess.run(
            [sys.executable, "scripts/check_publication.py"],
            cwd=self.root,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_includes_public_docs_and_leaves_private_files_out(self):
        (self.root / "docs").mkdir()
        (self.root / "docs/README.md").write_text("Public guide")
        (self.root / "docs/internal.md").write_text("Local report")
        (self.root / ".env").write_text("FIXTURE=local-only")
        result = self.check_publication()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("3 files", result.stdout)

    def test_rejects_private_file_even_after_forced_add(self):
        (self.root / ".env").write_text("FIXTURE=local-only")
        subprocess.run(["git", "add", "-f", ".env"], cwd=self.root, check=True)
        result = self.check_publication()
        self.assertEqual(result.returncode, 1)
        self.assertIn("Private/ignored file is still tracked: .env", result.stderr)

    def test_rejects_oversized_candidate(self):
        with (self.root / "capture.bin").open("wb") as output:
            output.truncate(10 * 1024 * 1024 + 1)
        result = self.check_publication()
        self.assertEqual(result.returncode, 1)
        self.assertIn("File exceeds 10 MiB: capture.bin", result.stderr)

    def test_requires_review_of_symlinks(self):
        (self.root / ".env").write_text("FIXTURE=local-only")
        (self.root / "config-link").symlink_to(".env")
        result = self.check_publication()
        self.assertEqual(result.returncode, 1)
        self.assertIn("Review symlink before publishing: config-link", result.stderr)


if __name__ == "__main__":
    unittest.main()

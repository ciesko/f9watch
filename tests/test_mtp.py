import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class MtpTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        header = os.environ.get("LIBMTP_HEADER_DIR")
        if header:
            flags = ["-I", header]
        else:
            result = subprocess.run(["pkg-config", "--cflags", "libmtp"], capture_output=True, text=True)
            if result.returncode:
                raise unittest.SkipTest("libmtp headers not installed; set LIBMTP_HEADER_DIR to test with headers only")
            flags = shlex.split(result.stdout)
        cls.temp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.temp.cleanup)
        cls.directory = Path(cls.temp.name)
        cls.binary = cls.directory / "mtp-test"
        subprocess.run(["clang", "-std=c11", "-Wall", "-Wextra", "-Werror", *flags,
                        str(ROOT / "tools/mtp-install.c"), str(ROOT / "tests/mtp_stub.c"),
                        "-o", str(cls.binary)], check=True, capture_output=True, text=True)
        cls.prg = cls.directory / "face.prg"
        cls.prg.write_bytes(b"a test watch face binary")

    def run_case(self, case, answer="y\n"):
        log = self.directory / f"{case}.log"
        result = subprocess.run([str(self.binary), str(self.prg)], input=answer,
                                env=dict(os.environ, MTP_TEST=case, MTP_TEST_LOG=str(log)),
                                capture_output=True, text=True, timeout=5)
        return result, log.read_text() if log.exists() else ""

    def test_selects_garmin_not_first_usb_device_and_verifies_before_replacing(self):
        result, log = self.run_case("success")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("open 2334", log)
        self.assertLess(log.index("read 20"), log.index("rename 10"))
        self.assertLess(log.index("rename 20 MARSWATCH.PRG"), log.index("delete 10"))
        self.assertNotIn("delete 77", log)

    def test_declining_writes_nothing(self):
        result, log = self.run_case("decline", "n\n")
        self.assertEqual(result.returncode, 2)
        self.assertNotIn("send", log)

    def test_unsafe_targets_and_ambiguous_folder_contents_are_rejected(self):
        for case in ("multiple", "wrong-model", "missing-folder", "duplicate"):
            with self.subTest(case=case):
                result, log = self.run_case(case)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("send", log)
                self.assertNotIn("delete", log)

    def test_failed_upload_or_read_back_preserves_old_build(self):
        for case in ("upload-failure", "corrupt"):
            with self.subTest(case=case):
                result, log = self.run_case(case)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("delete 10", log)
                self.assertNotIn("rename 10", log)

    def test_finalization_failure_restores_old_filename(self):
        result, log = self.run_case("rename-failure")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("rename 10 MARSWATCH-BACKUP.PRG", log)
        self.assertIn("rename 10 MARSWATCH.PRG", log)
        self.assertNotIn("delete 10", log)


if __name__ == "__main__":
    unittest.main()

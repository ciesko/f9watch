import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for script in ("run.sh", "prerequisites.sh"):
            shutil.copy(ROOT / script, self.root / script)
        self.commands = self.root / "commands"
        self.commands.mkdir()
        self.log = self.root / "calls"
        self.env = dict(os.environ, HOME=str(self.root),
                        PATH=f"{self.commands}:/usr/bin:/bin",
                        CIQ_SDK_HOME="", CIQ_DEVELOPER_KEY="",
                        TEST_CALLS=str(self.log))
        self.executable(self.commands / "brew", 'printf "brew %s\\n" "$*" >> "$TEST_CALLS"\n')
        self.executable(self.commands / "java", "exit 0\n")
        self.executable(self.commands / "xcode-select", "exit 0\n")
        self.executable(self.commands / "open", 'printf "open %s\\n" "$*" >> "$TEST_CALLS"\n')

    def executable(self, path, text):
        path.write_text("#!/bin/bash\n" + text)
        path.chmod(0o755)

    def sdk(self, devices=("fenix9pro51mm", "fenix5x")):
        sdk = self.root / "SDK with spaces"
        (sdk / "bin").mkdir(parents=True)
        self.executable(sdk / "bin/monkeyc",
                        'printf "monkeyc %s\\n" "$*" >> "$TEST_CALLS"\n'
                        'while [ "$#" -gt 0 ]; do\n'
                        '  if [ "$1" = "-o" ]; then shift; printf test > "$1"; fi\n'
                        '  shift\n'
                        'done\n')
        ciq = self.root / "Library/Application Support/Garmin/ConnectIQ"
        ciq.mkdir(parents=True)
        (ciq / "current-sdk.cfg").write_text(str(sdk) + "\r\n")
        for device in devices:
            path = ciq / "Devices" / device
            path.mkdir(parents=True)
            (path / "compiler.json").write_text("{}")
        key = self.root / "existing key.der"
        key.write_text("test signing key")
        self.env["CIQ_DEVELOPER_KEY"] = str(key)

    def run_script(self, script, answers, args=()):
        return subprocess.run(["/bin/bash", str(self.root / script), *args],
                              input=answers, text=True, env=self.env,
                              capture_output=True, timeout=10)

    def test_quit_needs_no_sdk(self):
        result = self.run_script("run.sh", "6\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / ".local").exists())

    def test_build_uses_current_sdk_with_spaces_and_selected_device(self):
        self.sdk()
        result = self.run_script("run.sh", "4\n2\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("-d fenix5x", self.log.read_text())
        self.assertTrue((self.root / "bin/MarsWatch-fenix5x.prg").exists())
        self.assertNotIn("open ", self.log.read_text())

    def test_export_checks_both_device_packages(self):
        self.sdk(("fenix9pro51mm",))
        result = self.run_script("run.sh", "5\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing Garmin device package: fenix5x", result.stderr)
        self.assertNotIn("monkeyc", self.log.read_text())
        self.assertNotIn("brew install", self.log.read_text())

    def test_store_export_is_distinct_from_device_build(self):
        self.sdk()
        result = self.run_script("run.sh", "5\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("-e -r", self.log.read_text())
        self.assertNotIn("-d fenix", self.log.read_text())
        self.assertTrue((self.root / "bin/MarsWatch.iq").exists())

    def test_missing_sdk_fails_without_installing(self):
        result = self.run_script("run.sh", "4\n1\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No current Connect IQ SDK", result.stderr)
        self.assertFalse(self.log.exists())

    def test_declining_prerequisites_does_not_install(self):
        result = self.run_script("prerequisites.sh", "n\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.log.exists())

    def test_prerequisites_opens_the_actual_homebrew_app(self):
        result = self.run_script("prerequisites.sh", "y\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("brew install --cask connectiq-sdk-manager", self.log.read_text())
        self.assertIn("open -a SdkManager", self.log.read_text())


if __name__ == "__main__":
    unittest.main()

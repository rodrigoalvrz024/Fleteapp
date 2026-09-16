import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest


class StorageDependencyBoundaryTests(unittest.TestCase):
    def test_api_loads_and_storage_tests_pass_with_removed_provider_blocked(self):
        app_root = Path(next(iter(importlib.util.find_spec("app").submodule_search_locations))).parent
        test_root = Path(__file__).resolve().parents[1]
        script = textwrap.dedent("""
            import importlib.abc
            import socket
            import sys
            import unittest
            from unittest.mock import patch

            sys.path[:0] = [sys.argv[1], sys.argv[2]]

            class RemovedProviderBlocked(importlib.abc.MetaPathFinder):
                def find_spec(self, fullname, path=None, target=None):
                    if fullname == "cloudinary" or fullname.startswith("cloudinary."):
                        raise ImportError("Removed storage provider must not be imported")
                    return None

            sys.meta_path.insert(0, RemovedProviderBlocked())
            try:
                import cloudinary
            except ImportError:
                pass
            else:
                raise AssertionError("Import guard is not active")

            with patch.object(socket.socket, "connect", side_effect=AssertionError("No external connection")):
                from app.main import app
                assert app.title == "Muvv API"
                suite = unittest.defaultTestLoader.loadTestsFromNames([
                    "tests.test_freight_flow", "tests.test_chat_access", "tests.test_freight_access",
                ])
                result = unittest.TextTestRunner(verbosity=0).run(suite)
                if not result.wasSuccessful():
                    raise SystemExit(1)
            assert not any(name == "cloudinary" or name.startswith("cloudinary.") for name in sys.modules)
            print("REMOVED_PROVIDER_BOUNDARY_OK")
        """)
        environment = {
            key: value for key, value in os.environ.items()
            if key.upper() in {"SYSTEMROOT", "WINDIR", "PATH", "TEMP", "TMP", "HOME", "LANG"}
        }
        environment.update({
            "APP_ENV": "test", "RUN_STARTUP_MIGRATIONS": "false",
            "DATABASE_URL": "postgresql://postgres:postgres@127.0.0.1:1/muvv_test",
            "SECRET_KEY": "isolated-storage-dependency-test-key-not-for-production",
            "ACCESS_TOKEN_EXPIRE_MINUTES": "1440",
        })
        with tempfile.TemporaryDirectory(prefix="muvv-storage-test-") as isolated_directory:
            completed = subprocess.run(
                [sys.executable, "-I", "-B", "-c", script, str(app_root), str(test_root)],
                env=environment, cwd=isolated_directory, capture_output=True, text=True, timeout=30,
            )
        self.assertEqual(completed.returncode, 0, "Isolated removed-provider test failed")
        self.assertIn("REMOVED_PROVIDER_BOUNDARY_OK", completed.stdout)


if __name__ == "__main__":
    unittest.main()

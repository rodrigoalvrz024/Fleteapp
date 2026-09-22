from pathlib import Path
import os
import stat
from types import SimpleNamespace
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
TARGETS = tuple(Path('/usr/share/man') / name for name in ('man1', 'man5', 'man7', 'man8'))
PARENTS = tuple(Path(name) for name in ('/', '/usr', '/usr/share', '/usr/share/man'))


class ManualDirectoryPermissionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.recipes = {}
        for name in ('Dockerfile', 'Dockerfile.python314'):
            path = ROOT / 'backend' / name
            if path.exists():
                text = path.read_text(encoding='utf-8')
                cls.recipes[name] = text.split("RUN python -I -B - <<'PY'\n", 1)[1].split('\nPY\n', 1)[0]
        if not cls.recipes:
            raise unittest.SkipTest('Docker recipes not mounted in this candidate')

    def execute(self, *, overrides=None, mode=0o2775):
        entries = {path: SimpleNamespace(st_mode=stat.S_IFDIR | (mode if path in TARGETS else 0o755),
                                        st_uid=0) for path in PARENTS + TARGETS}
        entries.update(overrides or {})

        def metadata(path):
            value = entries[path]
            if isinstance(value, Exception):
                raise value
            return value

        for name, source in self.recipes.items():
            with patch.object(Path, 'lstat', metadata), patch.object(os, 'chmod') as chmod:
                try:
                    exec(compile(source, name, 'exec'), {})
                except BaseException:
                    chmod.assert_not_called()
                    raise
                self.assertEqual(len(chmod.call_args_list), 4)
                self.assertEqual([call.args[0] for call in chmod.call_args_list], list(TARGETS))
                for call in chmod.call_args_list:
                    self.assertEqual(call.args[1], mode & ~0o022)
                    self.assertEqual(call.kwargs, {'follow_symlinks': False})

    def test_recipes_share_the_same_narrow_permission_fix(self):
        if len(self.recipes) == 2:
            self.assertEqual(*self.recipes.values())
        self.execute()

    def test_read_execute_and_special_bits_are_preserved(self):
        for mode in (0o755, 0o775, 0o777, 0o2775, 0o2750):
            with self.subTest(mode=mode):
                self.execute(mode=mode)

    def test_missing_path_stops_before_changing_any_permissions(self):
        with self.assertRaises(FileNotFoundError):
            self.execute(overrides={TARGETS[-1]: FileNotFoundError()})

    def test_symlink_or_regular_file_anywhere_in_path_is_rejected(self):
        for path in PARENTS + TARGETS:
            for kind in (stat.S_IFLNK, stat.S_IFREG):
                with self.subTest(path=path, kind=kind), self.assertRaises(SystemExit):
                    self.execute(overrides={path: SimpleNamespace(st_mode=kind | 0o755, st_uid=0)})

    def test_nonroot_ownership_anywhere_in_path_is_rejected(self):
        for path in PARENTS + TARGETS:
            with self.subTest(path=path), self.assertRaises(SystemExit):
                self.execute(overrides={path: SimpleNamespace(st_mode=stat.S_IFDIR | 0o755, st_uid=100)})


if __name__ == '__main__':
    unittest.main()

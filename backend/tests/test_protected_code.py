import importlib.util
from pathlib import Path
import stat
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch


path = Path(__file__).resolve().parents[2] / "scripts/verify-protected-code.py"
spec = importlib.util.spec_from_file_location("protected_code", path)
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


def metadata(mode=stat.S_IFREG | 0o644, uid=0):
    return SimpleNamespace(st_mode=mode, st_uid=uid)


class ProtectedCodeTests(unittest.TestCase):
    def link(self):
        link = Mock(spec=Path)
        link.lstat.return_value = metadata(stat.S_IFLNK | 0o777)
        link.readlink.return_value = Path("/app/target").absolute()
        target = Mock(spec=Path)
        target.is_relative_to.return_value = True
        target.stat.return_value = metadata()
        link.resolve.return_value = target
        return link, target

    def test_valid_link_destination_is_checked_even_when_link_is_root_owned(self):
        link, target = self.link()
        with patch.object(checker.os, "access", return_value=False) as access:
            checker.check_entry(link, (Path("/app").absolute(),))
        link.resolve.assert_called_once_with(strict=True)
        target.stat.assert_called_once_with()
        self.assertEqual(access.call_count, 2)

    def test_writable_target_is_rejected(self):
        link, _ = self.link()
        with patch.object(checker.os, "access", side_effect=[False, True]), self.assertRaises(ValueError):
            checker.check_entry(link, (Path("/app").absolute(),))

    def test_directory_link_outside_scanned_roots_is_rejected(self):
        link, target = self.link()
        target.is_relative_to.return_value = False
        target.stat.return_value = metadata(stat.S_IFDIR | 0o755)
        with patch.object(checker.os, "access", return_value=False), self.assertRaisesRegex(ValueError, "escapes"):
            checker.check_entry(link, (Path("/app").absolute(),))

    def test_broken_denied_and_cyclic_links_are_not_treated_as_safe(self):
        for error in (FileNotFoundError(), PermissionError(), RuntimeError("loop")):
            link, _ = self.link()
            link.resolve.side_effect = error
            with patch.object(checker.os, "access", return_value=False), self.assertRaises(type(error)):
                checker.check_entry(link, (Path("/app").absolute(),))

    def test_untrusted_target_owner_or_mode_is_rejected(self):
        for bad in (metadata(uid=1000), metadata(stat.S_IFREG | 0o666), metadata(stat.S_IFREG | 0o4755)):
            link, target = self.link()
            target.stat.return_value = bad
            with patch.object(checker.os, "access", return_value=False), self.assertRaises(ValueError):
                checker.check_entry(link, (Path("/app").absolute(),))

    def test_link_access_itself_is_not_skipped(self):
        link, _ = self.link()
        with patch.object(checker.os, "access", return_value=True), self.assertRaises(ValueError):
            checker.check_entry(link, (Path("/app"),))

    def test_regular_file_does_not_need_link_resolution(self):
        path = Mock(spec=Path)
        path.lstat.return_value = metadata()
        with patch.object(checker.os, "access", return_value=False):
            checker.check_entry(path, (Path("/app"),))
        path.resolve.assert_not_called()

    def test_external_hop_cannot_resolve_back_into_safe_root(self):
        link, _ = self.link()
        link.readlink.return_value = Path("/tmp/redirect").absolute()
        with patch.object(checker.os, "access", return_value=False), self.assertRaisesRegex(ValueError, "traverses"):
            checker.check_entry(link, (Path("/app").absolute(),))

    def test_parent_components_cannot_hide_external_traversal(self):
        for raw in (Path("/tmp/hop/../../app/target"), Path("../target")):
            link, _ = self.link()
            link.readlink.return_value = raw
            with patch.object(checker.os, "access", return_value=False), self.assertRaisesRegex(ValueError, "traversal"):
                checker.check_entry(link, (Path("/app").absolute(),))


if __name__ == "__main__":
    unittest.main()

import importlib.util
from datetime import datetime, timedelta, timezone
from pathlib import Path
import sys
import unittest

from cryptography import x509
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding


# Resolve from the installed app, so container tests inspect the actual image.
APP_ROOT = Path(importlib.util.find_spec("app.database").origin).parent.parent
CA_PATH = APP_ROOT / "certs" / "supabase-root-2021.crt"
CA_SHA256 = "807025ad50d4ed219d2c9c7d299c004f824eb00cf7f65afef607d07b72e6cafa"


class DatabaseCaBundleTests(unittest.TestCase):
    def test_bundle_contains_only_the_reviewed_public_certificate(self):
        data = CA_PATH.read_bytes()
        certificates = x509.load_pem_x509_certificates(data)
        self.assertEqual(len(certificates), 1)
        self.assertEqual(data.count(b"-----BEGIN "), 1)
        self.assertNotIn(b"PRIVATE KEY", data)
        self.assertEqual(certificates[0].fingerprint(hashes.SHA256()).hex(), CA_SHA256)

    def test_certificate_is_a_current_self_signed_ca(self):
        cert = x509.load_pem_x509_certificate(CA_PATH.read_bytes())
        self.assertTrue(cert.extensions.get_extension_for_class(x509.BasicConstraints).value.ca)
        self.assertTrue(cert.extensions.get_extension_for_class(x509.KeyUsage).value.key_cert_sign)
        self.assertEqual(cert.issuer, cert.subject)
        cert.public_key().verify(cert.signature, cert.tbs_certificate_bytes,
                                 padding.PKCS1v15(), cert.signature_hash_algorithm)
        now = datetime.now(timezone.utc)
        self.assertLessEqual(cert.not_valid_before_utc, now)
        self.assertGreater(cert.not_valid_after_utc, now + timedelta(days=90))

    @unittest.skipUnless(sys.platform == "linux" and APP_ROOT == Path("/app"),
                         "Image ownership is checked in the Linux container")
    def test_image_certificate_and_directory_are_protected(self):
        for path in (CA_PATH, CA_PATH.parent):
            self.assertFalse(path.is_symlink())
            self.assertEqual(path.stat().st_uid, 0)
            self.assertEqual(path.stat().st_mode & 0o022, 0)
        self.assertEqual(CA_PATH.stat().st_mode & 0o777, 0o444)


if __name__ == "__main__":
    unittest.main()

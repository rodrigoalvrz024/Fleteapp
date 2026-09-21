import ssl
import unittest
from unittest.mock import AsyncMock, MagicMock, patch

from anyio.streams.tls import TLSStream


class AnyioTlsSecurityTests(unittest.IsolatedAsyncioTestCase):
    async def wrap_without_network(self, hostname, *, custom_context=False):
        context = ssl.create_default_context()
        if custom_context:
            context = MagicMock(wraps=context)
        # Exercise AnyIO and real SSL hostname encoding, not a network handshake.
        with patch.object(TLSStream, "_call_sslobject_method", new_callable=AsyncMock):
            return await TLSStream.wrap(MagicMock(), hostname=hostname,
                                        ssl_context=context, server_side=False)

    async def test_unicode_hostname_uses_idna_2008_in_native_context(self):
        stream = await self.wrap_without_network("fa\u00df.example.invalid")
        self.assertEqual(stream._ssl_object.server_hostname, "xn--fa-hia.example.invalid")

    async def test_unicode_hostname_uses_idna_2008_in_custom_context(self):
        stream = await self.wrap_without_network("fa\u00df.example.invalid", custom_context=True)
        self.assertEqual(stream._ssl_object.server_hostname, "xn--fa-hia.example.invalid")

    async def test_ascii_and_ip_hostnames_are_preserved(self):
        for hostname in ("api.example.invalid", "127.0.0.1"):
            with self.subTest(hostname=hostname):
                stream = await self.wrap_without_network(hostname)
                self.assertEqual(stream._ssl_object.server_hostname, hostname)


if __name__ == "__main__":
    unittest.main()

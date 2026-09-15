import unittest
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
from types import SimpleNamespace
from unittest.mock import patch

from fastapi import HTTPException

from app.core import rate_limit as limits


class RateLimitTests(unittest.TestCase):
    def setUp(self):
        limits._BUCKETS.clear()
        self.addCleanup(limits._BUCKETS.clear)
        self.clock = self.enterContext(patch.object(limits, "monotonic", return_value=100.0))
        self.enterContext(patch.object(limits, "_NEXT_SWEEP", 0.0, create=True))
        self.request = SimpleNamespace(headers={}, client=SimpleNamespace(host="127.0.0.1"))

    def check(self, identifier="account", **kwargs):
        return limits.check_rate_limit(self.request, scope="test", identifier=identifier,
            max_attempts=kwargs.get("attempts", 2), window_seconds=kwargs.get("window", 60))

    def test_sliding_window_expires_at_boundary(self):
        self.check()
        self.clock.return_value = 130.0
        self.check()
        self.clock.return_value = 159.0
        with self.assertRaises(HTTPException) as error:
            self.check()
        self.assertEqual(error.exception.status_code, 429)
        self.assertEqual(error.exception.headers["Retry-After"], "1")
        self.clock.return_value = 160.0
        self.check()

    def test_unused_expired_identifiers_are_reclaimed(self):
        for index in range(20):
            self.check(str(index))
        self.clock.return_value = 200.0
        self.check("new")
        self.assertEqual(len(limits._BUCKETS), 1)

    def test_capacity_rejects_new_identifiers_without_erasing_active_limits(self):
        with patch.object(limits, "_MAX_BUCKETS", 2, create=True):
            self.check("first")
            self.check("second")
            with self.assertRaises(HTTPException) as error:
                self.check("third")
            self.assertEqual(error.exception.status_code, 503)
            self.check("first")
            with self.assertRaises(HTTPException) as limited:
                self.check("first")
            self.assertEqual(limited.exception.status_code, 429)
            self.assertEqual(len(limits._BUCKETS), 2)
            self.clock.return_value = 200.0
            self.check("third")

    def test_concurrent_requests_cannot_exceed_quota(self):
        start = Barrier(24)

        def attempt(_):
            start.wait(timeout=10)
            try:
                self.check(attempts=8)
                return 200
            except HTTPException as error:
                return error.status_code

        with ThreadPoolExecutor(max_workers=24) as pool:
            results = list(pool.map(attempt, range(24)))
        self.assertEqual(results.count(200), 8)
        self.assertEqual(results.count(429), 16)

    def test_scope_and_account_are_independent(self):
        self.check("first", attempts=1)
        self.check("second", attempts=1)
        limits.check_rate_limit(self.request, scope="different", identifier="first",
            max_attempts=1, window_seconds=60)
        with self.assertRaises(HTTPException):
            self.check("first", attempts=1)

    def test_long_windows_are_not_evicted_by_short_window_cleanup(self):
        self.check("long", attempts=1, window=3600)
        self.check("short", attempts=1)
        self.clock.return_value = 200.0
        self.check("new")
        with self.assertRaises(HTTPException):
            self.check("long", attempts=1, window=3600)
        self.assertEqual(len(limits._BUCKETS), 2)

    def test_keys_do_not_retain_raw_identifiers(self):
        identifier = "synthetic@example.com"
        self.check(identifier)
        scope, digest = next(iter(limits._BUCKETS))
        self.assertEqual(scope, "test")
        self.assertIsInstance(digest, bytes)
        self.assertEqual(len(digest), 32)
        self.assertNotIn(identifier, repr(limits._BUCKETS))

    def test_rejected_attempts_do_not_extend_lockout(self):
        self.check(attempts=1)
        for second in (130, 140, 159):
            self.clock.return_value = second
            with self.assertRaises(HTTPException):
                self.check(attempts=1)
        self.clock.return_value = 160
        self.check(attempts=1)

    def test_invalid_or_conflicting_policies_cannot_grow_state(self):
        for options in ({"attempts": 1001}, {"attempts": True}, {"attempts": 0},
                        {"window": 86401}, {"window": 0}, {"window": 1.5}):
            with self.subTest(options=options), self.assertRaises(ValueError):
                self.check(**options)
        self.assertEqual(limits._BUCKETS, {})
        self.check()
        with self.assertRaises(ValueError):
            self.check(attempts=3)

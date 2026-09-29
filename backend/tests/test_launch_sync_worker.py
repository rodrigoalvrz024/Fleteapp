import unittest
from unittest.mock import patch
from tests.test_launch_signup import settings
from app.services import launch_sync_worker as worker


class SyncWorkerTests(unittest.IsolatedAsyncioTestCase):
    def test_retries_both_queues_without_logging_contacts(self):
        with patch.object(worker, "retry_pending", return_value=(1, 1)) as drivers, patch.object(worker, "retry_launch_pending", return_value=(0, 1)) as launch:
            with self.assertLogs(worker.logger, level="WARNING") as logs:
                worker.sync_batch()
            drivers.assert_called_once_with(limit=5)
            launch.assert_called_once_with(limit=5)
            self.assertIn("retry scheduled", logs.output[0])

    def test_provider_exception_is_not_logged(self):
        with patch.object(worker, "retry_pending", side_effect=RuntimeError("private-contact@example.com")):
            with self.assertLogs(worker.logger, level="WARNING") as logs:
                worker.sync_batch()
            self.assertNotIn("private-contact", str(logs.output))

    async def test_disabled_worker_does_not_start(self):
        with patch.object(settings, "LAUNCH_SHEETS_SYNC_ENABLED", False), patch.object(worker.asyncio, "create_task") as create:
            async with worker.launch_sync_lifespan(None):
                pass
            create.assert_not_called()

    async def test_missing_credentials_fail_before_start(self):
        with patch.object(settings, "LAUNCH_SHEETS_SYNC_ENABLED", True), patch.object(settings, "PREREGISTRATION_SHEETS_CREDENTIALS_JSON", ""):
            with self.assertRaises(RuntimeError):
                async with worker.launch_sync_lifespan(None):
                    pass

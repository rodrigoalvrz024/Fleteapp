"""Retry durable launch queues without sending notifications or logging contacts."""
import asyncio
import logging
from contextlib import asynccontextmanager
from app.core.config import settings
from app.services.preregistration_sheets import retry_pending, retry_launch_pending

logger = logging.getLogger(__name__)


def sync_batch():
    try:
        results = [retry_pending(limit=5), retry_launch_pending(limit=5)]
        if any(done < total for done, total in results):
            logger.warning("Launch Sheets sync pending; retry scheduled")
    except Exception:
        logger.warning("Launch Sheets sync unavailable; retry scheduled")


async def worker(stop):
    while not stop.is_set():
        await asyncio.to_thread(sync_batch)
        try:
            await asyncio.wait_for(stop.wait(), timeout=60)
        except asyncio.TimeoutError:
            pass


@asynccontextmanager
async def launch_sync_lifespan(app):
    stop = asyncio.Event()
    task = None
    if settings.LAUNCH_SHEETS_SYNC_ENABLED:
        if not settings.PREREGISTRATION_SHEETS_ID or not settings.PREREGISTRATION_SHEETS_CREDENTIALS_JSON:
            raise RuntimeError("Sheets sync enabled without dedicated credentials")
        task = asyncio.create_task(worker(stop))
    try:
        yield
    finally:
        stop.set()
        if task:
            # An interrupted batch remains in the durable queue for next startup.
            await task

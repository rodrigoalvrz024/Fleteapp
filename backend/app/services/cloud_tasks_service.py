import base64
import json
from typing import Any

import google.auth
import requests
from google.auth.transport.requests import Request as GoogleAuthRequest

from app.core.config import settings


def _project_id() -> str:
    return settings.GOOGLE_CLOUD_PROJECT.strip()


def _target_base_url() -> str:
    return (settings.CLOUD_TASKS_TARGET_BASE_URL or settings.PUBLIC_API_URL).rstrip("/")


def _queue_path() -> str:
    return (
        f"projects/{_project_id()}/locations/"
        f"{settings.CLOUD_TASKS_LOCATION}/queues/{settings.CLOUD_TASKS_QUEUE}"
    )


def _access_token() -> str:
    credentials, _ = google.auth.default(
        scopes=["https://www.googleapis.com/auth/cloud-platform"]
    )
    credentials.refresh(GoogleAuthRequest())
    return credentials.token


def enqueue_freight_driver_notification_task(
    *,
    freight_id: int,
    title: str,
    body: str,
    data: dict[str, Any],
) -> str | None:
    if not settings.NOTIFICATION_TASKS_ENABLED:
        return None

    project_id = _project_id()
    base_url = _target_base_url()
    service_account = settings.CLOUD_TASKS_SERVICE_ACCOUNT.strip()
    if not project_id or not base_url or not service_account:
        print("[cloud-tasks] Missing notification task configuration")
        return None

    parent = _queue_path()
    target_url = f"{base_url}/internal/tasks/freights/{freight_id}/notify-drivers"
    audience = (settings.CLOUD_TASKS_AUDIENCE or base_url).rstrip("/")
    payload = {
        "freight_id": freight_id,
        "title": title,
        "body": body,
        "data": data,
    }
    encoded_body = base64.b64encode(
        json.dumps(payload, separators=(",", ":")).encode("utf-8")
    ).decode("ascii")
    task_name = f"{parent}/tasks/freight-{freight_id}-notify-drivers"
    task = {
        "task": {
            "name": task_name,
            "httpRequest": {
                "httpMethod": "POST",
                "url": target_url,
                "headers": {"Content-Type": "application/json"},
                "body": encoded_body,
                "oidcToken": {
                    "serviceAccountEmail": service_account,
                    "audience": audience,
                },
            },
        }
    }
    api_url = f"https://cloudtasks.googleapis.com/v2/{parent}/tasks"
    response = requests.post(
        api_url,
        headers={
            "Authorization": f"Bearer {_access_token()}",
            "Content-Type": "application/json",
        },
        json=task,
        timeout=5,
    )
    if response.status_code == 409:
        print(f"[cloud-tasks] Notification task already exists for freight {freight_id}")
        return task_name
    if response.status_code >= 400:
        print(f"[cloud-tasks] Could not enqueue task: {response.text[:500]}")
        return None
    created = response.json()
    created_name = created.get("name", task_name)
    print(f"[cloud-tasks] Created notification task: {created_name}")
    return created_name

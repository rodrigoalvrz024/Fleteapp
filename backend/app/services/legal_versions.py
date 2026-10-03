from app.core.config import settings


def consent_versions(role: str) -> tuple[str, str]:
    # Admin links to the published website, not the older mobile documents.
    # Keep these defaults aligned with web-public and the admin login build.
    if role == "admin":
        return settings.ADMIN_TERMS_VERSION, settings.ADMIN_PRIVACY_VERSION
    return settings.TERMS_VERSION, settings.PRIVACY_VERSION

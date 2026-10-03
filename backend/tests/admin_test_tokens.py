"""Post-authentication fixtures; actual login/OTP behavior is tested separately."""
from datetime import datetime, timedelta, timezone

from app.core.security import admin_credential_stamp, create_access_token
from app.models.admin_second_factor import AdminSecondFactor


def authenticated_admin_token(db, user):
    now = datetime.now(timezone.utc)
    if db.get(AdminSecondFactor, user.id) is None:
        db.add(AdminSecondFactor(user_id=user.id, encrypted_secret="synthetic-fixture-not-an-enrollment",
            last_counter=-1, failures=0, activated_at=now))
        db.commit()
    return create_access_token({"sub": str(user.id), "role": "admin",
        "session_version": user.session_version, "admin_mfa": True,
        "admin_mfa_at": int(now.timestamp()), "admin_credentials": admin_credential_stamp(user)},
        expires_delta=timedelta(minutes=5))

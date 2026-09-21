from fastapi import HTTPException
from sqlalchemy import text
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Query


def lock_first(query: Query):
    """Bound contention for a transaction that changes freight/payment state."""
    db = query.session
    db.execute(text("SET LOCAL lock_timeout = '5s'"))
    try:
        return query.with_for_update().first()
    except OperationalError as exc:
        if getattr(exc.orig, "pgcode", None) != "55P03":
            raise
        db.rollback()
        raise HTTPException(
            status_code=409, detail="Hay otra operacion en curso. Intenta nuevamente en unos segundos"
        ) from None

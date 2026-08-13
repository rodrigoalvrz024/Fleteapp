from uuid import uuid4

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from app.core.config import settings
from app.database import engine, Base, SessionLocal
from app.db_migrations import run_startup_migrations
from app.models.audit_event import AuditEvent
from app.routers import (
    admin,
    analytics,
    auth,
    drivers,
    freights,
    internal_tasks,
    payments,
    payouts,
    places,
    pricing,
    ratings,
    users,
)

if settings.RUN_STARTUP_MIGRATIONS:
    Base.metadata.create_all(bind=engine)
    run_startup_migrations(engine)
else:
    print("[startup] Skipping automatic DB migrations.")

app = FastAPI(
    title="Muvv API",
    description="API para app de fletes en Chile",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=False,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "Accept", "X-Request-ID"],
)


def _record_backend_error(
    request,
    error: Exception | None,
    status_code: int,
    request_id: str,
) -> None:
    db = SessionLocal()
    try:
        db.add(
            AuditEvent(
                entity_type="system",
                entity_id=f"{request.method} {request.url.path}",
                event_type="system.backend_error",
                reason=None,
                ip_address=(request.client.host if request.client else None),
                user_agent=request.headers.get("user-agent"),
                request_id=request_id,
                after_data={"status_code": status_code},
                event_metadata={
                    "method": request.method,
                    "path": request.url.path,
                    "error_type": type(error).__name__ if error else None,
                },
            )
        )
        db.commit()
    except Exception:
        db.rollback()
        print("[monitoring] Could not record backend error")
    finally:
        db.close()


@app.middleware("http")
async def record_backend_errors(request, call_next):
    request_id = uuid4().hex
    request.state.request_id = request_id
    content_length = request.headers.get("content-length")
    if content_length:
        try:
            if int(content_length) > settings.MAX_REQUEST_BODY_MB * 1024 * 1024:
                return JSONResponse(
                    status_code=413,
                    content={"detail": "La solicitud supera el tamano permitido."},
                    headers={"X-Request-ID": request_id, "Cache-Control": "no-store"},
                )
        except ValueError:
            return JSONResponse(
                status_code=400,
                content={"detail": "Content-Length invalido."},
                headers={"X-Request-ID": request_id, "Cache-Control": "no-store"},
            )
    try:
        response = await call_next(request)
    except Exception as exc:
        _record_backend_error(request, exc, 500, request_id)
        return JSONResponse(
            status_code=500,
            content={"detail": "Ocurrio un error interno. Intenta nuevamente."},
            headers={
                "X-Request-ID": request_id,
                "Cache-Control": "no-store",
                "X-Content-Type-Options": "nosniff",
                "X-Frame-Options": "DENY",
            },
        )
    if response.status_code >= 500:
        _record_backend_error(request, None, response.status_code, request_id)
    response.headers.setdefault("X-Request-ID", request_id)
    response.headers.setdefault("X-Content-Type-Options", "nosniff")
    response.headers.setdefault("X-Frame-Options", "DENY")
    response.headers.setdefault("Referrer-Policy", "strict-origin-when-cross-origin")
    response.headers.setdefault("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
    if request.url.path not in {"/", "/health"}:
        response.headers.setdefault("Cache-Control", "no-store")
    if "server" in response.headers:
        del response.headers["server"]
    if (
        request.url.scheme == "https"
        or request.headers.get("x-forwarded-proto") == "https"
    ):
        response.headers.setdefault(
            "Strict-Transport-Security",
            "max-age=31536000; includeSubDomains; preload",
        )
    return response


app.include_router(auth.router)
app.include_router(users.router)
app.include_router(drivers.router)
app.include_router(freights.router)
app.include_router(internal_tasks.router)
app.include_router(payments.router)
app.include_router(payouts.router)
app.include_router(places.router)
app.include_router(pricing.router)
app.include_router(ratings.router)
app.include_router(analytics.router)
app.include_router(admin.router)

@app.get("/")
def root():
    return {"status": "ok", "message": "Muvv API funcionando"}

@app.get("/health")
def health():
    return {"status": "healthy"}

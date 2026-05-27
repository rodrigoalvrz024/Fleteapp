from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.database import engine, Base, SessionLocal
from app.db_migrations import run_startup_migrations
from app.models.audit_event import AuditEvent
from app.routers import auth, users, drivers, freights, payments, ratings, admin

Base.metadata.create_all(bind=engine)
run_startup_migrations(engine)

app = FastAPI(
    title="FleteApp API",
    description="API para app de fletes en Chile",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def _record_backend_error(request, error: Exception | None, status_code: int) -> None:
    db = SessionLocal()
    try:
        db.add(
            AuditEvent(
                entity_type="system",
                entity_id=f"{request.method} {request.url.path}",
                event_type="system.backend_error",
                reason=(str(error)[:500] if error else None),
                ip_address=(request.client.host if request.client else None),
                user_agent=request.headers.get("user-agent"),
                request_id=request.headers.get("x-request-id"),
                after_data={"status_code": status_code},
                event_metadata={
                    "method": request.method,
                    "path": request.url.path,
                    "query": str(request.url.query)[:500],
                    "error_type": type(error).__name__ if error else None,
                },
            )
        )
        db.commit()
    except Exception as log_error:
        db.rollback()
        print(f"[monitoring] Could not record backend error: {log_error}")
    finally:
        db.close()


@app.middleware("http")
async def record_backend_errors(request, call_next):
    try:
        response = await call_next(request)
    except Exception as exc:
        _record_backend_error(request, exc, 500)
        raise
    if response.status_code >= 500:
        _record_backend_error(request, None, response.status_code)
    return response


app.include_router(auth.router)
app.include_router(users.router)
app.include_router(drivers.router)
app.include_router(freights.router)
app.include_router(payments.router)
app.include_router(ratings.router)
app.include_router(admin.router)

@app.get("/")
def root():
    return {"status": "ok", "message": "FleteApp API funcionando"}

@app.get("/health")
def health():
    return {"status": "healthy"}

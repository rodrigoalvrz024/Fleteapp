from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.database import engine, Base
from app.routers import auth, users, drivers, freights, payments, ratings, admin

Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="FleteApp API",
    description="API para app de fletes en Chile",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:8000",
        "http://10.0.2.2:8000",
        "*",  # Cambiar por tu dominio real después
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(users.router)
app.include_router(drivers.router)
app.include_router(freights.router)
app.include_router(payments.router)
app.include_router(ratings.router)
app.include_router(admin.router)
from .routers import admin
app.include_router(admin.router)

@app.get("/")
def root():
    return {"status": "ok", "message": "FleteApp API funcionando"}

@app.get("/health")
def health():
    return {"status": "healthy"}
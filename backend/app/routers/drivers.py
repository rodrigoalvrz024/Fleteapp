from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.user import User, UserRole
from app.models.driver import Driver
from app.models.vehicle import Vehicle
from app.schemas.driver import DriverCreate, DriverUpdate, VehicleCreate, DriverResponse, VehicleResponse
from app.core.security import get_current_user, require_role

router = APIRouter(prefix="/drivers", tags=["Conductores"])

@router.post("/register", response_model=DriverResponse, status_code=201)
def register_driver(data: DriverCreate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    if current_user.role != UserRole.driver:
        raise HTTPException(status_code=403, detail="Solo conductores pueden registrarse aquí")
    if db.query(Driver).filter(Driver.user_id == current_user.id).first():
        raise HTTPException(status_code=400, detail="Ya tienes un perfil de conductor")
    driver = Driver(user_id=current_user.id, **data.model_dump())
    db.add(driver)
    db.commit()
    db.refresh(driver)
    return driver

@router.get("/me", response_model=DriverResponse)
def get_driver_profile(db: Session = Depends(get_db), current_user: User = Depends(require_role("driver"))):
    driver = db.query(Driver).filter(Driver.user_id == current_user.id).first()
    if not driver:
        raise HTTPException(status_code=404, detail="Perfil de conductor no encontrado")
    return driver

@router.put("/me", response_model=DriverResponse)
def update_driver(data: DriverUpdate, db: Session = Depends(get_db), current_user: User = Depends(require_role("driver"))):
    driver = db.query(Driver).filter(Driver.user_id == current_user.id).first()
    if not driver:
        raise HTTPException(status_code=404, detail="Perfil no encontrado")
    for field, value in data.model_dump(exclude_none=True).items():
        setattr(driver, field, value)
    db.commit()
    db.refresh(driver)
    return driver

@router.post("/vehicle", response_model=VehicleResponse, status_code=201)
def add_vehicle(data: VehicleCreate, db: Session = Depends(get_db), current_user: User = Depends(require_role("driver"))):
    driver = db.query(Driver).filter(Driver.user_id == current_user.id).first()
    if not driver:
        raise HTTPException(status_code=404, detail="Primero regístrate como conductor")
    if driver.vehicle:
        raise HTTPException(status_code=400, detail="Ya tienes un vehículo registrado")
    vehicle = Vehicle(driver_id=driver.id, **data.model_dump())
    db.add(vehicle)
    db.commit()
    db.refresh(vehicle)
    return vehicle
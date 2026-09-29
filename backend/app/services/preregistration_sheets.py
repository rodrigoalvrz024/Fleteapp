"""Durable pending records; retry with python -m app.services.preregistration_sheets.

Use a dedicated, unsorted tab: a database ID always maps to the same row.
RAW writes prevent user text from being interpreted as spreadsheet formulas.
"""
import json
import re
from datetime import datetime, timezone
from urllib.parse import quote

from google.auth.transport.requests import AuthorizedSession
from google.oauth2.service_account import Credentials

from app.core.config import settings
from app.database import SessionLocal
from app.models.driver_preregistration import DriverPreregistration
from app.models.launch_signup import LaunchSignup

HEADERS = ["ID", "Fecha UTC", "Nombre", "Correo", "Celular", "Comuna", "Vehículo",
           "Disponibilidad", "Contacto autorizado", "Promociones autorizadas", "Versión consentimiento"]


def write_sheet_entry(entry):
    sheet_id = settings.PREREGISTRATION_SHEETS_ID
    if not re.fullmatch(r"[A-Za-z0-9_-]+", sheet_id):
        raise ValueError("Invalid spreadsheet ID")
    info = json.loads(settings.PREREGISTRATION_SHEETS_CREDENTIALS_JSON)
    credentials = Credentials.from_service_account_info(info, scopes=["https://www.googleapis.com/auth/spreadsheets"])
    base = f"https://sheets.googleapis.com/v4/spreadsheets/{sheet_id}/values/"
    values = [str(entry.id), entry.created_at.isoformat(), entry.full_name, entry.email,
              entry.phone, entry.commune, entry.vehicle_type, entry.availability or "",
              "Sí" if entry.contact_consent else "No", "Sí" if entry.marketing_consent else "No", entry.consent_version] if isinstance(entry, DriverPreregistration) else []
    tab, last_column, headers = "Preinscripciones", "K", HEADERS
    if isinstance(entry, LaunchSignup):
        tab, last_column = "Lanzamiento", "I"
        headers = ["ID", "Fecha UTC", "Nombre", "Correo", "Celular", "Plataforma",
                   "Aviso por correo", "Aviso por WhatsApp", "Versión consentimiento"]
        values = [str(entry.id), entry.created_at.isoformat(), entry.full_name, entry.email,
                  entry.phone, entry.platform, "Sí" if entry.email_consent else "No",
                  "Sí" if entry.whatsapp_consent else "No", entry.consent_version]
    with AuthorizedSession(credentials) as session:
        for cell_range, row in ((f"{tab}!A1:{last_column}1", headers),
                                (f"{tab}!A{entry.id + 1}:{last_column}{entry.id + 1}", values)):
            result = session.put(base + quote(cell_range, safe=""), params={"valueInputOption": "RAW"},
                                 json={"values": [row]}, timeout=15)
            result.raise_for_status()


def _sync_entry(model, entry_id):
    if not settings.PREREGISTRATION_SHEETS_ID or not settings.PREREGISTRATION_SHEETS_CREDENTIALS_JSON:
        return False
    # Do not log exceptions: provider responses may include personal data or secrets.
    try:
        with SessionLocal() as db:
            entry = db.get(model, entry_id)
            if entry is None or entry.sheets_synced_at is not None:
                return True
            write_sheet_entry(entry)
            entry.sheets_synced_at = datetime.now(timezone.utc)
            db.commit()
        return True
    except Exception:
        return False


def sync_preregistration(entry_id):
    return _sync_entry(DriverPreregistration, entry_id)


def sync_launch_signup(entry_id):
    return _sync_entry(LaunchSignup, entry_id)


def retry_pending(limit=100):
    with SessionLocal() as db:
        ids = [row[0] for row in db.query(DriverPreregistration.id)
               .filter(DriverPreregistration.sheets_synced_at.is_(None))
               .order_by(DriverPreregistration.id).limit(limit).all()]
    return sum(sync_preregistration(entry_id) for entry_id in ids), len(ids)


def retry_launch_pending(limit=100):
    with SessionLocal() as db:
        ids = [row[0] for row in db.query(LaunchSignup.id)
               .filter(LaunchSignup.sheets_synced_at.is_(None))
               .order_by(LaunchSignup.id).limit(limit).all()]
    return sum(sync_launch_signup(entry_id) for entry_id in ids), len(ids)


if __name__ == "__main__":
    results = [retry_pending(), retry_launch_pending()]
    completed = sum(result[0] for result in results)
    attempted = sum(result[1] for result in results)
    print(f"Sincronizadas: {completed}; revisadas: {attempted}")
    raise SystemExit(0 if completed == attempted else 1)

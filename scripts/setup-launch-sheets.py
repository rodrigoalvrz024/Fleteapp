"""Prepare dedicated launch tabs in the existing authorized private spreadsheet."""
import argparse
import json
from pathlib import Path
from google.auth.transport.requests import AuthorizedSession
from google.oauth2.service_account import Credentials

parser = argparse.ArgumentParser()
parser.add_argument("--credentials", required=True)
args = parser.parse_args()
info = json.loads(Path(args.credentials).read_text())
if info.get("client_email") != "muvv-launch-sheets@muvv-dev.iam.gserviceaccount.com":
    raise SystemExit("Unexpected service account")
credentials = Credentials.from_service_account_info(info, scopes=["https://www.googleapis.com/auth/spreadsheets"])
base = "https://sheets.googleapis.com/v4/spreadsheets/1JPkf6ml1O4UHrepH-WKpkiuz0UkQ3X7D91aeUcN9SQI"
headers = {
    "Preinscripciones": ["ID", "Fecha UTC", "Nombre", "Correo", "Celular", "Comuna", "Vehículo", "Disponibilidad", "Contacto autorizado", "Promociones autorizadas", "Versión consentimiento"],
    "Lanzamiento": ["ID", "Fecha UTC", "Nombre", "Correo", "Celular", "Plataforma", "Aviso por correo", "Aviso por WhatsApp", "Versión consentimiento"],
}
try:
    with AuthorizedSession(credentials) as session:
        response = session.get(base, params={"fields": "sheets.properties"}, timeout=20)
        response.raise_for_status()
        existing = {s["properties"]["title"]: s["properties"] for s in response.json()["sheets"]}
        changes = []
        for title, columns in headers.items():
            if title not in existing:
                changes.append({"addSheet": {"properties": {"title": title, "gridProperties": {"rowCount": 10000, "columnCount": 15, "frozenRowCount": 1}}}})
            else:
                check = session.get(base + "/values/" + title + "!A1:K1", timeout=20)
                check.raise_for_status()
                values = check.json().get("values", [])
                if values and values[0][:len(columns)] != columns:
                    raise ValueError("Existing tab has unexpected headers; preserve it")
        if changes:
            response = session.post(base + ":batchUpdate", json={"requests": changes}, timeout=20)
            response.raise_for_status()
        for title, columns in headers.items():
            response = session.put(base + "/values/" + title + "!A1", params={"valueInputOption": "RAW"}, json={"values": [columns]}, timeout=20)
            response.raise_for_status()
        response = session.get(base, params={"fields": "sheets.properties"}, timeout=20)
        response.raise_for_status()
        updates = []
        for sheet in response.json()["sheets"]:
            properties = sheet["properties"]
            title = properties["title"]
            if title not in headers:
                continue
            sheet_id = properties["sheetId"]
            updates.append({"repeatCell": {"range": {"sheetId": sheet_id, "startRowIndex": 0, "endRowIndex": 1, "startColumnIndex": 0, "endColumnIndex": len(headers[title])}, "cell": {"userEnteredFormat": {"backgroundColor": {"red": .04, "green": .09, "blue": .22}, "textFormat": {"bold": True, "foregroundColor": {"red": 1, "green": 1, "blue": 1}}, "wrapStrategy": "WRAP"}}, "fields": "userEnteredFormat"}})
            updates.append({"updateDimensionProperties": {"range": {"sheetId": sheet_id, "dimension": "COLUMNS", "startIndex": 0, "endIndex": len(headers[title])}, "properties": {"pixelSize": 180}, "fields": "pixelSize"}})
        response = session.post(base + ":batchUpdate", json={"requests": updates}, timeout=20)
        response.raise_for_status()
        print("Verified tabs: Preinscripciones and Lanzamiento. RAW headers and private access preserved.")
except Exception as exc:
    print("Sheets setup did not complete:", type(exc).__name__)
    raise SystemExit(1) from None

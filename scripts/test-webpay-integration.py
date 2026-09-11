"""Finite Webpay integration checkout, with no application database or real keys."""

import argparse
from datetime import datetime, timezone
from html import escape
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile
import time
from urllib.parse import parse_qs, urlsplit


ROOT = Path(__file__).resolve().parents[1]
SANDBOX = "https://webpay3gint.transbank.cl"
AMOUNT = 1000


def isolated_environment():
    environment = {
        key: value for key, value in os.environ.items()
        if key.upper() in {"SYSTEMROOT", "WINDIR", "TEMP", "TMP", "PATH"}
    }
    environment.update(
        APP_ENV="test",
        DATABASE_URL="postgresql://invalid:invalid@127.0.0.1:1/no_database",
        SECRET_KEY="synthetic-webpay-check-not-a-production-secret",
        TRANSBANK_ENVIRONMENT="integration",
        TRANSBANK_COMMERCE_CODE="",
        TRANSBANK_API_KEY="",
        PYTHONDONTWRITEBYTECODE="1",
        PYTHONIOENCODING="utf-8",
    )
    return environment


def classify_result(result, order):
    if result.buy_order != order or result.amount != AMOUNT:
        return "mismatch"
    if result.status == "AUTHORIZED" and result.response_code == 0:
        return "approved"
    if result.status != "AUTHORIZED" and result.response_code != 0:
        return "declined"
    return "inconsistent"


def callback_fields(data):
    fields = parse_qs(data, keep_blank_values=True, max_num_fields=8)
    if any(len(values) != 1 for values in fields.values()):
        raise ValueError("Duplicate callback field")
    return {key: values[0] for key, values in fields.items()}


def run_checkout(args):
    sys.path.insert(0, str(ROOT / "backend"))
    from app.services import transbank_service as webpay

    host, headers = webpay._configuration()
    if (host != SANDBOX
            or headers["Tbk-Api-Key-Id"] != webpay._INTEGRATION_COMMERCE_CODE
            or headers["Tbk-Api-Key-Secret"] != webpay._INTEGRATION_API_KEY):
        raise RuntimeError("Only public integration credentials are allowed")

    order = "muvv-test-" + secrets.token_hex(8)
    route = "/" + secrets.token_urlsafe(24)
    payment = None
    outcome = None
    commit_attempts = 0
    report = {
        "started_at": datetime.now(timezone.utc).isoformat(),
        "environment": "integration",
        "host": urlsplit(host).hostname,
        "amount_clp": AMOUNT,
        "expected": args.expect,
        "database_used": False,
        "merchant_credentials_used": False,
        "created": False,
    }

    class Handler(BaseHTTPRequestHandler):
        def setup(self):
            super().setup()
            self.connection.settimeout(5)

        def log_message(self, format, *values):
            # Provider callbacks can contain a token in the query string.
            pass

        def reply(self, status, body):
            content = ("<!doctype html><html lang='es'><meta charset='utf-8'>"
                       "<title>Muvv - Webpay integracion</title>" + body + "</html>").encode()
            self.send_response(status)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(content)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("Referrer-Policy", "no-referrer")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Content-Security-Policy",
                             f"default-src 'none'; form-action {SANDBOX}; "
                             "base-uri 'none'; frame-ancestors 'none'")
            self.end_headers()
            self.wfile.write(content)

        def handle_callback(self, data):
            nonlocal outcome, commit_attempts
            try:
                fields = callback_fields(data)
            except ValueError:
                self.reply(400, "Callback invalido")
                return
            token = fields.get("token_ws", "")
            cancelled = fields.get("TBK_TOKEN", "")
            if token and cancelled:
                self.reply(400, "Callback ambiguo")
                return
            if cancelled and secrets.compare_digest(cancelled, payment.token):
                outcome = "cancelled"
            elif token and secrets.compare_digest(token, payment.token):
                if commit_attempts == 0:
                    commit_attempts += 1
                    try:
                        result = webpay.commit_webpay_transaction(token)
                        outcome = classify_result(result, order)
                        report.update(
                            provider_status=result.status,
                            response_code=result.response_code,
                            amount_matches=result.amount == AMOUNT,
                            order_matches=result.buy_order == order,
                        )
                    except Exception:
                        # Do not log provider responses, request URLs or headers.
                        outcome = "commit_unknown"
            else:
                self.reply(400, "Token no corresponde a esta prueba")
                return
            self.reply(200, "<h1>Prueba de integracion</h1><p>Resultado: "
                       + escape(outcome or "pending") + "</p><p>Sin dinero real.</p>")

        def do_GET(self):
            if self.headers.get("Host") != address:
                self.reply(400, "Host invalido")
                return
            parsed = urlsplit(self.path)
            if parsed.path == route and not parsed.query:
                self.reply(200, "<h1>Webpay: solo integracion</h1>"
                           "<p>CLP 1.000 ficticios. Usar solo tarjetas oficiales de prueba.</p>"
                           f"<form method='post' action='{escape(payment.url, quote=True)}'>"
                           f"<input type='hidden' name='token_ws' value='{escape(payment.token, quote=True)}'>"
                           "<button type='submit'>Abrir Webpay de prueba</button></form>")
            elif parsed.path == route + "/return" and len(parsed.query) <= 4096:
                self.handle_callback(parsed.query)
            else:
                self.reply(404, "No encontrado")

        def do_POST(self):
            if self.headers.get("Host") != address or self.path != route + "/return":
                self.reply(404, "No encontrado")
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if not 0 < length <= 4096 or self.headers.get("Transfer-Encoding"):
                    raise ValueError("Invalid length")
                if self.headers.get_content_type() != "application/x-www-form-urlencoded":
                    raise ValueError("Invalid form")
                data = self.rfile.read(length).decode("ascii")
            except (ValueError, UnicodeError):
                self.reply(400, "Formulario invalido")
                return
            self.handle_callback(data)

    with HTTPServer(("127.0.0.1", 0), Handler) as server:
        server.timeout = 1
        address = f"127.0.0.1:{server.server_port}"
        try:
            payment = webpay.create_webpay_transaction(
                buy_order=order,
                session_id="synthetic-check-" + secrets.token_hex(12),
                amount=AMOUNT,
                return_url=f"http://{address}{route}/return",
            )
            report["created"] = True
            print(f"CHECKOUT http://{address}{route}", flush=True)
            deadline = time.monotonic() + args.timeout
            while outcome is None and time.monotonic() < deadline:
                server.handle_request()
            outcome = outcome or "expired_locally"
        except KeyboardInterrupt:
            outcome = "interrupted"
        except Exception:
            outcome = "create_or_server_failed"

    report.update(outcome=outcome, commit_attempts=commit_attempts,
                  passed=outcome == args.expect,
                  finished_at=datetime.now(timezone.utc).isoformat())
    report_path = Path.cwd() / "result.json"
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report), flush=True)
    return 0 if report["passed"] else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expect", choices=("approved", "declined", "cancelled"),
                        default="approved")
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--isolated-child", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if not 10 <= args.timeout <= 900:
        parser.error("timeout must be between 10 and 900 seconds")
    if args.isolated_child:
        # Even direct child invocation cannot inherit merchant keys or a .env.
        environment = isolated_environment()
        os.environ.clear()
        os.environ.update(environment)
        if (Path.cwd() / ".env").exists():
            raise RuntimeError("Run through the isolated launcher, not inside an app directory")
        return run_checkout(args)
    scratch = ROOT / ".local-tools" / "webpay-integration"
    scratch.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="checkout-", dir=scratch) as directory:
        result = subprocess.run(
            [sys.executable, "-B", str(Path(__file__).resolve()), "--isolated-child",
             "--expect", args.expect, "--timeout", str(args.timeout)],
            cwd=directory, env=isolated_environment(), check=False,
        )
        report = Path(directory) / "result.json"
        if report.exists():
            destination = scratch / (datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
                                     + "-" + args.expect + "-" + secrets.token_hex(3) + ".json")
            destination.write_bytes(report.read_bytes())
            print(f"REPORT {destination}", flush=True)
        return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())

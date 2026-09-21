"""Check explicit PostgreSQL TLS settings; network access requires an opt-in flag."""

import argparse
import ipaddress
import json
import os
from pathlib import Path
import re

import psycopg2
from sqlalchemy.engine import make_url


class ConfigurationError(ValueError):
    pass


class PrivateArgumentParser(argparse.ArgumentParser):
    def error(self, message):
        raise ConfigurationError("invalid_arguments")


def connection_parameters(environment):
    value = environment.get("DATABASE_URL", "")
    if not value:
        raise ConfigurationError("database_url_missing")
    # Reject implicit libpq overrides rather than silently testing another configuration.
    if any(key.upper().startswith("PG") for key in environment):
        raise ConfigurationError("libpq_environment_requires_review")
    if value.startswith("postgres://"):
        value = "postgresql://" + value[len("postgres://"):]
    try:
        url = make_url(value)
        if url.drivername not in {"postgresql", "postgresql+psycopg2"}:
            raise ConfigurationError("unsupported_driver")
        if any(not isinstance(item, str) for item in url.query.values()):
            raise ConfigurationError("duplicate_connection_parameter")
        if set(url.query) - {"sslmode", "sslrootcert"}:
            raise ConfigurationError("connection_parameters_require_review")
        if url.query.get("sslmode") != "verify-full":
            raise ConfigurationError("server_identity_verification_required")
        host = url.host or ""
        try:
            ipaddress.ip_address(host)
        except ValueError:
            if not re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?", host):
                raise ConfigurationError("single_tcp_host_required") from None
        if not url.username or not url.password:
            raise ConfigurationError("explicit_credentials_required")
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_-]{0,62}", url.database or ""):
            raise ConfigurationError("database_name_requires_review")
        port = 5432 if url.port is None else url.port
        if not 1 <= port <= 65535:
            raise ConfigurationError("invalid_port")
        root_value = url.query.get("sslrootcert", "")
        root = Path(root_value)
        if root_value.startswith("\\") or root_value.replace("\\", "/").startswith("//") or not root.is_absolute():
            raise ConfigurationError("explicit_ca_file_required")
    except ConfigurationError:
        raise
    except Exception:
        # URL parsing and filesystem exceptions can include addresses or credentials.
        raise ConfigurationError("invalid_configuration") from None
    return dict(host=host, port=port, dbname=url.database, user=url.username,
                password=url.password, sslmode="verify-full", sslrootcert=str(root),
                connect_timeout=10, gssencmode="disable", ssl_min_protocol_version="TLSv1.2",
                application_name="muvv_tls_readonly_check")


def inspect_connection(parameters):
    conn = None
    try:
        conn = psycopg2.connect(**parameters)
        if not conn.info.ssl_in_use:
            raise RuntimeError("tls_not_active")
        if conn.info.ssl_attribute("protocol") not in {"TLSv1.2", "TLSv1.3"}:
            raise RuntimeError("unsupported_tls_protocol")
        actual = conn.get_dsn_parameters()
        if any(actual.get(key) != parameters[key] for key in ("host", "sslmode", "sslrootcert")):
            raise RuntimeError("connection_configuration_mismatch")
        conn.set_session(readonly=True, autocommit=False)
        with conn.cursor() as cursor:
            cursor.execute("SET LOCAL statement_timeout = '7s'")
            cursor.execute("SET LOCAL lock_timeout = '3s'")
            cursor.execute("SHOW transaction_read_only")
            if cursor.fetchone() != ("on",):
                raise RuntimeError("readonly_not_active")
        conn.rollback()
    finally:
        if conn is not None:
            conn.close()


def main(argv=None, environment=None):
    parser = PrivateArgumentParser(description=__doc__)
    parser.add_argument("--connect-read-only", action="store_true",
                        help="Explicitly connect using DATABASE_URL; no application tables are queried.")
    report = {"configuration_valid": False, "connection_verified": False,
              "application_configuration_changed": False, "deployment_approved": False}
    try:
        args = parser.parse_args(argv)
        parameters = connection_parameters(os.environ if environment is None else environment)
        report["configuration_valid"] = True
        if args.connect_read_only:
            if not Path(parameters["sslrootcert"]).is_file():
                raise ConfigurationError("ca_file_missing")
            inspect_connection(parameters)
            report["connection_verified"] = True
        report["result"] = "connection_verified" if args.connect_read_only else "configuration_only"
        code = 0
    except ConfigurationError as error:
        report["result"] = str(error)
        code = 1
    except Exception:
        report["result"] = "verification_failed_check_privately"
        code = 2
    print(json.dumps(report, sort_keys=True))
    return code


if __name__ == "__main__":
    raise SystemExit(main())

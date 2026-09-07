import os
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

import psycopg2


TABLES = [
    "audit_events",
    "data_privacy_requests",
    "driver_payouts",
    "driver_review_audits",
    "drivers",
    "freight_cargo_photos",
    "freight_chat_messages",
    "freight_driver_declines",
    "freight_price_quotes",
    "freight_pricing_snapshots",
    "freight_requests",
    "notifications",
    "password_reset_tokens",
    "payments",
    "ratings",
    "trip_feedback",
    "trip_status_history",
    "user_consents",
    "users",
    "vehicles",
]
API_ROLES = ("anon", "authenticated")


def _database_url() -> str:
    value = os.environ.get("DATABASE_URL", "").strip()
    if not value:
        raise RuntimeError("DATABASE_URL no esta configurado.")
    parts = urlsplit(value)
    query = dict(parse_qsl(parts.query, keep_blank_values=True))
    if query.get("sslmode") not in {"require", "verify-ca", "verify-full"}:
        query["sslmode"] = "require"
    return urlunsplit(
        (
            parts.scheme,
            parts.netloc,
            parts.path,
            urlencode(query),
            parts.fragment,
        )
    )


def inspect_access(conn) -> dict:
    with conn.cursor() as cursor:
        cursor.execute(
            """
            SELECT c.relname, c.relrowsecurity
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'public'
              AND c.relkind IN ('r', 'p')
              AND c.relname = ANY(%s)
            ORDER BY c.relname
            """,
            (TABLES,),
        )
        rows = cursor.fetchall()

        cursor.execute(
            """
            SELECT c.relname, r.rolname, p.privilege
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            CROSS JOIN pg_roles r
            CROSS JOIN (VALUES ('SELECT'), ('INSERT'), ('UPDATE'),
                ('DELETE'), ('TRUNCATE'), ('REFERENCES'), ('TRIGGER')) p(privilege)
            WHERE n.nspname = 'public'
              AND c.relkind IN ('r', 'p')
              AND c.relname = ANY(%s)
              AND r.rolname = ANY(%s)
              AND has_table_privilege(r.oid, c.oid, p.privilege)
            ORDER BY c.relname, r.rolname, p.privilege
            """,
            (TABLES, list(API_ROLES)),
        )
        grants = cursor.fetchall()

        # Column-only grants are not reported by has_table_privilege.
        cursor.execute(
            """
            SELECT c.relname, r.rolname, p.privilege
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            CROSS JOIN pg_roles r
            CROSS JOIN (VALUES ('SELECT'), ('INSERT'), ('UPDATE'),
                ('REFERENCES')) p(privilege)
            WHERE n.nspname = 'public'
              AND c.relkind IN ('r', 'p')
              AND c.relname = ANY(%s)
              AND r.rolname = ANY(%s)
              AND has_any_column_privilege(r.oid, c.oid, p.privilege)
              AND NOT has_table_privilege(r.oid, c.oid, p.privilege)
            ORDER BY c.relname, r.rolname, p.privilege
            """,
            (TABLES, list(API_ROLES)),
        )
        column_grants = cursor.fetchall()

        cursor.execute(
            """
            SELECT rolname, rolsuper OR rolbypassrls
            FROM pg_roles WHERE rolname = ANY(%s) ORDER BY rolname
            """,
            (list(API_ROLES),),
        )
        roles = cursor.fetchall()

    return {
        "checked": len(rows),
        "missing": sorted(set(TABLES) - {name for name, _ in rows}),
        "disabled": sorted(name for name, enabled in rows if not enabled),
        "grants": grants,
        "column_grants": column_grants,
        "missing_roles": sorted(set(API_ROLES) - {name for name, _ in roles}),
        "bypass_roles": sorted(name for name, bypass in roles if bypass),
    }


def main() -> int:
    conn = None
    try:
        conn = psycopg2.connect(
            _database_url(),
            connect_timeout=10,
            options="-c default_transaction_read_only=on -c statement_timeout=7000",
        )
        result = inspect_access(conn)
    except Exception as error:
        # Connection exceptions can contain credentials or internal addresses.
        print(
            f"RLS verification failed ({type(error).__name__}). "
            "Check connection/configuration privately."
        )
        return 2
    finally:
        if conn is not None:
            conn.close()

    print("RLS tables checked:", result["checked"])
    for label, key in (
        ("RLS disabled", "disabled"),
        ("Missing tables", "missing"),
        ("Missing API roles", "missing_roles"),
        ("API roles bypassing RLS", "bypass_roles"),
    ):
        print(f"{label}:", ", ".join(result[key]) or "none")
    for key in ("grants", "column_grants"):
        print(f"Effective anon/authenticated {key}:", len(result[key]))
        for table_name, grantee, privilege in result[key]:
            print(f"- {table_name}: {grantee} {privilege}")
    return int(any(value for key, value in result.items() if key != "checked"))


if __name__ == "__main__":
    raise SystemExit(main())

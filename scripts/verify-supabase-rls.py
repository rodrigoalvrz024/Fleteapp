import os
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

import psycopg2


TABLES = [
    "audit_events",
    "data_privacy_requests",
    "driver_payouts",
    "driver_review_audits",
    "drivers",
    "freight_requests",
    "notifications",
    "password_reset_tokens",
    "payments",
    "ratings",
    "trip_status_history",
    "user_consents",
    "users",
    "vehicles",
]


def _database_url() -> str:
    value = os.environ.get("DATABASE_URL", "").strip()
    if not value:
        raise RuntimeError("DATABASE_URL no esta configurado.")
    if "sslmode=" in value:
        return value

    parts = urlsplit(value)
    query = dict(parse_qsl(parts.query, keep_blank_values=True))
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


def main() -> int:
    conn = psycopg2.connect(_database_url())
    try:
        with conn.cursor() as cursor:
            cursor.execute(
                """
                SELECT c.relname, c.relrowsecurity
                FROM pg_class c
                JOIN pg_namespace n ON n.oid = c.relnamespace
                WHERE n.nspname = 'public'
                  AND c.relkind = 'r'
                  AND c.relname = ANY(%s)
                ORDER BY c.relname
                """,
                (TABLES,),
            )
            rows = cursor.fetchall()

            cursor.execute(
                """
                SELECT table_name, grantee, privilege_type
                FROM information_schema.table_privileges
                WHERE table_schema = 'public'
                  AND table_name = ANY(%s)
                  AND grantee IN ('anon', 'authenticated')
                ORDER BY table_name, grantee, privilege_type
                """,
                (TABLES,),
            )
            grants = cursor.fetchall()
    finally:
        conn.close()

    missing = sorted(set(TABLES) - {row[0] for row in rows})
    disabled = [name for name, enabled in rows if not enabled]

    print("RLS tables checked:", len(rows))
    print("RLS disabled:", ", ".join(disabled) if disabled else "none")
    print("Missing tables:", ", ".join(missing) if missing else "none")
    print("anon/authenticated table grants:", len(grants))
    if grants:
        for table_name, grantee, privilege in grants:
            print(f"- {table_name}: {grantee} {privilege}")
        return 1
    if missing or disabled:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

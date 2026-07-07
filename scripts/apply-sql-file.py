import os
from pathlib import Path
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

import psycopg2


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
    sql_file = Path(os.environ.get("SQL_FILE", "")).resolve()
    if not sql_file.is_file():
        raise RuntimeError(f"No se encontro SQL_FILE: {sql_file}")

    sql = sql_file.read_text(encoding="utf-8")
    conn = psycopg2.connect(_database_url())
    try:
        with conn:
            with conn.cursor() as cursor:
                cursor.execute(sql)
        print(f"SQL aplicado correctamente: {sql_file.name}")
    finally:
        conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

FROM python:3.11-slim-trixie

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Apply Debian security updates even when the Python base tag is not rebuilt yet.
RUN apt-get update \
    && apt-get upgrade -y --no-install-recommends \
    && apt-get purge -y --no-auto-remove mount \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip==26.2.1 setuptools==84.0.0 wheel==0.48.0 \
    && pip install --no-cache-dir -r requirements.txt

RUN addgroup --system app && adduser --system --ingroup app app

COPY --chown=root:root app ./app
COPY --chown=root:root alembic ./alembic
COPY --chown=root:root alembic.ini .
COPY --chown=root:root --chmod=0444 certs/supabase-root-2021.crt ./certs/supabase-root-2021.crt

# The API never changes OS identities or edits its installed code.
RUN chmod -R go-w /app /usr/local \
    && rm -- /usr/bin/infocmp /usr/bin/nsenter \
    && find / -xdev -type f -perm /6000 -exec chmod a-s {} +

# Keep manual pages readable; remove only group/world directory write access.
RUN python -I -B - <<'PY'
import os
from pathlib import Path
import stat

paths = [Path('/usr/share/man') / name for name in ('man1', 'man5', 'man7', 'man8')]
parents = [Path('/'), Path('/usr'), Path('/usr/share'), Path('/usr/share/man')]
entries = [(path, path.lstat()) for path in parents + paths]
if any(not stat.S_ISDIR(meta.st_mode) or meta.st_uid != 0 for _, meta in entries):
    raise SystemExit('Manual directory layout is not trusted')
for path, meta in entries[len(parents):]:
    os.chmod(path, stat.S_IMODE(meta.st_mode) & ~0o022, follow_symlinks=False)
PY

USER app

CMD ["python", "-m", "app.server"]

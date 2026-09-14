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

# The API never changes OS identities or edits its installed code.
RUN chmod -R go-w /app /usr/local \
    && rm -- /usr/bin/infocmp /usr/bin/nsenter \
    && find / -xdev -type f -perm /6000 -exec chmod a-s {} +

USER app

CMD ["python", "-m", "app.server"]

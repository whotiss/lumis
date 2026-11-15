# Lumis backend image for Google Cloud Run. Built by Cloud Build with cloudbuild.yaml (see deploy/README.md),
# which first fetches the 1.7 GB model file into models/ because that file is not in git.
FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    ENVIRONMENT=production
# ENVIRONMENT=production is fixed in the image on purpose: if a deploy forgets the database, the JWT secret or
# the photo bucket, the server refuses to start instead of quietly running with development defaults.

WORKDIR /srv

# Layers are ordered from rarely changed to often changed, so a code change does not redo the slow steps.
COPY requirements.txt .
RUN pip install -r requirements.txt

COPY models/ models/
COPY app/ app/
COPY scripts/ scripts/

# Stop the build here if the model file is missing or does not match the checksum in its config.
RUN python scripts/check_model.py

# Run as an ordinary user, not root. The server writes nothing to its own disk.
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin lumis
USER lumis

# Cloud Run tells the container which port to listen on through PORT. One worker process: the model takes
# about 2 GB of memory, and ONNX Runtime already uses every CPU core for one photo.
CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8080} --workers 1 --proxy-headers --forwarded-allow-ips='*' --no-server-header"]

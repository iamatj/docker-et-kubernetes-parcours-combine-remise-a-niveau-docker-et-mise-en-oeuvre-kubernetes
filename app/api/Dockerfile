# syntax=docker/dockerfile:1
# Étape 1 : on installe les dépendances dans un environnement virtuel.
FROM mirror.gcr.io/library/python:3.13-slim AS construction
RUN python -m venv /opt/venv
ENV PATH=/opt/venv/bin:$PATH
COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip pip install -r requirements.txt

# Étape 2 : l'image livrée ne contient que Python, l'environnement virtuel et le code.
FROM mirror.gcr.io/library/python:3.13-slim
ARG APP_VERSION=dev
ENV APP_VERSION=$APP_VERSION \
    PATH=/opt/venv/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin cordee
WORKDIR /app
COPY --from=construction /opt/venv /opt/venv
COPY app.py .
USER 10001
EXPOSE 8000
ENTRYPOINT ["gunicorn"]
CMD ["--bind", "0.0.0.0:8000", "--workers", "2", "--preload", "--access-logfile", "-", "app:app"]

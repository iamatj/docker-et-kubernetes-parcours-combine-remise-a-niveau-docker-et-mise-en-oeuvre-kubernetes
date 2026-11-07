# syntax=docker/dockerfile:1
# Squelette du Dockerfile de l'API (tp/02-dockerfile/README.md, étape 3).
# Copiez-le dans app/api/Dockerfile, écrivez les lignes demandées par chaque TODO,
# puis supprimez les deux lignes « a-completer » ci-dessous : tant qu'elles sont là, le build échoue.
FROM mirror.gcr.io/library/busybox:1.37 AS a-completer
RUN echo "TODO : complétez app/api/Dockerfile (tp/02-dockerfile/README.md, étape 3)" && exit 1

# ---- Étape 1 : construction des dépendances
# TODO 1 : partir de mirror.gcr.io/library/python:3.13-slim et nommer l'étape « construction »

# (fourni) un environnement virtuel, pour pouvoir le recopier d'un bloc à l'étape 2
# RUN python -m venv /opt/venv
# ENV PATH=/opt/venv/bin:$PATH

# TODO 2 : copier UNIQUEMENT requirements.txt, puis installer les dépendances avec pip,
#          en gardant le cache de pip entre deux builds : RUN --mount=type=cache,target=/root/.cache/pip …

# ---- Étape 2 : l'image livrée
# TODO 3 : repartir de la même image slim (sans nom d'étape)

# (fourni) la version est donnée au build : docker build --build-arg APP_VERSION=1.0 …
# ARG APP_VERSION=dev
# ENV APP_VERSION=$APP_VERSION \
#     PATH=/opt/venv/bin:$PATH \
#     PYTHONUNBUFFERED=1 \
#     PYTHONDONTWRITEBYTECODE=1

# TODO 4 : créer l'utilisateur cordee : useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin cordee

# TODO 5 : se placer dans /app, copier /opt/venv depuis l'étape « construction », puis copier app.py

# TODO 6 : passer à l'utilisateur 10001 et documenter le port 8000

# TODO 7 : ENTRYPOINT ["gunicorn"] et, en CMD (forme JSON), les arguments par défaut :
#          --bind 0.0.0.0:8000 --workers 2 --preload --access-logfile - app:app

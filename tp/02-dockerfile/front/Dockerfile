# syntax=docker/dockerfile:1
# Squelette du Dockerfile du site (tp/02-dockerfile/README.md, étape 8). Copiez-le dans app/front/Dockerfile,
# complétez les TODO, puis supprimez les deux lignes « a-completer ».
FROM mirror.gcr.io/library/busybox:1.37 AS a-completer
RUN echo "TODO : complétez app/front/Dockerfile (tp/02-dockerfile/README.md, étape 8)" && exit 1

# TODO 1 : partir de ghcr.io/nginx/nginx-unprivileged:1.28-alpine
# (fourni) ARG APP_VERSION=dev
# TODO 2 : copier default.conf dans /etc/nginx/conf.d/default.conf, et le dossier html/ dans /usr/share/nginx/html/
# (fourni) écrire la version dans version.txt : l'image tourne sous l'utilisateur 101, qui n'a pas le droit d'écrire là.
# USER root
# RUN echo "$APP_VERSION" > /usr/share/nginx/html/version.txt
# TODO 3 : revenir à l'utilisateur 101 et documenter le port 8080

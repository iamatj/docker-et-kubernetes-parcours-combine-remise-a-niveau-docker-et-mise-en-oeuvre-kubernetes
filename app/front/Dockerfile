# syntax=docker/dockerfile:1
FROM ghcr.io/nginx/nginx-unprivileged:1.28-alpine
ARG APP_VERSION=dev
COPY default.conf /etc/nginx/conf.d/default.conf
COPY html/ /usr/share/nginx/html/
USER root
RUN echo "$APP_VERSION" > /usr/share/nginx/html/version.txt
USER 101
EXPOSE 8080

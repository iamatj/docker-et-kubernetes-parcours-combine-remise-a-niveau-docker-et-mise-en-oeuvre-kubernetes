#!/usr/bin/env bash
# Prépare la machine client pour le jour 1 (Docker seulement), en une commande :
#   bash lab/preparer-jour-1.sh
#
# Ne touche à rien d'autre que cette machine : pas de SSH, pas de nœuds, pas de cluster.
# Le cluster du jour 2 est préparé à part (lab/preparer-lab.sh).
# Prérequis : Ubuntu 24.04 x64, un compte avec sudo, un accès Internet.
# Relançable sans risque : chaque étape vérifie ce qui est déjà fait. Bilan à la fin.
set -euo pipefail

CURL="curl -fsSL --connect-timeout 20 --retry 3"
etape() { echo; echo "=================== $*"; }

etape "1/4 Paquets de base"
sudo apt-get -o DPkg::Lock::Timeout=600 update -q
sudo DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 install -y -q ca-certificates curl gpg jq git bash-completion

etape "2/4 Docker Engine, Buildx et Compose V2 (dépôt officiel de Docker)"
if ! command -v docker >/dev/null; then
  sudo install -m 0755 -d /etc/apt/keyrings
  $CURL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get -o DPkg::Lock::Timeout=600 update -q
  sudo DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
sudo systemctl enable --now docker >/dev/null
sudo usermod -aG docker "$USER"

etape "3/4 Images des TP 00 à 04, téléchargées à l'avance"
IMAGES=(
  mirror.gcr.io/library/hello-world:latest
  mirror.gcr.io/library/python:3.13
  mirror.gcr.io/library/python:3.13-slim
  mirror.gcr.io/library/postgres:17-alpine
  mirror.gcr.io/library/registry:2
  mirror.gcr.io/library/busybox:1.37
  ghcr.io/nginx/nginx-unprivileged:1.28-alpine
  ghcr.io/aquasecurity/trivy:latest
)
for img in "${IMAGES[@]}"; do
  echo "  $img"
  sudo docker pull -q "$img" >/dev/null || echo "  échec : $img (il sera téléchargé pendant le TP)"
done
# Base de vulnérabilités de Trivy (TP 04) : téléchargée une fois ici, dans le volume que le TP réutilise.
sudo docker run --rm -v trivy-cache:/root/.cache ghcr.io/aquasecurity/trivy:latest image --download-db-only >/dev/null 2>&1 \
  || echo "  base Trivy non préchargée (elle sera téléchargée au TP 04)"

etape "4/4 Bilan"
ECHECS=0
verifie() { if eval "$2" >/dev/null 2>&1; then echo "  OK     $1"; else echo "  ÉCHEC  $1"; ECHECS=$((ECHECS + 1)); fi; }
verifie "Docker répond (client et daemon)"      "sudo docker info"
verifie "Docker Compose V2 (docker compose)"   "sudo docker compose version"
verifie "Buildx (BuildKit)"                    "sudo docker buildx version"
verifie "$USER est dans le groupe docker"      "getent group docker | grep -qw $USER"
for img in "${IMAGES[@]}"; do verifie "image $img" "sudo docker image inspect $img"; done
echo
if [ "$ECHECS" -eq 0 ]; then echo "Poste prêt pour le jour 1."; else echo "$ECHECS point(s) en échec : relancez le script, ou voyez guide-installation-lab.md."; fi
echo "Pour lancer docker sans sudo, déconnectez-vous puis reconnectez-vous (bureau compris) : les groupes ne sont lus qu'à l'ouverture de session."
echo "Si id ne montre toujours pas docker, redémarrez la machine (sudo reboot)."

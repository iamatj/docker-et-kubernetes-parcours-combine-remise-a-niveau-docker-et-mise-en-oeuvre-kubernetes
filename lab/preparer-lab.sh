#!/usr/bin/env bash
# Prépare tout le lab d'un participant, depuis la machine client, en une commande :
#   bash lab/preparer-lab.sh
#
# Prérequis : 3 VM Ubuntu 24.04 x64 : client .10, qui est aussi le control plane (alias control-plane),
# worker-1 .20 et worker-2 .30 ; un compte « formation » (ou UTILISATEUR_SSH) avec sudo sans mot de passe
# sur les 3 machines, et SSH ouvert du client vers les workers et vers lui-même.
# Pas de Docker sur le client : il sert au jour 1 seulement ; s'il est encore installé, le script le désinstalle (guide-installation-lab.md, section 1). Le script crée la clé SSH et la copie (mot de passe demandé une fois par nœud).
#
# Relançable sans risque : chaque étape vérifie ce qui est déjà fait. Bilan à la fin (lab/verifier-lab.sh).
set -euo pipefail

UTILISATEUR_SSH=${UTILISATEUR_SSH:-formation}
CP=10.10.0.10                 # le poste client lui-même
WORKERS=("10.10.0.11:worker-1" "10.10.0.12:worker-2")
VERSION_K8S=v1.36
VERSION_HELM=v4.3.1
VERSION_CALICO=v3.32.1
VERSION_METALLB=v0.16.2
VERSION_LOCAL_PATH=v0.0.37
VERSION_GATEWAY_API=v1.6.2
VERSION_METRICS=v0.9.0
COMPTE_IMAGES=${COMPTE_IMAGES:-iamatj}

ICI=$(cd "$(dirname "$0")" && pwd)
CURL="curl -fsSL --connect-timeout 20 --retry 3"
SSH="ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"
etape() { echo; echo "=================== $*"; }

# ---------------------------------------------------------------- 1. le client
etape "1/9 Client : paquets, kubectl, Helm"
sudo apt-get update -q
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q ca-certificates curl gpg jq openssl git bash-completion openssh-server
grep -q "10.10.0.10 control-plane" /etc/hosts || sudo tee -a /etc/hosts >/dev/null <<'EOF'
10.10.0.10 client
10.10.0.10 control-plane
10.10.0.11 worker-1
10.10.0.12 worker-2
10.10.0.200 huiteo.lab beta.huiteo.lab
EOF

# Le poste devient le control plane : Docker (jour 1) et Kubernetes sur la même machine se gênent
# (containerd, règles réseau). S'il est encore là, on le désinstalle avec ses données et ses règles réseau.
if command -v docker >/dev/null || dpkg -s docker-ce >/dev/null 2>&1; then
  echo "Docker (jour 1) trouvé sur ce poste : désinstallation avant de monter le control plane."
  sudo systemctl disable --now docker.socket docker containerd >/dev/null 2>&1 || true
  sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y -q docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras >/dev/null 2>&1 || true
  sudo apt-get autoremove -y -q >/dev/null
  sudo rm -rf /var/lib/docker /var/lib/containerd /etc/containerd /etc/apt/sources.list.d/docker.list
  sudo ip link delete docker0 >/dev/null 2>&1 || true
  { sudo iptables-save | grep -vi docker || true; } | sudo iptables-restore || true
  sudo apt-get update -q
  if command -v docker >/dev/null; then echo "Docker est toujours présent : désinstallez-le à la main (guide, section 1)." >&2; exit 1; fi
fi
sudo systemctl enable --now ssh >/dev/null 2>&1 || true
sudo install -m 0755 -d /etc/apt/keyrings

if ! command -v kubectl >/dev/null; then
  $CURL "https://pkgs.k8s.io/core:/stable:/$VERSION_K8S/deb/Release.key" | sudo gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$VERSION_K8S/deb/ /" \
    | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
  sudo apt-get update -q && sudo apt-get install -y -q kubectl
fi
if ! command -v helm >/dev/null; then
  $CURL "https://get.helm.sh/helm-$VERSION_HELM-linux-amd64.tar.gz" | tar xz -C /tmp
  sudo install -m 0755 /tmp/linux-amd64/helm /usr/local/bin/helm
fi
grep -q "kubectl completion" ~/.bashrc || cat >> ~/.bashrc <<'EOF'
source <(kubectl completion bash)
alias k=kubectl
complete -o default -F __start_kubectl k
EOF

# ---------------------------------------------------------------- 2. SSH vers les nœuds
etape "2/9 Clé SSH vers les nœuds"
[ -f ~/.ssh/id_ed25519 ] || ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519 -q
for ip in $CP 10.10.0.11 10.10.0.12; do
  $SSH -o BatchMode=yes "$UTILISATEUR_SSH@$ip" true 2>/dev/null || ssh-copy-id -o StrictHostKeyChecking=accept-new "$UTILISATEUR_SSH@$ip"
done

# ---------------------------------------------------------------- 3. préparation des nœuds
etape "3/9 Nœuds : containerd et kubeadm (en parallèle)"
PIDS=()
for cible in "$CP:control-plane" "${WORKERS[@]}"; do
  ip=${cible%%:*}; nom=${cible#*:}
  scp -q "$ICI/preparer-noeud.sh" "$UTILISATEUR_SSH@$ip:/tmp/preparer-noeud.sh"
  $SSH "$UTILISATEUR_SSH@$ip" "sudo VERSION_K8S=$VERSION_K8S bash /tmp/preparer-noeud.sh $nom" > "/tmp/preparer-$nom.log" 2>&1 &
  PIDS+=($!)
done
for pid in "${PIDS[@]}"; do wait "$pid" || { echo "Échec sur un nœud : voir /tmp/preparer-*.log" >&2; exit 1; }; done
tail -n 1 /tmp/preparer-*.log

# ---------------------------------------------------------------- 4. control plane
etape "4/9 kubeadm init sur control-plane"
$SSH "$UTILISATEUR_SSH@$CP" "sudo test -f /etc/kubernetes/admin.conf" || \
  $SSH "$UTILISATEUR_SSH@$CP" "sudo kubeadm init --apiserver-advertise-address=$CP --pod-network-cidr=10.244.0.0/16 --node-name control-plane" \
    > /tmp/kubeadm-init.log 2>&1 || { echo "kubeadm init a échoué : /tmp/kubeadm-init.log" >&2; exit 1; }
$SSH "$UTILISATEUR_SSH@$CP" 'mkdir -p ~/.kube && sudo cp /etc/kubernetes/admin.conf ~/.kube/config && sudo chown $(id -u):$(id -g) ~/.kube/config'
mkdir -p ~/.kube
# Le control plane est ce poste : avec le même compte, ~/.kube/config est déjà en place.
[ "$USER" = "$UTILISATEUR_SSH" ] || scp -q "$UTILISATEUR_SSH@$CP:.kube/config" ~/.kube/config
chmod 600 ~/.kube/config

etape "5/9 Réseau des pods : Calico $VERSION_CALICO"
if ! kubectl -n kube-system get daemonset calico-node >/dev/null 2>&1; then
  $CURL "https://raw.githubusercontent.com/projectcalico/calico/$VERSION_CALICO/manifests/calico.yaml" -o /tmp/calico.yaml
  sed -i 's|# - name: CALICO_IPV4POOL_CIDR|- name: CALICO_IPV4POOL_CIDR|; s|#   value: "192.168.0.0/16"|  value: "10.244.0.0/16"|' /tmp/calico.yaml
  kubectl apply -f /tmp/calico.yaml >/dev/null
fi

etape "6/9 Ajout des workers"
JOIN=$($SSH "$UTILISATEUR_SSH@$CP" "sudo kubeadm token create --print-join-command")
for cible in "${WORKERS[@]}"; do
  ip=${cible%%:*}; nom=${cible#*:}
  kubectl get node "$nom" >/dev/null 2>&1 || $SSH "$UTILISATEUR_SSH@$ip" "sudo $JOIN --node-name $nom" > "/tmp/join-$nom.log" 2>&1
done
kubectl wait --for=condition=Ready node --all --timeout=300s

# ---------------------------------------------------------------- 7. modules du cluster
etape "7/9 Stockage, LoadBalancer, métriques"
kubectl apply -f "https://raw.githubusercontent.com/rancher/local-path-provisioner/$VERSION_LOCAL_PATH/deploy/local-path-storage.yaml" >/dev/null
kubectl patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' >/dev/null
kubectl apply -f "$ICI/manifests/storageclass-retain.yaml" >/dev/null

kubectl apply -f "https://raw.githubusercontent.com/metallb/metallb/$VERSION_METALLB/config/manifests/metallb-native.yaml" >/dev/null
kubectl -n metallb-system wait --for=condition=Available deployment/controller --timeout=180s
kubectl -n metallb-system rollout status daemonset/speaker --timeout=180s >/dev/null
for _ in 1 2 3 4 5 6; do kubectl apply -f "$ICI/manifests/metallb-pool.yaml" >/dev/null 2>&1 && break; sleep 10; done

$CURL "https://github.com/kubernetes-sigs/metrics-server/releases/download/$VERSION_METRICS/components.yaml" -o /tmp/metrics.yaml
sed -i 's|- --metric-resolution=15s|- --metric-resolution=15s\n        - --kubelet-insecure-tls|' /tmp/metrics.yaml
kubectl apply -f /tmp/metrics.yaml >/dev/null

etape "8/9 Gateway API, Traefik (Ingress et Gateway), Headlamp"
kubectl apply --server-side -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/$VERSION_GATEWAY_API/standard-install.yaml" >/dev/null
helm repo add traefik https://traefik.github.io/charts --force-update >/dev/null
helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/ --force-update >/dev/null
helm repo update >/dev/null
helm upgrade --install traefik traefik/traefik -n traefik --create-namespace -f "$ICI/manifests/valeurs-traefik.yaml" --wait --timeout 5m >/dev/null
helm upgrade --install headlamp headlamp/headlamp -n headlamp --create-namespace --wait --timeout 5m >/dev/null \
  || echo "Headlamp non installé (facultatif, TP 05 bonus)."

etape "9/9 Images des TP téléchargées à l'avance sur les workers"
IMAGES_NOEUDS="mirror.gcr.io/library/postgres:17-alpine mirror.gcr.io/library/busybox:1.37 \
  ghcr.io/$COMPTE_IMAGES/huiteo-api:1.0 ghcr.io/$COMPTE_IMAGES/huiteo-api:1.1 \
  ghcr.io/$COMPTE_IMAGES/huiteo-front:1.0 ghcr.io/$COMPTE_IMAGES/huiteo-front:1.1"
for cible in "${WORKERS[@]}"; do
  ip=${cible%%:*}
  $SSH "$UTILISATEUR_SSH@$ip" "for i in $IMAGES_NOEUDS; do sudo crictl pull \$i >/dev/null || echo \"  échec sur $ip : \$i\"; done"
done

echo
bash "$ICI/verifier-lab.sh"

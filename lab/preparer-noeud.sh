#!/usr/bin/env bash
# Prépare un nœud Kubernetes (control-plane, worker-1 ou worker-2) : swap, modules, containerd, kubeadm/kubelet/kubectl.
# Relançable sans risque. Lancé par preparer-lab.sh, ou à la main :
#   sudo bash preparer-noeud.sh <nom-du-noeud>
set -euo pipefail

NOM=${1:?usage: sudo bash preparer-noeud.sh <control-plane|worker-1|worker-2>}
VERSION_K8S=${VERSION_K8S:-v1.36}
CURL="curl -fsSL --connect-timeout 20 --retry 3"

[ "$(id -u)" -eq 0 ] || { echo "À lancer avec sudo." >&2; exit 1; }
export DEBIAN_FRONTEND=noninteractive

echo "== $NOM : nom d'hôte et /etc/hosts"
hostnamectl set-hostname "$NOM"
grep -q "192.168.56.20 control-plane" /etc/hosts || cat >> /etc/hosts <<'EOF'
192.168.56.10 client
192.168.56.20 control-plane
192.168.56.30 worker-1
192.168.56.40 worker-2
EOF

echo "== $NOM : swap désactivé"
swapoff -a
sed -ri '/\sswap\s/ s/^([^#])/# \1/' /etc/fstab

echo "== $NOM : modules et réglages réseau du noyau"
printf 'overlay\nbr_netfilter\n' > /etc/modules-load.d/k8s.conf
modprobe overlay
modprobe br_netfilter
cat > /etc/sysctl.d/99-kubernetes.conf <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system >/dev/null

echo "== $NOM : paquets de base et containerd"
apt-get update -q
apt-get install -y -q apt-transport-https ca-certificates curl gpg containerd conntrack socat jq
mkdir -p /etc/containerd
if ! grep -q "SystemdCgroup = true" /etc/containerd/config.toml 2>/dev/null; then
  containerd config default > /etc/containerd/config.toml
  sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
fi
systemctl restart containerd
systemctl enable containerd >/dev/null

echo "== $NOM : dépôt Kubernetes $VERSION_K8S"
mkdir -p /etc/apt/keyrings
$CURL "https://pkgs.k8s.io/core:/stable:/$VERSION_K8S/deb/Release.key" | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$VERSION_K8S/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
apt-get update -q
apt-get install -y -q kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl >/dev/null
systemctl enable kubelet >/dev/null

echo "== $NOM : crictl pointe sur containerd"
cat > /etc/crictl.yaml <<'EOF'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
EOF

echo "== $NOM : prêt ($(kubeadm version -o short))"

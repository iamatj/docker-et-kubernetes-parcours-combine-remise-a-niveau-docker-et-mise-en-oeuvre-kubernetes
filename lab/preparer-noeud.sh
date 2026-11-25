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
# Le control plane est le poste client : il garde son nom d'hôte (le nœud s'appelle control-plane dans le cluster).
[ "$NOM" = control-plane ] || hostnamectl set-hostname "$NOM"
grep -q "10.10.0.10 control-plane" /etc/hosts || cat >> /etc/hosts <<'EOF'
10.10.0.10 client
10.10.0.10 control-plane
10.10.0.11 worker-1
10.10.0.12 worker-2
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
apt-get -o DPkg::Lock::Timeout=600 update -q
apt-get -o DPkg::Lock::Timeout=600 install -y -q apt-transport-https ca-certificates curl gpg conntrack socat jq
dpkg -s containerd.io >/dev/null 2>&1 || apt-get -o DPkg::Lock::Timeout=600 install -y -q containerd
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
apt-get -o DPkg::Lock::Timeout=600 update -q
apt-get -o DPkg::Lock::Timeout=600 install -y -q kubelet kubeadm kubectl cri-tools   # cri-tools : crictl (plus tiré par kubeadm depuis 1.36)
apt-mark hold kubelet kubeadm kubectl cri-tools >/dev/null
systemctl enable kubelet >/dev/null

echo "== $NOM : crictl pointe sur containerd"
cat > /etc/crictl.yaml <<'EOF'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
EOF

echo "== $NOM : prêt ($(kubeadm version -o short))"

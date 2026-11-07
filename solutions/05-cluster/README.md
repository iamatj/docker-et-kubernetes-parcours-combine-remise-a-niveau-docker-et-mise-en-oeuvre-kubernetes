# Correction du TP 05 – Explorer le cluster

**1.** À l'API Server, `https://192.168.56.20:6443`. L'identité est un certificat client (`kubernetes-admin`, membre du groupe des administrateurs) contenu dans le fichier `~/.kube/config`, copié depuis `/etc/kubernetes/admin.conf` du control-plane par le script du lab. Tous les droits : on fera mieux au TP 10.

**2.** `v1.36.x`, runtime `containerd://…`, Ubuntu 24.04. Le nœud `control-plane` porte la **taint** `node-role.kubernetes.io/control-plane:NoSchedule` : le scheduler n'y place que les pods qui la tolèrent (les composants système). Les applications vont sur `worker-1` et `worker-2`.

**3.** Ce sont des **pods statiques** : le kubelet du control-plane lit les fichiers YAML de `/etc/kubernetes/manifests` et lance lui-même ces conteneurs, sans passer par l'API Server. Il ne peut pas en être autrement : l'API Server et etcd sont justement ce qui permet aux autres pods d'exister ; ils doivent démarrer avant. Le kubelet publie ensuite un « miroir » de ces pods dans l'API, d'où leur présence dans `kubectl get pods`.

**4.** Le **kubelet** (et containerd) tournent en services systemd : ils doivent exister avant tout pod. En pods, gérés par des DaemonSets (un exemplaire par nœud) : `kube-proxy`, qui programme les règles réseau des Services (iptables ou nftables) sur chaque nœud, et `calico-node`, le CNI, qui donne une IP à chaque pod, route le trafic entre nœuds et applique les Network Policies (TP 10).

**5.** Le **contrôleur ReplicaSet** (dans `kube-controller-manager`) a constaté 2 pods au lieu de 3 et en a créé un ; le scheduler lui a choisi un nœud ; le kubelet de ce nœud l'a lancé. Chaîne : le Deployment possède un ReplicaSet (un par version du gabarit de pod), le ReplicaSet possède les pods (`ownerReferences`). Le contrôleur Deployment gère les versions (mises à jour, TP 07), le contrôleur ReplicaSet gère le nombre. Les 5 pods sont répartis sur `worker-1` et `worker-2` (souvent 3 et 2), jamais sur `control-plane`.

**6.** Dans **etcd**, sur `control-plane`. Si le control-plane s'arrête, les pods déjà lancés continuent de tourner (les kubelets et kube-proxy gardent leur état), mais plus rien ne change : pas de nouveau déploiement, pas de remplacement d'un pod qui meurt, `kubectl` ne répond plus. D'où, en production, 3 control planes (etcd a besoin d'une majorité). Si `worker-1` s'arrête, au bout d'environ 5 minutes ses pods sont considérés perdus et recréés sur `worker-2` (s'il a la place).

**7.** Poste de développeur : Minikube (ou kind, ou le Kubernetes de Docker Desktop). Ses propres serveurs : kubeadm (c'est ce qui a monté ce lab), ou une distribution qui l'enrobe (RKE2, Talos, OpenShift). Objet connecté ou petite machine : K3s, un seul binaire léger. Production chez un cloud : un service managé (EKS, AKS, GKE), où le fournisseur opère le control plane (on en reparle à la clôture du jour 3).

**Bonus.** L'API Server pointe vers etcd en `https://127.0.0.1:2379`, la plage des Services est `10.96.0.0/12`, et l'autorisation est `Node,RBAC`.

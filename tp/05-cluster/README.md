# TP 05 – Explorer le cluster

| Durée | Branche | Correction |
|-------|---------|------------|
| 70 min (9h35 – 10h45) | `tp-05-cluster` | `solutions/05-cluster/README.md` |

## L'incident

> Lundi, 9h. Cordée a loué un cluster Kubernetes de trois machines chez un hébergeur, monté avec kubeadm. Sophie reçoit un fichier `kubeconfig` et un mail : « Votre cluster est prêt. » Avant d'y mettre la moindre réservation, elle veut savoir ce qui tourne, où, et qui décide de quoi.

## Objectifs

- Se connecter au cluster et lire son architecture : control plane, nœuds, composants système.
- Voir le rôle de chaque composant en action : API Server, scheduler, controller manager, kubelet, container runtime.
- Manipuler les objets fondamentaux : Namespace, Pod, ReplicaSet, Deployment.
- Accéder au cluster de trois façons : kubectl, l'API REST, une interface web.

## Point de départ

```bash
cd ~/cordee
git fetch
git stash -u
git checkout tp-05-cluster
kubectl version            # Client et Server en v1.36.x
```

Le cluster a été monté avant la formation par `lab/preparer-lab.sh` (voir `guide-installation-lab.md`) : on ne l'installe pas, on l'exploite.

| Machine | IP | Rôle |
|---------|----|------|
| `client` | 192.168.56.10 | votre poste : kubectl, Helm, navigateur |
| `control-plane` | 192.168.56.20 | control plane |
| `worker-1` | 192.168.56.30 | nœud |
| `worker-2` | 192.168.56.40 | nœud |

Les nœuds sont joignables en SSH depuis `client` avec le compte `formation` : `ssh formation@control-plane`.

## Étapes

### 1. La connexion au cluster (8 min)

```bash
kubectl config get-contexts
kubectl config view --minify | grep -E 'server:|user:|name:'
kubectl cluster-info
```

**Question 1** – À quelle adresse et sur quel port kubectl envoie-t-il ses requêtes ? Avec quelle identité ? Où est rangé ce fichier ?

### 2. Les nœuds (7 min)

```bash
kubectl get nodes -o wide
kubectl describe node worker-1 | grep -A 6 -E '^Capacity|^Allocatable'
kubectl describe node control-plane | grep -A 2 Taints
```

**Question 2** – Quelle version de Kubernetes, quel container runtime, quel OS ? Pourquoi vos applications ne seront-elles pas placées sur `control-plane` ?

### 3. Le control plane (12 min)

```bash
kubectl -n kube-system get pods -o wide
ssh formation@control-plane 'ls /etc/kubernetes/manifests'
ssh formation@control-plane 'sudo crictl ps --name "kube-|etcd" -o table' | cut -c1-110
kubectl get --raw '/livez?verbose' | tail -5
```

Vous devez reconnaître quatre composants, chacun dans un pod nommé `<composant>-control-plane` : `kube-apiserver`, `etcd`, `kube-scheduler`, `kube-controller-manager`.

**Question 3** – Ces pods n'appartiennent à aucun Deployment. Qui les lance, à partir de quoi ? Pourquoi ne peuvent-ils pas être lancés par l'API Server comme les autres ?

### 4. Les nœuds de travail (8 min)

```bash
ssh formation@worker-1 'systemctl is-active kubelet containerd'
ssh formation@worker-1 'sudo crictl ps -o table' | cut -c1-110
kubectl -n kube-system get daemonsets
```

**Question 4** – Quel composant tourne en service systemd sur chaque nœud, et lesquels tournent en pods ? À quoi servent `kube-proxy` et `calico-node` ?

### 5. Namespaces et objets (5 min)

```bash
kubectl get namespaces
kubectl create namespace essai
kubectl api-resources --namespaced=true | head -15
kubectl explain pod.spec.containers.image
```

### 6. Un Pod, seul (10 min)

```bash
kubectl -n essai run hello --image=ghcr.io/nginx/nginx-unprivileged:1.28-alpine --port 8080
kubectl -n essai get pod hello -o wide -w
```

Attendez `Running` puis Ctrl+C.

```bash
kubectl -n essai describe pod hello | sed -n '/^Events/,$p'
```

Les événements racontent l'histoire : `Scheduled` (par `default-scheduler`, qui a choisi un nœud), `Pulled`, `Created`, `Started` (par le kubelet de ce nœud).

```bash
kubectl -n essai delete pod hello
kubectl -n essai get pods
```

Le pod a disparu, et personne ne le recrée.

### 7. Un Deployment, qui veille (12 min)

```bash
kubectl -n essai create deployment hello --image=ghcr.io/nginx/nginx-unprivileged:1.28-alpine --replicas=3 --port 8080
kubectl -n essai rollout status deployment hello
kubectl -n essai get deployment,replicaset,pod -o wide
```

Supprimez un pod (prenez son nom dans la liste) et regardez :

```bash
POD=$(kubectl -n essai get pods -o jsonpath='{.items[0].metadata.name}')
kubectl -n essai delete pod $POD --wait=false
kubectl -n essai get pods -w
```

Un nouveau pod apparaît en quelques secondes. Ctrl+C.

```bash
kubectl -n essai get pod -o jsonpath='{range .items[*]}{.metadata.name}{" → "}{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}{"\n"}{end}'
kubectl -n essai get replicaset -o jsonpath='{.items[0].metadata.ownerReferences[0].kind}{"/"}{.items[0].metadata.ownerReferences[0].name}{"\n"}'
kubectl -n essai scale deployment hello --replicas=5
kubectl -n essai get pods -o wide
```

**Question 5** – Qui a recréé le pod supprimé ? Dessinez la chaîne Deployment → ReplicaSet → Pod, et dites quel contrôleur s'occupe de quoi. Sur quels nœuds sont les 5 pods ?

### 8. L'API REST (5 min)

```bash
kubectl -n essai get pods -v=6 2>&1 | grep -E 'GET https' | head -2
kubectl get --raw /apis/apps/v1/namespaces/essai/deployments | jq -r '.items[] | "\(.metadata.name) : \(.status.readyReplicas)/\(.spec.replicas)"'
kubectl proxy --port 8001 >/dev/null 2>&1 &
sleep 1
curl -s http://localhost:8001/api/v1/namespaces/essai/pods | jq -r '.items[].spec.nodeName' | sort | uniq -c
kill %1
```

`kubectl proxy` tourne en arrière-plan le temps de la requête ; `kill %1` l'arrête.

### 9. L'interface web : Headlamp (3 min)

Le Dashboard Kubernetes historique a été retiré par le projet ; l'interface web recommandée est Headlamp, installée sur le lab.

```bash
kubectl -n headlamp create token headlamp --duration=4h
kubectl -n headlamp port-forward svc/headlamp 4466:80 >/dev/null 2>&1 &
```

Ouvrez <http://localhost:4466> dans Firefox, collez le jeton, et retrouvez le Deployment `hello` dans le namespace `essai`. Arrêtez ensuite la redirection : `kill %1`.

> Si `svc/headlamp` n'existe pas (`kubectl -n headlamp get svc`), Headlamp n'a pas été installé sur ce lab : passez cette étape.

## Nettoyage

```bash
kubectl delete namespace essai
jobs                     # aucune tâche en arrière-plan ne doit rester
```

## Questions de fin

6. Où est stocké l'état du cluster ? Que se passe-t-il pour les applications déjà lancées si `control-plane` s'arrête ? Et si `worker-1` s'arrête ?
7. Minikube, kubeadm, K3s, EKS / AKS / GKE : lequel choisir pour un poste de développeur, un cluster sur ses propres serveurs, un objet connecté, la production de Cordée chez un cloud ?

## Bonus

- `kubectl get events -A --sort-by=.lastTimestamp | tail` : les derniers événements de tout le cluster.
- `ssh formation@control-plane 'sudo cat /etc/kubernetes/manifests/kube-apiserver.yaml' | grep -E 'etcd-servers|service-cluster-ip-range|authorization-mode'`

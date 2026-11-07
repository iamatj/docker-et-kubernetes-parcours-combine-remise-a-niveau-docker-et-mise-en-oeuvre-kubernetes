# Guide d'installation du lab

Chaque participant dispose de son propre lab de 4 machines. La formation **n'apprend pas à monter un cluster** : il est préparé avant la session par `lab/preparer-lab.sh`, et les TP portent sur son exploitation.

## 1. Les machines

| Nom d'hôte | IP | Rôle | vCPU | Mémoire | Disque |
|------------|----|------|------|---------|--------|
| `client` | 192.168.56.10 | poste du participant : Docker (jour 1), kubectl, Helm, navigateur | 4 | 8 Go | 40 Go |
| `control-plane` | 192.168.56.20 | control plane Kubernetes 1.36 (API Server, etcd, scheduler, controller manager) | 2 | 4 Go | 30 Go |
| `worker-1` | 192.168.56.30 | nœud de travail | 2 | 4 Go | 30 Go |
| `worker-2` | 192.168.56.40 | nœud de travail | 2 | 4 Go | 30 Go |

Ces noms et ces IP sont utilisés tels quels dans tous les TP et les slides. S'ils changent, remplacez-les partout d'un coup.

Adresses réservées sur le même réseau : **192.168.56.200 à .220** pour les Services `LoadBalancer` (MetalLB). La .200 est celle de Traefik (`cordee.lab`).

### À demander à l'organisme qui fournit les machines

- 4 VM **Ubuntu Server 24.04 LTS x64** par participant, sur un réseau privé commun `192.168.56.0/24` (les 4 machines d'un participant se voient, sans pare-feu entre elles), avec accès Internet sortant (HTTPS vers `ghcr.io`, `mirror.gcr.io`, `pkgs.k8s.io`, `download.docker.com`, `get.helm.sh`, `github.com`, `raw.githubusercontent.com`, `traefik.github.io`, `kubernetes-sigs.github.io`).
- Sur les 3 nœuds : un compte `formation` avec `sudo` sans mot de passe, SSH ouvert depuis `client`, swap désactivable.
- Sur `client` : un bureau graphique avec un navigateur (Firefox), accessible au participant (console, bureau à distance). Si ce sont des VM cloud sans bureau, voir la section 6.
- La préparation (section 2) est faite **la veille** par le formateur ou par l'organisme : environ 15 min par lab, plusieurs labs en parallèle.

### Variante légère

3 VM au lieu de 4 : le rôle `client` est tenu par `control-plane` (Docker y est installé le jour 1, puis désinstallé avant le jour 2). Coût : on perd la séparation poste / cluster, Docker gêne le réseau des pods s'il n'est pas retiré proprement, et le participant travaille sur un nœud du cluster. À éviter si possible.

## 2. Préparation en une commande

Sur `client`, avec le compte du participant :

```bash
git clone https://github.com/iamatj/docker-et-kubernetes-parcours-combine-remise-a-niveau-docker-et-mise-en-oeuvre-kubernetes.git ~/cordee
cd ~/cordee
bash lab/preparer-lab.sh
```

Le script demande le mot de passe du compte `formation` une fois par nœud (copie de la clé SSH), puis enchaîne sans intervention :

| Étape | Ce qui est fait | Où |
|-------|-----------------|----|
| 1 | paquets de base, Docker Engine + Compose V2 + BuildKit, kubectl 1.36, Helm 4.3, `/etc/hosts`, complétion `kubectl` et alias `k` | client |
| 2 | clé SSH `~/.ssh/id_ed25519` copiée sur les 3 nœuds | client |
| 3 | swap, modules du noyau, containerd (cgroup systemd), kubeadm / kubelet / kubectl 1.36 (`lab/preparer-noeud.sh`) | 3 nœuds, en parallèle |
| 4 | `kubeadm init` (réseau des pods `10.244.0.0/16`), copie de `~/.kube/config` sur le client | control-plane |
| 5 | Calico 3.32.1 (réseau des pods et Network Policies) | cluster |
| 6 | `kubeadm join` des deux workers | workers |
| 7 | local-path-provisioner 0.0.37 (StorageClass par défaut `local-path`, et `local-path-retain`), MetalLB 0.16.2 (pool .200 – .220), metrics-server 0.9.0 | cluster |
| 8 | CRD Gateway API 1.6.2, Traefik (IngressClass et GatewayClass `traefik`, IP .200), Headlamp (interface web) | cluster |
| 9 | téléchargement à l'avance des images des TP, sur le client et sur les workers | client, workers |

Il est relançable sans risque : une étape déjà faite est vérifiée puis sautée. Il se termine par le bilan de la section 4. **Fermez ensuite la session du participant et rouvrez-la** (bureau compris), sinon `docker` demande `sudo`.

## 3. Avant la formation, côté dépôt

1. **Publier les images** : dans GitHub, onglet **Actions** > workflow **images** > **Run workflow** (branche `main`). Il publie `ghcr.io/iamatj/cordee-api` et `ghcr.io/iamatj/cordee-front` en versions `1.0` et `1.1`. La version `1.2` n'existe pas : c'est la panne du TP 07.
2. **Rendre les images publiques** : profil GitHub > **Packages** > `cordee-api` > **Package settings** > **Change visibility** > **Public**. Idem pour `cordee-front`. Sinon les nœuds affichent `ImagePullBackOff` dès le TP 06.
3. **QCM** : GitHub Pages publie `main` ; vérifiez que <https://iamatj.github.io/docker-et-kubernetes-parcours-combine-remise-a-niveau-docker-et-mise-en-oeuvre-kubernetes/qcm/> s'ouvre.

Faites les étapes 1 et 2 **avant** de lancer `preparer-lab.sh` : son étape 9 télécharge ces images sur les workers.

## 4. Vérifications

```bash
bash lab/verifier-lab.sh
```

Résultat attendu : une ligne `OK` par point, puis `Lab prêt.` Chaque `ÉCHEC` donne la piste à suivre. À la main :

```bash
kubectl get nodes -o wide                 # 3 nœuds Ready, version v1.36.x
kubectl get pods -A                       # tout en Running (ou Completed)
kubectl get storageclass                  # local-path (default), local-path-retain
kubectl -n traefik get svc traefik        # EXTERNAL-IP 192.168.56.200
kubectl get gatewayclass                  # traefik  ACCEPTED True
docker run --rm mirror.gcr.io/library/hello-world
```

Le guide ne crée ni ne supprime aucun objet utilisé par les TP : chaque TP nettoie ce qu'il crée, en dernière étape.

## 5. Terminal propre

Si chaque ligne du terminal est précédée de messages techniques (intégration du shell mal configurée sur l'image du lab) :

```bash
unset PROMPT_COMMAND
PS1='\u@\h:\w\$ '
PS0=''
```

Pour que ce soit permanent :

```bash
echo 'unset PROMPT_COMMAND; PS1="\u@\h:\w\$ "' >> ~/.bashrc
echo 'PS0=""' >> ~/.bashrc
source ~/.bashrc
```

Si les messages reviennent, cherchez le fichier qui les active : `grep -n "machineid\|PROMPT_COMMAND" ~/.bashrc ~/.profile /etc/profile.d/* 2>/dev/null`.

Tous les TP se font **dans un seul terminal** : ce qui doit tourner longtemps passe en arrière-plan (`&`, `docker run -d`, `kubectl port-forward … &`).

## 6. VM cloud sans bureau

Si `client` est une VM cloud sans interface graphique :

```bash
sudo apt-get update && sudo apt-get install -y xfce4 xfce4-goodies xrdp
echo xfce4-session > ~/.xsession && sudo adduser xrdp ssl-cert && sudo systemctl enable --now xrdp
sudo snap install firefox
```

Depuis Windows, ouvrez un tunnel et laissez la fenêtre ouverte : `ssh -L 3390:localhost:3389 <utilisateur>@<ip-publique-du-client>`, puis lancez `mstsc` sur `localhost:3390`. Seul le port 22 reste ouvert. Écran noir : une autre session XFCE est ouverte avec le même compte.

## 7. Dépannage

| Symptôme | Cause probable | Que faire |
|----------|----------------|-----------|
| `permission denied … docker.sock` | la session date d'avant l'ajout au groupe `docker` | fermer la session (bureau compris) et la rouvrir |
| le script reste bloqué sur un téléchargement | dépôt lent ou filtré | Ctrl+C, vérifier `curl -I https://pkgs.k8s.io`, relancer le script |
| `kubeadm init` échoue | swap actif, port 6443 occupé, ancien essai | `/tmp/kubeadm-init.log` ; sur control-plane `sudo kubeadm reset -f` puis relancer |
| nœud `NotReady` | Calico pas encore démarré | `kubectl -n kube-system get pods -o wide`, attendre 2 min |
| un worker n'apparaît pas | jeton expiré, horloge décalée | `/tmp/join-worker-N.log` ; sur le worker `sudo kubeadm reset -f`, relancer le script |
| `ImagePullBackOff` sur `cordee-*` | image non publiée ou privée | section 3 |
| Traefik sans EXTERNAL-IP | pool MetalLB absent | `kubectl apply -f lab/manifests/metallb-pool.yaml` |
| `kubectl top` : `Metrics API not available` | metrics-server démarre | attendre 1 min |

## 8. Remettre un lab à zéro entre deux sessions

Le plus simple est de recréer les VM. Sinon, depuis `client` :

```bash
kubectl delete namespace cordee cordee-preprod equipe diagnostic --ignore-not-found
kubectl delete pv --all
helm list -A                       # ne garder que traefik et headlamp
docker rm -f $(docker ps -aq) 2>/dev/null; docker system prune -af --volumes
```

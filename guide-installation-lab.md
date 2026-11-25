# Guide d'installation du lab

Chaque participant dispose de son propre lab de 3 machines : son poste, qui est aussi le control plane du cluster, et deux nœuds de travail. La formation **n'apprend pas à monter un cluster** : il est préparé avant la session, et les TP portent sur son exploitation.

La préparation se fait en deux temps, parce que le jour 1 et le jour 2 sont espacés :

- **avant le jour 1** : seulement la machine `client`, avec Docker (`lab/preparer-jour-1.sh`, section 2) ;
- **avant le jour 2** : le cluster Kubernetes sur les trois machines, le poste `client` devenant aussi le control plane (`lab/preparer-lab.sh`, section 2 bis).

## 1. Les machines

| Nom d'hôte | IP | Rôle | vCPU | Mémoire | Disque |
|------------|----|------|------|---------|--------|
| `client`, alias `control-plane` | 10.10.0.10 | poste du participant (kubectl, Helm, navigateur ; Docker au jour 1 seulement) et control plane Kubernetes 1.36 (API Server, etcd, scheduler, controller manager) | 4 | 8 Go | 40 Go |
| `worker-1` | 10.10.0.20 | nœud de travail | 2 | 4 Go | 30 Go |
| `worker-2` | 10.10.0.30 | nœud de travail | 2 | 4 Go | 30 Go |

Ces noms et ces IP sont utilisés tels quels dans tous les TP et les slides. S'ils changent, remplacez-les partout d'un coup.

Adresses réservées sur le même réseau : **10.10.0.200 à .220** pour les Services `LoadBalancer` (MetalLB). La .200 est celle de Traefik (`huiteo.lab`). Elles doivent être libres : hors de la plage DHCP, sans aucune machine dessus. À confirmer avec l'organisme ; vérification depuis `client`, avant d'installer : `ping -c1 -W1 10.10.0.200` ne doit rien recevoir. Pour une autre plage, modifiez `lab/manifests/metallb-pool.yaml`, `lab/manifests/valeurs-traefik.yaml` et les adresses des TP 07 à 12.

### À demander à l'organisme qui fournit les machines

- 3 VM **Ubuntu Server 24.04 LTS x64** par participant, sur un réseau privé commun `10.10.0.0/24` (les 3 machines d'un participant se voient, sans pare-feu entre elles), avec accès Internet sortant (HTTPS vers `ghcr.io`, `mirror.gcr.io`, `pkgs.k8s.io`, `download.docker.com`, `get.helm.sh`, `github.com`, `raw.githubusercontent.com`, `traefik.github.io`, `kubernetes-sigs.github.io`).
- Sur les 3 nœuds : un compte `formation` avec `sudo` sans mot de passe, SSH ouvert depuis `client`, swap désactivable.
- Sur `client` : un bureau graphique avec un navigateur (Firefox), accessible au participant (console, bureau à distance). Si ce sont des VM cloud sans bureau, voir la section 6.
- La préparation (section 2) est faite **la veille** par le formateur ou par l'organisme : environ 15 min par lab, plusieurs labs en parallèle.

### Le poste fait aussi control plane

Le poste `client` tient aussi le rôle de control plane : `control-plane` est un alias de `client` dans `/etc/hosts`, et c'est le nom du nœud dans le cluster. Le control plane porte une taint : les applications des TP tournent sur les deux workers.

Docker sert au jour 1 seulement, et le script du jour 2 ne l'installe pas : Docker et Kubernetes sur la même machine se gênent (containerd partagé, règles réseau). Sur un poste qui a servi au jour 1, désinstallez Docker avant de lancer `preparer-lab.sh` :

```bash
sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo rm -rf /var/lib/docker /var/lib/containerd /etc/containerd
```

Le plus simple reste de repartir de VM neuves pour le jour 2.

## 2. Avant le jour 1 : la machine client

Sur `client`, avec le compte du participant :

```bash
git clone https://github.com/iamatj/docker-et-kubernetes-parcours-combine-remise-a-niveau-docker-et-mise-en-oeuvre-kubernetes.git ~/huiteo
cd ~/huiteo
bash lab/preparer-jour-1.sh
```

Le script ne touche qu'à cette machine : pas de SSH, pas de nœud, rien à interrompre. Il enchaîne quatre étapes (environ 5 min) :

| Étape | Ce qui est fait |
|-------|-----------------|
| 1 | paquets de base (`curl`, `jq`, `git`…) |
| 2 | Docker Engine, Buildx (BuildKit) et Compose V2 depuis le dépôt officiel de Docker ; ajout du compte au groupe `docker` |
| 3 | téléchargement des images des TP 00 à 04, et de la base de vulnérabilités de Trivy (TP 04) |
| 4 | bilan : une ligne `OK` ou `ÉCHEC` par point, puis `Poste prêt pour le jour 1.` |

Il est relançable sans risque. **Ensuite, déconnectez la session du participant et reconnectez-la** (bureau compris), sinon `docker` demande `sudo` : le compte vient d'entrer dans le groupe `docker`, et les groupes ne sont lus qu'à l'ouverture de session. Fermer le terminal ne suffit pas. Le plus souvent, la déconnexion suffit ; si `id` ne montre toujours pas `docker` alors que `id <compte>` le montre, un morceau de l'ancienne session a survécu (autre connexion ouverte, processus du bureau) : **redémarrez la machine** (`sudo reboot`). Le plus simple : lancer le script la veille, puis redémarrer chaque machine. En dépannage, `newgrp docker` donne le groupe au terminal en cours.

Pour le jour 1, les deux workers ne servent pas encore : ils peuvent être livrés plus tard.

## 2 bis. Avant le jour 2 : le cluster

Sur `client`, toujours dans `~/huiteo` :

```bash
git fetch && git checkout main
bash lab/preparer-lab.sh
```

Le script demande le mot de passe du compte `formation` une fois par machine, y compris le poste lui-même (copie de la clé SSH), puis enchaîne sans intervention :

| Étape | Ce qui est fait | Où |
|-------|-----------------|----|
| 1 | paquets de base, serveur SSH, kubectl 1.36, Helm 4.3, `/etc/hosts`, complétion `kubectl` et alias `k` ; pas de Docker (section 1) | client |
| 2 | clé SSH `~/.ssh/id_ed25519` copiée sur les 3 machines | client |
| 3 | swap, modules du noyau, containerd (cgroup systemd), kubeadm / kubelet / kubectl 1.36 (`lab/preparer-noeud.sh`) | 3 nœuds, en parallèle |
| 4 | `kubeadm init` (réseau des pods `10.244.0.0/16`), copie de `~/.kube/config` | client (control plane) |
| 5 | Calico 3.32.1 (réseau des pods et Network Policies) | cluster |
| 6 | `kubeadm join` des deux workers | workers |
| 7 | local-path-provisioner 0.0.37 (StorageClass par défaut `local-path`, et `local-path-retain`), MetalLB 0.16.2 (pool .200 – .220), metrics-server 0.9.0 | cluster |
| 8 | CRD Gateway API 1.6.2, Traefik (IngressClass et GatewayClass `traefik`, IP .200), Headlamp (interface web) | cluster |
| 9 | téléchargement à l'avance des images des TP sur les workers | workers |

Il est relançable sans risque : une étape déjà faite est vérifiée puis sautée. Il se termine par le bilan de la section 4.

## 3. Avant la formation, côté dépôt

1. **Publier les images** : dans GitHub, onglet **Actions** > workflow **images** > **Run workflow** (branche `main`). Il publie `ghcr.io/iamatj/huiteo-api` et `ghcr.io/iamatj/huiteo-front` en versions `1.0` et `1.1`. La version `1.2` n'existe pas : c'est la panne du TP 07.
2. **Rendre les images publiques** : profil GitHub > **Packages** > `huiteo-api` > **Package settings** > **Change visibility** > **Public**. Idem pour `huiteo-front`. Sinon les nœuds affichent `ImagePullBackOff` dès le TP 06.
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
kubectl -n traefik get svc traefik        # EXTERNAL-IP 10.10.0.200
kubectl get gatewayclass                  # traefik  ACCEPTED True
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
| `permission denied … docker.sock`, ou `docker` absent de `id` alors que `id <compte>` le montre | la session date d'avant l'ajout au groupe `docker` | se déconnecter puis se reconnecter ; si ça ne suffit pas, redémarrer la machine (`sudo reboot`) ; en dépannage, `newgrp docker` |
| le script reste bloqué sur un téléchargement | dépôt lent ou filtré | Ctrl+C, vérifier `curl -I https://pkgs.k8s.io`, relancer le script |
| `kubeadm init` échoue | swap actif, port 6443 occupé, ancien essai | `/tmp/kubeadm-init.log` ; sur control-plane `sudo kubeadm reset -f` puis relancer |
| nœud `NotReady` | Calico pas encore démarré | `kubectl -n kube-system get pods -o wide`, attendre 2 min |
| un worker n'apparaît pas | jeton expiré, horloge décalée | `/tmp/join-worker-N.log` ; sur le worker `sudo kubeadm reset -f`, relancer le script |
| `ImagePullBackOff` sur `huiteo-*` | image non publiée ou privée | section 3 |
| Traefik sans EXTERNAL-IP | pool MetalLB absent | `kubectl apply -f lab/manifests/metallb-pool.yaml` |
| `kubectl top` : `Metrics API not available` | metrics-server démarre | attendre 1 min |

## 8. Remettre un lab à zéro entre deux sessions

Le plus simple est de recréer les VM. Sinon, depuis `client` :

```bash
kubectl delete namespace huiteo huiteo-preprod equipe diagnostic --ignore-not-found
kubectl delete pv --all
helm list -A                       # ne garder que traefik et headlamp
```

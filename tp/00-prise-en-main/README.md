# TP 00 – Prise en main du poste et de Docker

| Durée | Branche | Correction |
|-------|---------|------------|
| 30 min (9h30 – 10h00) | `tp-00-prise-en-main` | `solutions/00-prise-en-main/README.md` |

## L'incident

> Lundi, 8h12. Karim a livré l'API de Huiteo sur le serveur de l'hébergeur. Elle refuse de démarrer : le serveur a Python 3.9, son poste Python 3.13, et une bibliothèque manque. « Chez moi, ça marche. » Léa, la responsable produit, décide que Huiteo livrera désormais des conteneurs. Sophie, qui administre les serveurs, veut d'abord comprendre ce que Docker installe sur ses machines, et qui pourra s'en servir.

## Objectifs

- Se repérer sur le poste `client` et dans le dépôt de la formation.
- Distinguer le client Docker, le daemon `dockerd`, `containerd` et `runc`, et parler à l'API sans le client.
- Voir qu'un conteneur est un processus du poste, isolé.
- Comprendre pourquoi le groupe `docker` équivaut à `root`.
- Lancer un premier conteneur, et utiliser la syntaxe actuelle `docker compose`.

## Point de départ

Ouvrez un terminal sur `client` (tout le TP se fait dans ce seul terminal).

Si chaque ligne est précédée de messages techniques, nettoyez le prompt :

```bash
unset PROMPT_COMMAND
PS1='\u@\h:\w\$ '
PS0=''
```

Récupérez le dépôt et placez-vous sur la branche du TP :

```bash
cd ~/huiteo 2>/dev/null || git clone https://github.com/iamatj/docker-et-kubernetes-parcours-combine-remise-a-niveau-docker-et-mise-en-oeuvre-kubernetes.git ~/huiteo
cd ~/huiteo
git fetch
git checkout tp-00-prise-en-main
ls
```

Vous devez voir `app/`, `lab/`, `tp/`, `README.md`, `programme-3-jours.md`.

## Étapes

### 1. Le poste et vos droits (3 min)

```bash
hostname            # client
id                  # le groupe docker doit apparaître
ip -br addr         # 192.168.56.10 sur l'interface du lab
```

Si `docker` n'apparaît pas dans `id`, fermez la session (bureau compris), rouvrez-la, et recommencez.

### 2. Le client et le daemon (5 min)

```bash
docker version
```

La sortie a **deux blocs** : `Client` (la commande que vous tapez) et `Server: Docker Engine` (le daemon `dockerd`, un service qui tourne en permanence).

**Question 1** – Quelle est la version du client ? Du serveur ? Quelle version de l'API parlent-ils (`API version`) ?

```bash
docker info --format 'Pilote de stockage : {{.Driver}} | cgroups : {{.CgroupDriver}} | dossier : {{.DockerRootDir}} | conteneurs : {{.Containers}}'
systemctl status docker --no-pager | head -5
ls -l /var/run/docker.sock
```

**Question 2** – Où Docker range-t-il les images et les conteneurs sur le disque ? Qui écoute sur `/var/run/docker.sock` ?

### 3. Ce qui lance vraiment un conteneur (7 min)

`dockerd` ne lance pas lui-même les conteneurs : il délègue à `containerd` (un autre service), qui utilise `runc` pour créer le processus isolé. Vérifiez-le :

```bash
systemctl is-active docker containerd                         # deux services : active, active
docker run -d --name dodo mirror.gcr.io/library/busybox:1.37 sleep 600
ps -ef --forest | grep -B1 'sleep 600' | grep -v grep          # le parent du sleep
PID=$(docker inspect -f '{{.State.Pid}}' dodo); echo $PID
ps -o pid,user,cmd -p $PID                                     # un processus ordinaire du poste
sudo ls -l /proc/$PID/ns | head -8                             # ses namespaces : son isolement
```

Le `sleep` du conteneur est un processus du poste, visible avec `ps`, dont le parent est `containerd-shim-runc-v2`. Les namespaces (`pid`, `net`, `mnt`, `uts`…) lui donnent sa propre vue du système.

Arrêtez maintenant le daemon, puis réessayez :

```bash
sudo systemctl stop docker docker.socket
docker ps                       # Cannot connect to the Docker daemon at unix:///var/run/docker.sock
sudo systemctl start docker
docker ps                       # dodo est revenu… ou pas : regardez la colonne STATUS
docker rm -f dodo
```

**Question 3** – Sans daemon, que sait encore faire le client `docker` ? Le conteneur `dodo` a-t-il survécu à l'arrêt du daemon ? Qu'en concluez-vous pour une mise à jour de Docker sur un serveur de production ?

### 4. Parler à l'API sans le client (5 min)

Le client `docker` n'est qu'un programme qui envoie des requêtes HTTP au daemon, par le socket. Faites-le vous-même :

```bash
curl -s --unix-socket /var/run/docker.sock http://localhost/version | jq '{Version, ApiVersion, Os, Arch}'
curl -s --unix-socket /var/run/docker.sock http://localhost/images/json | jq -r '.[].RepoTags[]'
```

La seconde commande liste les images déjà téléchargées pendant la préparation du lab : c'est exactement ce que fait `docker image ls`.

**Question 4** – Quel est l'intérêt de cette API pour une chaîne CI/CD, pour Compose ou pour un outil comme VS Code ?

### 5. Le groupe `docker`, c'est `root` (4 min)

```bash
ls -l /var/run/docker.sock      # srw-rw---- root docker : le groupe docker peut écrire dessus
cat /etc/shadow                 # Permission denied : vous n'êtes pas root
docker run --rm -v /etc:/hote mirror.gcr.io/library/busybox:1.37 head -3 /hote/shadow
```

La dernière commande affiche le début du fichier des mots de passe du poste, sans `sudo`. Le conteneur tourne en `root`, et `-v /etc:/hote` lui monte le dossier `/etc` du poste.

**Question 5** – Pourquoi cela fonctionne-t-il ? À qui peut-on donner le groupe `docker` sur un serveur ? Citez deux façons de limiter ce risque.

### 6. Premier conteneur (4 min)

```bash
docker run mirror.gcr.io/library/hello-world
docker ps          # rien : le conteneur est déjà terminé
docker ps -a       # il est là, à l'état Exited (0)
```

`mirror.gcr.io` est un miroir public de Docker Hub : on l'utilise pour ne pas dépendre des limites de téléchargement anonymes de Docker Hub (100 téléchargements par 6 h et par adresse IP).

**Question 6** – Relisez le texte affiché par `hello-world` : quelles sont les quatre étapes entre votre commande et le texte affiché ? Laquelle n'a pas eu lieu, et pourquoi ?

Supprimez le conteneur :

```bash
docker rm $(docker ps -aq --filter ancestor=mirror.gcr.io/library/hello-world)
```

### 7. `docker compose`, sans tiret (2 min)

```bash
docker compose version
docker-compose version
```

La première commande répond (Compose V2, un plugin du client). La seconde doit échouer : `command not found`. N'installez pas le paquet `docker-compose` qu'Ubuntu propose : c'est l'ancienne version.

**Question 7** – Pourquoi `docker-compose` (avec un tiret) n'existe-t-il plus ? Que faites-vous d'un vieux script ou d'une vieille documentation qui l'utilise ?

## Questions de fin

8. Remettez dans l'ordre et définissez en une phrase : *Dockerfile, image, conteneur, registry, daemon, Compose*.
9. Conteneur ou machine virtuelle : lequel embarque un noyau ? Pour Huiteo, que faut-il choisir pour isoler deux études clientes qui ne se font pas confiance ?

## Bonus

- **Contextes** : `docker context ls`. Un contexte dit au client **à quel daemon** parler ; sur ce poste, `default` pointe sur `unix:///var/run/docker.sock`. Sur un poste Windows avec Docker Desktop, où tourne le daemon ? Citez deux différences avec Docker Engine sur Linux.
- `docker run --rm -it mirror.gcr.io/library/busybox:1.37 sh`, puis `ps`, `hostname`, `ip addr` : que voit le conteneur du poste ? Sortez avec `exit`.
- `docker system df` : combien de place occupent les images préchargées ?
- `sudo journalctl -u docker -n 20 --no-pager` : les journaux du daemon, le premier endroit où regarder quand Docker ne démarre pas. Sa configuration, quand elle existe, est dans `/etc/docker/daemon.json`.

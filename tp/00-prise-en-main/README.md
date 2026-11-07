# TP 00 – Prise en main du poste et de Docker

| Durée | Branche | Correction |
|-------|---------|------------|
| 30 min (9h30 – 10h00) | `tp-00-prise-en-main` | `solutions/00-prise-en-main/README.md` |

## L'incident

> Lundi, 8h12. Karim a livré l'API de Cordée sur le serveur de l'hébergeur. Elle refuse de démarrer : le serveur a Python 3.9, son poste Python 3.13, et une bibliothèque manque. « Chez moi, ça marche. » Léa décide que Cordée livrera désormais des conteneurs.

## Objectifs

- Se repérer sur le poste `client` et dans le dépôt de la formation.
- Distinguer le client Docker, le daemon et l'API, et parler à l'API sans le client.
- Lancer un premier conteneur et comprendre ce qui s'est passé.
- Utiliser la syntaxe actuelle `docker compose`.

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
cd ~/cordee 2>/dev/null || git clone https://github.com/iamatj/docker-et-kubernetes-parcours-combine-remise-a-niveau-docker-et-mise-en-oeuvre-kubernetes.git ~/cordee
cd ~/cordee
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

### 2. Le client et le daemon (7 min)

```bash
docker version
```

La sortie a **deux blocs** : `Client` (la commande que vous tapez) et `Server: Docker Engine` (le daemon `dockerd`).

**Question 1** – Quelle est la version du client ? Du serveur ? Quelle version de l'API parlent-ils (`API version`) ?

```bash
docker info --format 'Pilote de stockage : {{.Driver}} | cgroups : {{.CgroupDriver}} | dossier : {{.DockerRootDir}} | conteneurs : {{.Containers}}'
systemctl status docker --no-pager | head -5
ls -l /var/run/docker.sock
```

**Question 2** – Où Docker range-t-il les images et les conteneurs sur le disque ? Qui écoute sur `/var/run/docker.sock` ?

### 3. Parler à l'API sans le client (7 min)

Le client `docker` n'est qu'un programme qui envoie des requêtes HTTP au daemon. Faites-le vous-même :

```bash
curl -s --unix-socket /var/run/docker.sock http://localhost/version | jq '{Version, ApiVersion, Os, Arch}'
curl -s --unix-socket /var/run/docker.sock http://localhost/images/json | jq -r '.[].RepoTags[]'
```

La seconde commande liste les images déjà téléchargées pendant la préparation du lab.

**Question 3** – Quel est l'intérêt de cette API pour une chaîne CI/CD ou pour un outil comme VS Code ? Quel risque pose le fait d'être membre du groupe `docker` ?

### 4. Premier conteneur (6 min)

```bash
docker run mirror.gcr.io/library/hello-world
docker ps          # rien : le conteneur est déjà terminé
docker ps -a       # il est là, à l'état Exited (0)
```

`mirror.gcr.io` est un miroir public de Docker Hub : on l'utilise pour ne pas dépendre des limites de téléchargement anonymes de Docker Hub (100 téléchargements par 6 h et par adresse IP).

**Question 4** – Relisez le texte affiché par `hello-world` : quelles sont les quatre étapes entre votre commande et le texte affiché ? Laquelle n'a pas eu lieu, et pourquoi ?

Supprimez le conteneur :

```bash
docker rm $(docker ps -aq --filter ancestor=mirror.gcr.io/library/hello-world)
```

### 5. `docker compose`, sans tiret (3 min)

```bash
docker compose version
docker-compose version
```

La première commande répond (Compose V2, un plugin du client). La seconde doit échouer : `command not found`.

**Question 5** – Pourquoi `docker-compose` (avec un tiret) n'existe-t-il plus ? Que faites-vous d'un vieux script ou d'une vieille documentation qui l'utilise ?

### 6. Contextes et Docker Desktop (4 min)

```bash
docker context ls
```

Un contexte dit au client **à quel daemon** parler. Sur ce poste, `default` pointe sur `unix:///var/run/docker.sock`.

**Question 6** – Sur un poste Windows avec Docker Desktop, où tourne le daemon ? Citez deux différences entre Docker Engine sur Linux et Docker Desktop.

## Questions de fin

7. Remettez dans l'ordre et définissez en une phrase : *Dockerfile, image, conteneur, registry, daemon, Compose*.
8. Conteneur ou machine virtuelle : lequel embarque un noyau ? Pour Cordée, que faut-il choisir pour isoler deux clients qui ne se font pas confiance ?

## Bonus

- `docker run --rm -it mirror.gcr.io/library/busybox:1.37 sh`, puis `ps`, `hostname`, `ip addr` : que voit le conteneur du poste ? Sortez avec `exit`.
- `docker system df` : combien de place occupent les images préchargées ?

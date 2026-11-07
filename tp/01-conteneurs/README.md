# TP 01 – Conteneurs, images et registres

| Durée | Branche | Correction |
|-------|---------|------------|
| 90 min (10h15 – 10h45, pause, 11h00 – 12h00) | `tp-01-conteneurs` | `solutions/01-conteneurs/README.md` |

## L'incident

> Dimanche, 23h40. Le site vitrine de Cordée ne répond plus. Sophie se connecte au serveur : un processus nginx lancé « à la main » il y a trois mois s'est arrêté. Personne ne sait quelle version tournait, ni avec quelles options il avait été lancé. Il faut que ce soit reproductible, observable, et que ça redémarre tout seul.

## Objectifs

- Lire une image : nom complet, tag, digest, couches, configuration.
- Lancer un conteneur avec les bonnes options : détaché, ports, variables d'environnement, limites, politique de redémarrage.
- Administrer un conteneur : `logs`, `exec`, `inspect`, `stats`, `stop` / `start` / `restart` / `rm`.
- Pousser et récupérer une image dans un registre privé.

## Point de départ

```bash
cd ~/cordee
git fetch
git checkout tp-01-conteneurs
docker ps -a        # aucun conteneur du TP précédent ne doit rester
```

Tout le TP se fait dans un seul terminal ; ce qui doit tourner est lancé en arrière-plan (`-d`).

## Partie A – Les images (20 min)

### A1. Nommer une image

```bash
docker pull ghcr.io/nginx/nginx-unprivileged:1.28-alpine
docker image ls
```

Un nom d'image complet a quatre parties : `registre/dépôt:tag`, plus un digest facultatif `@sha256:…`.

| Écrit | Nom complet |
|-------|-------------|
| `nginx` | `docker.io/library/nginx:latest` |
| `mirror.gcr.io/library/postgres:17-alpine` | registre `mirror.gcr.io`, dépôt `library/postgres`, tag `17-alpine` |
| `ghcr.io/nginx/nginx-unprivileged:1.28-alpine` | registre `ghcr.io`, dépôt `nginx/nginx-unprivileged`, tag `1.28-alpine` |

**Question 1** – Pourquoi `nginx:latest` est-il une mauvaise idée en production ?

### A2. Le digest

```bash
docker image inspect ghcr.io/nginx/nginx-unprivileged:1.28-alpine --format '{{index .RepoDigests 0}}'
```

Copiez le résultat (il commence par `ghcr.io/nginx/nginx-unprivileged@sha256:`). Le tag peut être déplacé par l'éditeur ; le digest, jamais.

### A3. Les couches et l'historique

```bash
docker image history ghcr.io/nginx/nginx-unprivileged:1.28-alpine
docker image inspect ghcr.io/nginx/nginx-unprivileged:1.28-alpine --format '{{len .RootFS.Layers}} couches'
docker image inspect ghcr.io/nginx/nginx-unprivileged:1.28-alpine --format 'Utilisateur : {{.Config.User}} | Ports : {{.Config.ExposedPorts}} | Commande : {{.Config.Cmd}}'
```

**Question 2** – Combien de couches ? Quelles lignes de l'historique ont une taille de `0B`, et pourquoi ? Sous quel utilisateur, et sur quel port, cette image fait-elle tourner nginx ?

## Partie B – Un conteneur pour le site vitrine (30 min)

### B1. Lancer, en arrière-plan, avec un port publié

```bash
docker run -d --name vitrine -p 8081:8080 ghcr.io/nginx/nginx-unprivileged:1.28-alpine
docker ps
curl -s http://localhost:8081/ | head -5
```

Vous devez voir la page d'accueil par défaut de nginx (`Welcome to nginx!`). `-p 8081:8080` : le port 8081 du poste mène au port 8080 du conteneur.

### B2. Y mettre le site de Cordée

```bash
docker cp ~/cordee/app/front/html/. vitrine:/usr/share/nginx/html/
curl -s http://localhost:8081/ | grep -o '<title>.*</title>'
```

Attendu : `<title>Cordée · Réservez votre nuit en refuge</title>`. Ouvrez <http://localhost:8081> dans Firefox : la page s'affiche avec le bandeau **« API injoignable »**. C'est normal : il n'y a pas encore d'API.

### B3. Observer

```bash
docker logs vitrine --tail 5           # une ligne par requête, dont celles de curl et Firefox
docker exec vitrine id                 # uid=101(nginx)
docker exec vitrine ps                 # le processus maître nginx et ses workers
docker exec -it vitrine sh             # un shell dans le conteneur ; tapez « ls /usr/share/nginx/html » puis « exit »
docker stats --no-stream vitrine       # CPU, mémoire, réseau
docker inspect vitrine --format 'IP : {{.NetworkSettings.IPAddress}} | Redémarrages : {{.RestartCount}} | Politique : {{.HostConfig.RestartPolicy.Name}}'
```

**Question 3** – `docker exec` crée-t-il un nouveau conteneur ? Que se passe-t-il pour le conteneur si vous sortez du shell avec `exit` ?

### B4. Le cycle de vie

```bash
docker stop vitrine && docker ps -a --filter name=vitrine     # Exited
docker start vitrine && curl -s http://localhost:8081/ | grep -c Cordée
docker restart vitrine
docker rm -f vitrine
docker run -d --name vitrine -p 8081:8080 ghcr.io/nginx/nginx-unprivileged:1.28-alpine
curl -s http://localhost:8081/ | grep -c Cordée
```

**Question 4** – Après `stop` puis `start`, le site de Cordée est-il toujours là ? Et après `rm` puis un nouveau `run` ? Qu'en déduisez-vous sur l'endroit où il faut mettre le site ?

### B5. Redémarrer tout seul

```bash
docker rm -f vitrine
docker run -d --name vitrine --restart unless-stopped -p 8081:8080 ghcr.io/nginx/nginx-unprivileged:1.28-alpine
docker exec vitrine sh -c 'kill 1'       # on simule l'arrêt brutal du processus principal
sleep 3
docker ps --filter name=vitrine --format '{{.Names}} {{.Status}}'
docker inspect vitrine --format 'Redémarrages : {{.RestartCount}}'
```

Attendu : le conteneur est `Up` depuis quelques secondes et `RestartCount` vaut 1.

**Question 5** – Quelle différence entre `--restart always` et `--restart unless-stopped` après un redémarrage du serveur ?

## Partie C – PostgreSQL : variables et limites (20 min)

### C1. Une erreur de configuration à diagnostiquer

```bash
docker run -d --name pg mirror.gcr.io/library/postgres:17-alpine
sleep 3
docker ps -a --filter name=pg --format '{{.Names}} {{.Status}}'
docker logs pg
```

Le conteneur est `Exited (1)`. Lisez les logs : il manque une variable d'environnement.

### C2. Le relancer correctement, avec des limites

```bash
docker rm pg
docker run -d --name pg \
  -e POSTGRES_DB=cordee -e POSTGRES_USER=cordee -e POSTGRES_PASSWORD=essai \
  --memory 256m --cpus 0.5 \
  mirror.gcr.io/library/postgres:17-alpine
sleep 5
docker exec pg psql -U cordee -d cordee -c 'SELECT version();'
docker stats --no-stream pg
docker inspect pg --format 'Mémoire max : {{.HostConfig.Memory}} octets | CPU : {{.HostConfig.NanoCpus}} nano-CPU'
```

`docker stats` affiche `MEM USAGE / LIMIT` avec une limite de 256 MiB.

**Question 6** – Que se passe-t-il si un conteneur dépasse sa limite de mémoire ? Et sa limite de CPU ?

### C3. Mode interactif

```bash
docker run --rm -it mirror.gcr.io/library/postgres:17-alpine psql --version
docker run --rm -it --link pg mirror.gcr.io/library/postgres:17-alpine psql -h pg -U cordee -d cordee -c '\dt'
```

Le mot de passe demandé est `essai`. `--rm` supprime le conteneur à sa sortie ; `-it` branche votre clavier et votre terminal.

> `--link` est une option ancienne, utilisée ici seulement pour joindre `pg` par son nom sur le réseau par défaut. Au TP 03, on fera mieux avec un réseau dédié.

## Partie D – Un registre privé (20 min)

### D1. Lancer le registre

```bash
docker run -d --name registre --restart unless-stopped -p 5000:5000 mirror.gcr.io/library/registry:2
curl -s http://localhost:5000/v2/_catalog          # {"repositories":[]}
```

Ce registre est **le vôtre** : il sert jusqu'à la fin de la journée (TP 02). Ne le supprimez pas.

### D2. Pousser une image

```bash
docker tag ghcr.io/nginx/nginx-unprivileged:1.28-alpine localhost:5000/cordee/nginx:1.28
docker image ls | grep nginx                       # même IMAGE ID pour les deux noms
docker push localhost:5000/cordee/nginx:1.28
curl -s http://localhost:5000/v2/_catalog
curl -s http://localhost:5000/v2/cordee/nginx/tags/list
```

**Question 7** – `docker tag` a-t-il copié l'image ? Pourquoi le push affiche-t-il `Pushed` pour chaque couche ?

### D3. Récupérer l'image depuis le registre

```bash
docker rmi localhost:5000/cordee/nginx:1.28
docker pull localhost:5000/cordee/nginx:1.28
```

La seconde commande affiche `Already exists` pour les couches : elles sont encore sur le poste sous l'autre nom.

**Question 8** – Comment ferait-on pour pousser sur Docker Hub ou sur `ghcr.io` ? Que faut-il en plus ?

## Nettoyage

```bash
docker rm -f vitrine pg
docker ps            # il ne reste que « registre »
```

## Questions de fin

9. Quelle commande donne, pour un conteneur, l'image exacte (digest) avec laquelle il a été lancé ?
10. Sophie veut savoir, dimanche soir, avec quelles options le nginx de la vitrine avait été lancé. Avec un conteneur, où trouve-t-elle cette information ?

## Bonus

- `docker run -d --name essai --memory 20m mirror.gcr.io/library/postgres:17-alpine` avec les variables de C2 : que montre `docker inspect essai --format '{{.State.OOMKilled}}'` ?
- `docker events --since 10m --until 0s` : retrouvez l'arrêt brutal de la partie B5.

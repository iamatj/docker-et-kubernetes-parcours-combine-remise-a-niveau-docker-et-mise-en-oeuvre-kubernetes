# TP 03 – Volumes, réseaux et Docker Compose V2

| Durée | Branche | Correction |
|-------|---------|------------|
| 75 min (14h45 – 15h15, pause, 15h30 – 16h15) | `tp-03-compose` | `solutions/03-compose/` (`README.md` et `app/compose.yaml`) |

La pause tombe après la partie B : on reprend à la partie C à 15h30.

## L'incident

> Jeudi, 7h30. Le serveur de Cordée a redémarré pendant la nuit (mise à jour du noyau). Karim relance ses trois `docker run` de mémoire. Le site revient… vide : les 312 réservations de la veille ont disparu. Et l'API refuse de démarrer une fois sur deux : elle se lance avant que PostgreSQL soit prêt.

## Objectifs

- Garder des données au-delà de la vie d'un conteneur : volume nommé, bind mount, tmpfs.
- Comprendre les réseaux Docker : bridge par défaut, réseau dédié et son DNS, `host`, `none`.
- Décrire Cordée dans un `compose.yaml` : services, réseaux, volumes, `depends_on` avec `service_healthy`.
- Piloter la stack : `up`, `down`, `ps`, `logs`, `exec`, `build`.

## Point de départ

```bash
cd ~/cordee
git fetch
git stash -u                  # met de côté votre travail du TP 02
git checkout tp-03-compose
ls app/api app/front          # les Dockerfile corrigés du TP 02 sont là
docker ps -a                  # seul « registre » tourne
```

## Partie A – Volumes (15 min)

### A1. Un volume nommé survit au conteneur

```bash
docker volume create essai-db
docker run -d --name pg1 -e POSTGRES_PASSWORD=essai -v essai-db:/var/lib/postgresql/data mirror.gcr.io/library/postgres:17-alpine
sleep 5
docker exec pg1 psql -U postgres -c "CREATE TABLE refuge (nom text); INSERT INTO refuge VALUES ('La Pra');"
docker rm -f pg1
docker run -d --name pg2 -e POSTGRES_PASSWORD=essai -v essai-db:/var/lib/postgresql/data mirror.gcr.io/library/postgres:17-alpine
sleep 5
docker exec pg2 psql -U postgres -c "SELECT * FROM refuge;"
```

Attendu : `La Pra`, alors que `pg1` a été supprimé.

```bash
docker volume inspect essai-db --format '{{.Mountpoint}}'
```

**Question 1** – Où sont physiquement les données ? Que se serait-il passé sans `-v essai-db:…` ?

### A2. Un bind mount : un dossier du poste dans le conteneur

```bash
docker run -d --name vitrine -p 8081:8080 -v ~/cordee/app/front/html:/usr/share/nginx/html:ro ghcr.io/nginx/nginx-unprivileged:1.28-alpine
curl -s http://localhost:8081/ | grep -o '<title>.*</title>'
sed -i 's/Réservez votre nuit en refuge/Réservez votre nuit là-haut/' ~/cordee/app/front/html/index.html
curl -s http://localhost:8081/ | grep -o '<title>.*</title>'
git -C ~/cordee checkout app/front/html/index.html
docker exec vitrine touch /usr/share/nginx/html/essai
```

La modification se voit tout de suite, sans rien relancer. La dernière commande échoue : `Read-only file system` (option `:ro`).

### A3. tmpfs et nettoyage

```bash
docker run --rm --tmpfs /tmp:size=16m mirror.gcr.io/library/busybox:1.37 df -h /tmp
docker rm -f pg2 vitrine
docker volume ls
docker system df
docker volume rm essai-db
```

**Question 2** – Dans quel cas utiliser un bind mount, un volume nommé, un tmpfs ?

## Partie B – Réseaux (15 min)

### B1. Le réseau par défaut n'a pas de DNS

```bash
docker run -d --name serveur mirror.gcr.io/library/busybox:1.37 httpd -f -p 8000
docker run --rm mirror.gcr.io/library/busybox:1.37 wget -qO- -T 3 http://serveur:8000/ ; echo "code : $?"
```

Attendu : `bad address 'serveur'`. Sur le pont `bridge` par défaut, les conteneurs ne se connaissent pas par leur nom.

### B2. Un réseau dédié en a un

```bash
docker network create labo
docker network connect labo serveur
docker run --rm --network labo mirror.gcr.io/library/busybox:1.37 wget -qO- -T 3 http://serveur:8000/ ; echo "code : $?"
docker run --rm --network labo mirror.gcr.io/library/busybox:1.37 nslookup serveur 127.0.0.11
```

Le `wget` répond maintenant (`404 Not Found` de httpd, ou une page vide : l'important est que le nom est résolu). `127.0.0.11` est le DNS interne de Docker.

### B3. `host` et `none`

```bash
docker run --rm --network host mirror.gcr.io/library/busybox:1.37 ip -br addr | head -4
docker run --rm --network none mirror.gcr.io/library/busybox:1.37 ip -br addr
docker rm -f serveur && docker network rm labo
```

**Question 3** – Que voit un conteneur en `--network host` ? En `none` ? Pourquoi `-p` n'a-t-il pas de sens en mode `host` ?

## Partie C – Cordée avec Compose (40 min, après la pause)

### C1. Le squelette

```bash
cd ~/cordee/app
cp ~/cordee/tp/03-compose/compose.yaml compose.yaml
docker compose config --services
```

Ouvrez `app/compose.yaml`. Supprimez le service `a-completer` (ses 3 lignes) : il ne sert qu'à faire échouer un fichier non complété. Puis lancez la stack telle quelle :

```bash
docker compose up -d --build
sleep 10
docker compose ps -a
docker compose logs api --tail 5
```

Le plus souvent, `api` est `Exited (1)` : ses logs montrent `base injoignable (essai 3/3)` puis `abandon`. PostgreSQL initialise sa base pendant plusieurs secondes ; `depends_on: [db]` n'attend que le **démarrage** du conteneur, pas que la base accepte des connexions. Si l'API a démarré du premier coup, relancez `docker compose down && docker compose up -d` : le problème est aléatoire, c'est ce qui le rend dangereux.

### C2. Attendre que la base soit prête

Dans `db`, ajoutez (TODO C2) :

```yaml
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U cordee -d cordee"]
      interval: 5s
      timeout: 3s
      retries: 10
      start_period: 5s
```

Dans `api`, remplacez `depends_on` par :

```yaml
    depends_on:
      db:
        condition: service_healthy
    restart: unless-stopped
```

```bash
docker compose down
docker compose up -d
docker compose ps
```

Attendu : `db` passe à `(healthy)`, puis `api` démarre, puis `front`. Ouvrez <http://localhost:8080> : les refuges s'affichent, le pied de page indique `site 1.0 · API 1.0 · servi par <identifiant du conteneur>`. Faites une réservation.

### C3. Garder les réservations

```bash
docker compose down
docker compose up -d
sleep 10
curl -s http://localhost:8080/api/reservations
```

Résultat : `[]`. Votre réservation a disparu avec le conteneur `db`. Ajoutez le volume (TODO C3) :

```yaml
# dans db :
    volumes:
      - donnees-db:/var/lib/postgresql/data

# tout en bas du fichier :
volumes:
  donnees-db:
```

```bash
docker compose up -d
```

Refaites une réservation dans le navigateur, puis :

```bash
docker compose down
docker compose up -d
sleep 10
curl -s http://localhost:8080/api/reservations       # la réservation est là
docker volume ls | grep cordee                         # cordee_donnees-db
```

### C4. Deux réseaux : le site ne voit pas la base

Ajoutez `networks: [arriere]` à `db`, `networks: [arriere, avant]` à `api`, `networks: [avant]` à `front`, et en bas du fichier :

```yaml
networks:
  avant:
  arriere:
```

```bash
docker compose up -d
docker network ls | grep cordee
docker compose exec front wget -qO- -T 2 http://api:8000/healthz
docker compose exec front wget -qO- -T 2 http://db:5432/
```

Attendu : `{"statut":"ok"}` pour l'API, puis pour la base : `bad address 'db'`. Le site joint l'API, mais ne connaît même pas le nom de la base.

### C5. tmpfs et commandes du quotidien

Ajoutez à `api` :

```yaml
    tmpfs:
      - /tmp
```

```bash
docker compose up -d
docker compose ps
docker compose logs api --tail 3
docker compose exec db psql -U cordee -c 'SELECT count(*) FROM reservation;'
docker compose exec api sh -c 'df -h /tmp'
docker compose top api
```

Comparez votre fichier à la correction : `diff ~/cordee/solutions/03-compose/app/compose.yaml ~/cordee/app/compose.yaml`.

### C6. Ce que `down -v` fait

```bash
docker compose down -v
docker volume ls | grep cordee ; echo "plus de volume"
```

**Question 4** – Quelle commande a fait perdre les réservations de Cordée dans l'incident ? Quelle est la différence entre `down` et `down -v` ?

**Question 5** – Le mot de passe vaut `${DB_PASSWORD:-change-moi}`. D'où peut venir `DB_PASSWORD`, et que se passe-t-il si on le change après la première initialisation de la base ?

## Fin du TP

Relancez la stack pour le TP 04 :

```bash
cd ~/cordee/app && docker compose up -d
```

## Questions de fin

6. `depends_on` règle-t-il tous les problèmes de démarrage ? Que doit faire l'API si la base redémarre **pendant** la journée ?
7. Pourquoi l'API est-elle sur les deux réseaux ?

## Bonus

- `docker compose watch` et la clé `develop.watch` : reconstruire l'API automatiquement quand `app.py` change.
- `docker compose up -d --scale api=3` : pourquoi cela échouerait-il si l'API publiait un port avec `ports:` ?

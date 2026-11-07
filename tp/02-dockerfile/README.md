# TP 02 – Dockerfile et bonnes pratiques

| Durée | Branche | Correction |
|-------|---------|------------|
| 70 min (12h20 – 12h30, déjeuner, 13h30 – 14h30) | `tp-02-dockerfile` | `solutions/02-dockerfile/` (`README.md` et `app/…/Dockerfile`) |

Le déjeuner tombe après l'étape 1 : on reprend à l'étape 2 à 13h30.

## L'incident

> Mardi, 17h05. Karim corrige une faute de frappe dans l'API. Il relance le build : quatre minutes, et l'image fait plus d'un gigaoctet. Sophie, elle, a remarqué que le processus tourne en root. « Si quelqu'un trouve une faille dans Flask, il est root dans le conteneur. »

## Objectifs

- Mesurer ce que coûte un Dockerfile naïf : taille, temps de reconstruction, utilisateur.
- Écrire un Dockerfile multi-stage, non root, avec `.dockerignore`, `ARG` et `ENV`.
- Comprendre le cache de BuildKit et l'ordre des instructions.
- Distinguer `CMD` et `ENTRYPOINT`, `COPY` et `ADD`.

## Point de départ

```bash
cd ~/cordee
git fetch
git checkout tp-02-dockerfile
docker ps --filter name=registre        # le registre du TP 01 doit tourner
ls app/api                               # app.py, requirements.txt, Dockerfile.avant
```

Si le registre n'est pas là : `docker run -d --name registre --restart unless-stopped -p 5000:5000 mirror.gcr.io/library/registry:2`.

## Étapes

### 1. Le Dockerfile historique (10 min, avant le déjeuner)

```bash
cd ~/cordee/app/api
cat Dockerfile.avant
time docker build -f Dockerfile.avant -t cordee-api:avant .
```

Laissez le build se terminer (1 à 3 min). Notez le temps `real`.

### 2. Ce qu'il coûte (10 min)

```bash
docker image ls cordee-api
docker run --rm --entrypoint id cordee-api:avant
docker image history cordee-api:avant | head -8
```

**Question 1** – Quelle taille fait l'image ? Sous quel utilisateur tourne-t-elle ? Quelle est la couche la plus lourde, et d'où vient-elle ?

Modifiez une ligne de commentaire du code, puis reconstruisez :

```bash
sed -i '1s/.*/"""API de Cordée (modifiée) : réservation de nuitées dans les refuges de montagne./' app.py
time docker build -f Dockerfile.avant -t cordee-api:avant .
```

**Question 2** – Le `pip install` a-t-il été rejoué ? Pourquoi, alors que `requirements.txt` n'a pas changé ?

Remettez le fichier dans son état d'origine : `git checkout app.py`.

### 3. Le Dockerfile multi-stage (20 min)

```bash
cp ~/cordee/tp/02-dockerfile/api/Dockerfile ~/cordee/app/api/Dockerfile
cp ~/cordee/tp/02-dockerfile/api/.dockerignore ~/cordee/app/api/.dockerignore
```

Ouvrez `app/api/Dockerfile` (VS Code : `code ~/cordee`, ou `nano`) et complétez-le :

| TODO | Instruction(s) à écrire |
|------|-------------------------|
| 1 | `FROM mirror.gcr.io/library/python:3.13-slim AS construction` |
| (fourni) | décommentez les lignes `RUN python -m venv …` et `ENV PATH=…` |
| 2 | `COPY requirements.txt .` puis `RUN --mount=type=cache,target=/root/.cache/pip pip install -r requirements.txt` |
| 3 | `FROM mirror.gcr.io/library/python:3.13-slim` |
| (fourni) | décommentez `ARG APP_VERSION=dev` et le bloc `ENV` |
| 4 | `RUN useradd …` (la commande est dans le commentaire) |
| 5 | `WORKDIR /app`, `COPY --from=construction /opt/venv /opt/venv`, `COPY app.py .` |
| 6 | `USER 10001` et `EXPOSE 8000` |
| 7 | `ENTRYPOINT ["gunicorn"]` et `CMD ["--bind", "0.0.0.0:8000", "--workers", "2", "--preload", "--access-logfile", "-", "app:app"]` |

Supprimez enfin les deux lignes `a-completer` en tête du fichier. Tant qu'elles sont là, le build échoue avec le message `TODO : complétez app/api/Dockerfile`.

Complétez aussi `app/api/.dockerignore`, une entrée par ligne :

```
__pycache__/
*.pyc
.venv/
.env
Dockerfile*
.dockerignore
```

### 4. Construire et comparer (10 min)

```bash
cd ~/cordee/app/api
time docker build --build-arg APP_VERSION=1.0 -t cordee-api:1.0 .
docker image ls cordee-api
docker run --rm --entrypoint id cordee-api:1.0
docker run --rm --entrypoint sh cordee-api:1.0 -c 'echo $APP_VERSION; ls /app'
```

Attendu : une image d'environ 150 à 200 Mo (contre plus d'1 Go), `uid=10001(cordee)`, `1.0`, et seulement `app.py` dans `/app`.

Si le build échoue, lisez la ligne `ERROR` : elle donne l'instruction fautive et son numéro de ligne.

### 5. Le cache de BuildKit (8 min)

Même modification du code qu'à l'étape 2 :

```bash
sed -i '1s/.*/"""API de Cordée (modifiée) : réservation de nuitées dans les refuges de montagne./' app.py
time docker build --progress=plain --build-arg APP_VERSION=1.0 -t cordee-api:1.0 . 2>&1 | grep -E 'CACHED|DONE|^real' | head -20
git checkout app.py
```

Les étapes `COPY requirements.txt` et `RUN … pip install` affichent `CACHED` : seul `COPY app.py` est rejoué. Le build prend quelques secondes.

**Question 3** – Quelles sont les deux raisons pour lesquelles ce Dockerfile se reconstruit vite ? Que fait `--mount=type=cache` de plus que le cache des couches ?

### 6. Lancer l'image : CMD et ENTRYPOINT (7 min)

```bash
docker run --rm cordee-api:1.0
```

L'API démarre, tente trois fois de joindre la base, puis s'arrête : chaque ligne est un log JSON (`"niveau": "ERROR"`, `"message": "base injoignable (essai 1/3) …"`). C'est voulu : il n'y a pas encore de base (TP 03).

```bash
docker run --rm cordee-api:1.0 --version                                   # les arguments remplacent CMD
docker run --rm --entrypoint python cordee-api:1.0 -c 'import flask; print(flask.__version__)'
```

**Question 4** – Que s'est-il passé avec `--version` ? Quel est le rôle respectif d'`ENTRYPOINT` et de `CMD` ? Pourquoi la forme JSON (`["…", "…"]`) plutôt que la forme texte du `Dockerfile.avant` ?

**Question 5** – `COPY` ou `ADD` : lequel utiliser pour copier `app.py`, et que fait `ADD` de plus ?

### 7. BuildKit (3 min)

```bash
docker buildx ls
docker buildx du | tail -3
```

**Question 6** – Depuis quelle version de Docker Engine BuildKit est-il le builder par défaut ? Citez deux choses qu'il fait mieux que l'ancien builder.

### 8. L'image du site (7 min)

```bash
cp ~/cordee/tp/02-dockerfile/front/Dockerfile ~/cordee/app/front/Dockerfile
printf 'Dockerfile*\n.dockerignore\n' > ~/cordee/app/front/.dockerignore
```

Complétez `app/front/Dockerfile` :

| TODO | Instruction(s) à écrire |
|------|-------------------------|
| 1 | `FROM ghcr.io/nginx/nginx-unprivileged:1.28-alpine` |
| (fourni) | décommentez `ARG APP_VERSION=dev` |
| 2 | `COPY default.conf /etc/nginx/conf.d/default.conf` et `COPY html/ /usr/share/nginx/html/` |
| (fourni) | décommentez `USER root` et le `RUN echo …` |
| 3 | `USER 101` et `EXPOSE 8080` |

Supprimez les deux lignes `a-completer`, puis :

```bash
cd ~/cordee/app/front
docker build --build-arg APP_VERSION=1.0 -t cordee-front:1.0 .
docker run --rm --entrypoint cat cordee-front:1.0 /usr/share/nginx/html/version.txt      # 1.0
```

> Ne lancez pas encore ce conteneur seul : sa configuration nginx renvoie `/api/` vers un hôte `api`, qui n'existe pas encore. nginx refuserait de démarrer (`host not found in upstream "api"`). Ce sera réglé au TP 03.

### 9. Pousser dans le registre (5 min)

```bash
for image in cordee-api cordee-front; do
  docker tag $image:1.0 localhost:5000/cordee/$image:1.0
  docker push localhost:5000/cordee/$image:1.0
done
curl -s http://localhost:5000/v2/_catalog
```

Attendu : `{"repositories":["cordee/cordee-api","cordee/cordee-front","cordee/nginx"]}`.

## Questions de fin

7. Pourquoi `.dockerignore` compte-t-il, même pour un petit projet ? Donnez un exemple de fuite qu'il évite.
8. Dans la seconde étape, pourquoi n'a-t-on pas besoin de `pip` ni des fichiers de construction ?
9. `ARG` ou `ENV` : lequel est encore visible dans le conteneur au moment où il tourne ?

## Bonus

- **Distroless** : une seconde étape `FROM gcr.io/distroless/python3-debian12` n'a ni shell ni gestionnaire de paquets. Qu'est-ce qui changerait pour copier l'environnement virtuel (version de Python) et pour déboguer (`docker exec … sh`) ?
- **Alpine** : `python:3.13-alpine` est plus petite que `slim`. Quel est le risque avec des dépendances compilées (glibc contre musl) ?
- `docker build --target construction -t cordee-api:construction .` : à quoi sert `--target` ?

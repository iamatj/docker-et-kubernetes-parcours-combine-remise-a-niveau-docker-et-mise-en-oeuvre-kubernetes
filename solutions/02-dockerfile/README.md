# Correction du TP 02 – Dockerfile et bonnes pratiques

Les fichiers corrigés sont aux mêmes chemins qu'à la racine : `solutions/02-dockerfile/app/api/Dockerfile`, `app/api/.dockerignore`, `app/front/Dockerfile`, `app/front/.dockerignore`. Pour comparer : `diff solutions/02-dockerfile/app/api/Dockerfile app/api/Dockerfile`. Pour repartir de la correction : `cp -r solutions/02-dockerfile/app/. app/`.

**1.** Plus d'1 Go (l'image `python:3.13` complète embarque un Debian avec compilateurs et en-têtes). Elle tourne en `root` (`uid=0`) car aucun `USER` n'est donné. La couche la plus lourde est celle de l'image de base (`FROM python:3.13`), loin devant le `pip install`.

**2.** Oui. `COPY . .` est placé **avant** `pip install` : toute modification d'un fichier du dossier (même un commentaire dans `app.py`) invalide la couche du `COPY`, donc toutes les suivantes, dont le `pip install`. Le cache est séquentiel : une instruction invalidée invalide la suite.

**3.** (1) L'ordre : on copie d'abord `requirements.txt` seul et on installe, puis on copie le code, qui change souvent. Les couches de dépendances restent en cache tant que `requirements.txt` ne change pas. (2) Le `.dockerignore` réduit le contexte envoyé et évite qu'un fichier inutile (cache Python) invalide une couche. `--mount=type=cache` garde le cache de téléchargement de pip **entre** les builds, même quand la couche est invalidée (une nouvelle dépendance ne retélécharge pas les autres), sans que ce cache entre dans l'image.

**4.** `--version` a remplacé le `CMD` : la commande lancée est `gunicorn --version`. `ENTRYPOINT` fixe le programme, `CMD` donne ses arguments par défaut, que l'on remplace en ajoutant des arguments à `docker run` ; `--entrypoint` remplace le programme lui-même. La forme JSON lance le programme directement (PID 1, il reçoit le signal d'arrêt de `docker stop` et s'arrête proprement) ; la forme texte passe par `/bin/sh -c`, qui ne retransmet pas les signaux : le conteneur attend 10 s puis est tué.

**5.** `COPY`. `ADD` sait en plus décompresser une archive locale et télécharger une URL ; ces effets implicites sont une source de surprises (et de failles), donc on réserve `ADD` à ces usages, explicitement.

**6.** Depuis Docker Engine 23 (février 2023). Il construit en parallèle les étapes indépendantes, ne construit que les étapes nécessaires à la cible, a un cache plus fin (et exportable vers un registre en CI), et ajoute les `RUN --mount` (cache, secrets, SSH) : un secret de build ne finit pas dans une couche.

**7.** Le contexte de build part entièrement au daemon : sans `.dockerignore`, un `COPY . .` embarque `.env`, des clés, `.git`, des caches. Exemple : un fichier `.env` avec le mot de passe de la base copié dans l'image et publié sur un registre public. Il accélère aussi les builds et stabilise le cache.

**8.** La seconde étape n'a besoin que du résultat : l'environnement virtuel déjà rempli et le code. Ce qui a servi à construire (cache de pip, fichiers temporaires, éventuels compilateurs) reste dans l'étape `construction`, qui n'est pas livrée. Moins de fichiers, c'est une image plus petite et une surface d'attaque plus faible (TP 04).

**9.** `ENV`. `ARG` n'existe que pendant le build ; on le recopie dans un `ENV` (`ENV APP_VERSION=$APP_VERSION`) pour que l'API puisse lire sa version au démarrage. Un `ARG` n'est pas un endroit pour un secret : sa valeur reste visible dans `docker image history`.

**Bonus.** Distroless : l'image `python3-debian12` contient Python 3.11, il faut donc construire l'environnement virtuel avec la même version (`python:3.11-slim-bookworm`) ; pas de shell, donc pas de `docker exec … sh` : on débogue avec une image `:debug` ou un conteneur éphémère à côté. Alpine utilise musl au lieu de glibc : certaines roues binaires (wheels) n'existent pas pour musl, pip compile alors depuis les sources (il faut un compilateur, le build est long) et le comportement peut différer. `--target construction` construit seulement jusqu'à cette étape : utile pour déboguer une étape, ou pour une image de tests.

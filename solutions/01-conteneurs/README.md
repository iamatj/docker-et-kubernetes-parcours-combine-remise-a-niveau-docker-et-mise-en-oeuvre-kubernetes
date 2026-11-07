# Correction du TP 01 – Conteneurs, images et registres

**1.** `latest` n'est qu'un tag par défaut, déplacé à chaque nouvelle publication : deux `docker pull` à une semaine d'intervalle peuvent donner deux images différentes, un rollback ne sait pas à quoi revenir, et on ne sait jamais ce qui tourne. En production : un tag de version précis (`1.28-alpine`), et pour une garantie totale le digest (`@sha256:…`).

**2.** Une dizaine de couches selon la version. Les lignes à `0B` correspondent à des instructions qui ne modifient que la **configuration** de l'image (`ENV`, `EXPOSE`, `USER`, `CMD`, `ENTRYPOINT`, `LABEL`, `STOPSIGNAL`) : elles n'ajoutent pas de fichiers, donc pas de couche de contenu. L'image fait tourner nginx sous l'utilisateur `101` (nginx), sur le port `8080/tcp` ; c'est ce qui la distingue de l'image `nginx` officielle (root, port 80).

**3.** Non : `docker exec` lance un **processus supplémentaire** dans le conteneur existant (mêmes namespaces, même système de fichiers). En sortant du shell, seul ce processus se termine ; le conteneur continue, car sa vie est liée à son processus principal (PID 1), nginx.

**4.** Après `stop` / `start` : oui, le site est là. Le conteneur a gardé sa couche en écriture, où `docker cp` avait écrit. Après `rm` puis `run` : non (`grep -c` affiche 0), un nouveau conteneur repart de l'image. Les fichiers d'un conteneur sont jetables : ce qui doit durer va **dans l'image** (le site : TP 02, Dockerfile du front) ou **dans un volume** (les données : TP 03).

**5.** Les deux redémarrent le conteneur s'il s'arrête de lui-même. Après un redémarrage du daemon ou du serveur, `always` relance aussi un conteneur qu'on avait arrêté volontairement avec `docker stop`, `unless-stopped` le laisse arrêté. Autres valeurs : `no` (défaut) et `on-failure[:N]` (seulement si le code de sortie n'est pas 0).

**6.** Mémoire : la limite est dure. Au-delà, le noyau tue un processus du conteneur (OOM killer) ; si c'est le PID 1, le conteneur s'arrête et `State.OOMKilled` vaut `true`. CPU : la limite est un plafond de temps de calcul. Au-delà, le conteneur est ralenti (throttling), jamais tué. Les mêmes notions reviendront dans Kubernetes (`resources.limits`) au TP 06.

**7.** Non : `docker tag` ajoute un **nom** à la même image (même `IMAGE ID`). Le push envoie chaque couche que le registre ne possède pas encore ; il est vide, donc toutes. Un second push n'enverrait plus rien (`Layer already exists`).

**8.** Le nom de l'image doit commencer par le registre et le compte (`docker.io/<compte>/cordee-api:1.0`, `ghcr.io/<compte>/cordee-api:1.0`), puis on s'authentifie avec `docker login <registre>` (pour ghcr.io : un jeton GitHub avec le droit `write:packages`). C'est ce que fait le workflow `.github/workflows/images.yml` du dépôt pour publier les images utilisées dans Kubernetes.

**9.** `docker inspect <conteneur> --format '{{.Image}}'` donne l'identifiant de l'image ; `docker image inspect <image> --format '{{.RepoDigests}}'` donne le digest du registre. `docker ps` n'affiche que le nom utilisé au lancement.

**10.** `docker inspect vitrine` : image, commande, variables d'environnement, ports, volumes, limites, politique de redémarrage, date de démarrage, nombre de redémarrages. Mieux encore : on n'aura plus besoin de chercher, puisque la commande complète sera écrite dans un fichier versionné (Compose au TP 03, manifests Kubernetes ensuite).

**Bonus.** Avec 20 Mo, PostgreSQL est tué pendant son initialisation : `Exited (137)` et `OOMKilled` à `true` (137 = 128 + 9, signal KILL). `docker events` montre la séquence `kill`, `die`, `start` du conteneur `vitrine`.

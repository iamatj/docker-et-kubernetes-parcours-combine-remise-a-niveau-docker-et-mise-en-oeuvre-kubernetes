# Correction du TP 03 – Volumes, réseaux et Docker Compose V2

Le fichier complet est `solutions/03-compose/app/compose.yaml`. Pour comparer : `diff solutions/03-compose/app/compose.yaml app/compose.yaml`.

**1.** Dans `/var/lib/docker/volumes/essai-db/_data` sur le poste, géré par Docker et indépendant de tout conteneur. Sans `-v`, l'image `postgres` déclare un volume (`VOLUME /var/lib/postgresql/data`) : Docker aurait créé un volume **anonyme** (un identifiant hexadécimal), que `pg2` n'aurait pas retrouvé ; et un `docker rm -v` ou un `docker volume prune` l'aurait supprimé.

**2.** Bind mount : partager un dossier du poste, connu et modifiable à la main (le code en développement, un fichier de configuration). Volume nommé : des données que l'application possède (base de données), gérées par Docker, portables d'un hôte à l'autre, sauvegardables. tmpfs : des fichiers temporaires en mémoire, qui ne doivent jamais toucher le disque (fichiers de travail, secrets temporaires) ; ils disparaissent à l'arrêt.

**3.** En `host`, le conteneur partage la pile réseau du poste : il voit toutes ses interfaces, et un service qui écoute sur 8000 écoute directement sur le 8000 du poste ; il n'y a rien à « publier », donc `-p` est ignoré. En `none`, il n'a que l'interface `lo` : aucun accès réseau (utile pour un traitement de fichiers isolé).

**4.** Un `docker rm` du conteneur PostgreSQL sans volume nommé : les données étaient dans la couche en écriture (ou un volume anonyme) du conteneur. `docker compose down` supprime conteneurs et réseaux mais garde les volumes nommés ; `down -v` supprime aussi les volumes déclarés dans le fichier, donc les données. À ne jamais taper sur un serveur.

**5.** De l'environnement du shell (`DB_PASSWORD=… docker compose up -d`) ou d'un fichier `.env` à côté de `compose.yaml`, lu automatiquement (et à mettre dans `.gitignore`). L'image `postgres` n'utilise `POSTGRES_PASSWORD` qu'à la **première** initialisation, quand le volume est vide. Changer la variable ensuite ne change pas le mot de passe en base : l'API, qui reçoit le nouveau, ne peut plus se connecter. Il faut changer le mot de passe dans PostgreSQL (`ALTER USER`), ou repartir d'un volume vide.

**6.** Non. `depends_on` ne joue qu'au démarrage, et seulement sur un hôte. Si la base redémarre en cours de journée, l'API doit se reconnecter d'elle-même (ici, chaque requête ouvre une nouvelle connexion, et `/readyz` répond 503 tant que la base est absente). Kubernetes ne connaît même pas `depends_on` : chaque composant doit tolérer l'absence des autres, et les sondes (TP 08) disent quand il est prêt.

**7.** L'API est le seul composant qui doit parler aux deux : le site l'appelle (réseau `avant`), elle appelle la base (réseau `arriere`). Le site n'a aucune raison de joindre la base : s'il est compromis, il ne peut pas l'attaquer directement. C'est la même idée que les Network Policies du TP 10.

**Bonus.** `docker compose watch` suit les fichiers listés dans `develop.watch` (actions `sync`, `rebuild`, `sync+restart`) et met à jour le service sans relancer toute la stack. `--scale api=3` crée trois conteneurs ; avec `ports: ["8000:8000"]`, les trois voudraient le même port du poste et seul le premier démarrerait. Sans port publié, c'est possible : le DNS de Compose répartit les requêtes sur les trois.

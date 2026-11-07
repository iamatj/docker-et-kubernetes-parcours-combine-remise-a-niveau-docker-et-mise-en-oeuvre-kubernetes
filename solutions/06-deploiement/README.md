# Correction du TP 06 – Déployer Cordée sur Kubernetes

Les manifests corrigés sont dans `solutions/06-deploiement/k8s/`, aux mêmes noms que dans `k8s/`. Attention : sur cette branche, `k8s/` n'existe pas avant le TP, c'est vous qui le créez. Pour comparer : `diff -r solutions/06-deploiement/k8s k8s`. Pour repartir de la correction : `cp solutions/06-deploiement/k8s/* k8s/ && kubectl apply -f k8s/`.

**1.** (1) `image` indentée d'un espace de trop : erreur de **syntaxe** YAML (`mapping values are not allowed`), le fichier n'est même pas lisible. (2) `containerPort: "8080"` : une chaîne là où le schéma attend un entier. (3) `value: yes` : en YAML 1.1, `yes`, `no`, `on`, `off` sont des booléens ; une variable d'environnement doit être une chaîne, il faut `"yes"`. (4) `value: 3` : un entier, il faut `"3"`. Les trois dernières sont des erreurs de **schéma** : le YAML est valide, mais l'objet ne respecte pas l'API Kubernetes, d'où l'intérêt de `--dry-run=server`. Correction :

```yaml
spec:
  containers:
  - name: essai
    image: ghcr.io/nginx/nginx-unprivileged:1.28-alpine
    ports:
      - containerPort: 8080
    env:
      - name: MODE
        value: "yes"
      - name: NIVEAU
        value: "3"
```

**2.** Le mot de passe de la base est écrit en clair dans un fichier versionné dans Git (TP 08 : Secret). Les données sont dans un `emptyDir`, qui disparaît avec le pod (TP 09 : volume persistant). On peut ajouter : une seule instance de la base, sans sonde ni limite de ressources.

**3.** Un Service NodePort ouvre le même port (30080) sur **tous** les nœuds. `kube-proxy`, présent sur chaque nœud, y programme des règles qui renvoient le trafic vers un pod `front`, où qu'il soit. Le nœud qui reçoit la requête n'a pas besoin de faire tourner le site.

**4.** Ni l'un ni l'autre n'est idéal pour les clients : un NodePort est un port élevé sur l'IP d'un nœud (si ce nœud tombe, l'adresse ne répond plus) ; on lui préférera un LoadBalancer (TP 07) ou un Ingress (TP 11). Le port-forward est l'outil du développeur : temporaire, lié à sa session kubectl et à ses droits, il traverse l'API Server et n'ouvre rien sur le réseau.

**5.** 2 replicas : `kubectl apply` remet l'état décrit dans le fichier (`replicas: 2`), qui fait foi. Le `kubectl scale` était une modification impérative, perdue au premier `apply`. Pour garder 3 API, on l'écrit dans le fichier (dans Git), puis on l'applique : `replicas: 3` dans `k8s/20-api.yaml`.

**6.** Perdue : le nouveau pod PostgreSQL a reçu un `emptyDir` neuf, donc une base vide. L'API l'a remarqué à la requête suivante (`tables absentes : la base a été recréée vide`) et a recréé les tables et les refuges : le site fonctionne, sans aucune réservation. C'est exactement l'incident du TP 09.

**7.** L'API Server refuse le Deployment : `selector does not match template labels`. Le Deployment ne saurait pas quels pods sont les siens. Et une fois créé, le `selector` ne peut plus être modifié (champ immuable) : il faut le choisir avec soin dès le départ.

**8.** Par le DNS du cluster (CoreDNS) : chaque Service reçoit un nom `<service>.<namespace>.svc.cluster.local`, et un pod du namespace `cordee` peut l'abréger en `postgres`. Le nom donne l'IP virtuelle (ClusterIP) du Service, que kube-proxy redirige vers le pod de la base. On l'étudiera au TP 11.

**Bonus.** `custom-columns` permet de choisir ses colonnes. `kubectl diff` compare le fichier à l'objet du cluster et affiche ce qui changerait, comme un `git diff`.

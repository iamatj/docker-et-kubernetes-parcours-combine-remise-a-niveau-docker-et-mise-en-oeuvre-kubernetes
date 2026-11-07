# Correction du TP 08 – Configuration, sondes et diagnostic

Fichiers corrigés : `solutions/08-configuration/k8s/` (`01-configmap.yaml`, `02-secret.yaml`, `10-postgres.yaml`, `20-api.yaml`, `30-front.yaml`). Sur cette branche, `k8s/` est l'état de **départ** : `diff -r solutions/08-configuration/k8s k8s`. Copiez les fichiers étape par étape plutôt que d'un coup, sinon vous ne verrez pas les échecs que le TP veut montrer.

**1.** Une **étiquette** sert à sélectionner : Services, Deployments, Network Policies et `kubectl -l` choisissent leurs objets par étiquettes ; elle est courte et indexée. Une **annotation** sert à décrire : texte libre, non sélectionnable, lu par des humains ou des outils (`kubernetes.io/change-cause`, le responsable, une configuration d'Ingress). La quarantaine marche parce que le Service et le ReplicaSet ne connaissent leurs pods que par l'étiquette `app=api` : en la changeant, le pod sort des endpoints (plus de trafic) et du ReplicaSet (qui en recrée un), mais reste vivant pour l'enquête.

**2.** Non : `data` est encodé en **base64**, ce n'est pas un chiffrement (`base64 -d` le relit). Dans le cluster, le peut quiconque a le droit `get` sur les Secrets du namespace (RBAC, TP 10), quiconque peut créer un pod qui monte ce Secret, et quiconque lit etcd, où les Secrets ne sont pas chiffrés par défaut (il faut activer le chiffrement au repos). Ce fichier ne devrait pas être dans Git en production : on utilise Sealed Secrets (un Secret chiffré pour le cluster, qu'on peut commiter), External Secrets (le mot de passe reste dans un coffre : Vault, Azure Key Vault, AWS Secrets Manager) ou SOPS. Pour la formation, on le garde dans le dépôt pour que chacun reparte d'un état complet.

**3.** Les variables d'environnement sont lues **au démarrage** du conteneur ; changer la ConfigMap ne touche pas les processus déjà lancés. `rollout restart` ajoute une annotation horodatée au gabarit, ce qui relance une mise à jour progressive. Automatiquement : mettre une empreinte de la ConfigMap en annotation du gabarit (c'est ce que fera le chart Helm du TP 12 avec `checksum/configuration`), ou un outil comme Reloader. Une ConfigMap montée en **fichier** se met à jour seule (au bout de quelques dizaines de secondes), mais l'application doit relire le fichier.

**4.**

| Sonde | Question posée | En cas d'échec |
|-------|----------------|----------------|
| `startupProbe` | « as-tu fini de démarrer ? » ; tant qu'elle n'a pas réussi, les deux autres ne sont pas testées | au bout de `failureThreshold × periodSeconds` (ici 60 s), le conteneur est tué et redémarré |
| `readinessProbe` | « peux-tu recevoir du trafic maintenant ? » (`/readyz` vérifie la base) | le pod sort des endpoints du Service, sans redémarrer ; il y revient quand elle repasse |
| `livenessProbe` | « es-tu encore vivant ? » (`/healthz`, sans dépendance) | le conteneur est tué et redémarré |

Piège classique : mettre la base dans la liveness probe. Si la base tombe, toutes les API redémarreraient en boucle sans rien réparer.

**5.** Le nouveau pod n'est jamais devenu prêt (la startupProbe échoue, puis il redémarre en boucle : `CrashLoopBackOff`) ; avec `maxUnavailable: 0`, les anciens pods ont continué à servir. La livraison, elle, est bloquée : `rollout status` expire, et au bout de `progressDeadlineSeconds` le Deployment passe à `Progressing=False` (`ProgressDeadlineExceeded`). Pour être prévenu : une chaîne de livraison qui attend `rollout status` et échoue, ou une alerte de supervision sur `kube_deployment_status_condition` ou sur les redémarrages de pods.

**6.**

| Application | Symptôme | Commande qui donne la cause | Cause | Correction |
|-------------|----------|-----------------------------|-------|------------|
| `billetterie` | `ErrImagePull` puis `ImagePullBackOff` | `describe pod` (Events : `not found`) | le tag `1.28-alpinee` (faute de frappe) n'existe pas | `kubectl -n diagnostic set image deployment/billetterie billetterie=ghcr.io/nginx/nginx-unprivileged:1.28-alpine` |
| `meteo` | `CreateContainerConfigError` | `describe pod` (Events : `couldn't find key CLE_API in Secret diagnostic/meteo`) | le Secret contient `CLE`, le pod demande `CLE_API` | `kubectl -n diagnostic edit deployment meteo` : `key: CLE` |
| `vitrine` | pods `Running` et prêts, mais le Service ne répond pas (`wget` : délai dépassé ou connexion refusée) | `get endpoints vitrine` (aucune adresse) | le `selector` du Service (`app: vitrin`) ne correspond pas aux pods (`app: vitrine`) | `kubectl -n diagnostic edit service vitrine` : `app: vitrine` |
| `statistiques` | `CrashLoopBackOff` | `logs <pod>` (ou `--previous`) : `superuser password is not specified` | il manque `POSTGRES_PASSWORD` | `kubectl -n diagnostic set env deployment/statistiques POSTGRES_PASSWORD=essai` |

La méthode : on part de l'état (`get`), on lit ce que Kubernetes a fait (`describe`, `events`), puis ce que l'application dit (`logs`). Une erreur **avant** le démarrage du conteneur (image, configuration) se lit dans les événements ; une erreur **de** l'application, dans les logs ; une erreur **de câblage**, dans les endpoints.

**7.** Un DaemonSet fait tourner **un pod par nœud** (ou par nœud sélectionné), et en ajoute un quand un nœud rejoint le cluster : agents réseau (Calico, kube-proxy), collecteurs de logs (Fluent Bit), agents de supervision (node-exporter). Cordée en écrirait un pour collecter les logs JSON de ses API sur chaque nœud, pas pour son application.

**8.** Une **anti-affinité** de pods (`affinity.podAntiAffinity`, `requiredDuringSchedulingIgnoredDuringExecution` sur `topologyKey: kubernetes.io/hostname` et l'étiquette `app: api`) : le scheduler refuse de placer deux pods `api` sur le même nœud. Avec 3 replicas et 2 workers, le troisième resterait `Pending` : on préfère souvent la version « preferred », ou `topologySpreadConstraints` pour répartir au mieux.

**Bonus.** Une ConfigMap montée en volume est mise à jour dans le pod au bout d'une minute environ (sauf avec `subPath`). Après `set env` puis `undo`, la variable `DB_HOST` a disparu du gabarit : on est revenu à la révision précédente.

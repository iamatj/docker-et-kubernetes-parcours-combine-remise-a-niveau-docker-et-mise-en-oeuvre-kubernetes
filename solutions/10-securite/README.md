# Correction du TP 10 – Sécuriser le cluster

Fichiers corrigés : `solutions/10-securite/k8s/` (`00-namespace.yaml`, `05-serviceaccounts.yaml`, `20-api.yaml`, `30-front.yaml`, `securite/00-equipe.yaml`, `securite/10-rbac.yaml`, `securite/20-networkpolicies.yaml`). Comparer : `diff -r solutions/10-securite/k8s k8s`. Appliquer : `kubectl apply -R -f k8s/`.

**Tableau de l'étape A3**

| Action | karim | sophie | lea |
|--------|-------|--------|-----|
| `list pods -n cordee` | oui | oui | oui |
| `get secrets -n cordee` | non | non | oui |
| `patch deployments -n cordee` | oui | non | oui |
| `delete deployments -n cordee` | non | non | oui |
| `list pods -n kube-system` | non | oui | oui |
| `delete pods -n cordee` | non | oui | oui |
| `update deployments/scale -n cordee` | non | oui | oui |
| `create clusterrolebindings` | non | non | oui |

**1.** Non dans les deux cas : ni `developpeur` ni `operateur` n'ont le verbe `delete` sur les Deployments. Sophie peut supprimer un **pod** (il sera recréé par son ReplicaSet), pas l'application. Un Role vaut pour un seul namespace (Karim travaille sur `cordee`) ; un ClusterRole lié par un ClusterRoleBinding vaut pour tout le cluster, et pour des ressources sans namespace comme les nœuds et les PV (Sophie exploite tout le cluster). Un ClusterRole peut aussi être lié par un simple RoleBinding, pour le réutiliser dans un seul namespace.

**2.** Le jeton est un JWT signé par la clé des ServiceAccounts du cluster ; l'API Server vérifie sa signature, son audience et sa date d'expiration à chaque requête (`kubectl create token` ne stocke rien). À l'expiration, chaque commande répond `Unauthorized` : il faut en demander un autre. Des jetons courts limitent les dégâts d'une fuite ; le rôle, lui, se retire en supprimant le RoleBinding.

**3.** Quand le programme du pod appelle lui-même l'API Kubernetes : un contrôleur, un opérateur, un outil de déploiement. Sur le lab : Headlamp (lire tout le cluster), MetalLB (lire les Services, écrire leur statut), Traefik (lire les Ingress, les HTTPRoute et les Services), Calico. Ni l'API ni le site de Cordée n'en ont besoin : pas de jeton.

**4.** Oui : le trafic qui vient du nœud où tourne le pod (le kubelet et ses sondes) est toujours autorisé. Le DNS aussi : nos politiques ne restreignent que l'**entrée** (`Ingress`) des pods de `cordee` ; la sortie du pirate vers CoreDNS n'est pas filtrée, et l'entrée de CoreDNS (dans `kube-system`) non plus.

**5.** Il est traité comme le site et peut joindre l'API : les Network Policies font confiance aux étiquettes. Ce qui l'en empêche : RBAC (sans le droit `create pods` dans `cordee`, pas de pirate, d'où le Role de Karim qui ne permet pas de créer de pods), des politiques qui combinent étiquettes et namespace, ou une identité forte entre services (maillage de services, mTLS).

**6.** L'image devient un système de fichiers en lecture seule ; les programmes qui ont besoin d'écrire (gunicorn pour ses fichiers de travail, nginx pour son PID et ses fichiers temporaires) écrivent dans un `emptyDir` monté sur `/tmp`. Face à une faille, l'attaquant ne peut ni modifier le code de l'application, ni déposer un outil dans le système, ni changer la configuration ; ajouté à `runAsNonRoot`, `drop ALL` et `allowPrivilegeEscalation: false`, il n'a presque aucun levier.

**7.** (1) Le fichier d'administration distribué à tous « pour regarder » (l'incident) : un compte par personne, des rôles adaptés, l'administration réservée à très peu. (2) Le fichier commité dans un dépôt ou copié dans une image : `.gitignore`, scan de secrets, jamais de `kubeconfig` dans une image. (3) Le poste d'un administrateur compromis : jetons courts (OIDC, `kubelogin`), MFA, révocation par l'annuaire, et pas de certificat client sans date d'expiration.

**8.** RBAC protège l'**API Kubernetes** : qui peut lire ou modifier quels objets. Les Network Policies protègent le **réseau entre pods** : qui peut parler à qui, même sans aucun droit RBAC. Le SecurityContext (et Pod Security Admission) protège le **nœud et le conteneur** : ce qu'un processus compromis peut faire une fois dedans. Ce sont trois couches indépendantes : il faut les trois.

**Bonus.** Une politique `Egress` sur `tier: back` doit autoriser la base (`tier: donnees`, 5432) **et** le DNS (pods `k8s-app: kube-dns` du namespace `kube-system`, port 53 en UDP et TCP), sinon l'API ne résout plus `postgres`. Le ServiceAccount `default` n'a que les droits de découverte (`selfsubjectaccessreviews`, `selfsubjectrulesreviews`, URL non-ressource `/api`, `/version`…).

# TP 10 – Sécuriser le cluster

| Durée | Branche | Correction |
|-------|---------|------------|
| 90 min (11h00 – 12h30) | `tp-10-securite` | `solutions/10-securite/` (`README.md` et `k8s/`) |

## L'incident

> Jeudi, 15h20. Un stagiaire, à qui on avait donné le `kubeconfig` d'administration « pour regarder », a supprimé le Deployment de l'API en voulant nettoyer son namespace de test. Le soir même, un audit montre qu'un pod quelconque du cluster pouvait se connecter directement à PostgreSQL. Léa : « Chacun ses droits, et la base ne parle qu'à l'API. »

## Objectifs

- Donner à chaque profil (développeur, opérateur, administratrice) les droits dont il a besoin, et pas plus : Role, ClusterRole, RoleBinding, ClusterRoleBinding.
- Utiliser une identité réelle, avec un jeton, et vérifier ses droits.
- Donner aux pods leur propre ServiceAccount, sans jeton inutile.
- Segmenter le trafic entre pods avec des Network Policies.
- Durcir les conteneurs avec un SecurityContext et Pod Security Admission.

## Point de départ

```bash
cd ~/cordee
git fetch
git stash -u
git checkout tp-10-securite
kubectl -n cordee delete deployment postgres --ignore-not-found   # si la base est encore un Deployment (TP 09 non terminé)
kubectl apply -f k8s/
kubectl -n cordee rollout status statefulset postgres
kubectl -n cordee rollout status deployment api
curl -s http://192.168.56.201/api/info | jq -r .version
```

Si vous n'aviez pas fini le TP 09, la base est neuve (un nouveau volume) : l'API recrée les tables, sans réservations.

## Partie A – RBAC (35 min)

### A1. Les identités de l'équipe

```bash
kubectl apply -f tp/10-securite/securite/00-equipe.yaml
kubectl -n equipe get serviceaccounts
kubectl auth can-i list pods -n cordee --as=system:serviceaccount:equipe:karim
```

Réponse : `no`. Une identité sans aucun rôle n'a aucun droit.

> Dans un vrai cluster, Karim, Sophie et Léa seraient des utilisateurs d'un annuaire (OIDC : Entra ID, Keycloak…), et les rôles seraient donnés à des groupes. Ici, on utilise des ServiceAccounts, dont on peut tirer des jetons sans annuaire.

### A2. Le rôle développeur

```bash
mkdir -p k8s/securite
cp tp/10-securite/securite/00-equipe.yaml tp/10-securite/securite/10-rbac.yaml k8s/securite/
```

Dans `k8s/securite/10-rbac.yaml`, remplacez `rules: []` du Role `developpeur` par :

```yaml
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log", "services", "endpoints", "configmaps", "events"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets", "statefulsets"]
    verbs: ["get", "list", "watch", "patch"]
```

Supprimez les lignes de commentaire `TODO`, puis lisez le reste du fichier : le RoleBinding de Karim, le ClusterRole `operateur` et le binding de Sophie, le binding de Léa sur `cluster-admin`.

```bash
kubectl apply -R -f k8s/securite/
```

### A3. Vérifier les droits sans se connecter

Complétez le tableau avec `oui` / `non`, en lançant pour chaque case `kubectl auth can-i <verbe> <ressource> -n <namespace> --as=system:serviceaccount:equipe:<nom>` :

| Action | karim | sophie | lea |
|--------|-------|--------|-----|
| `list pods -n cordee` | | | |
| `get secrets -n cordee` | | | |
| `patch deployments -n cordee` | | | |
| `delete deployments -n cordee` | | | |
| `list pods -n kube-system` | | | |
| `delete pods -n cordee` | | | |
| `update deployments/scale -n cordee` | | | |
| `create clusterrolebindings` | | | |

Exemple pour la première case :

```bash
kubectl auth can-i list pods -n cordee --as=system:serviceaccount:equipe:karim
```

Et la vue d'ensemble d'une identité :

```bash
kubectl auth can-i --list -n cordee --as=system:serviceaccount:equipe:karim
```

### A4. Se connecter vraiment, avec un jeton

```bash
JETON=$(kubectl -n equipe create token karim --duration=2h)
kubectl config set-credentials karim --token="$JETON"
kubectl config set-context karim --cluster=kubernetes --user=karim --namespace=cordee
kubectl --context=karim get pods
kubectl --context=karim logs deployment/api --tail 2
kubectl --context=karim get secrets
kubectl --context=karim delete deployment api
kubectl --context=karim rollout restart deployment api
```

Attendu : les pods et les logs s'affichent ; `get secrets` et `delete` échouent avec `Forbidden` ; le `rollout restart` (un `patch`) passe.

> Ne mettez jamais `--token=…` directement sur la ligne de commande avec le contexte d'administration : le certificat d'administrateur du `kubeconfig` serait utilisé en premier, et vous testeriez les droits de l'administrateur.

**Question 1** – Le stagiaire de l'incident aurait-il pu supprimer l'API avec le contexte `karim` ? Et avec celui de Sophie ? Pourquoi Sophie a-t-elle un ClusterRole et Karim un Role ?

**Question 2** – Le jeton est valable 2 heures. Où est-il vérifié, et que se passe-t-il à son expiration ?

## Partie B – L'identité des pods (10 min)

```bash
kubectl -n cordee exec deployment/api -- ls /var/run/secrets/kubernetes.io/serviceaccount/
kubectl -n cordee get pod -l app=api -o jsonpath='{.items[0].spec.serviceAccountName}{"\n"}'
```

Chaque pod reçoit par défaut le jeton du ServiceAccount `default` de son namespace : un attaquant qui prend la main sur l'API pourrait l'utiliser contre l'API Kubernetes.

```bash
cp tp/10-securite/05-serviceaccounts.yaml k8s/
kubectl apply -f k8s/05-serviceaccounts.yaml
```

Dans `k8s/20-api.yaml`, au niveau `spec` du **gabarit de pod** (juste au-dessus de `containers:`), ajoutez `serviceAccountName: api`. Dans `k8s/30-front.yaml`, `serviceAccountName: front`.

```bash
kubectl apply -f k8s/
kubectl -n cordee rollout status deployment api
kubectl -n cordee exec deployment/api -- ls /var/run/secrets/kubernetes.io/serviceaccount/
```

Attendu : `No such file or directory` : le ServiceAccount `api` a `automountServiceAccountToken: false`.

**Question 3** – Dans quel cas un pod a-t-il besoin d'un jeton et de droits RBAC ? Donnez un exemple tiré du lab.

## Partie C – Network Policies (25 min)

### C1. Aujourd'hui, tout le monde parle à tout le monde

```bash
kubectl -n cordee run pirate --rm -i --restart=Never --image=mirror.gcr.io/library/busybox:1.37 -- \
  sh -c 'wget -qO- -T 3 http://api:8000/api/info; echo; nc -w 3 postgres 5432 </dev/null && echo "base joignable"'
```

Le pod `pirate`, lancé par n'importe qui dans le namespace, joint l'API et la base.

### C2. Tout fermer

```bash
cp tp/10-securite/securite/20-networkpolicies.yaml k8s/securite/
kubectl apply -f k8s/securite/20-networkpolicies.yaml
kubectl -n cordee get networkpolicy
curl -s -m 5 -o /dev/null -w "%{http_code}\n" http://192.168.56.201/api/info
```

Le fichier contient `refus-par-defaut` (plus rien n'entre dans les pods de `cordee`) et `front-ouvert` (le site reste joignable sur 8080). Résultat : `504` ou `502`. Le site répond, mais il ne joint plus l'API : on vient de reproduire une panne.

> Les Network Policies ne marchent que si le plugin réseau (CNI) les applique. Calico le fait ; d'autres (flannel seul) les acceptent sans rien appliquer.

### C3. Ouvrir ce qui doit l'être

Ajoutez à la fin de `k8s/securite/20-networkpolicies.yaml`, à la place du commentaire `TODO` :

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-depuis-front
  namespace: cordee
spec:
  podSelector:
    matchLabels:
      tier: back
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - podSelector:
            matchLabels:
              tier: front
      ports:
        - port: 8000
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: postgres-depuis-api
  namespace: cordee
spec:
  podSelector:
    matchLabels:
      tier: donnees
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - podSelector:
            matchLabels:
              tier: back
      ports:
        - port: 5432
```

```bash
kubectl apply -f k8s/securite/20-networkpolicies.yaml
curl -s -m 5 http://192.168.56.201/api/refuges | jq length
kubectl -n cordee run pirate --rm -i --restart=Never --image=mirror.gcr.io/library/busybox:1.37 -- \
  sh -c 'wget -qO- -T 3 http://api:8000/api/info || echo "API fermée"; nc -w 3 postgres 5432 </dev/null && echo "base joignable" || echo "base fermée"'
kubectl -n cordee exec deployment/front -- wget -qO- -T 3 http://api:8000/healthz
```

Attendu : `5` refuges ; pour le pirate, `API fermée` et `base fermée` ; depuis le site, `{"statut":"ok"}`.

**Question 4** – Les sondes du kubelet (`/readyz`, `pg_isready`) passent-elles encore ? Pourquoi ? Et la résolution DNS du pirate, qui sort vers CoreDNS ?

**Question 5** – Le pirate lance un pod avec l'étiquette `tier: front`. Que se passe-t-il ? Qu'est-ce qui l'en empêcherait ?

## Partie D – Durcir les conteneurs (20 min)

### D1. Pod Security Admission

```bash
kubectl label --dry-run=server --overwrite namespace cordee pod-security.kubernetes.io/enforce=restricted
```

Kubernetes liste les pods qui seraient refusés en profil `restricted`, et pourquoi (`allowPrivilegeEscalation`, `capabilities`, `runAsNonRoot`, `seccompProfile`).

Ajoutez dans `k8s/00-namespace.yaml`, sous `labels:` :

```yaml
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/warn: restricted
```

```bash
kubectl apply -f k8s/00-namespace.yaml
```

### D2. Le SecurityContext de l'API

Dans `k8s/20-api.yaml`, au niveau `spec` du gabarit (à côté de `serviceAccountName: api`) :

```yaml
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        runAsGroup: 10001
        seccompProfile:
          type: RuntimeDefault
```

Dans le conteneur `api`, juste au-dessus de `resources:` :

```yaml
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
          volumeMounts:
            - name: tmp
              mountPath: /tmp
```

Et à la fin du gabarit, au même niveau que `containers:` :

```yaml
      volumes:
        - name: tmp
          emptyDir: {}
```

Faites de même pour `k8s/30-front.yaml` avec `runAsUser: 101` et `runAsGroup: 101` (l'utilisateur nginx de l'image).

```bash
kubectl apply -f k8s/
kubectl -n cordee rollout status deployment api
kubectl -n cordee rollout status deployment front
kubectl -n cordee exec deployment/api -- sh -c 'id; touch /app/pirate'
kubectl -n cordee exec deployment/api -- sh -c 'touch /tmp/ok && echo "/tmp inscriptible"'
curl -s http://192.168.56.201/api/info | jq -r .version
kubectl label --dry-run=server --overwrite namespace cordee pod-security.kubernetes.io/enforce=restricted
```

Attendu : `uid=10001`, `Read-only file system` pour `/app`, `/tmp inscriptible`, le site répond. La dernière commande ne signale plus que `postgres-0` : l'image PostgreSQL démarre en root pour préparer son dossier de données, c'est pourquoi le namespace reste en `baseline`.

**Question 6** – Pourquoi `readOnlyRootFilesystem` impose-t-il un volume sur `/tmp` ? Qu'apporte-t-il face à une faille dans l'API ?

## Fin du TP

```bash
kubectl apply -R -f k8s/
kubectl -n cordee get pods
kubectl config use-context kubernetes-admin@kubernetes
ls -R k8s/
```

Depuis ce TP, `k8s/` a un sous-dossier : on applique avec `kubectl apply -R -f k8s/`.

## Questions de fin

7. Citez trois façons dont un `kubeconfig` d'administration finit entre de mauvaises mains, et la parade pour chacune.
8. RBAC, Network Policies, SecurityContext : contre quoi protège chacun ?

## Bonus

- Une NetworkPolicy en `Egress` qui interdit à l'API de sortir ailleurs que vers la base et CoreDNS (port 53 UDP/TCP vers `kube-system`).
- `kubectl auth can-i --list --as=system:serviceaccount:cordee:default -n cordee` : que peut faire le ServiceAccount par défaut ?

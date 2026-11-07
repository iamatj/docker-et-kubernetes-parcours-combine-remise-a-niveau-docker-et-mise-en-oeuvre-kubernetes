# TP 08 – Configuration, sondes et diagnostic

| Durée | Branche | Correction |
|-------|---------|------------|
| 75 min (15h30 – 16h45) | `tp-08-configuration` | `solutions/08-configuration/` (`README.md` et `k8s/`) |

## L'incident

> Mercredi, 14h. Un stagiaire a publié le dépôt de Cordée en public sur GitHub par erreur, trois heures durant : le mot de passe de la base était dedans, en clair, dans deux fichiers. Le même jour, à 16h, la base tombe ; le site, lui, continue d'envoyer les visiteurs vers des API qui répondent « 500 ». Kubernetes ne voit rien : pour lui, les conteneurs tournent.

## Objectifs

- Organiser et filtrer les ressources avec des étiquettes (labels), des sélecteurs et des annotations.
- Sortir la configuration des images et des manifests : ConfigMap et Secret, et connaître les limites des Secrets.
- Dire à Kubernetes quand un pod est démarré, prêt, vivant : startup, readiness et liveness probes.
- Suivre une méthode de diagnostic sur des pods en erreur.

## Point de départ

```bash
cd ~/cordee
git fetch
git stash -u
git checkout tp-08-configuration
kubectl apply -f k8s/
kubectl -n cordee rollout status deployment api
curl -s http://192.168.56.201/api/info
```

`k8s/` contient la correction du TP 07 (API 1.1, stratégie sans indisponibilité, LoadBalancer).

## Partie A – Étiquettes, sélecteurs, annotations (12 min)

### A1. Filtrer

```bash
kubectl -n cordee get pods --show-labels
kubectl -n cordee get pods -l app=api
kubectl -n cordee get pods -l 'app in (api,front)' -L app
kubectl get pods -A -l k8s-app=kube-dns
```

### A2. Ajouter des étiquettes dans les fichiers

Dans le **gabarit de pod** (`spec.template.metadata.labels`, pas le `selector`) de chaque Deployment, ajoutez :

| Fichier | Étiquettes à ajouter sous `app: …` |
|---------|------------------------------------|
| `k8s/10-postgres.yaml` | `tier: donnees` et `partie-de: cordee` |
| `k8s/20-api.yaml` | `tier: back` et `partie-de: cordee` |
| `k8s/30-front.yaml` | `tier: front` et `partie-de: cordee` |

Ne touchez pas au `selector` : il est immuable, `kubectl apply` refuserait la modification. Les étiquettes `tier` serviront aux Network Policies du TP 10.

```bash
kubectl apply -f k8s/
kubectl -n cordee rollout status deployment api
kubectl -n cordee get pods -L tier
```

### A3. Mettre un pod en quarantaine

```bash
POD=$(kubectl -n cordee get pods -l app=api -o jsonpath='{.items[0].metadata.name}')
kubectl -n cordee label pod $POD app=quarantaine --overwrite
kubectl -n cordee get pods -L app
kubectl -n cordee get endpoints api -o jsonpath='{.subsets[0].addresses[*].targetRef.name}{"\n"}'
```

Le pod `$POD` tourne toujours, mais il n'est plus dans les endpoints du Service, et le ReplicaSet a créé un remplaçant. On peut maintenant l'examiner tranquillement (`logs`, `exec`), puis le supprimer :

```bash
kubectl -n cordee delete pod $POD
```

### A4. Une annotation

```bash
kubectl -n cordee annotate deployment api cordee.lab/responsable="Karim Benali"
kubectl -n cordee get deployment api -o jsonpath='{.metadata.annotations}' | jq
```

**Question 1** – Quelle différence entre une étiquette et une annotation ? Pourquoi la quarantaine marche-t-elle ?

Reportez l'annotation dans `k8s/20-api.yaml` (`metadata.annotations`, à côté de `kubernetes.io/change-cause`), sinon elle n'existe que dans le cluster.

## Partie B – ConfigMap et Secret (23 min)

### B1. La ConfigMap

```bash
cp tp/08-configuration/01-configmap.yaml k8s/
```

Remplacez le `TODO` de `MESSAGE_ACCUEIL` par `Ouverture des réservations de Noël !`, puis :

```bash
kubectl apply -f k8s/01-configmap.yaml
kubectl -n cordee describe configmap cordee-config
```

### B2. Le Secret

```bash
kubectl -n cordee create secret generic cordee-db \
  --from-literal=DB_USER=cordee --from-literal=DB_PASSWORD=Neige-2026 \
  --dry-run=client -o yaml > k8s/02-secret.yaml
cat k8s/02-secret.yaml
kubectl apply -f k8s/02-secret.yaml
kubectl -n cordee get secret cordee-db -o jsonpath='{.data.DB_PASSWORD}' | base64 -d; echo
```

**Question 2** – Le mot de passe est-il chiffré dans `k8s/02-secret.yaml` ? Qui peut le lire dans le cluster ? Ce fichier devrait-il être dans Git ?

### B3. Les utiliser

Dans `k8s/20-api.yaml`, remplacez tout le bloc `env:` du conteneur par :

```yaml
          envFrom:
            - configMapRef:
                name: cordee-config
            - secretRef:
                name: cordee-db
```

Dans `k8s/10-postgres.yaml`, remplacez le bloc `env:` par :

```yaml
          env:
            - name: POSTGRES_DB
              valueFrom:
                configMapKeyRef:
                  name: cordee-config
                  key: DB_NAME
            - name: POSTGRES_USER
              valueFrom:
                secretKeyRef:
                  name: cordee-db
                  key: DB_USER
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: cordee-db
                  key: DB_PASSWORD
```

```bash
grep -rn "Neige-2026" k8s/          # rien ne doit s'afficher : dans 02-secret.yaml, il est encodé en base64
kubectl apply -f k8s/
kubectl -n cordee rollout status deployment postgres
kubectl -n cordee rollout status deployment api
curl -s http://192.168.56.201/api/info | jq -r .message
```

Attendu : `Ouverture des réservations de Noël !`.

> PostgreSQL a redémarré (son gabarit a changé) : la base est repartie vide, à cause de l'`emptyDir`. C'est l'incident du TP 09 ; ici, l'API recrée les tables toute seule.

### B4. Changer la configuration

Changez le message dans `k8s/01-configmap.yaml` (par exemple `Plus que 3 places au Goûter !`), puis :

```bash
kubectl apply -f k8s/01-configmap.yaml
curl -s http://192.168.56.201/api/info | jq -r .message
kubectl -n cordee rollout restart deployment api
kubectl -n cordee rollout status deployment api
curl -s http://192.168.56.201/api/info | jq -r .message
```

**Question 3** – Pourquoi le message n'a-t-il changé qu'après le `rollout restart` ? Citez une façon de faire en sorte que ce soit automatique.

## Partie C – Les sondes (20 min)

### C1. Un démarrage lent sans startupProbe

Dans `k8s/20-api.yaml`, sous `envFrom` (même indentation), ajoutez une variable qui simule un démarrage de 40 s, et deux sondes sous `ports` :

```yaml
          env:
            - name: DELAI_DEMARRAGE
              value: "40"
```

```yaml
          readinessProbe:
            httpGet:
              path: /readyz
              port: 8000
            periodSeconds: 5
            failureThreshold: 2
          livenessProbe:
            httpGet:
              path: /healthz
              port: 8000
            periodSeconds: 5
            failureThreshold: 3
```

```bash
kubectl apply -f k8s/20-api.yaml
sleep 60
kubectl -n cordee get pods -l app=api
kubectl -n cordee describe pods -l app=api | grep -E 'Liveness probe failed|Killing' | sort -u | head -3
```

Le nouveau pod redémarre en boucle (`RESTARTS` augmente) : la liveness probe le tue au bout de 15 s, avant la fin de son démarrage de 40 s. Les anciens pods tournent toujours (`maxUnavailable: 0`).

### C2. La startupProbe

Ajoutez, avant la `readinessProbe` :

```yaml
          startupProbe:
            httpGet:
              path: /healthz
              port: 8000
            periodSeconds: 2
            failureThreshold: 30
```

```bash
kubectl apply -f k8s/20-api.yaml
kubectl -n cordee rollout status deployment api
```

Chaque nouveau pod met environ 45 s à devenir prêt, sans redémarrer. **Question 4** – Que fait chacune des trois sondes, et que se passe-t-il quand elle échoue ?

Remettez `DELAI_DEMARRAGE` à `"5"`, puis `kubectl apply -f k8s/20-api.yaml`.

Ajoutez au site (`k8s/30-front.yaml`, sous `ports`) une readinessProbe et une livenessProbe `httpGet` sur `/healthz`, port `8080`, `periodSeconds: 5` et `10`, puis `kubectl apply -f k8s/30-front.yaml`.

### C3. Une mise à jour sans aucune erreur

```bash
sonde() { : > /tmp/sonde.log; while true; do curl -s -m 2 -o /dev/null -w "%{http_code}\n" http://192.168.56.201/api/info; sleep 0.2; done >> /tmp/sonde.log & }
bilan() { kill %1 2>/dev/null; sleep 0.5; sort /tmp/sonde.log | uniq -c; }
sonde
kubectl -n cordee rollout restart deployment api
kubectl -n cordee rollout status deployment api
sleep 3; bilan
```

Attendu : uniquement des `200`, contrairement au TP 07.

### C4. Une configuration fausse, sans panne visible

```bash
sonde
kubectl -n cordee set env deployment/api DB_HOST=postgres-ancien
sleep 45
kubectl -n cordee get pods -l app=api
bilan
```

Le site marche toujours (que des `200`). **Ne vous fiez pas qu'au navigateur** : la livraison est-elle allée au bout ?

```bash
kubectl -n cordee rollout status deployment api --timeout=10s
kubectl -n cordee logs -l app=api --tail 2 --prefix | grep -i injoignable | head -2
kubectl -n cordee rollout undo deployment api
kubectl -n cordee rollout status deployment api
```

**Question 5** – Pourquoi le site a-t-il continué à marcher ? Qu'aurait-il fallu pour que l'équipe soit prévenue ?

## Partie D – Diagnostiquer (20 min)

```bash
bash tp/08-configuration/pannes.sh
kubectl -n diagnostic get pods
```

Quatre applications sont en panne : `billetterie`, `meteo`, `vitrine`, `statistiques`. Pour chacune, suivez la méthode, dans cet ordre, et arrêtez-vous dès que vous avez la cause :

| Étape | Commande | Ce qu'on cherche |
|-------|----------|------------------|
| 1. État | `kubectl -n diagnostic get pods -o wide` | `STATUS`, `READY`, `RESTARTS` |
| 2. Détail | `kubectl -n diagnostic describe pod <pod>` | la section `Events` en bas, `State` / `Last State`, `Reason` |
| 3. Logs | `kubectl -n diagnostic logs <pod>` (et `--previous` après un redémarrage) | le message d'erreur de l'application |
| 4. Événements | `kubectl -n diagnostic get events --sort-by=.lastTimestamp` | ce qui s'est passé, dans l'ordre |
| 5. Réseau | `kubectl -n diagnostic get endpoints`, puis un `wget` depuis un pod jetable | un Service sans pod derrière |

Pour la vitrine, testez le Service depuis un pod jetable :

```bash
kubectl -n diagnostic run test --rm -i --restart=Never --image=mirror.gcr.io/library/busybox:1.37 -- wget -qO- -T 3 http://vitrine:8080/
```

Pour chaque panne, notez : le symptôme, la commande qui a donné la cause, la cause, et la correction. Corrigez avec `kubectl -n diagnostic edit …` (éditeur `vi` : `i` pour écrire, `Échap` puis `:wq` pour enregistrer) ou `kubectl -n diagnostic set …`, et vérifiez que tout passe en `Running` et `READY`.

**Question 6** – Remplissez le tableau pour les quatre pannes.

Nettoyage :

```bash
kubectl delete namespace diagnostic
jobs                      # aucune sonde ne doit rester ; sinon kill %1
```

## Questions de fin

7. Les nœuds du cluster font tourner `calico-node` et `kube-proxy` : `kubectl get daemonsets -A`. Qu'est-ce qu'un DaemonSet, et dans quel cas Cordée en écrirait-elle un ?
8. Karim veut que deux pods de l'API ne soient jamais sur le même nœud. Quel mécanisme utiliser ?

## Bonus

- Montez la ConfigMap comme fichier (`volumes` + `volumeMounts`) dans un pod busybox : le fichier se met-il à jour quand la ConfigMap change ?
- `kubectl -n cordee get pods -l app=api -o jsonpath='{.items[0].spec.containers[0].env}'` après `set env` puis `undo`.

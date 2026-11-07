# TP 06 – Déployer Cordée sur Kubernetes

| Durée | Branche | Correction |
|-------|---------|------------|
| 70 min (11h20 – 12h30) | `tp-06-deploiement` | `solutions/06-deploiement/` (`README.md` et `k8s/`) |

## L'incident

> Mardi, 10h. L'ouverture des réservations de Noël est vendredi. Léa veut Cordée sur le cluster avant, « et avec plusieurs exemplaires de l'API, au cas où ». Karim a déjà écrit le manifest de la base ; il reste l'API et le site.

## Objectifs

- Passer de l'impératif (`kubectl create`) au déclaratif (fichiers YAML dans Git, `kubectl apply`).
- Lire et corriger du YAML Kubernetes.
- Déployer les trois composants de Cordée et les relier par des Services.
- Exposer le site hors du cluster (NodePort, port-forward) et changer le nombre de replicas.

## Point de départ

```bash
cd ~/cordee
git fetch
git stash -u
git checkout tp-06-deploiement
ls tp/06-deploiement
kubectl get namespace cordee 2>/dev/null || echo "pas encore de namespace cordee : normal"
```

Les images `ghcr.io/iamatj/cordee-api` et `cordee-front` (versions `1.0` et `1.1`) sont publiées par le dépôt ; ce sont les mêmes Dockerfile qu'au TP 02.

## Étapes

### 1. De l'impératif au déclaratif (5 min)

```bash
kubectl create deployment api --image=ghcr.io/iamatj/cordee-api:1.0 --replicas=2 --port=8000 --dry-run=client -o yaml
```

Rien n'est créé (`--dry-run=client`) : kubectl affiche le YAML qu'il aurait envoyé. C'est un bon point de départ pour écrire un manifest. Repérez `apiVersion`, `kind`, `metadata`, `spec`, `spec.selector`, `spec.template`.

### 2. Corriger un YAML cassé (10 min)

```bash
kubectl apply --dry-run=server -f tp/06-deploiement/yaml-casse.yaml
```

Le fichier contient quatre erreurs. Corrigez-les une par une dans `tp/06-deploiement/yaml-casse.yaml` en relançant la commande après chaque correction, jusqu'à obtenir `pod/essai-yaml created (server dry run)`.

> Le `--dry-run=server` envoie l'objet à l'API Server, qui le valide sans le créer. Il échouera tant que le namespace `cordee` n'existe pas : créez-le d'abord à l'étape 3, puis revenez ici si besoin.

**Question 1** – Quelles étaient les quatre erreurs ? Lesquelles sont des erreurs de syntaxe YAML, et lesquelles des erreurs de schéma Kubernetes ?

### 3. Le namespace et la base (8 min)

```bash
mkdir -p k8s
cp tp/06-deploiement/00-namespace.yaml tp/06-deploiement/10-postgres.yaml k8s/
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/10-postgres.yaml
kubectl -n cordee get deployment,pod,service
kubectl -n cordee rollout status deployment postgres
```

Lisez `k8s/10-postgres.yaml`. **Question 2** – Relevez les deux choses que Sophie n'aimerait pas voir en production dans ce fichier.

### 4. L'API (12 min)

Ouvrez `tp/06-deploiement/20-api.yaml` et remplacez chaque `TODO-…` :

| Valeur à remplacer | Par |
|--------------------|-----|
| `TODO-etiquette` | `api` |
| `TODO-image-de-l-api` | `ghcr.io/iamatj/cordee-api:1.0` |
| `TODO-nom-du-service-postgres` | le nom du Service de la base (`kubectl -n cordee get svc`) |
| `TODO-port-du-service` | `8000` |

```bash
cp tp/06-deploiement/20-api.yaml k8s/
kubectl apply -f k8s/20-api.yaml
kubectl -n cordee get pods -w
```

Attendez deux pods `api-…` en `Running` et `READY 1/1`, puis Ctrl+C. Si un pod affiche `InvalidImageName` ou `ErrImagePull`, un `TODO` est resté dans le fichier : `kubectl -n cordee describe pod -l app=api | grep -A3 Events`.

```bash
kubectl -n cordee logs deployment/api --tail 3
kubectl -n cordee get endpoints api
```

Les logs montrent `base de données prête`. `endpoints` liste les IP des deux pods derrière le Service `api`.

Testez le Service depuis l'intérieur du cluster, avec un pod jetable :

```bash
kubectl -n cordee run test --rm -i --restart=Never --image=mirror.gcr.io/library/busybox:1.37 -- wget -qO- -T 3 http://api:8000/api/info
```

Attendu : `{"hote":"api-…","message":"Bienvenue sur Cordée","version":"1.0"}`, puis `pod "test" deleted`.

### 5. Le site et le NodePort (10 min)

Dans `tp/06-deploiement/30-front.yaml`, remplacez `TODO-image-du-site` par `ghcr.io/iamatj/cordee-front:1.0`, puis écrivez le Service à la place du commentaire `TODO`, en vous inspirant de celui de l'API :

```yaml
apiVersion: v1
kind: Service
metadata:
  name: front
  namespace: cordee
spec:
  type: NodePort
  selector:
    app: front
  ports:
    - port: 8080
      targetPort: 8080
      nodePort: 30080
```

```bash
cp tp/06-deploiement/30-front.yaml k8s/
kubectl apply -f k8s/
kubectl -n cordee get all
for ip in 192.168.56.20 192.168.56.30 192.168.56.40; do curl -s -m 2 -o /dev/null -w "$ip : %{http_code}\n" http://$ip:30080/; done
```

Attendu : `200` sur les trois adresses, même `control-plane`, qui ne fait tourner aucun pod du site.

Ouvrez <http://192.168.56.30:30080> dans Firefox : les refuges s'affichent, le pied de page indique `site 1.0 · API 1.0 · servi par api-…`. Faites une réservation.

**Question 3** – Pourquoi le site répond-il sur l'IP de `control-plane` ? Quel composant rend cela possible ?

### 6. Port-forward : l'accès du développeur (5 min)

```bash
kubectl -n cordee port-forward service/front 8080:8080 >/dev/null 2>&1 &
sleep 1
curl -s http://localhost:8080/api/info
kill %1
```

**Question 4** – NodePort ou port-forward : lequel donner aux clients de Cordée, lequel à Karim pour déboguer ?

### 7. Plus d'exemplaires (12 min)

```bash
kubectl -n cordee scale deployment api --replicas=4
kubectl -n cordee get pods -l app=api -o wide
for i in $(seq 20); do curl -s http://192.168.56.30:30080/api/info | jq -r .hote; done | sort | uniq -c
```

Les 20 requêtes sont réparties entre les 4 pods. Rechargez la page dans Firefox : le nom du pod dans le pied de page change.

Maintenant, réappliquez les fichiers :

```bash
kubectl apply -f k8s/
kubectl -n cordee get deployment api
```

**Question 5** – Combien de replicas après `kubectl apply` ? Pourquoi ? Que faut-il faire pour que Cordée garde durablement 3 API ?

Faites-le : mettez `replicas: 3` dans `k8s/20-api.yaml`, puis `kubectl apply -f k8s/20-api.yaml` et vérifiez `3/3`.

### 8. Un aperçu de ce qui nous attend (3 min)

```bash
kubectl -n cordee delete pod -l app=postgres
kubectl -n cordee rollout status deployment postgres
curl -s http://192.168.56.30:30080/api/reservations
```

**Question 6** – Où est passée votre réservation ? (On le corrigera au TP 09.) Pourquoi le site a-t-il continué à afficher les refuges ?

Gardez tout en place : le TP 07 part de cet état.

## Questions de fin

7. Que se passe-t-il si le `selector` d'un Deployment ne correspond pas aux étiquettes de son gabarit de pod ?
8. Comment l'API trouve-t-elle la base avec seulement `DB_HOST=postgres` ?

## Bonus

- `kubectl -n cordee get pods -o custom-columns=POD:.metadata.name,NŒUD:.spec.nodeName,IP:.status.podIP`
- `kubectl diff -f k8s/` après avoir modifié un fichier : voir ce que `apply` changerait avant de l'appliquer.

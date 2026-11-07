# TP 07 – Mettre à jour sans couper

| Durée | Branche | Correction |
|-------|---------|------------|
| 80 min (13h40 – 15h00) | `tp-07-mise-a-jour` | `solutions/07-mise-a-jour/` (`README.md` et `k8s/`) |

## L'incident

> Samedi, 8h02. Karim livre l'API 1.1 avant le rush du week-end. Pendant une minute, une partie des clients voit « API injoignable ». Pire : à 8h20, quelqu'un livre une version `1.2`… qui n'a jamais été publiée. Sophie doit revenir en arrière, vite, sans savoir quelle version tournait juste avant.

## Objectifs

- Observer une mise à jour progressive (rolling update) et mesurer les erreurs qu'elle provoque.
- Régler la stratégie : `maxSurge`, `maxUnavailable`, `minReadySeconds`.
- Tenir un historique lisible et revenir en arrière (`rollout undo`).
- Exposer le site à l'extérieur du cluster avec un Service LoadBalancer.

## Point de départ

```bash
cd ~/cordee
git fetch
git stash -u
git checkout tp-07-mise-a-jour
kubectl apply -f k8s/
kubectl -n cordee rollout status deployment api
kubectl -n cordee get deployment
```

`k8s/` contient la correction du TP 06 : 3 API, 2 sites, la base. Le site répond sur <http://192.168.56.30:30080>.

## Étapes

### 1. Une sonde qui écoute pendant qu'on agit (5 min)

Un seul terminal : la sonde tourne **en arrière-plan** et écrit dans un fichier ; on le lira après chaque mise à jour.

```bash
sonde() {
  : > /tmp/sonde.log
  while true; do curl -s -m 2 -o /dev/null -w "%{http_code}\n" http://192.168.56.30:30080/api/info; sleep 0.2; done >> /tmp/sonde.log &
}
bilan() { kill %1 2>/dev/null; sleep 0.5; echo "Réponses :"; sort /tmp/sonde.log | uniq -c; }
sonde; sleep 5; bilan
```

Attendu : uniquement des `200`. `000` voudrait dire « pas de réponse en 2 secondes », `502` « le site n'a pas pu joindre l'API ».

### 2. Une mise à jour avec la stratégie par défaut (12 min)

```bash
kubectl -n cordee get deployment api -o jsonpath='{.spec.strategy}{"\n"}'
sonde
kubectl -n cordee set image deployment/api api=ghcr.io/iamatj/cordee-api:1.1
kubectl -n cordee rollout status deployment api
sleep 3; bilan
```

Une fois la mise à jour terminée, regardez les ReplicaSets :

```bash
kubectl -n cordee get replicaset -l app=api
```

Deux ReplicaSets : l'ancien (version 1.0) descendu à 0, le nouveau (1.1) monté à 3.

**Question 1** – Combien d'erreurs la sonde a-t-elle vues ? Avec `maxSurge: 25%` et `maxUnavailable: 25%` sur 3 replicas, combien de pods au maximum et au minimum pendant la mise à jour ? Pourquoi y a-t-il des erreurs alors qu'il reste toujours des pods ?

### 3. L'historique et le retour arrière (8 min)

```bash
kubectl -n cordee rollout history deployment api
kubectl -n cordee rollout history deployment api --revision=2 | grep Image
sonde
kubectl -n cordee rollout undo deployment api
kubectl -n cordee rollout status deployment api
sleep 3; bilan
curl -s http://192.168.56.30:30080/api/info | jq -r .version
```

Attendu : `1.0`. La colonne `CHANGE-CAUSE` de l'historique est vide : impossible de savoir ce que contenait chaque révision sans l'ouvrir.

### 4. Une stratégie sans indisponibilité, écrite dans le fichier (15 min)

Ouvrez `k8s/20-api.yaml` et modifiez le Deployment :

1. dans `metadata`, sous `namespace: cordee`, ajoutez :

   ```yaml
     annotations:
       kubernetes.io/change-cause: "API 1.1 : rolling update sans indisponibilité"
   ```

2. dans `spec`, sous `replicas: 3`, ajoutez :

   ```yaml
     strategy:
       type: RollingUpdate
       rollingUpdate:
         maxSurge: 1
         maxUnavailable: 0
     minReadySeconds: 5
   ```

3. remplacez l'image par `ghcr.io/iamatj/cordee-api:1.1`.

```bash
kubectl diff -f k8s/20-api.yaml | grep -E '^[+-] ' 
sonde
kubectl apply -f k8s/20-api.yaml
kubectl -n cordee rollout status deployment api
sleep 3; bilan
kubectl -n cordee rollout history deployment api
```

Pendant le `rollout status`, la mise à jour avance pod par pod, avec une pause de 5 s après chaque nouveau pod.

**Question 2** – Le nombre d'erreurs a-t-il baissé ? Est-il nul ? Que manque-t-il à Kubernetes pour savoir qu'un nouveau pod est vraiment prêt à recevoir du trafic ? (Réponse complète au TP 08.)

Ajoutez la même `strategy`, le même `minReadySeconds`, et l'annotation `kubernetes.io/change-cause: "site 1.0 : stratégie de mise à jour sans indisponibilité"` à `k8s/30-front.yaml` (gardez l'image `1.0`), puis `kubectl apply -f k8s/30-front.yaml`.

### 5. La version qui n'existe pas (15 min)

```bash
sonde
kubectl -n cordee set image deployment/api api=ghcr.io/iamatj/cordee-api:1.2
kubectl -n cordee rollout status deployment api --timeout=60s
```

Après 60 s : `error: timed out waiting for the condition`. Diagnostiquez :

```bash
kubectl -n cordee get pods -l app=api
kubectl -n cordee describe pod -l app=api | grep -E 'Image:|Failed|Back-off' | sort -u
sleep 3; bilan
```

Un nouveau pod est en `ErrImagePull` puis `ImagePullBackOff` : `ghcr.io/iamatj/cordee-api:1.2: not found`. Les trois anciens pods tournent toujours.

**Question 3** – Le site a-t-il été coupé ? Grâce à quel réglage ? Qu'aurait fait la stratégie par défaut ?

Revenez à la dernière version qui marchait :

```bash
kubectl -n cordee rollout undo deployment api
kubectl -n cordee rollout status deployment api
kubectl -n cordee rollout history deployment api
curl -s http://192.168.56.30:30080/api/info | jq -r .version
```

Attendu : `1.1`. **Question 4** – Après `undo`, `kubectl apply -f k8s/` changerait-il quelque chose ? Pourquoi est-il préférable de corriger le fichier puis de l'appliquer, plutôt que de taper `set image` ?

### 6. Un LoadBalancer (15 min)

Créez `k8s/31-front-lb.yaml` :

```yaml
apiVersion: v1
kind: Service
metadata:
  name: front-lb
  namespace: cordee
  annotations:
    metallb.io/loadBalancerIPs: 192.168.56.201
spec:
  type: LoadBalancer
  selector:
    app: front
  ports:
    - port: 80
      targetPort: 8080
```

```bash
kubectl apply -f k8s/31-front-lb.yaml
kubectl -n cordee get service
curl -s http://192.168.56.201/api/info
```

Attendu : `front-lb` a l'`EXTERNAL-IP` `192.168.56.201`, et le site répond sur le port 80 de cette adresse. Ouvrez <http://192.168.56.201> dans Firefox.

**Question 5** – Qui a donné cette adresse ? Que verrait-on sur un cluster kubeadm sans MetalLB, et sur un cluster managé (AKS, EKS, GKE) ?

**Question 6** – Comparez ClusterIP, NodePort et LoadBalancer : qui peut joindre chacun, et lequel s'appuie sur lequel ?

## Fin du TP

```bash
jobs                     # aucune sonde ne doit tourner ; sinon : kill %1
kubectl -n cordee get deployment,service
```

Gardez tout en place : le TP 08 part de cet état.

## Questions de fin

7. Comment mettre une mise à jour en pause à mi-chemin pour vérifier quelques pods avant de continuer ?
8. Une base de données en Deployment peut-elle être mise à jour avec `maxSurge: 1` ? Quel risque ?

## Bonus

- `kubectl -n cordee rollout pause deployment api`, `set image … 1.0`, observer, puis `rollout resume`.
- `kubectl -n cordee get replicaset -l app=api` : combien d'anciens ReplicaSets sont conservés, et quel champ du Deployment règle ce nombre ?

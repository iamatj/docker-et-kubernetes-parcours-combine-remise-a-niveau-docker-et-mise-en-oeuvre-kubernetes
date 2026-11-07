# TP 09 – Stockage persistant

| Durée | Branche | Correction |
|-------|---------|------------|
| 65 min (9h25 – 10h30) | `tp-09-stockage` | `solutions/09-stockage/` (`README.md` et `k8s/10-postgres.yaml`) |

## L'incident

> Jeudi, 6h50. Le nœud `worker-2` a redémarré pendant la nuit (mise à jour de sécurité). Le pod PostgreSQL a été recréé ailleurs, tout neuf : 47 réservations de Noël ont disparu. Léa a passé la matinée au téléphone avec des familles en colère.

## Objectifs

- Comprendre pourquoi un `emptyDir` ne suffit pas pour une base.
- Demander un volume persistant (PVC), le voir provisionné dynamiquement par une StorageClass (PV).
- Comparer les politiques de rétention `Delete` et `Retain`.
- Passer la base en StatefulSet, sans perdre les données.

## Point de départ

```bash
cd ~/cordee
git fetch
git stash -u
git checkout tp-09-stockage
kubectl apply -f k8s/
kubectl -n cordee rollout status deployment api
kubectl get storageclass
```

Deux StorageClass existent : `local-path` (par défaut) et `local-path-retain`. Elles créent les volumes dans un dossier du nœud (`/opt/local-path-provisioner`) : simple, mais lié à ce nœud. Sur un cloud, une StorageClass créerait un disque réseau.

## Étapes

### A. Constater la perte (8 min)

Faites deux réservations dans Firefox (<http://192.168.56.201>), puis :

```bash
curl -s http://192.168.56.201/api/reservations | jq length
kubectl -n cordee delete pod -l app=postgres
kubectl -n cordee rollout status deployment postgres
sleep 5
curl -s http://192.168.56.201/api/reservations | jq length
```

Attendu : `2`, puis `0`.

**Question 1** – Où était stockée la base ? Pourquoi un `emptyDir` disparaît-il avec le pod, et dans quel cas est-il quand même utile ?

### B. Un PVC pour la base (17 min)

```bash
cp tp/09-stockage/11-pvc-postgres.yaml k8s/
kubectl apply -f k8s/11-pvc-postgres.yaml
kubectl -n cordee get pvc
```

Le PVC est `Pending` : la StorageClass attend qu'un pod l'utilise pour savoir sur quel nœud créer le volume (`WaitForFirstConsumer`).

Modifiez `k8s/10-postgres.yaml` :

1. dans `spec`, sous `replicas: 1`, ajoutez la stratégie qui arrête l'ancien pod avant de lancer le nouveau :

   ```yaml
     strategy:
       type: Recreate
   ```

2. dans la liste `env` du conteneur, ajoutez (PostgreSQL veut un sous-dossier vide) :

   ```yaml
               - name: PGDATA
                 value: /var/lib/postgresql/data/pgdata
   ```

3. remplacez le volume `emptyDir` en bas du fichier par :

   ```yaml
         volumes:
           - name: donnees
             persistentVolumeClaim:
               claimName: donnees-postgres
   ```

```bash
kubectl apply -f k8s/10-postgres.yaml
kubectl -n cordee rollout status deployment postgres
kubectl -n cordee get pvc
kubectl get pv
```

Le PVC est `Bound` à un PV créé automatiquement (`pvc-…`), de classe `local-path`, politique `Delete`.

Faites une réservation, puis recommencez la panne :

```bash
curl -s http://192.168.56.201/api/reservations | jq length
kubectl -n cordee delete pod -l app=postgres
kubectl -n cordee rollout status deployment postgres
sleep 5
curl -s http://192.168.56.201/api/reservations | jq length
```

Le nombre est le même avant et après. Allez voir le volume sur le disque :

```bash
PV=$(kubectl -n cordee get pvc donnees-postgres -o jsonpath='{.spec.volumeName}')
kubectl get pv $PV -o jsonpath='{.spec.local.path}{.spec.hostPath.path}{"  sur  "}{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]}{"\n"}'
NOEUD=$(kubectl -n cordee get pod -l app=postgres -o jsonpath='{.items[0].spec.nodeName}')
ssh formation@$NOEUD "sudo ls /opt/local-path-provisioner/ | grep donnees-postgres"
```

**Question 2** – Pourquoi la stratégie `Recreate` ? Que se passerait-il si le nœud du volume tombait définitivement ?

### C. Rétention : Delete ou Retain (12 min)

```bash
kubectl apply -f tp/09-stockage/pvc-essai-retain.yaml
kubectl -n cordee wait --for=condition=Ready pod/essai-retain --timeout=90s
kubectl -n cordee exec essai-retain -- cat /donnees/preuve.txt
kubectl get pv
kubectl delete -f tp/09-stockage/pvc-essai-retain.yaml
kubectl get pv
```

Le PV de `essai-retain` est passé à `Released` : la demande a disparu, mais le volume et ses données restent. Il ne sera pas réutilisé automatiquement.

```bash
PV_RETAIN=$(kubectl get pv -o jsonpath='{.items[?(@.spec.claimRef.name=="essai-retain")].metadata.name}')
echo $PV_RETAIN
kubectl delete pv $PV_RETAIN
```

**Question 3** – Le dossier du volume existe-t-il encore sur le nœud après `kubectl delete pv` ? Quelle politique choisir pour la base de Cordée, et pourquoi ? Avec `Delete`, que se passe-t-il quand on supprime le PVC ?

### D. Un StatefulSet pour la base (25 min)

Un Deployment avec un PVC marche pour **une** base. Un StatefulSet donne à chaque pod un nom stable (`postgres-0`), son propre volume, et un ordre de démarrage : c'est l'objet prévu pour les applications avec état.

Lisez `tp/09-stockage/10-postgres-statefulset.yaml` : repérez `serviceName`, `volumeClaimTemplates`, `storageClassName: local-path-retain`, et le Service `postgres-headless`.

Le StatefulSet aura un **nouveau** volume. Pour garder les réservations, on sauvegarde la base, puis on la restaure :

```bash
kubectl -n cordee exec deployment/postgres -- pg_dump -U cordee cordee > /tmp/cordee.sql
echo "code de retour : $?"; wc -l /tmp/cordee.sql; grep -c 'INSERT\|COPY' /tmp/cordee.sql
```

Le code de retour doit être `0` et le fichier non vide. Ensuite, remplacez la base :

```bash
kubectl -n cordee delete deployment postgres
kubectl -n cordee delete pvc donnees-postgres
rm k8s/11-pvc-postgres.yaml
cp tp/09-stockage/10-postgres-statefulset.yaml k8s/10-postgres.yaml
kubectl apply -f k8s/10-postgres.yaml
kubectl -n cordee rollout status statefulset postgres
kubectl -n cordee get statefulset,pod,pvc -l app=postgres
kubectl -n cordee get pvc
```

Le PVC s'appelle `donnees-postgres-0` (le nom du gabarit + le nom du pod). **Ne rechargez pas le site maintenant** : à la première requête, l'API recréerait des tables vides. Restaurez :

```bash
kubectl -n cordee exec -i postgres-0 -- psql -U cordee -d cordee -v ON_ERROR_STOP=1 < /tmp/cordee.sql
kubectl -n cordee rollout restart deployment api
kubectl -n cordee rollout status deployment api
curl -s http://192.168.56.201/api/reservations | jq length
```

Les réservations sont revenues. Si `psql` s'est arrêté sur `relation "refuge" already exists`, l'API a recréé les tables entre-temps : videz la base (`kubectl -n cordee exec postgres-0 -- psql -U cordee -d cordee -c 'DROP TABLE reservation, refuge;'`) et relancez la restauration.

Testez la résistance :

```bash
kubectl -n cordee delete pod postgres-0
kubectl -n cordee get pods -l app=postgres -w
```

Le pod revient **sous le même nom**, avec le même volume. Ctrl+C, puis vérifiez le nombre de réservations.

```bash
kubectl -n cordee run test --rm -i --restart=Never --image=mirror.gcr.io/library/busybox:1.37 -- nslookup postgres-0.postgres-headless.cordee.svc.cluster.local
```

**Question 4** – Que donne le DNS pour `postgres-0.postgres-headless` ? À quoi sert un Service sans ClusterIP (`clusterIP: None`) ?

**Question 5** – Pourquoi la restauration se fait-elle avant de redémarrer l'API ? Que se serait-il passé dans l'autre ordre ?

## Fin du TP

```bash
kubectl -n cordee get statefulset,deployment,pvc
ls k8s/          # plus de 11-pvc-postgres.yaml
```

## Questions de fin

6. Stateful ou stateless : classez l'API, le site, la base, et dites lesquels on peut multiplier sans précaution.
7. `kubectl scale statefulset postgres --replicas=3` donne-t-il une base répliquée ? Que faudrait-il ?

## Bonus

- `kubectl get pv -o custom-columns=NOM:.metadata.name,CLASSE:.spec.storageClassName,RETENTION:.spec.persistentVolumeReclaimPolicy,ETAT:.status.phase,DEMANDE:.spec.claimRef.name`
- Un CronJob qui fait un `pg_dump` chaque nuit dans un PVC dédié : quel piège avec `pg_dump | gzip` ?

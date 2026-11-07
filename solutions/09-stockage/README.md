# Correction du TP 09 – Stockage persistant

Fichier corrigé : `solutions/09-stockage/k8s/10-postgres.yaml` (le StatefulSet, identique à `tp/09-stockage/10-postgres-statefulset.yaml`). L'étape intermédiaire (Deployment + PVC `donnees-postgres`) n'est pas gardée : elle est remplacée à l'étape D. Comparer : `diff solutions/09-stockage/k8s/10-postgres.yaml k8s/10-postgres.yaml`.

**1.** Dans un `emptyDir` : un dossier créé sur le nœud à la création du pod et supprimé avec lui. Il survit au redémarrage d'un **conteneur** du pod, pas à la disparition du **pod** (suppression, nœud qui redémarre, déplacement). Il est utile pour des fichiers temporaires (`/tmp` en lecture seule au TP 10), un cache, ou un dossier partagé entre deux conteneurs d'un même pod.

**2.** `Recreate` arrête l'ancien pod avant de lancer le nouveau. Avec `RollingUpdate`, deux PostgreSQL utiliseraient en même temps les mêmes fichiers (corruption), ou le nouveau attendrait un volume `ReadWriteOnce` déjà pris. Si le nœud du volume disparaît, le volume `local-path` disparaît avec lui (il est sur son disque) et le pod reste `Pending` : c'est la limite d'un stockage local. En production, on utilise un stockage réseau (disque cloud, Ceph, NFS…) qui peut suivre le pod sur un autre nœud, et **des sauvegardes**.

**3.** Oui : avec `Retain`, ni la suppression du PVC ni celle du PV ne touchent aux données ; le dossier `pvc-…_cordee_essai-retain` reste sur le nœud, et `preuve.txt` dedans. Il faut le nettoyer à la main. Pour la base de Cordée : `Retain`, pour qu'une fausse manœuvre (`kubectl delete pvc`, `helm uninstall`, suppression du namespace) ne détruise pas les réservations ; le prix, c'est du ménage manuel. Avec `Delete` (défaut des StorageClass dynamiques), supprimer le PVC supprime le PV **et** les données.

**4.** L'adresse IP du pod `postgres-0` lui-même. Un Service « headless » (`clusterIP: None`) n'a pas d'IP virtuelle ni de répartition de charge : le DNS renvoie directement les IP des pods, et chaque pod d'un StatefulSet obtient un nom stable `<pod>.<service>`. C'est indispensable pour une base répliquée, où les clients doivent savoir qui est le primaire (`postgres-0`) et qui sont les réplicas.

**5.** Au démarrage, l'API crée les tables et insère les refuges si elles n'existent pas. Si elle redémarre (ou reçoit une requête) avant la restauration, la base contient déjà des tables : `pg_dump` les recrée, `psql` s'arrête sur `already exists` (grâce à `ON_ERROR_STOP`), sinon on aurait eu des refuges en double ou une restauration partielle. On restaure donc sur une base vide, puis on relance les clients.

**6.** Le site (`front`) et l'API sont **stateless** : tout leur état est dans la base, on peut en lancer autant qu'on veut, les tuer, les déplacer. La base est **stateful** : elle possède ses données et a besoin d'un volume, d'une identité stable, d'arrêts propres. Seuls les stateless se multiplient sans précaution.

**7.** Non : on aurait trois PostgreSQL indépendants, chacun avec son propre volume vide, et le Service `postgres` répartirait les requêtes entre trois bases différentes. Une base répliquée demande une configuration de réplication (primaire, réplicas, bascule) : on utilise un opérateur (CloudNativePG, Zalando Postgres Operator) ou un service managé (Azure Database for PostgreSQL, Amazon RDS).

**Bonus.** Le piège de `pg_dump | gzip > fichier` : le code de retour du pipeline est celui de `gzip`, qui réussit même si `pg_dump` échoue (mot de passe faux, base absente). Le Job finit `Completed` avec une sauvegarde vide. Lancer `pg_dump` seul vers un fichier, tester son code de retour, puis compresser.

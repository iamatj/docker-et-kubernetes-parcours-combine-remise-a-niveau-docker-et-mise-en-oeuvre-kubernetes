# TP 12 – Industrialiser avec Helm

| Durée | Branche | Correction |
|-------|---------|------------|
| 60 min (15h30 – 16h30) | `tp-12-helm` | `solutions/12-helm/` (`README.md` et `helm/cordee/`) |

Le TP se termine à 16h30 : la clôture (QCM, synthèse, évaluation) occupe les 30 dernières minutes.

## L'incident

> Vendredi, 14h. Léa veut une préproduction pour que l'Office de tourisme teste les réservations de groupe. Karim copie `k8s/` dans `k8s-preprod/`, change le namespace dans 12 fichiers, le message d'accueil, le NodePort, le nombre d'API… et en oublie deux : la préproduction écrit dans la base de production. Il faut un seul modèle, et des valeurs par environnement.

## Objectifs

- Utiliser Helm comme client : dépôts, charts, releases.
- Lire la structure d'un chart : `Chart.yaml`, `values.yaml`, `templates/`, helpers.
- Compléter le chart de Cordée et l'installer avec des valeurs propres à la préproduction.
- Gérer le cycle de vie d'une release : install, upgrade, history, rollback, uninstall.

## Point de départ

```bash
cd ~/cordee
git fetch
git stash -u
git checkout tp-12-helm
helm version
ls tp/12-helm/cordee tp/12-helm/cordee/templates
```

La production (`k8s/`, namespace `cordee`) reste en place et n'est pas touchée : la préproduction ira dans le namespace `cordee-preprod`.

## Étapes

### 1. Helm, vous l'avez déjà utilisé (8 min)

Le lab a installé Traefik et Headlamp avec Helm :

```bash
helm list -A
helm repo list
helm search repo traefik/traefik
helm -n traefik history traefik
helm -n traefik get values traefik
```

**Question 1** – Que sont un **chart**, une **release**, un **repository** ? D'où viennent les valeurs affichées par `get values` ?

### 2. La structure d'un chart (7 min)

```bash
cd /tmp && helm create demo && find demo -type f | sort && cd ~/cordee
helm template essai /tmp/demo | head -30
rm -rf /tmp/demo
```

`helm template` affiche les manifests produits, sans rien installer.

Ouvrez maintenant le chart de Cordée :

```bash
cat tp/12-helm/cordee/Chart.yaml tp/12-helm/cordee/values.yaml
cat tp/12-helm/cordee/templates/_helpers.tpl
```

Repérez `{{ .Values.… }}`, `{{ .Release.Name }}`, `{{ include "cordee.labels" . | nindent 4 }}`.

### 3. Compléter le chart (15 min)

```bash
mkdir -p helm
cp -r tp/12-helm/cordee helm/
helm lint helm/cordee
```

`helm lint` échoue sur `TODO 1`. Complétez les trois `TODO`, en relançant `helm lint helm/cordee` après chacun :

| TODO | Fichier | Remplacez le `{{ fail … }}` par |
|------|---------|---------------------------------|
| 1 | `helm/cordee/templates/api.yaml` | `{{ .Values.api.replicas }}` |
| 2 | `helm/cordee/templates/configuration.yaml` | `{{ .Values.messageAccueil \| quote }}` |
| 3 | `helm/cordee/templates/front.yaml` | `{{ include "cordee.image" .Values.front }}` |

Attendu : `1 chart(s) linted, 0 chart(s) failed`. Regardez le résultat :

```bash
helm template cordee helm/cordee --namespace cordee-preprod | grep -E '^kind:|image:|replicas:|MESSAGE'
```

### 4. Les valeurs de la préproduction (5 min)

Créez `helm/cordee/values-preprod.yaml` :

```yaml
messageAccueil: "PRÉPRODUCTION – réservations fictives"
api:
  replicas: 1
front:
  service:
    nodePort: 30081
```

```bash
helm template cordee helm/cordee -f helm/cordee/values-preprod.yaml | grep -E 'replicas:|nodePort:|MESSAGE'
```

**Question 2** – Dans quel ordre Helm combine-t-il `values.yaml`, `-f values-preprod.yaml` et `--set` ?

### 5. Installer (8 min)

```bash
helm install cordee helm/cordee -n cordee-preprod --create-namespace \
  -f helm/cordee/values-preprod.yaml --set db.motDePasse=Preprod-2026 --wait --timeout 3m
helm -n cordee-preprod list
kubectl -n cordee-preprod get all,pvc
curl -s http://192.168.56.30:30081/api/info | jq
curl -s http://192.168.56.30:30080/api/info | jq -r .message
```

Attendu : la préproduction répond sur `30081` avec le message `PRÉPRODUCTION – réservations fictives` et l'API `1.0` ; la production, sur `30080`, n'a pas bougé. Ouvrez <http://192.168.56.30:30081>.

### 6. Mettre à jour, revenir en arrière (12 min)

```bash
helm upgrade cordee helm/cordee -n cordee-preprod -f helm/cordee/values-preprod.yaml \
  --set db.motDePasse=Preprod-2026 --set api.image.tag=1.1 --set front.image.tag=1.1 --wait
curl -s http://192.168.56.30:30081/api/info | jq -r .version
helm -n cordee-preprod history cordee
helm -n cordee-preprod get values cordee
```

Attendu : `1.1`, et le site en bleu. Revenez à la révision 1 :

```bash
helm -n cordee-preprod rollback cordee 1 --wait
curl -s http://192.168.56.30:30081/api/info | jq -r .version
helm -n cordee-preprod history cordee
```

**Question 3** – Pourquoi faut-il redonner `-f values-preprod.yaml` et `--set db.motDePasse=…` à chaque `upgrade` ? Que propose `--reuse-values`, et quel est son piège ?

**Question 4** – Changez seulement le message (`--set messageAccueil="Groupes : -20 %"` dans un `upgrade`). Les pods de l'API redémarrent-ils ? Grâce à quelle ligne du chart ?

### 7. Désinstaller (5 min)

```bash
helm -n cordee-preprod uninstall cordee
kubectl -n cordee-preprod get all,pvc
```

Il ne reste que le PVC `donnees-postgres-0` : Helm ne supprime pas les volumes créés par un StatefulSet.

**Question 5** – Est-ce un bien ou un mal ? Comment le supprimer, et que fallait-il faire pour le garder sciemment ?

```bash
kubectl delete namespace cordee-preprod
```

## Questions de fin

6. Le chart Cordée et les manifests de `k8s/` décrivent la même application : lequel garder pour la production, et pourquoi ?
7. Où publier le chart pour que d'autres équipes l'installent avec `helm install` ?

## Bonus

- `helm package helm/cordee` puis `helm push cordee-0.1.0.tgz oci://ghcr.io/<compte>/charts` (après `helm registry login ghcr.io`).
- `helm upgrade --install` : une seule commande pour la première installation et les suivantes, idéale en CI.
- `helm diff` (un plugin) : voir ce qu'un `upgrade` changerait.

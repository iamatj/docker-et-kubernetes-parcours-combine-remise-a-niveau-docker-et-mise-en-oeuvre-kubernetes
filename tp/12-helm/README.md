# TP 12 – Industrialiser avec Helm

| Durée | Branche | Correction |
|-------|---------|------------|
| 60 min (15h30 – 16h30) | `tp-12-helm` | `solutions/12-helm/` (`README.md` et `helm/huiteo/`) |

Le TP se termine à 16h30 : la clôture (QCM, synthèse, évaluation) occupe les 30 dernières minutes.

## L'incident

> Vendredi, 14h. Léa veut une préproduction pour que le groupement d'études teste les rendez-vous à plusieurs signataires. Karim copie `k8s/` dans `k8s-preprod/`, change le namespace dans 12 fichiers, le message d'accueil, le NodePort, le nombre d'API… et en oublie deux : la préproduction écrit dans la base de production. Il faut un seul modèle, et des valeurs par environnement.

## Objectifs

- Utiliser Helm comme client : dépôts, charts, releases.
- Lire la structure d'un chart : `Chart.yaml`, `values.yaml`, `templates/`, helpers.
- Compléter le chart de Huiteo et l'installer avec des valeurs propres à la préproduction.
- Gérer le cycle de vie d'une release : install, upgrade, history, rollback, uninstall.

## Point de départ

```bash
cd ~/huiteo
git fetch
git stash -u
git checkout tp-12-helm
helm version
ls tp/12-helm/huiteo tp/12-helm/huiteo/templates
```

La production (`k8s/`, namespace `huiteo`) reste en place et n'est pas touchée : la préproduction ira dans le namespace `huiteo-preprod`.

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

Si vous êtes en retard, sautez ce premier bloc et passez directement au chart de Huiteo, plus bas.

```bash
cd /tmp && helm create demo && find demo -type f | sort && cd ~/huiteo
helm template essai /tmp/demo | head -30
rm -rf /tmp/demo
```

`helm template` affiche les manifests produits, sans rien installer.

Ouvrez maintenant le chart de Huiteo :

```bash
cat tp/12-helm/huiteo/Chart.yaml tp/12-helm/huiteo/values.yaml
cat tp/12-helm/huiteo/templates/_helpers.tpl
```

Repérez `{{ .Values.… }}`, `{{ .Release.Name }}`, `{{ include "huiteo.labels" . | nindent 4 }}`.

### 3. Compléter le chart (15 min)

```bash
mkdir -p helm
cp -r tp/12-helm/huiteo helm/
helm lint helm/huiteo
```

`helm lint` échoue sur `TODO 1`. Complétez les trois `TODO`, en relançant `helm lint helm/huiteo` après chacun :

| TODO | Fichier | Remplacez le `{{ fail … }}` par |
|------|---------|---------------------------------|
| 1 | `helm/huiteo/templates/api.yaml` | `{{ .Values.api.replicas }}` |
| 2 | `helm/huiteo/templates/configuration.yaml` | `{{ .Values.messageAccueil \| quote }}` |
| 3 | `helm/huiteo/templates/front.yaml` | `{{ include "huiteo.image" .Values.front }}` |

Attendu : `1 chart(s) linted, 0 chart(s) failed`. Regardez le résultat :

```bash
helm template huiteo helm/huiteo --namespace huiteo-preprod | grep -E '^kind:|image:|replicas:|MESSAGE'
```

### 4. Les valeurs de la préproduction (5 min)

Créez `helm/huiteo/values-preprod.yaml` :

```yaml
messageAccueil: "PRÉPRODUCTION – rendez-vous fictifs"
api:
  replicas: 1
front:
  service:
    nodePort: 30081
```

```bash
helm template huiteo helm/huiteo -f helm/huiteo/values-preprod.yaml | grep -E 'replicas:|nodePort:|MESSAGE'
```

**Question 2** – Dans quel ordre Helm combine-t-il `values.yaml`, `-f values-preprod.yaml` et `--set` ?

### 5. Installer (8 min)

```bash
helm install huiteo helm/huiteo -n huiteo-preprod --create-namespace \
  -f helm/huiteo/values-preprod.yaml --set db.motDePasse=Preprod-2026 --wait --timeout 3m
helm -n huiteo-preprod list
kubectl -n huiteo-preprod get all,pvc
curl -s http://10.10.0.11:30081/api/info | jq
curl -s http://10.10.0.11:30080/api/info | jq -r .message
```

Attendu : la préproduction répond sur `30081` avec le message `PRÉPRODUCTION – rendez-vous fictifs` et l'API `1.0` ; la production, sur `30080`, n'a pas bougé. Ouvrez <http://10.10.0.11:30081>.

### 6. Mettre à jour, revenir en arrière (12 min)

```bash
helm upgrade huiteo helm/huiteo -n huiteo-preprod -f helm/huiteo/values-preprod.yaml \
  --set db.motDePasse=Preprod-2026 --set api.image.tag=1.1 --set front.image.tag=1.1 --wait
curl -s http://10.10.0.11:30081/api/info | jq -r .version
helm -n huiteo-preprod history huiteo
helm -n huiteo-preprod get values huiteo
```

Attendu : `1.1`, et le site en bleu. Revenez à la révision 1 :

```bash
helm -n huiteo-preprod rollback huiteo 1 --wait
curl -s http://10.10.0.11:30081/api/info | jq -r .version
helm -n huiteo-preprod history huiteo
```

**Question 3** – Pourquoi faut-il redonner `-f values-preprod.yaml` et `--set db.motDePasse=…` à chaque `upgrade` ? Que propose `--reuse-values`, et quel est son piège ?

**Question 4** – Changez seulement le message (`--set messageAccueil="Groupes : -20 %"` dans un `upgrade`). Les pods de l'API redémarrent-ils ? Grâce à quelle ligne du chart ?

### 7. Désinstaller (5 min)

```bash
helm -n huiteo-preprod uninstall huiteo
kubectl -n huiteo-preprod get all,pvc
```

Il ne reste que le PVC `donnees-postgres-0` : Helm ne supprime pas les volumes créés par un StatefulSet.

**Question 5** – Est-ce un bien ou un mal ? Comment le supprimer, et que fallait-il faire pour le garder sciemment ?

```bash
kubectl delete namespace huiteo-preprod
```

## Questions de fin

6. Le chart Huiteo et les manifests de `k8s/` décrivent la même application : lequel garder pour la production, et pourquoi ?
7. Où publier le chart pour que d'autres équipes l'installent avec `helm install` ?

## Bonus

- `helm package helm/huiteo` puis `helm push huiteo-0.1.0.tgz oci://ghcr.io/<compte>/charts` (après `helm registry login ghcr.io`).
- `helm upgrade --install` : une seule commande pour la première installation et les suivantes, idéale en CI.
- `helm diff` (un plugin) : voir ce qu'un `upgrade` changerait.

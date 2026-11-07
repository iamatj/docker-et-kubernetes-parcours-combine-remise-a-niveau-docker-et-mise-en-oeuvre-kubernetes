# Docker et Kubernetes – parcours combiné

Remise à niveau Docker et mise en œuvre de Kubernetes, en 3 jours (21 h), dont **74 % de pratique**.

Fil rouge : **Cordée**, une jeune entreprise grenobloise qui vend en ligne les nuitées de cinq refuges de montagne. On part d'une API « qui marche chez Karim » et on finit avec une application conteneurisée, déployée sur un cluster Kubernetes, sécurisée, exposée en HTTPS et installée par Helm.

| Document | Contenu |
|----------|---------|
| [`programme-3-jours.md`](programme-3-jours.md) | le programme détaillé : fil rouge, chapitres, horaires, correspondance avec le programme officiel |
| [`guide-installation-lab.md`](guide-installation-lab.md) | le lab : machines, préparation en une commande, vérifications, dépannage |
| [`app/`](app/) | l'application Cordée : site nginx, API Flask, PostgreSQL |
| [`presentation/`](presentation/) | les slides (sur `main` uniquement) |
| [QCM](https://iamatj.github.io/docker-et-kubernetes-parcours-combine-remise-a-niveau-docker-et-mise-en-oeuvre-kubernetes/qcm/) | un QCM autocorrigé de 10 questions par jour |

## Les branches

Chaque TP a sa branche. La branche `tp-NN-…` contient l'application dans l'état attendu **au début** du TP, son énoncé `tp/NN-…/README.md`, et les corrections des TP précédents dans `solutions/`. Chaque branche part de la précédente.

| Jour | TP | Branche | Sujet |
|------|----|---------|-------|
| 1 | 00 | `tp-00-prise-en-main` | client, daemon, API Docker |
| 1 | 01 | `tp-01-conteneurs` | images, conteneurs, registre privé |
| 1 | 02 | `tp-02-dockerfile` | Dockerfile multi-stage, non root, BuildKit |
| 1 | 03 | `tp-03-compose` | volumes, réseaux, Docker Compose V2 |
| 1 | 04 | `tp-04-securite-images` | scan Trivy, conteneur durci |
| 2 | 05 | `tp-05-cluster` | architecture du cluster, Pod, ReplicaSet, Deployment, API REST |
| 2 | 06 | `tp-06-deploiement` | YAML, Deployments, Services, NodePort, scaling |
| 2 | 07 | `tp-07-mise-a-jour` | rolling update, rollback, LoadBalancer |
| 2 | 08 | `tp-08-configuration` | étiquettes, ConfigMap, Secret, sondes, diagnostic |
| 3 | 09 | `tp-09-stockage` | PV, PVC, StorageClass, StatefulSet |
| 3 | 10 | `tp-10-securite` | RBAC, ServiceAccounts, Network Policies, SecurityContext |
| 3 | 11 | `tp-11-reseau` | DNS, Ingress et TLS, Gateway API |
| 3 | 12 | `tp-12-helm` | chart, values, releases |
| – | – | `solution-finale` | l'état complet de Cordée après le TP 12 |

## Pour les participants

Le premier jour, sur la machine `client` :

```bash
git clone https://github.com/iamatj/docker-et-kubernetes-parcours-combine-remise-a-niveau-docker-et-mise-en-oeuvre-kubernetes.git ~/cordee
cd ~/cordee
git checkout tp-00-prise-en-main
```

Au début de chaque TP suivant :

```bash
cd ~/cordee && git fetch
git stash -u                    # met de côté le travail du TP précédent
git checkout tp-NN-sujet
kubectl apply -R -f k8s/        # à partir du TP 07 : l'état attendu au début du TP
```

La correction d'un TP est dans `solutions/NN-sujet/`, aux mêmes chemins qu'à la racine. Sur une branche, `k8s/` est l'état de **départ**, pas la correction : `diff -r solutions/NN-sujet/k8s k8s` montre ce qu'il fallait faire.

## Pour le formateur

1. **Images** : onglet **Actions** > workflow **images** > **Run workflow**, puis rendre publics les paquets `cordee-api` et `cordee-front` (profil GitHub > **Packages** > **Package settings** > **Change visibility**).
2. **Lab** : faire préparer les machines décrites dans le guide, puis lancer `bash lab/preparer-lab.sh` sur chaque `client` (la veille), et vérifier avec `bash lab/verifier-lab.sh`.
3. **Slides** : ouvrir `presentation/index.html` dans un navigateur (flèches pour naviguer, `N` pour les notes, `F` pour le plein écran). Après une modification d'une slide : `python presentation/construire.py`.
4. **QCM** : publiés par GitHub Pages depuis `main` ; l'adresse est sur les slides `qcm-j1`, `qcm-j2`, `qcm-j3`.

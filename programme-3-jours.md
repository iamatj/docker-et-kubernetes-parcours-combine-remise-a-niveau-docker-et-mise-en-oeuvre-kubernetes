# Docker et Kubernetes – parcours combiné : programme détaillé (3 jours, 21 h)

Ce document est la source de vérité de la formation : les slides, les TP et les QCM en découlent.

## Rythme d'une journée

| Créneau | Horaires |
|---------|----------|
| Matin | 9h00 – 12h30, pause de 10h45 à 11h00 |
| Déjeuner | 12h30 – 13h30 |
| Après-midi | 13h30 – 17h00, pause de 15h15 à 15h30 |

Une journée de 7 h compte 30 min de pauses, soit **390 min de contenu**.

| Jour | Pratique (TP) | Théorie | Autre (accueil, récapitulatif, QCM, clôture) | Part de pratique |
|------|---------------|---------|----------------------------------------------|------------------|
| 1 | 285 min | 75 min | 30 min | 73,1 % |
| 2 | 295 min | 70 min | 25 min | 75,6 % |
| 3 | 290 min | 60 min | 40 min | 74,4 % |
| **Total** | **870 min (14 h 30)** | **205 min** | **95 min** | **74,4 %** |

La théorie d'un chapitre tient en 10 à 25 min : l'incident chez Cordée, le concept, puis le TP. Les QCM sont comptés dans « autre ».

## Le fil rouge : Cordée

**Cordée** est une jeune entreprise grenobloise qui vend en ligne les nuitées de cinq refuges de montagne (Belledonne, Mont-Blanc, Grandes Rousses, Écrins). L'hiver arrive, et avec lui la ruée des réservations de Noël.

L'application, au début de la formation :

- un site statique servi par nginx (`app/front`) qui appelle l'API sur `/api/` ;
- une API Python Flask (`app/api`) : `/api/refuges`, `/api/reservations`, `/api/info` (version, pod qui a répondu, message d'accueil), `/healthz`, `/readyz` (vérifie la base), logs JSON ;
- une base PostgreSQL ;
- le tout lancé « à la main » sur le poste de Karim, avec un Dockerfile historique de 1 Go qui tourne en root.

Les personnages :

| Personnage | Rôle | Ce qu'il attend de la formation |
|------------|------|---------------------------------|
| **Léa Marchand** | fondatrice, ancienne gardienne de refuge | que le site tienne le soir de l'ouverture des réservations |
| **Karim Benali** | développeur de l'API et du site | livrer souvent sans tout casser |
| **Sophie Garnier** | exploitation et astreinte | comprendre le cluster loué, dormir la nuit |

## Les chapitres

| Ch. | Incident chez Cordée | Concept | Module officiel | TP et branche |
|-----|----------------------|---------|-----------------|---------------|
| 1 | « Chez moi ça marche » : l'API refuse de démarrer sur le serveur, pas la même version de Python | conteneur vs VM, architecture Docker (daemon, client, API) | 1 | TP 00 `tp-00-prise-en-main` |
| 2 | Le site vitrine est tombé dans la nuit, personne ne sait le relancer ni quelle version tournait | images, couches, registres, cycle de vie d'un conteneur | 2 | TP 01 `tp-01-conteneurs` |
| 3 | L'image de l'API pèse plus d'1 Go, chaque build prend des minutes, et elle tourne en root | Dockerfile, multi-stage, BuildKit, non-root | 3 | TP 02 `tp-02-dockerfile` |
| 4 | Après un redémarrage, toutes les réservations ont disparu, et l'API démarre avant la base | volumes, réseaux, Compose V2, `service_healthy` | 4 | TP 03 `tp-03-compose` |
| 5 | Un audit trouve des centaines de CVE dans l'image ; et un seul serveur pour toute la saison | limites de Compose, orchestration, scan | 5 | TP 04 `tp-04-securite-images` |
| 6 | Cordée loue un cluster de 3 machines ; Sophie doit comprendre ce que l'hébergeur a monté | control plane, nœuds, objets, kubectl, API REST, interface web | 6 | TP 05 `tp-05-cluster` |
| 7a | Il faut mettre Cordée en ligne sur le cluster avant vendredi | Deployment, YAML, scaling, ClusterIP / NodePort | 7 | TP 06 `tp-06-deploiement` |
| 7b | La mise à jour 1.1 de samedi 8h a coupé le site ; et quelqu'un a livré une 1.2 qui n'existe pas | rolling update, rollback, LoadBalancer | 7 | TP 07 `tp-07-mise-a-jour` |
| 8 | Le mot de passe de la base est en clair dans Git ; un pod répond alors que la base est en panne | labels, ConfigMap, Secret, sondes, méthode de diagnostic | 8 | TP 08 `tp-08-configuration` |
| 9 | Le pod PostgreSQL a redémarré : 47 réservations perdues | PV, PVC, StorageClass, rétention, StatefulSet | 9 | TP 09 `tp-09-stockage` |
| 10 | Un stagiaire a supprimé un déploiement en production ; un pod compromis pouvait joindre la base | RBAC, ServiceAccounts, Network Policies, SecurityContext | 10 | TP 10 `tp-10-securite` |
| 11 | Le partenaire Office de tourisme exige `https://cordee.lab` ; Karim veut tester la 1.1 sur 10 % des visiteurs | DNS, Ingress, TLS, limites d'Ingress, Gateway API | 11 | TP 11 `tp-11-reseau` |
| 12 | Créer une préproduction a demandé de recopier et retoucher 12 fichiers YAML à la main | Helm : chart, values, releases | 12 | TP 12 `tp-12-helm` |

Les bugs de départ sont dans le code des branches : le Dockerfile historique (`app/api/Dockerfile.avant`), le mot de passe en clair dans `k8s/` (TP 06 à 07), PostgreSQL sur un `emptyDir` (TP 06 à 08), l'absence de toute restriction réseau (jusqu'au TP 10).

## Jour 1 – Remise à niveau Docker

Tout se passe sur la machine `client`.

| Heure | Type | Contenu |
|-------|------|---------|
| 9h00 – 9h15 | Autre | Accueil, tour de table, présentation du lab |
| 9h15 – 9h30 | Théorie | Chapitre 1 : conteneurs vs VM, Docker dans le DevOps, daemon / client / API, Engine vs Desktop, `docker compose` sans tiret |
| 9h30 – 10h00 | Pratique | **TP 00** : prise en main du poste et de Docker (30 min) |
| 10h00 – 10h15 | Théorie | Chapitre 2 : couches et cache, registres et nommage, options de `docker run`, cycle de vie |
| 10h15 – 10h45 | Pratique | **TP 01** : conteneurs, images et registres (1/2) |
| 10h45 – 11h00 | Pause | |
| 11h00 – 12h00 | Pratique | **TP 01** (2/2) – 90 min au total |
| 12h00 – 12h20 | Théorie | Chapitre 3 : instructions du Dockerfile, multi-stage, slim / alpine / distroless, non-root, `.dockerignore`, BuildKit |
| 12h20 – 12h30 | Pratique | **TP 02** : Dockerfile multi-stage (1/2) |
| 12h30 – 13h30 | Déjeuner | |
| 13h30 – 14h30 | Pratique | **TP 02** (2/2) – 70 min au total |
| 14h30 – 14h45 | Théorie | Chapitre 4 : bind mount / volume / tmpfs, réseaux bridge / host / none, DNS interne, Compose V2 |
| 14h45 – 15h15 | Pratique | **TP 03** : stack Compose (1/2) |
| 15h15 – 15h30 | Pause | |
| 15h30 – 16h15 | Pratique | **TP 03** (2/2) – 75 min au total |
| 16h15 – 16h25 | Théorie | Chapitre 5 : limites de Compose en multi-hôte, Swarm et Kubernetes, surface d'attaque |
| 16h25 – 16h45 | Pratique | **TP 04** : scanner et durcir ses images (20 min) |
| 16h45 – 17h00 | Autre | **QCM du jour 1** (10 questions, 15 min) |

## Jour 2 – Kubernetes : fondamentaux et exploitation

Le cluster `control-plane` / `worker-1` / `worker-2` est déjà monté par les scripts du lab ; on le pilote depuis `client`.

| Heure | Type | Contenu |
|-------|------|---------|
| 9h00 – 9h10 | Autre | Récapitulatif : les questions les plus ratées du QCM 1 |
| 9h10 – 9h35 | Théorie | Chapitre 6 : de Docker à l'orchestration, CNCF et distributions, control plane et nœuds, Pod / ReplicaSet / Deployment / Service / Namespace, kubectl / interface web / API REST |
| 9h35 – 10h45 | Pratique | **TP 05** : explorer le cluster (70 min) |
| 10h45 – 11h00 | Pause | |
| 11h00 – 11h20 | Théorie | Chapitre 7a : impératif vs déclaratif, YAML, Deployment, replicas, ClusterIP / NodePort |
| 11h20 – 12h30 | Pratique | **TP 06** : déployer Cordée (70 min) |
| 12h30 – 13h30 | Déjeuner | |
| 13h30 – 13h40 | Théorie | Chapitre 7b : rolling update, `maxSurge` / `maxUnavailable`, historique et rollback, LoadBalancer |
| 13h40 – 15h00 | Pratique | **TP 07** : mettre à jour sans couper (80 min) |
| 15h00 – 15h15 | Théorie | Chapitre 8 : labels / selectors / annotations, ConfigMap, Secret et ses limites, sondes, méthode de diagnostic, DaemonSets et affinités (mention) |
| 15h15 – 15h30 | Pause | |
| 15h30 – 16h45 | Pratique | **TP 08** : configuration, sondes et diagnostic (75 min) |
| 16h45 – 17h00 | Autre | **QCM du jour 2** (10 questions, 15 min) |

## Jour 3 – Stockage, sécurité, réseau et industrialisation

| Heure | Type | Contenu |
|-------|------|---------|
| 9h00 – 9h10 | Autre | Récapitulatif : les questions les plus ratées du QCM 2 |
| 9h10 – 9h25 | Théorie | Chapitre 9 : volumes, PV / PVC, StorageClass, rétention, stateful vs stateless |
| 9h25 – 10h30 | Pratique | **TP 09** : stockage persistant (65 min) |
| 10h30 – 10h45 | Théorie | Chapitre 10 : RBAC, profils, ServiceAccounts, Network Policies (CNI), SecurityContext |
| 10h45 – 11h00 | Pause | |
| 11h00 – 12h30 | Pratique | **TP 10** : sécuriser le cluster (90 min) |
| 12h30 – 13h30 | Déjeuner | |
| 13h30 – 13h45 | Théorie | Chapitre 11 : modèle réseau, Service Discovery, Ingress Controller, TLS, limites d'Ingress, Gateway API |
| 13h45 – 15h00 | Pratique | **TP 11** : exposition avancée (75 min) |
| 15h00 – 15h15 | Théorie | Chapitre 12 : Helm, charts / releases / repositories, templates et values |
| 15h15 – 15h30 | Pause | |
| 15h30 – 16h30 | Pratique | **TP 12** : industrialiser avec Helm (60 min) |
| 16h30 – 16h45 | Autre | Clôture : **QCM du jour 3** (10 questions, 15 min) |
| 16h45 – 17h00 | Autre | Clôture : synthèse (Docker pour le packaging, Kubernetes pour l'orchestration, autoscaling / HA / monitoring, managé vs on-premise), évaluation à chaud, tour de table |

Les 30 dernières minutes sont la clôture : le TP 12 se termine à 16h30.

## QCM

Un QCM de 10 questions par jour, sur les chapitres du jour, en page HTML autocorrigée : <https://iamatj.github.io/docker-et-kubernetes-parcours-combine-remise-a-niveau-docker-et-mise-en-oeuvre-kubernetes/qcm/>

- jours 1 et 2 : en fin de journée (16h45 – 17h00), 15 min prises sur le dernier module ; le récapitulatif du lendemain matin part des questions les plus ratées ;
- jour 3 : dans la clôture (16h30 – 16h45).

## Correspondance avec le programme officiel

Les durées officielles incluent leur part de pauses ; les durées prévues aussi.

| Module officiel | Durée officielle | Créneau prévu | Durée prévue | dont TP |
|-----------------|------------------|---------------|--------------|---------|
| 1 – Positionnement et architecture de Docker | 1 h | J1 9h00 – 10h00 | 1 h (dont accueil 15 min) | 30 min |
| 2 – Conteneurs, images et registres | 2 h | J1 10h00 – 12h00 | 2 h | 90 min |
| 3 – Dockerfile et bonnes pratiques | 1 h 30 | J1 12h00 – 12h30, 13h30 – 14h30 | 1 h 30 | 70 min |
| 4 – Volumes, réseau et Compose V2 | 2 h | J1 14h30 – 16h15 | 1 h 45 | 75 min |
| 5 – Ouverture sur l'orchestration | 30 min | J1 16h15 – 16h45 | 30 min | 20 min |
| QCM du jour 1 | – | J1 16h45 – 17h00 | 15 min (pris sur le module 4) | – |
| 6 – Positionnement et architecture de Kubernetes | 2 h | J2 9h00 – 11h00 | 2 h (dont récapitulatif 10 min) | 70 min |
| 7 – Déploiement et exposition d'applications | 3 h | J2 11h00 – 12h30, 13h30 – 15h00 | 3 h | 150 min |
| 8 – Exploitation et diagnostic des workloads | 2 h | J2 15h00 – 16h45 | 1 h 45 | 75 min |
| QCM du jour 2 | – | J2 16h45 – 17h00 | 15 min (pris sur le module 8) | – |
| 9 – Stockage persistant | 1 h 30 | J3 9h00 – 10h30 | 1 h 30 (dont récapitulatif 10 min) | 65 min |
| 10 – Sécurité du cluster | 2 h | J3 10h30 – 12h30 | 2 h | 90 min |
| 11 – Réseau et exposition avancée | 1 h 30 | J3 13h30 – 15h00 | 1 h 30 | 75 min |
| 12 – Industrialiser avec Helm | 1 h 30 | J3 15h00 – 16h30 | 1 h 30 | 60 min |
| Atelier final de synthèse | 30 min | J3 16h30 – 17h00 | 30 min (QCM, synthèse, évaluation) | – |

Les modules 4 et 8 cèdent chacun 15 min au QCM de fin de journée. Le module 4 garde tous ses points (volumes, réseaux, Compose, `depends_on` avec `service_healthy`) ; le module 8 garde la méthode de diagnostic dans le TP 08 et traite DaemonSets et affinités en mention.

## Correspondance détaillée

| Module | Points du programme officiel | Chapitre et horaires | Slides | TP (branche) |
|--------|------------------------------|----------------------|--------|--------------|
| 1 | conteneur vs VM, DevOps, daemon / client / API, Engine vs Desktop, `docker compose`, vocabulaire | Ch. 1, J1 9h15 – 10h00 | `c1-incident` à `c1-tp` | TP 00 (`tp-00-prise-en-main`) : `docker version`, `info`, API par le socket, contextes |
| 2 | couches, cache, historique, Docker Hub et registres privés, options du run, cycle de vie, exec / logs / inspect / stats | Ch. 2, J1 10h00 – 12h00 | `c2-incident` à `c2-tp` | TP 01 (`tp-01-conteneurs`) : site vitrine dans nginx, PostgreSQL limité en ressources, registre privé local |
| 3 | FROM, RUN, CMD, ENTRYPOINT, COPY, ADD, EXPOSE, ENV, ARG, multi-stage, distroless / alpine, non-root, `.dockerignore`, BuildKit | Ch. 3, J1 12h00 – 14h30 | `c3-incident` à `c3-tp` | TP 02 (`tp-02-dockerfile`) : de 1 Go à une image slim multi-stage non root |
| 4 | bind mount, volumes nommés, tmpfs, nettoyage, bridge / host / none, ports, DNS interne, `compose.yaml`, up / down / ps / logs / exec / build, `service_healthy` | Ch. 4, J1 14h30 – 16h15 | `c4-incident` à `c4-tp` | TP 03 (`tp-03-compose`) : Cordée complète avec volume et deux réseaux |
| 5 | limites de Compose, Swarm, Kubernetes, surface d'attaque, scan, moindre privilège | Ch. 5, J1 16h15 – 16h45 | `c5-incident` à `c5-tp` | TP 04 (`tp-04-securite-images`) : Trivy, `--read-only`, `--cap-drop` |
| 6 | Cloud Native, CNCF, distributions, control plane, nœuds, objets, kubectl / interface web / API REST | Ch. 6, J2 9h10 – 10h45 | `c6-incident` à `c6-tp` | TP 05 (`tp-05-cluster`) : nœuds, pods système, Pod → ReplicaSet → Deployment, API REST, Headlamp |
| 7 | déploiement manuel et YAML, syntaxe YAML, replicas, rolling update, rollback, ClusterIP / NodePort / LoadBalancer, exposition externe | Ch. 7a et 7b, J2 11h00 – 15h00 | `c7-incident` à `c7b-tp` | TP 06 (`tp-06-deploiement`) et TP 07 (`tp-07-mise-a-jour`) |
| 8 | labels / selectors / annotations, ConfigMap, Secret et ses limites, liveness / readiness / startup, troubleshooting, DaemonSets et affinités | Ch. 8, J2 15h00 – 16h45 | `c8-incident` à `c8-tp` | TP 08 (`tp-08-configuration`) : configuration externalisée, sondes, trois pannes à diagnostiquer |
| 9 | volumes, PV / PVC, StorageClass, rétention, StatefulSet | Ch. 9, J3 9h10 – 10h30 | `c9-incident` à `c9-tp` | TP 09 (`tp-09-stockage`) : PVC, `Retain` vs `Delete`, PostgreSQL en StatefulSet |
| 10 | Roles, ClusterRoles, bindings, profils dev / opérateur / admin, ServiceAccounts, Network Policies, SecurityContext | Ch. 10, J3 10h30 – 12h30 | `c10-incident` à `c10-tp` | TP 10 (`tp-10-securite`) |
| 11 | pod-to-pod, pod-to-service, DNS, variables d'environnement, Ingress Controller, HTTP / HTTPS, TLS, limites d'Ingress, Gateway API | Ch. 11, J3 13h30 – 15h00 | `c11-incident` à `c11-tp` | TP 11 (`tp-11-reseau`) : Traefik, `https://cordee.lab`, HTTPRoute pondérée 90 / 10 |
| 12 | charts, releases, repositories, installation, templates / values / helpers, `values.yaml`, install / upgrade / rollback / uninstall | Ch. 12, J3 15h00 – 16h30 | `c12-incident` à `c12-tp` | TP 12 (`tp-12-helm`) : chart Cordée, préproduction |
| Atelier final | packaging vs orchestration, autoscaling / HA / monitoring, managé vs on-premise, retours | Clôture, J3 16h30 – 17h00 | `epilogue`, `qcm-j3`, `fin` | – |

# Correction du TP 00 – Prise en main du poste et de Docker

**1.** Les numéros dépendent de l'installation (Docker Engine 28 ou 29 au moment de la formation). L'important : il y a deux programmes, le client et le serveur, qui peuvent avoir des versions différentes ; ils s'entendent sur une version d'API (`API version`, par exemple 1.5x). Un client plus récent sait parler à un daemon plus ancien en baissant sa version d'API.

**2.** Dans `/var/lib/docker` (`DockerRootDir`) : couches des images, systèmes de fichiers des conteneurs, volumes. Le pilote de stockage est `overlayfs` (ou `overlay2`). Le socket `/var/run/docker.sock` est ouvert par `dockerd`, lancé par systemd ; il appartient à `root:docker`.

**3.** Tout ce que fait le client passe par cette API REST : une chaîne CI, un IDE, un outil de supervision, Compose lui-même peuvent piloter Docker sans le client. Le risque : qui peut écrire sur le socket contrôle le daemon, qui tourne en root. Être dans le groupe `docker` revient à être root sur la machine (`docker run -v /:/hote …`). Monter le socket dans un conteneur lui donne le même pouvoir (on le fera pour Trivy au TP 04, en connaissance de cause).

**4.** Le client contacte le daemon ; le daemon télécharge l'image depuis le registre ; il crée un conteneur et lance son programme ; il renvoie la sortie au client, qui l'affiche. Le téléchargement n'a pas eu lieu : l'image était déjà présente (préchargée par `lab/preparer-lab.sh`). Sans elle, on aurait vu `Unable to find image … locally` puis `Pulling from …`.

**5.** Compose V1 (le programme Python `docker-compose`) n'est plus maintenu et a été retiré des distributions Docker depuis juin 2023. Compose V2 est un plugin du client écrit en Go : `docker compose`. On remplace `docker-compose` par `docker compose` dans les scripts ; le fichier `docker-compose.yml` reste lu, mais le nom recommandé est `compose.yaml`, et la clé `version:` en tête de fichier est obsolète (ignorée).

**6.** Docker Desktop fait tourner le daemon dans une petite VM Linux (WSL 2 sous Windows, une VM dédiée sous macOS), le client restant sur le poste. Différences : Desktop est une application graphique avec une licence payante au-delà d'une certaine taille d'entreprise ; le réseau et les montages de fichiers traversent la VM (plus lents, `host` ne se comporte pas pareil) ; Desktop peut embarquer un Kubernetes local. Docker Engine sur Linux est gratuit, sans VM, et c'est ce qu'on trouve sur les serveurs et les agents de CI.

**7.** Un **Dockerfile** décrit comment construire une **image** ; une image (des couches en lecture seule et une configuration) est stockée dans un **registry** ; le **daemon** télécharge l'image et en crée des **conteneurs** (des processus isolés qui ajoutent une couche en écriture) ; **Compose** décrit dans un fichier YAML un ensemble de conteneurs, réseaux et volumes qui forment une application.

**8.** La machine virtuelle embarque son propre noyau ; les conteneurs partagent celui de l'hôte (isolement par namespaces et cgroups). Pour deux clients qui ne se font pas confiance, l'isolement d'une VM (ou d'un conteneur dans une VM, comme sur les offres managées) est plus sûr : une faille du noyau touche tous les conteneurs d'un même hôte. Conteneurs et VM sont complémentaires : Cordée fera tourner des conteneurs… dans des VM.

**Bonus.** Le conteneur ne voit que ses propres processus (`ps` montre `sh` en PID 1), il a son propre nom d'hôte (l'identifiant du conteneur) et sa propre interface réseau (`eth0` en 172.17.x.x sur le pont `docker0`). `docker system df` montre quelques Go d'images : surtout `python:3.13` (environ 1 Go).

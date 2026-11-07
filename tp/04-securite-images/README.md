# TP 04 – Scanner et durcir ses images

| Durée | Branche | Correction |
|-------|---------|------------|
| 20 min (16h25 – 16h45) | `tp-04-securite-images` | `solutions/04-securite-images/README.md` |

## L'incident

> Vendredi, 11h. L'Office de tourisme, futur partenaire de Cordée, demande un rapport de vulnérabilités avant de signer. Sophie lance un scanner sur l'ancienne image de l'API : plusieurs centaines de CVE. Et Léa pose la vraie question : « Si ce serveur tombe pendant les vacances de Noël, on fait quoi ? »

## Objectifs

- Scanner une image avec Trivy et lire le résultat.
- Mesurer l'effet du multi-stage sur la surface d'attaque.
- Lancer un conteneur durci : lecture seule, sans capacités, sans élévation de privilèges.

## Point de départ

```bash
cd ~/cordee
git fetch
git stash -u
git checkout tp-04-securite-images
cd app && docker compose up -d && docker compose ps     # la stack du TP 03 tourne
docker image ls cordee-api                               # « avant » et « 1.0 » (TP 02)
```

Si `cordee-api:avant` manque : `docker build -f api/Dockerfile.avant -t cordee-api:avant api`.

## Étapes

### 1. Scanner les deux images (8 min)

Trivy tourne lui-même dans un conteneur ; il lit les images du poste par le socket Docker (le même que celui du TP 00).

```bash
alias trivy='docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v trivy-cache:/root/.cache ghcr.io/aquasecurity/trivy:latest'
trivy image --quiet --scanners vuln --severity HIGH,CRITICAL cordee-api:avant 2>/dev/null | grep -E '^(Total|cordee|Python)'
trivy image --quiet --scanners vuln --severity HIGH,CRITICAL cordee-api:1.0 2>/dev/null | grep -E '^(Total|cordee|Python)'
```

Le premier lancement télécharge la base de vulnérabilités (1 à 2 min) ; elle reste dans le volume `trivy-cache`.

Chaque cible a une ligne `Total: N (HIGH: x, CRITICAL: y)` : une pour les paquets du système (Debian), une pour les paquets Python.

**Question 1** – Notez les totaux des deux images. D'où viennent la plupart des vulnérabilités de `cordee-api:avant` ?

Pour voir le détail d'une vulnérabilité de l'image `1.0` :

```bash
trivy image --quiet --scanners vuln --severity HIGH,CRITICAL cordee-api:1.0 2>/dev/null | head -30
```

**Question 2** – Une CVE est listée avec `Status: affected` et sans `Fixed Version`. Que pouvez-vous faire ?

### 2. Qui tourne en root ? (2 min)

```bash
for image in cordee-api:avant cordee-api:1.0 cordee-front:1.0; do
  printf '%-20s ' $image; docker run --rm --entrypoint id $image
done
```

### 3. Un conteneur durci (8 min)

On lance un second site, sur le réseau `avant` de la stack Compose, avec le moins de droits possible :

```bash
docker run -d --name front-durci \
  --network cordee_avant -p 8082:8080 \
  --read-only --tmpfs /tmp \
  --cap-drop ALL --security-opt no-new-privileges \
  --memory 128m --pids-limit 100 \
  cordee-front:1.0
sleep 2
curl -s http://localhost:8082/api/info
docker exec front-durci touch /usr/share/nginx/html/pirate
docker exec front-durci sh -c 'grep Cap /proc/1/status'
```

Attendu : l'API répond (`"version":"1.0"`), le `touch` échoue (`Read-only file system`), et les lignes `CapEff` et `CapPrm` valent `0000000000000000`.

**Question 3** – Pourquoi nginx a-t-il besoin de `--tmpfs /tmp` pour démarrer en lecture seule ? Que protège `--cap-drop ALL` ?

### 4. Nettoyage (2 min)

```bash
docker rm -f front-durci
cd ~/cordee/app && docker compose down
docker ps            # il ne reste que « registre »
```

## Questions de fin

4. Léa demande : « Si le serveur tombe, on fait quoi ? » Que manque-t-il à Docker Compose pour répondre (trois points) ?
5. Docker Swarm répond à une partie de ces besoins. Pourquoi Cordée part-elle plutôt sur Kubernetes ?

## Bonus

- `trivy image --format table --scanners vuln,secret,misconfig cordee-api:avant` : Trivy trouve-t-il des secrets ou des erreurs de configuration ?
- `trivy config ~/cordee/app/api/Dockerfile.avant` : les règles de bonnes pratiques non respectées par le Dockerfile historique.

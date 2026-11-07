# TP 11 – Réseau et exposition avancée

| Durée | Branche | Correction |
|-------|---------|------------|
| 75 min (13h45 – 15h00) | `tp-11-reseau` | `solutions/11-reseau/` (`README.md` et `k8s/reseau/`) |

## L'incident

> Vendredi, 9h. L'Office de tourisme signe enfin, avec deux conditions : un vrai nom (`cordee.lab`) en HTTPS, plus de `:30080` ni d'adresse IP. Et Karim voudrait montrer la nouvelle version du site (1.1) à 10 % des visiteurs avant de la livrer à tous. Avec un NodePort par application, ni l'un ni l'autre n'est possible.

## Objectifs

- Comprendre comment un pod trouve un Service : DNS du cluster, variables d'environnement, IP des pods.
- Publier le site par un nom d'hôte avec un Ingress, et terminer le TLS.
- Voir une limite de l'API Ingress et la dépasser avec Gateway API : une route pondérée 90 / 10.

## Point de départ

```bash
cd ~/cordee
git fetch
git stash -u
git checkout tp-11-reseau
kubectl apply -R -f k8s/
kubectl -n cordee rollout status deployment api
kubectl -n traefik get service traefik
kubectl get ingressclass,gatewayclass
grep cordee.lab /etc/hosts
```

Traefik est installé sur le lab : il sert à la fois de contrôleur **Ingress** (IngressClass `traefik`) et de contrôleur **Gateway API** (GatewayClass `traefik`). Son Service LoadBalancer a l'adresse `192.168.56.200`. Le fichier `/etc/hosts` du poste fait pointer `cordee.lab` et `beta.cordee.lab` vers cette adresse.

## Partie A – Le réseau du cluster et la découverte de services (15 min)

### A1. Trois réseaux d'adresses

```bash
kubectl get nodes -o wide | awk '{print $1, $6}'
kubectl -n cordee get pods -o wide | awk '{print $1, $6, $7}'
kubectl -n cordee get services
```

Les nœuds sont en `192.168.56.x`, les pods en `10.244.x.x` (une plage par nœud, donnée par Calico), les Services en `10.96.x.x` à `10.111.x.x`.

### A2. Pod vers pod, pod vers Service

```bash
IP_API=$(kubectl -n cordee get pod -l app=api -o jsonpath='{.items[0].status.podIP}')
kubectl -n cordee exec deployment/front -- wget -qO- -T 3 http://$IP_API:8000/healthz
kubectl -n cordee exec deployment/front -- wget -qO- -T 3 http://api:8000/healthz
kubectl -n cordee get endpointslices -l kubernetes.io/service-name=api
```

Les deux marchent : en direct vers l'IP d'un pod (le CNI route entre nœuds), ou par le Service (kube-proxy répartit vers les endpoints).

### A3. Le DNS du cluster

```bash
kubectl -n cordee run dns --rm -i --restart=Never --image=mirror.gcr.io/library/busybox:1.37 -- \
  sh -c 'cat /etc/resolv.conf; nslookup api.cordee.svc.cluster.local; nslookup traefik.traefik.svc.cluster.local; ping -c1 -W1 api | head -1'
```

> Le pod `dns` est bloqué en entrée par les Network Policies du TP 10, mais il peut sortir : c'est suffisant pour interroger CoreDNS. `nslookup` de busybox n'utilise pas la liste `search` : on lui donne le nom complet. `ping` passe par la résolution normale du système, qui l'utilise : sa première ligne montre l'adresse trouvée pour `api` (le ping lui-même ne reçoit pas de réponse, une IP de Service ne répond pas à ICMP).

**Question 1** – Que contient `search` dans `/etc/resolv.conf` ? Pourquoi `api` suffit-il depuis `cordee`, et que faut-il écrire depuis un autre namespace ?

### A4. Les variables d'environnement

```bash
kubectl -n cordee exec deployment/api -- sh -c 'env | grep -E "^(POSTGRES|FRONT)_SERVICE" | sort'
```

**Question 2** – Pourquoi ces variables sont-elles moins fiables que le DNS ?

## Partie B – Ingress et TLS (25 min)

### B1. Le certificat

Un certificat autosigné pour `cordee.lab`, valable 30 jours, rangé dans un Secret de type TLS :

```bash
mkdir -p ~/tls && cd ~/tls
openssl req -x509 -newkey rsa:2048 -nodes -days 30 -keyout cordee.key -out cordee.crt \
  -subj "/CN=cordee.lab" -addext "subjectAltName=DNS:cordee.lab"
kubectl -n cordee create secret tls cordee-tls --cert=cordee.crt --key=cordee.key
kubectl -n cordee get secret cordee-tls
cd ~/cordee
```

Le certificat n'est pas dans Git : une clé privée n'a rien à y faire.

### B2. L'Ingress

```bash
mkdir -p k8s/reseau
cp tp/11-reseau/reseau/10-ingress.yaml k8s/reseau/
```

Dans `k8s/reseau/10-ingress.yaml`, remplacez les deux `TODO-nom-du-site` par `cordee.lab`. Lisez le fichier : `ingressClassName`, `tls`, `rules`, le `backend` vers le Service `front` sur le port `8080`.

```bash
kubectl apply -f k8s/reseau/10-ingress.yaml
kubectl -n cordee get ingress
curl -sk https://cordee.lab/api/info
curl -s --cacert ~/tls/cordee.crt https://cordee.lab/api/info
curl -sv --cacert ~/tls/cordee.crt https://cordee.lab/ 2>&1 | grep -E 'subject:|issuer:'
```

Attendu : l'API répond, et le certificat présenté a pour sujet `CN=cordee.lab`. Ouvrez <https://cordee.lab> dans Firefox : acceptez l'avertissement (certificat autosigné), le site s'affiche.

> Si `curl` renvoie `404 page not found`, Traefik n'a pas trouvé de route : vérifiez le nom (`kubectl -n cordee describe ingress cordee`) et l'IngressClass.

**Question 3** – Qui termine le TLS ? Le trafic entre Traefik et le pod `front` est-il chiffré ? Pourquoi la Network Policy `front-ouvert` laisse-t-elle passer Traefik ?

### B3. Une limite de l'API Ingress

Karim veut envoyer 10 % des visiteurs vers la version 1.1 du site. Cherchez dans la spécification :

```bash
kubectl explain ingress.spec.rules.http.paths.backend
```

Il n'y a qu'**un** backend par chemin, sans poids. Pour faire du 90 / 10 avec un Ingress, il faut des annotations propres à chaque contrôleur (Traefik, NGINX… chacun la sienne), donc non portables.

**Question 4** – Citez deux autres limites de l'API Ingress.

## Partie C – Gateway API (30 min)

### C1. Les rôles

Gateway API sépare les responsabilités en trois objets :

| Objet | Qui le gère | Ici |
|-------|-------------|-----|
| `GatewayClass` | le fournisseur du contrôleur | `traefik`, installé par le lab |
| `Gateway` | l'équipe plateforme : un point d'entrée, ses ports, ses noms | `cordee`, à créer |
| `HTTPRoute` | l'équipe applicative : les règles de routage vers ses Services | `cordee-beta`, à créer |

### C2. La version canari et la Gateway

```bash
cp tp/11-reseau/reseau/20-gateway.yaml tp/11-reseau/reseau/21-front-canary.yaml k8s/reseau/
kubectl apply -f k8s/reseau/21-front-canary.yaml
kubectl apply -f k8s/reseau/20-gateway.yaml
kubectl -n cordee rollout status deployment front-canary
kubectl -n cordee get gateway cordee
```

La Gateway doit afficher `PROGRAMMED True`. Son écoute est sur le port `8000` : c'est le port de l'entrée `web` de Traefik, publiée sur le port 80 par son Service.

**Question 5** – Pourquoi le pod `front-canary` est-il joignable malgré les Network Policies ?

### C3. La route pondérée

```bash
cp tp/11-reseau/reseau/22-httproute.yaml k8s/reseau/
```

Remplacez les deux poids : `90` pour `front`, `10` pour `front-canary`.

```bash
kubectl apply -f k8s/reseau/22-httproute.yaml
kubectl -n cordee get httproute cordee-beta
kubectl -n cordee describe httproute cordee-beta | grep -A3 -E 'Accepted|ResolvedRefs' | head -8
for i in $(seq 100); do curl -s http://beta.cordee.lab/version.txt; done | sort | uniq -c
```

Attendu : environ 90 réponses `1.0` et 10 réponses `1.1`. Ouvrez <http://beta.cordee.lab> et rechargez : de temps en temps, le site apparaît en bleu (version 1.1).

### C4. Basculer progressivement

Passez les poids à `50` / `50`, appliquez, recomptez. Puis à `0` / `100`.

```bash
kubectl apply -f k8s/reseau/22-httproute.yaml
for i in $(seq 100); do curl -s http://beta.cordee.lab/version.txt; done | sort | uniq -c
```

**Question 6** – Une fois la 1.1 validée, quelle est la suite propre : que changer dans `k8s/30-front.yaml`, et que faire de `front-canary` ?

Remettez `90` / `10` dans le fichier et appliquez : c'est l'état de la correction.

## Fin du TP

```bash
kubectl apply -R -f k8s/
kubectl -n cordee get ingress,gateway,httproute
```

## Questions de fin

7. Ingress ou Gateway API pour un nouveau projet ? Ingress va-t-il disparaître ?
8. Pourquoi a-t-on encore besoin d'un Service LoadBalancer (celui de Traefik) quand on utilise un Ingress ?

## Bonus

- Redirection HTTP vers HTTPS : `curl -sI http://cordee.lab/` répond-il ? Comment Traefik le permettrait (entrée `web` redirigée vers `websecure`) ?
- Ajoutez à la Gateway un listener HTTPS (port 8443, `tls.certificateRefs` vers `cordee-tls`) et une seconde HTTPRoute pour `cordee.lab`.

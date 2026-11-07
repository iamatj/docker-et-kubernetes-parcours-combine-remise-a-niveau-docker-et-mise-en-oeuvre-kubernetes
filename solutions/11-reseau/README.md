# Correction du TP 11 – Réseau et exposition avancée

Fichiers corrigés : `solutions/11-reseau/k8s/reseau/` (`10-ingress.yaml`, `20-gateway.yaml`, `21-front-canary.yaml`, `22-httproute.yaml`). Le Secret `cordee-tls` n'est pas dans Git : recréez-le avec les commandes de l'étape B1. Sans lui, Traefik présente son certificat par défaut. Comparer : `diff -r solutions/11-reseau/k8s/reseau k8s/reseau`.

**1.** `search cordee.svc.cluster.local svc.cluster.local cluster.local` (et `nameserver` = l'IP du Service de CoreDNS, `10.96.0.10`). Le résolveur essaie `api.cordee.svc.cluster.local` en premier : depuis le namespace `cordee`, `api` suffit. Depuis un autre namespace, il faut au moins `api.cordee` (ou le nom complet `api.cordee.svc.cluster.local`).

**2.** Elles ne sont injectées qu'au **démarrage** du pod, et seulement pour les Services qui existaient déjà dans son namespace (`FRONT_SERVICE_HOST` existe parce que le Service `front` a été créé avant les pods de l'API). Un Service créé ou recréé après n'apparaît pas, ou garde une ancienne IP. Le DNS est toujours à jour et fonctionne d'un namespace à l'autre.

**3.** Traefik : il présente le certificat du Secret `cordee-tls`, déchiffre, puis appelle le pod `front` en **HTTP clair** sur 8080, à l'intérieur du cluster. Pour chiffrer jusqu'au pod, il faudrait du TLS de bout en bout (re-chiffrement vers le pod) ou un maillage de services avec mTLS. `front-ouvert` autorise toute origine sur le port 8080 des pods `tier: front` : les pods Traefik (namespace `traefik`) en font partie.

**4.** Pas de répartition pondérée ni de miroir de trafic ; pas de routage sur les en-têtes ou les méthodes HTTP ; uniquement HTTP / HTTPS (pas de TCP, UDP, gRPC natif) ; une seule ressource mélange ce qui relève de la plateforme (TLS, ports) et de l'application (chemins) ; tout le reste passe par des **annotations** propres à chaque contrôleur, donc non portables (changer de contrôleur, c'est réécrire les annotations). Le projet ingress-nginx, contrôleur Ingress le plus répandu, a d'ailleurs été arrêté par la communauté en 2026.

**5.** Il porte l'étiquette `tier: front` : la politique `front-ouvert` s'applique à lui comme au site. Et il peut joindre l'API, que `api-depuis-front` ouvre à tous les pods `tier: front`. C'est pour cela que les Network Policies du TP 10 utilisent `tier` et non `app`.

**6.** Mettre l'image `ghcr.io/iamatj/cordee-front:1.1` dans `k8s/30-front.yaml` et l'appliquer (rolling update sans coupure), puis supprimer `21-front-canary.yaml` et le backend `front-canary` de la route (ou garder la route avec un seul backend), et `kubectl delete -f` le canari. Le canari ne sert qu'à valider ; la version de référence reste dans le Deployment principal.

**7.** Pour un nouveau projet : Gateway API, standard (`v1`) depuis 2023, plus expressive, avec des rôles séparés, et prise en charge par tous les grands contrôleurs (Traefik, Envoy Gateway, NGINX Gateway Fabric, Istio, Cilium, les clouds). Ingress ne disparaît pas de Kubernetes (API stable, figée), mais il n'évoluera plus : tout ce qui est nouveau arrive dans Gateway API.

**8.** L'Ingress n'est qu'une règle ; il faut un programme qui reçoit vraiment le trafic (le contrôleur, ici Traefik), et ce programme doit être joignable de l'extérieur : par un Service LoadBalancer (ici MetalLB, sur un cloud le répartiteur du fournisseur), ou un NodePort. Mais il n'en faut **qu'un** pour toutes les applications, au lieu d'un par Service.

**Bonus.** Selon la configuration de Traefik, `http://cordee.lab` répond le site en clair ou `404` : rien ne redirige vers HTTPS. Traefik se configure pour rediriger toute l'entrée `web` vers `websecure` (`ports.web.redirections` dans les valeurs du chart) ; avec Gateway API, une HTTPRoute sur le listener HTTP avec un filtre `RequestRedirect` (`scheme: https`) fait la même chose de façon portable.

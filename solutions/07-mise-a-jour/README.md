# Correction du TP 07 – Mettre à jour sans couper

Fichiers corrigés : `solutions/07-mise-a-jour/k8s/20-api.yaml`, `30-front.yaml`, `31-front-lb.yaml`. Rappel : sur cette branche, `k8s/` est l'état de **départ** du TP. Pour comparer : `diff -r solutions/07-mise-a-jour/k8s k8s`.

**1.** Quelques erreurs (`502`, parfois `000`) sur quelques centaines de `200`, selon le moment. Avec 3 replicas, 25 % arrondi donne `maxSurge` = 1 (arrondi au-dessus) et `maxUnavailable` = 0 (arrondi en dessous) : entre 3 et 4 pods. Pourtant, sans sonde, Kubernetes considère un pod comme prêt dès que son conteneur a démarré, alors que gunicorn n'écoute pas encore et que l'API n'a pas vérifié la base : le Service envoie des requêtes à un pod qui ne répond pas. Et un ancien pod qui s'arrête reçoit encore quelques requêtes pendant que les règles de kube-proxy sont mises à jour.

**2.** Il baisse (la mise à jour est plus lente, un pod à la fois), mais n'est généralement pas nul. `minReadySeconds` retarde seulement le pod suivant ; il n'empêche pas le Service d'envoyer du trafic au nouveau pod dès son démarrage. Il manque une **readinessProbe** : un test que Kubernetes répète pour savoir si le pod peut recevoir du trafic (TP 08, `/readyz`).

**3.** Non, la sonde ne voit que des `200`. `maxUnavailable: 0` interdit d'arrêter un ancien pod tant qu'un nouveau n'est pas disponible ; le nouveau ne démarre jamais (image introuvable), donc la mise à jour reste bloquée, sans dégâts. Avec la stratégie par défaut sur 3 replicas, c'était aussi `maxUnavailable` = 0 par arrondi ; mais avec 4 replicas ou plus, 25 % autorise à arrêter un ancien pod d'emblée, et on aurait perdu de la capacité. On peut aussi régler `progressDeadlineSeconds` (600 s par défaut) pour que le Deployment passe en échec (`ProgressDeadlineExceeded`) et alerte.

**4.** Presque rien : le fichier demande l'image 1.1, et le `undo` est revenu à la 1.1 (au plus une annotation diffère ; `kubectl diff -f k8s/20-api.yaml` le montre). Mais `set image` et `undo` modifient le cluster sans passer par Git : le fichier et la réalité peuvent diverger, et le prochain `apply` d'un collègue remettrait l'ancien état. La bonne pratique : corriger le fichier, le relire (`kubectl diff`), le commiter, l'appliquer. `set image` et `undo` restent des gestes d'urgence, à reporter ensuite dans le fichier.

**5.** MetalLB, installé sur le lab, qui annonce l'adresse sur le réseau (mode L2, ARP) ; l'annotation `metallb.io/loadBalancerIPs` demande une adresse précise du pool. Sans MetalLB, sur un cluster « nu », le Service reste en `<pending>` : personne ne sait fabriquer une adresse externe. Sur un cluster managé, le contrôleur du cloud crée un vrai répartiteur de charge (Azure Load Balancer, AWS NLB…) avec une IP publique, facturé à part.

**6.** ClusterIP : une IP virtuelle joignable seulement depuis le cluster (l'API, la base). NodePort : un port ouvert sur chaque nœud, joignable par quiconque atteint un nœud ; il s'appuie sur une ClusterIP. LoadBalancer : une adresse externe stable devant les nœuds ; il s'appuie sur un NodePort et une ClusterIP (regardez `kubectl -n cordee get svc front-lb` : il a aussi un port `80:3xxxx`).

**7.** `kubectl rollout pause deployment/api` : les modifications suivantes du gabarit (image, variables) s'accumulent sans déclencher de nouvelle mise à jour ; `kubectl rollout resume` reprend. Pour une vraie livraison progressive (quelques pourcents du trafic), on utilisera des poids sur deux Services avec Gateway API (TP 11), ou un outil comme Argo Rollouts.

**8.** Non : pendant un instant, deux pods PostgreSQL utiliseraient les mêmes données (s'ils partagent un volume) ou deux bases différentes (sinon). Pour une base, on utilise la stratégie `Recreate` (on arrête l'ancien avant de lancer le nouveau) ou, mieux, un StatefulSet (TP 09).

**Bonus.** Le Deployment garde 10 anciens ReplicaSets à 0 replicas (`spec.revisionHistoryLimit`) : ce sont eux qui permettent le `rollout undo`.

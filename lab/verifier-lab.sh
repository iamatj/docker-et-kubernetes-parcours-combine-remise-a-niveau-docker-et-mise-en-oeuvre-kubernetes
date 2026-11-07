#!/usr/bin/env bash
# Bilan du lab : chaque ligne dit OK ou ÉCHEC, avec la piste à suivre. Ne modifie rien.
#   bash lab/verifier-lab.sh
COMPTE_IMAGES=${COMPTE_IMAGES:-iamatj}
ECHECS=0
ok()    { printf '  OK     %s\n' "$1"; }
echec() { printf '  ÉCHEC  %s  → %s\n' "$1" "$2"; ECHECS=$((ECHECS + 1)); }
teste() { local libelle=$1 piste=$2; shift 2; if "$@" >/dev/null 2>&1; then ok "$libelle"; else echec "$libelle" "$piste"; fi; }

echo "Poste client"
teste "Docker répond"                     "sudo systemctl status docker ; groupe docker : fermer et rouvrir la session" \
      sg docker -c "docker info"
teste "Docker Compose V2 (docker compose)" "paquet docker-compose-plugin" sg docker -c "docker compose version"
teste "kubectl installé"                  "étape 1 de preparer-lab.sh" kubectl version --client
teste "Helm installé"                     "étape 1 de preparer-lab.sh" helm version

echo "Cluster"
teste "API du cluster joignable"          "~/.kube/config, kubelet du control-plane" kubectl get --raw /readyz
PRETS=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l)
[ "$PRETS" -eq 3 ] && ok "3 nœuds Ready" || echec "$PRETS nœud(s) Ready sur 3" "kubectl describe node ; journalctl -u kubelet sur le nœud"
teste "Calico prêt"                       "kubectl -n kube-system get pods -l k8s-app=calico-node" \
      kubectl -n kube-system rollout status daemonset/calico-node --timeout=5s
teste "CoreDNS prêt"                      "kubectl -n kube-system get pods -l k8s-app=kube-dns" \
      kubectl -n kube-system rollout status deployment/coredns --timeout=5s
DEFAUT=$(kubectl get storageclass -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{end}' 2>/dev/null)
[ "$DEFAUT" = "local-path" ] && ok "StorageClass par défaut : local-path" || echec "StorageClass par défaut : '$DEFAUT'" "étape 7 de preparer-lab.sh"
teste "StorageClass local-path-retain"    "kubectl apply -f lab/manifests/storageclass-retain.yaml" kubectl get storageclass local-path-retain
teste "MetalLB : pool d'adresses"         "kubectl apply -f lab/manifests/metallb-pool.yaml" kubectl -n metallb-system get ipaddresspool lab
IP_TRAEFIK=$(kubectl -n traefik get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
[ "$IP_TRAEFIK" = "192.168.56.200" ] && ok "Traefik sur 192.168.56.200" || echec "Traefik : IP '$IP_TRAEFIK'" "kubectl -n traefik get svc ; MetalLB"
teste "IngressClass traefik"              "helm -n traefik status traefik" kubectl get ingressclass traefik
teste "CRD Gateway API"                   "étape 8 de preparer-lab.sh" kubectl get crd httproutes.gateway.networking.k8s.io
ACCEPTEE=$(kubectl get gatewayclass traefik -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null)
[ "$ACCEPTEE" = "True" ] && ok "GatewayClass traefik acceptée" || echec "GatewayClass traefik : '$ACCEPTEE'" "valeurs-traefik.yaml (providers.kubernetesGateway)"
teste "metrics-server (kubectl top)"      "attendre 1 min après l'installation" kubectl top nodes

echo "Images de la formation (ghcr.io/$COMPTE_IMAGES)"
for image in cordee-api:1.0 cordee-api:1.1 cordee-front:1.0 cordee-front:1.1; do
  depot=${image%%:*}; tag=${image#*:}
  JETON=$(curl -fs -m 10 "https://ghcr.io/token?scope=repository:$COMPTE_IMAGES/$depot:pull" | jq -r .token 2>/dev/null)
  CODE=$(curl -s -m 10 -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $JETON" \
    -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.v2+json' \
    "https://ghcr.io/v2/$COMPTE_IMAGES/$depot/manifests/$tag")
  [ "$CODE" = "200" ] && ok "$image publique" || echec "$image (HTTP $CODE)" "workflow « images » du dépôt, paquet en visibilité Public"
done

echo
if [ "$ECHECS" -eq 0 ]; then echo "Lab prêt."; else echo "$ECHECS point(s) à corriger."; exit 1; fi

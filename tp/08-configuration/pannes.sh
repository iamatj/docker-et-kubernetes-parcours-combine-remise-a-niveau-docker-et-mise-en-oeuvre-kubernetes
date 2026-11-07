#!/usr/bin/env bash
# Crée le namespace « diagnostic » avec quatre applications en panne (tp/08-configuration/README.md, partie D).
# Relançable : remet les pannes à zéro.
set -euo pipefail
kubectl delete namespace diagnostic --ignore-not-found --wait=true >/dev/null
kubectl create namespace diagnostic >/dev/null
kubectl apply -n diagnostic -f - >/dev/null <<'YAML'
# Panne 1 : la billetterie
apiVersion: apps/v1
kind: Deployment
metadata: { name: billetterie }
spec:
  replicas: 1
  selector: { matchLabels: { app: billetterie } }
  template:
    metadata: { labels: { app: billetterie } }
    spec:
      containers:
        - name: billetterie
          image: ghcr.io/nginx/nginx-unprivileged:1.28-alpinee
---
# Panne 2 : la météo des refuges
apiVersion: v1
kind: Secret
metadata: { name: meteo }
stringData: { CLE: "abc123" }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: meteo }
spec:
  replicas: 1
  selector: { matchLabels: { app: meteo } }
  template:
    metadata: { labels: { app: meteo } }
    spec:
      containers:
        - name: meteo
          image: mirror.gcr.io/library/busybox:1.37
          command: ["sh", "-c", "echo météo prête; sleep 3600"]
          env:
            - name: CLE_API
              valueFrom: { secretKeyRef: { name: meteo, key: CLE_API } }
---
# Panne 3 : la vitrine
apiVersion: apps/v1
kind: Deployment
metadata: { name: vitrine }
spec:
  replicas: 2
  selector: { matchLabels: { app: vitrine } }
  template:
    metadata: { labels: { app: vitrine } }
    spec:
      containers:
        - name: vitrine
          image: ghcr.io/nginx/nginx-unprivileged:1.28-alpine
          ports: [{ containerPort: 8080 }]
---
apiVersion: v1
kind: Service
metadata: { name: vitrine }
spec:
  selector: { app: vitrin }
  ports: [{ port: 8080, targetPort: 8080 }]
---
# Panne 4 : la base des statistiques
apiVersion: apps/v1
kind: Deployment
metadata: { name: statistiques }
spec:
  replicas: 1
  selector: { matchLabels: { app: statistiques } }
  template:
    metadata: { labels: { app: statistiques } }
    spec:
      containers:
        - name: postgres
          image: mirror.gcr.io/library/postgres:17-alpine
          env:
            - { name: POSTGRES_DB, value: statistiques }
YAML
echo "Namespace « diagnostic » prêt : 4 applications (billetterie, meteo, vitrine, statistiques)."
echo "Commencez par : kubectl -n diagnostic get pods"

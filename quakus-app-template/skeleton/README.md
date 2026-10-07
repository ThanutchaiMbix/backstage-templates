# ${{ values.application_name }}

${{ values.description }}

Quarkus + Apache Camel service พร้อม Kubernetes manifests (`k8s/`) และ ArgoCD Application (`argocd/`) สำหรับ GitOps

## Quick start

```bash
mvn quarkus:dev          # dev mode
docker build -t ${{ values.image }} .   # build container image
```

ดูรายละเอียด Minikube/ArgoCD ทั้งหมดที่ [docs/index.md](docs/index.md)

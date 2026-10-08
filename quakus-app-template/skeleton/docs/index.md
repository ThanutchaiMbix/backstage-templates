# ${{ values.application_name }}

${{ values.description }}

Quarkus (Apache Camel) service พร้อมไฟล์ Deployment สำหรับ OpenShift (GitOps)

## มาตรฐาน Red Hat Build of Camel for Quarkus

โปรเจกต์นี้ตั้งต้นตาม migration guide (ดู README.md ของ workspace) ข้อ 1–6:

| ข้อ | ใช้ในโปรเจกต์นี้ |
|---|---|
| 1. Dependency & BOM | `com.redhat.quarkus.platform:quarkus-bom` + `quarkus-camel-bom` เวอร์ชันเดียวกัน ห้ามผสม community `io.quarkus.platform` |
| 2. Namespace | `jakarta.*` ทั้งหมด (persistence / validation / transaction) |
| 3. DI | CDI — `@ApplicationScoped` บน RouteBuilder, `@Inject`, bean ใน route อ้างด้วย Class type |
| 4. Configuration | `application.properties` (default) + prefix `app.*` สำหรับค่า app, อ่านด้วย `@ConfigProperty` |
| 5. Profiles | `%dev` / `%prod` prefix ในไฟล์เดียว (ไม่แยกไฟล์ application-dev.properties) |
| 6. Camel REST | ถ้าเพิ่ม REST DSL ต้องเรียก `restConfiguration()` ใน `configure()` เอง และระวัง REST DSL merge กับ `from("direct:X")` — ใช้ intermediate direct route คั่น |

> เพิ่ม camel component ใหม่: ใช้ `org.apache.camel.quarkus:camel-quarkus-xxx`
> (ไม่ต้องใส่ version — quarkus-camel-bom จัดการ) และเช็คว่า Red Hat รองรับ extension นั้น

## Run in dev mode

```bash
mvn quarkus:dev
```

- REST: <http://localhost:8080/hello>
- Swagger UI: <http://localhost:8080/q/swagger-ui>
- Health: <http://localhost:8080/q/health>
- Camel heartbeat log พิมพ์ทุก 10 วินาที

## Build & Run on Minikube

```bash
# 1. build image
docker build -t ${{ values.image }} .

# 2. โหลด image เข้า minikube
minikube image load ${{ values.image }}

# 3. deploy (หรือให้ ArgoCD sync ให้)
kubectl apply -f k8s/deployment.yaml

# 4. ทดสอบ
minikube service ${{ values.application_name }}
```

## GitOps with ArgoCD

- ไฟล์ manifests อยู่ที่ `k8s/` (ArgoCD watch path นี้)
- **การ deploy ไม่ได้เกิดตอน scaffold** — สร้าง ArgoCD Application ผ่าน Backstage
  template **"Deploy Service to OpenShift"** เลือก component นี้
- สร้างเอง manual ได้จาก `argocd/application.yaml`

```bash
kubectl apply -f argocd/application.yaml
```

## CI/CD (GitOps)

- **CI — Tekton (Pipelines as Code)**: ทุก push ไป `main` จะ trigger `.tekton/push.yaml`
  build image (buildah) ไปที่ internal registry ของ cluster แท็กด้วย commit sha
  แล้ว commit แท็กใหม่เข้า `k8s/deployment.yaml` กลับมาที่ repo นี้
- **CD — ArgoCD (OpenShift GitOps)**: จับตา `k8s/` ของ repo นี้ แล้ว sync ลง cluster
  เมื่อแท็ก image เปลี่ยน (Application ถูกสร้างผ่าน template "Deploy Service to OpenShift")

ข้อกำหนดก่อนใช้งาน (one-time ต่อ namespace): ดูหัวข้อ setup ที่หัวไฟล์ `.tekton/push.yaml`
(สิทธิ์ push image, privileged สำหรับ buildah, secret `github-push-token`,
และ `oc apply -f .tekton/repository.yaml`)

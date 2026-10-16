# Step-by-Step: สร้าง Backstage Software Template + GitOps บน OpenShift ครบวงจร

> บันทึกลำดับการทำจริงตั้งแต่เริ่มต้นจน `/hello` ตอบ 200 ผ่าน Route — แบ่งเป็นเฟสตามลำดับเวริก
> เอกสารคู่กัน: [openshift-lab-gitops-plan.md](openshift-lab-gitops-plan.md) (สถาปัตยกรรม + สถานะ) และ §7 ของไฟล์นั้น (gotchas 12 ข้อ)

## ภาพรวมปลายทาง

```
กด Template ใน Backstage → GitHub repo + catalog entity
→ git push → bash .tekton/trigger.sh (Tekton build ผ่าน proxy)
→ image ใน internal registry (tag = commit sha)
→ Tekton bump commit กลับ repo → ArgoCD sync อัตโนมัติ
→ https://<app>-<ns>.apps.<domain>/hello → 200 ✅
```

โครงสร้าง repo ใน workspace:

```
backstage-quakus/
├── mbix-backstage/            # Backstage portal (create-app v1.55)
│   ├── app-config.yaml        # catalog locations, integrations, argocd locator
│   └── packages/backend/src/
│       ├── index.ts           # ลงทะเบียน plugin + custom action module
│       └── argocd-module.ts   # custom action argocd:createApplication
├── quakus-app-template/       # Template 1 (scaffold ไม่ deploy)
│   ├── template.yaml
│   └── skeleton/              # สิ่งที่ถูก render ให้ผู้ใช้ (pom, src, k8s, .tekton ...)
├── deploy-service-template/   # Template 2 (onboard deploy)
└── openshift-lab-gitops-plan.md
```

---

## เฟส 0 — ของที่ต้องมีก่อนเริ่ม

| ของ | ที่ไหน | เตรียมยังไง |
|---|---|---|
| WSL (Ubuntu) | เครื่อง dev | ติดตั้ง `oc`, `tkn`, `git`, `docker` (`~/bin/tkn-pac` เพิ่มทีหลัง) |
| GitHub PAT | github.com → Settings → Developer settings | classic, scope `repo` (ใช้ทั้ง push, สร้าง repo ผ่าน Backstage, และ git push ใน pipeline) |
| OCP cluster | `api.ocp420.mbixtech.net` | ติดตั้ง operator: **OpenShift GitOps** + **OpenShift Pipelines** (OperatorHub) |
| Backstage app | `mbix-backstage/` | จาก create-app, รันด้วย `yarn start`, frontend :3000 backend :7007 |
| เข้าใจพื้นฐาน | — | Backstage Software Template (`${{ values.x }}`), ArgoCD Application, Tekton PipelineRun |

> login cluster: ใช้ WSL (`oc login --token=... --server=...` จากปุ่ม Copy login command ใน web console)

---

## เฟส 1 — สร้าง Template 1: Quarkus Service (scaffold)

หลักการ: **scaffold เท่านั้น ไม่ deploy** — deploy เป็นงานของ Template 2 (แยกสิทธิ์/แยกการตัดสินใจ)

### 1.1 โครงสร้างโฟลเดอร์

```
quakus-app-template/
├── template.yaml            # นิยามฟอร์ม + steps
└── skeleton/                # จะถูก render + copy ให้ผู้ใช้
    ├── pom.xml              # Red Hat BOM + repositories
    ├── src/main/java/...    # GreetingResource (REST /hello) + CamelRoute (heartbeat)
    ├── src/main/resources/application.properties  # config + %dev/%prod profiles
    ├── Dockerfile           # multi-stage + proxy + registry เต็ม
    ├── k8s/deployment.yaml  # Deployment + Service + Route (edge TLS, targetPort 8080)
    ├── .tekton/push.yaml    # PipelineRun (CI)
    ├── .tekton/trigger.sh   # สั่ง CI ด้วยมือ (intranet ไม่มี webhook)
    ├── .tekton/repository.yaml  # PAC Repository CR (เก็บไว้เผื่ออนาคต)
    ├── .gitattributes       # *.sh → LF (กัน CRLF พังใน WSL)
    └── catalog-info.yaml    # Component + API entity
```

### 1.2 pom.xml — มาตรฐาน Red Hat Build (migration guide ข้อ 1)

- BOM คู่ `com.redhat.quarkus.platform:quarkus-bom` + `quarkus-camel-bom` **เวอร์ชันเดียวกัน** (ตาม guide ห้ามผสม community `io.quarkus.platform`)
- **ประกาศ `<repositories>` Red Hat GA ใน pom เอง** — artifact `com.redhat.quarkus.platform` ไม่อยู่บน Maven Central (gotcha #1)
- camel deps เป็น `org.apache.camel.quarkus:camel-quarkus-xxx` ไม่ต้องใส่ version

### 1.3 โค้ด Java — jakarta + CDI (ข้อ 2–3)

- `GreetingResource.java`: REST `/hello` + `@ConfigProperty` อ่าน `app.greeting`
- `CamelRoute.java`: **ต้องมี `@ApplicationScoped`** บน RouteBuilder (pitfall #3) + javadoc เตือนเรื่อง REST DSL merge กับ `direct:` (ข้อ 6)

### 1.4 application.properties — ข้อ 4–5

- ใช้ `.properties` (default — ไม่ต้องพึ่ง `quarkus-config-yaml`), prefix `app.*`
- **profiles ใช้ `%dev.` / `%prod.` prefix ในไฟล์เดียว** (ห้ามแยกไฟล์ application-dev.properties)
- เพิ่ม `quarkus.smallrye-openapi.store-schema-directory=target/openapi`

### 1.5 k8s/deployment.yaml — จุดพลาดที่เจอจริง

- **Route `spec.port.targetPort` ต้องเป็น container port (`8080`)** — ใส่เป็น service front port (`80`) แล้ว router resolve ไม่ได้ → backend ว่าง → 503 (gotcha #7)
- Route ใส่ `tls: {termination: edge, insecureEdgeTerminationPolicy: Redirect}` — ไม่งั้น `https://` ใช้ไม่ได้
- Service ไม่ต้องใส่ namespace (ArgoCD ส่งเข้า destination namespace ให้)
- อย่าลืม label `backstage.io/kubernetes-id` ทั้ง Deployment/Service/Route (ไว้ให้ kubernetes plugin ภายหลัง)

### 1.6 Dockerfile — สามข้อที่ต้องมี

```dockerfile
ARG PROXY_URL=""
FROM docker.io/library/maven:3.9-eclipse-temurin-21 AS builder   # 1) registry เต็ม (buildah ไม่มี TTY ถาม short name)
ARG PROXY_URL
ENV HTTPS_PROXY=${PROXY_URL} ...                                  # 2) buildah อ่าน env
RUN ... สร้าง /root/.m2/settings.xml จาก $PROXY_URL ... mvn ...   # 3) mvn (Java) ไม่อ่าน env proxy — ต้อง settings.xml
FROM docker.io/library/eclipse-temurin:21-jre-jammy               # runtime ไม่ต้องมี proxy
```

### 1.7 .tekton/push.yaml — PipelineRun (Pipelines as Code)

โครงสร้าง Tekton **v1** ที่ต้องระวัง:

- inline steps ต้องอยู่ใน `taskSpec:` **และ** taskSpec ต้องประกาศ `workspaces` เอง
- ตรวจ syntax ก่อน push ทุกครั้ง: `oc apply --dry-run=server -n demo -f .tekton/push.yaml`
- placeholder สองชนิดไม่ชนกัน: `${{ values.x }}` = Backstage (render ตอน generate), `{{ repo_url }}` = PAC (ตอน trigger), `$(params.x)` = Tekton runtime

3 tasks ที่ pipeline ทำ: `fetch-source` (clone) → `build-and-push` (buildah login ด้วย **SA token ที่ pod mount มาเอง** + build + push ไป internal registry) → `update-manifests` (sed bump tag → commit `[skip ci]` → push กลับ GitHub ด้วย secret `github-push-token`)

### 1.8 .tekton/trigger.sh — สั่ง CI ด้วยมือ

เหตุผลที่ต้องมี: cluster เป็น intranet (GitHub ยิง webhook เข้าไม่ถึง) + องค์กรไม่ให้ลง GitHub App
→ หลัง push รัน `bash .tekton/trigger.sh --follow` (ใช้ `tkn-pac resolve` แทนค่า + `oc create`)
— ภายในไฟล์มี guard: ถ้า push.yaml ยังมี `${{` (ไฟล์ดิบจาก skeleton) ให้ fail ทันทีพร้อมบอกวิธีแก้

### 1.9 template.yaml — ฟอร์ม + steps

- parameters แบ่ง section: Ownership (**OwnerPicker**) → App Info → Cluster Info (`clusterAppsDomain`, `proxyUrl`)
- steps: `fetch:template` → `publish:github` (**`protectDefaultBranch: false`** — default ของ Backstage ใหม่ lock main ให้!) → `catalog:register`
- **ไม่มี step deploy** ใน Template 1

### 1.10 ตรวจก่อน push ทุกครั้ง (บทเรียนแพงที่สุด)

```bash
# 1) ทุกไฟล์ใน skeleton ต้อง render ผ่าน (comment ที่มีลำดับตัวอักษร ${{ ก็พัง!)
node .tools/render-test.js
# 2) PipelineRun ต้องผ่าน admission webhook จริง (render ค่าจำลองด้วย sed ก่อน)
oc apply --dry-run=server -n demo -f <(sed ... .tekton/push.yaml)
# 3) bash syntax ของ trigger.sh
bash -n .tekton/trigger.sh
```

---

## เฟส 2 — Push และลงทะเบียน Template ใน Backstage

1. push โฟลเดอร์ template ไป GitHub (เช่น `ThanutchaiMbix/backstage-templates`)
2. เพิ่มใน `mbix-backstage/app-config.yaml`:

```yaml
catalog:
  locations:
    - type: url
      target: https://github.com/ThanutchaiMbix/backstage-templates/blob/main/quakus-app-template/template.yaml
      rules: [{ allow: [Template] }]   # ← จำเป็น! catalog.rules ส่วนกลางไม่อนุญาต Template
    # ...อีกตัวสำหรับ deploy-service-template
```

3. ระวัง: **แก้ template.yaml → ต้อง Refresh entity** (⋯ → Refresh หน้า template หรือ restart) ส่วน skeleton/ ดึงสดตอนรัน task ไม่ต้อง refresh

---

## เฟส 3 — เตรียม Cluster (one-time)

```bash
# 1) namespace + label ให้ ArgoCD บริหารได้ (ขาดขั้นนี้ sync = forbidden!)
oc new-project demo
oc label namespace demo argocd.argoproj.io/managed-by=openshift-gitops

# 2) ให้ SA pipeline push image + buildah ใช้ privileged
oc policy add-role-to-user system:image-builder system:serviceaccount:demo:pipeline -n demo
oc adm policy add-scc-to-user privileged -z pipeline -n demo

# 3) secret สำหรับ pipeline push manifest กลับ repo (อ่านจาก env ไม่ผ่านแชท)
read -s -p "GitHub PAT: " T; echo
oc create secret generic github-push-token -n demo --from-literal=token=$T
unset T
```

# 4) credential ให้ ArgoCD อ่าน private repo ของ org (ครั้งเดียวต่อ org)
#    หมายเหตุ: ต้องเป็น secret ชนิด "repo-creds" + url แบบ prefix —
#    ชนิด "repository" ไม่รองรับ wildcard และจะได้ error "repository not accessible"
read -s -p "GitHub PAT: " PW; echo
oc create secret generic mbix-devops-repo-creds -n openshift-gitops \
  --from-literal=url='https://github.com/mbix-devops' \
  --from-literal=username='<GitHub user>' \
  --from-literal=password="$PW" \
  --from-literal=project='default'
oc label secret mbix-devops-repo-creds -n openshift-gitops \
  argocd.argoproj.io/secret-type=repo-creds
unset PW
```

> ไม่ต้องตั้ง secret registry — build step login internal registry ด้วย SA token เอง
> RBAC ของ backstage บน ArgoCD: account `backstage` (apiKey) + policy ให้ `applications, *, */*` — **AppProject สร้างไม่ได้ตามการออกแบบ** (เป็นหน้าที่ admin)

---

## เฟส 4 — ใช้งาน Template 1 + ยิง CI

```bash
# กด template ใน Backstage → ได้ repo + catalog entity (ไม่ deploy)
git clone https://github.com/ThanutchaiMbix/quarkus-demo-1 && cd quarkus-demo-1
bash .tekton/trigger.sh --follow        # CI: clone → build → push → bump commit
# ตรวจ: oc get is -n demo  +  commit "bump image to <sha>" บน GitHub
```

---

## เฟส 5 — Template 2 (Deploy) + Custom Action

### 5.1 Template 2 (deploy-service-template/template.yaml)

`EntityPicker` เลือก component → `catalog:fetch` อ่าน annotation `github.com/project-slug` → **`argocd:createApplication`** (custom action ของเรา)

### 5.2 Custom action ใน backend — สามด่านที่ต้องผ่าน (new backend system)

```ts
// packages/backend/src/argocd-module.ts
import { scaffolderActionsExtensionPoint } from '@backstage/plugin-scaffolder-node';  // ← root ไม่ใช่ /alpha
...
env.registerInit({
  deps: { actions: scaffolderActionsExtensionPoint, config: coreServices.rootConfig },
  async init({ actions, config }) {
    actions.addActions(createTemplateAction({ id: 'argocd:createApplication', ... }));  // ← พหูพจน์
  },
});
```

```ts
// packages/backend/src/index.ts — ไฟล์ local ต้อง STATIC import (dynamic import ได้ namespace ที่ backend.add ไม่รับ)
import { argocdModule } from './argocd-module';
backend.add(argocdModule);
```

หลักการของ action: **สร้างเฉพาะ Application** (POST `/api/v1/applications`, รับ 409 = idempotent) — **ไม่เรียก project API เลย** เพราะ AppProject เป็นหน้าที่ของ admin

### 5.3 app-config — จุดเชื่อมทั้งหมด

```yaml
integrations:
  github:
    - host: github.com
      token: ${GITHUB_TOKEN}        # publish:github + อ่าน repo
argocd:
  appLocatorMethods:
    - type: config
      instances:
        - name: default
          url: https://openshift-gitops-server-openshift-gitops.apps.<domain>
          token: ${ARGOCD_TOKEN}    # token ไม่มีวันหมดอายุ จาก account "backstage"
```

env vars ตอน `yarn start` (เก็บใน `.tools/env.local.ps1` — git-ignored): `GITHUB_TOKEN`, `ARGOCD_TOKEN`, `NODE_EXTRA_CA_CERTS` (= fullchain ของ route, ให้ Node เชื่อถือ cert ภายใน)

### 5.4 รัน Template 2 → ArgoCD Synced/Healthy

Application ถูกสร้าง → auto-sync (namespace ต้องมี label managed-by จากเฟส 3) → pod ขึ้น → Route ตอบ

---

## เฟส 5.5 — เพิ่ม Tekton plugin (มองเห็น PipelineRun ในหน้า component)

4 ชิ้นที่ต้องครบจึงจะแสดงผล:

1. **frontend plugin**: `yarn workspace app add @backstage-community/plugin-tekton`
   (v4.x มี `./alpha` export → new frontend system auto-discovery ผ่าน `app.packages: all` พาขึ้นเอง)
2. **kubernetes backend config** ใน app-config.yaml — cluster locator (SA token) +
   `customResources` สำหรับ `tekton.dev/v1` pipelineruns/taskruns
   (ถ้า log มี warning "valid kubernetes config is missing" = config ยังไม่ใส่)
3. **RBAC + token**: SA `backstage-k8s` + ClusterRole อ่าน tekton CRDs (`pipelineruns.tekton.dev`,
   `taskruns.tekton.dev` — **ไม่ใช่** `*.task.tekton.dev`) + pods/logs + ชุด resource การ์ด
   Workloads (configmaps, replicasets, hpa, jobs, ...) ไม่งั้นการ์ดจะ 403 + token จาก
   `oc create token backstage-k8s --duration=8760h`
4. **ผูก run กับ entity**: PipelineRun ต้องมี label `backstage.io/kubernetes-id: <ชื่อ app>`
   (ใส่ใน skeleton แล้ว — app เก่าที่ generate ก่อนหน้าต้องเติมเอง) และ catalog-info มี
   annotation `tekton.dev/cicd: "true"` — ถ้าไม่มี annotation นี้ **แท็บจะไม่โผล่**

> ข้อจำกัด: run เก่าที่ไม่มี label จะไม่ปรากฏ — รันใหม่ผ่าน trigger.sh หลังใส่ label

## เฟส 6 — พิสูจน์วงจรปิดจริง

```bash
# แก้ code → push → CI → bump commit → ArgoCD deploy เอง ภายใน ~1 นาที
sed -i 's/"Minikube"/"OpenShift"/' src/main/java/com/example/demo/GreetingResource.java
git commit -am "feat: greet OpenShift" && git push
bash .tekton/trigger.sh --follow
# จบแล้ว: curl https://<app>-<ns>.apps.<domain>/hello → ข้อความใหม่ โดยไม่แตะมือ deploy เลย
```

---

## ภาคแนบ — สรุป gotchas (รายละเอียดเต็มใน plan doc §7)

| # | อาการ | สาเหตุ | ทางแก้ |
|---|---|---|---|
| 1 | mvn หา artifact ไม่เจอ | Red Hat ไม่ได้ publish บน Central | `<repositories>` ใน pom |
| 2 | mvn timeout ใน build | egress ผ่าน proxy | settings.xml + `--build-arg PROXY_URL` |
| 3 | push โดน protected branch | `publish:github` default | `protectDefaultBranch: false` |
| 4 | PipelineRun validation error | steps ไม่ได้อยู่ใน `taskSpec` | โครงสร้าง v1 |
| 5 | `unsupported transport "docker"` | ใส่ prefix ตอน buildah push | ตัดออก ใช้ชื่อ image ตรง ๆ |
| 6 | `short-name resolution enforced` | FROM แบบสั้น | เติม `docker.io/library/` |
| 7 | route 503 backend ว่าง | `targetPort: 80` (service front port) | ใช้ container port `8080` |
| 8 | ArgoCD sync forbidden | ns ไม่มี label | `argocd.argoproj.io/managed-by` |
| 9 | `projects, create denied` | action พยายามสร้าง project | เขียน custom action ไม่แตะ project |
| 10 | `env.registerAction is not a function` / `addAction` | API คนละรูปแบบ | extension point + `addActions` |
| 11 | `Unterminated variable tag` ตอน generate | มี literal `${{` ใน comment | `render-test.js` ก่อน push |
| 12 | fetch failed ไป ArgoCD | Node ไม่เชื่อถือ CA ภายใน | `NODE_EXTRA_CA_CERTS` |

## มาตรฐานการทำงานต่อไป

1. แก้ skeleton/template → รัน `render-test.js` + `dry-run` + `bash -n` ก่อน push เสมอ
2. แก้ `template.yaml` → refresh entity; แก้ `skeleton/` → ไม่ต้อง
3. เจน app ใหม่: Template 1 → push → `trigger.sh` → Template 2 → จบ
4. template ตระกูลอื่น (node/python): ก๊อบแนว `.tekton/` + `k8s/` + Route จาก template นี้ เปลี่ยนแค่ build step

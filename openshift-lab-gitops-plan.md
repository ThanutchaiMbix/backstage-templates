# แผนสถาปัตยกรรม: Backstage + Quarkus Template + GitOps บน OpenShift Cluster Lab

> เป้าหมาย: ทำ Quarkus template เป็นต้นแบบ (golden path) ให้ app อื่น ๆ ใช้ CI/CD ด้วย Tekton + ArgoCD
> และ deploy Backstage dev portal ขึ้น OpenShift cluster เดียวกัน (cluster lab/test)
>
> **การตัดสินใจสำคัญ: แบ่งเป็น 2 template** — Template 1 (scaffold) เจน code/repo/catalog เท่านั้น
> Template 2 (onboard) เป็นตัว deploy ดูหัวข้อ 2.1 และ 6

---

## 1. ภาพรวมบน Cluster Lab

```
┌─────────────────────── OpenShift Cluster (lab) ───────────────────────┐
│                                                                        │
│  backstage (ns)          openshift-gitops (ns)     openshift-pipelines │
│  ┌─────────────┐         ┌──────────────┐         ┌───────────────┐    │
│  │  Backstage   │──create▶│   ArgoCD     │◀─watch──│    Tekton     │    │
│  │  (helm/RHDH) │         │ (GitOps op)  │  Git    │  + PAC        │    │
│  └─────────────┘         └──────┬───────┘         └───────┬───────┘    │
│                                 │ sync                     │ push img  │
│                                 ▼                          ▼           │
│  demo (ns: app ที่ generate)  ◀────────────────   image-registry       │
│  [Deployment, Service, Route]                      (internal)           │
└────────────────────────────────────────────────────────────────────────┘
```

ติดตั้งผ่าน operator ทั้งคู่:

| Component | Operator | Namespace | หมายเหตุ |
|---|---|---|---|
| ArgoCD | OpenShift GitOps | `openshift-gitops` | ได้ instance `openshift-gitops` พร้อมสิทธิ์ deploy ใน cluster ตัวเองอยู่แล้ว |
| Tekton | OpenShift Pipelines | `openshift-pipelines` | มี PAC (Pipelines as Code) ติดมาด้วย |
| Backstage | Helm chart หรือ RHDH | `backstage` | ดูหัวข้อ 4 |
| Apps ที่ generate | — | เช่น `demo` | Deployment + Service + Route |

---

## 2. Flow ที่ Template Generate ให้แต่ละ App

แบ่งหน้าที่ชัดเจน: **Tekton = CI (build/test/push image), ArgoCD = CD (sync manifest)**
อย่าให้ Tekton สั่ง `oc apply` เองเด็ดขาด — นั่นคือหัวใจของ GitOps

### 2.1 แบ่งเป็น 2 Template — scaffold ไม่ deploy

เหตุผล: app ที่เพิ่งเจนคือ Hello World ไม่มีอะไรน่า deploy / การ deploy คือการตัดสินใจ
(namespace, env, approval) ไม่ใช่ขั้นตอน / template แยกใช้กับ repo เดิม (brownfield) ได้ด้วย

```
Template 1: "Quarkus Service" (scaffold)          → quakus-app-template/
  กด → เจน code → publish repo → register catalog   ❌ ไม่แตะ cluster
  skeleton ใส่ k8s/ + .tekton/ ครบ แต่ "หลับ" อยู่
  (push → PAC build image ทันที แต่ไม่มีใคร deploy)

Template 2: "Deploy Service to OpenShift" (onboard) → deploy-service-template/
  เลือก component จาก catalog (EntityPicker) + namespace
  → catalog:fetch อ่าน annotation github.com/project-slug
  → สร้าง ArgoCD Application ชี้ k8s/ ของ repo นั้น    ✅ จุดเดียวที่แตะ cluster
```

จุดที่ทำให้แนวนี้สวย: เพราะ `k8s/` อยู่ใน repo แล้ว Template 2 **แทบไม่ต้อง commit อะไรเลย**
แค่สร้าง ArgoCD Application resource — และใช้กับ repo เดิมได้เพราะมี `project-slug`
annotation ใน catalog entity ก็พอ นอกจากนี้ยังแบ่งสิทธิ์ได้: Template 1 เปิดให้ dev ทุกคน
ส่วน Template 2 จำกัดเฉพาะ group ที่ดูแล cluster (RBAC ต่อ template)

```
git push ─▶ PAC trigger ─▶ Tekton PipelineRun (.tekton/push.yaml)
                             1. git-clone
                             2. maven test
                             3. buildah build → push → internal registry
                             4. git commit tag ใหม่ใน k8s/*.yaml → push กลับ repo
                                    │
ArgoCD เห็น manifest เปลี่ยน ────────┘
                             auto-sync → Deployment ใน cluster
```

**ขั้น 4 (bump image tag) มี 2 แนวทาง:**

| แนวทาง | ข้อดี | ข้อเสีย |
|---|---|---|
| Tekton commit กลับ repo | GitOps บริสุทธิ์ ได้ audit ใน git history | ต้องเขียน step commit/push ใน pipeline |
| ArgoCD Image Updater | สบาย ไม่ต้องแกะ step เอง | เพิ่ม component ต้องดูแลอีกตัว |

→ สำหรับ cluster lab แนะนำแบบ **Tekton commit** เพราะได้เห็น flow ครบและเรียนรู้ได้จริง

**ข้อดีของ `.tekton/` ไฟล์:** ไม่มีปัญหา syntax ชนกับ Backstage templating
(PAC ใช้ `{{ repo_url }}` ส่วน Tekton ใช้ `$(params.x)` — ไม่มี `${{ }}` ที่ชนกัน)
ต่างจาก GitHub Actions ที่ต้อง escape หรือ `copyWithoutRender` ทั้งโฟลเดอร์

---

## 3. Skeleton ที่ต้องแก้จากของเดิม

| ตอนนี้ | แก้เป็น |
|---|---|
| `.github/workflows/build.yml` (ghcr) | `.tekton/push.yaml` (PAC) + buildah push ไป internal registry `image-registry.openshift-image-registry.svc:5000/demo/<app>` |
| POST ArgoCD API ใน Template 1 | **ตัดออกจาก Template 1 แล้วย้ายไปเป็น Template 2** ทั้งตัว — คงใช้ `http:backstage:request` ผ่าน ArgoCD proxy เดิม (module `argocd:create-app` ของ janus-idp ถูก archive ไปแล้วไม่แนะนำ / แนว app-of-apps ไว้ต่อยอดภายหลัง) |
| ลิงก์/namespace hardcode `localhost`, `demo` | parameterize: cluster domain, target namespace เป็น parameter ของ template |
| `owner: user:guest`, hardcode `orgName` | OwnerPicker / RepoUrlPicker ใน template.yaml |
| `swagger/swagger.yaml` static | openapi auto-gen จาก quarkus (`quarkus.smallrye-openapi.store-schema-directory`) |

**สิ่งที่ควรเพิ่มใน skeleton เพื่อให้เป็นต้นแบบของ app อื่น:**

- `.tekton/` ให้ self-contained ในแต่ละ repo (แต่ละ app build ได้ด้วยตัวเอง ไม่ผูกกับ pipeline กลาง)
  — ตอนทำ template ตัวอื่น (node, python) ก๊อบแนว `.tekton/` + `k8s/` + `catalog-info.yaml`
  ชุดเดียวกัน แล้วเปลี่ยนแค่ build step
- ตัด `.github/workflows/` ทิ้ง — CI มีตัวเดียวคือ Tekton

**สิ่งที่ PAC ต้องเตรียม (ทีเดียวตอน setup cluster):**

- ตั้งค่า GitHub App (หรือ webhook) เชื่อมกับ PAC บน cluster
- `Repository` CR → template 1 สร้างไฟล์ `.tekton/repository.yaml` ให้แล้ว admin แค่
  `oc apply -f .tekton/repository.yaml` ตอน onboarding repo

**One-time setup ต่อ namespace (รายการคำสั่งอยู่ที่หัวไฟล์ `.tekton/push.yaml`):**

1. `oc policy add-role-to-user system:image-builder system:serviceaccount:<ns>:pipeline -n <ns>` — ให้ push image ได้
2. `oc adm policy add-scc-to-user privileged -z pipeline -n <ns>` — ให้ buildah รัน privileged ได้
3. secret `registry-auth` (จาก `oc registry login`) — สำหรับ login internal registry
4. secret `github-push-token` (fine-grained PAT, Contents: RW) — สำหรับ push manifest กลับ repo
5. `oc apply -f .tekton/repository.yaml` — ผูก repo กับ pipeline

---

## 4. Backstage ตัวเอง Deploy ลง Cluster

**ตัวเลือกการติดตั้ง:**

| ตัวเลือก | เหมาะกับ | หมายเหตุ |
|---|---|---|
| Helm chart (`backstage/backstage`) + PostgreSQL | cluster lab | ห่อ app-config เป็น ConfigMap/Secret |
| RHDH (Red Hat Developer Hub) | ถ้ามี subscription OpenShift | ตัวเดียวกับ Backstage แต่ supported และมี template Quarkus+Tekton+ArgoCD ติดมาให้เทียบ |

**app-config ที่ต้องเปลี่ยนตอนขึ้น cluster:**

- proxy ArgoCD: `localhost:8081` → route ของ `openshift-gitops-server` + token
- kubernetes plugin: ใช้ SA token ของ cluster ตัวเอง
- integrations GitHub: ย้าย token ไป Secret
- SA ของ Backstage ต้องมีสิทธิ์พอ (lab: cluster-admin ให้ง่าย แต่รู้ตัวว่า lab-only)

---

## 5. สรุปลำดับที่แนะนำ

1. **ติดตั้ง operator ทั้งสอง** + ตั้ง PAC กับ GitHub org `mbixdemodevs` ให้เรียบร้อยก่อน (ทีเดียวจบ)
2. ✅ **Template 1 (scaffold)**: ตัด Actions → `.tekton/push.yaml` + `.tekton/repository.yaml`,
   Route แทน NodePort, OwnerPicker + parameterize namespace/domain, **ตัด step ArgoCD ออก**
3. ✅ **Template 2 (onboard)**: `deploy-service-template/` ใหม่ทั้งตัว — EntityPicker +
   `catalog:fetch` + สร้าง ArgoCD Application ผ่าน proxy (ไม่ต้องติดตั้ง backend module เพิ่ม)
4. **One-time setup ต่อ namespace** ตามหัวข้อ 3 (role/SCC/secrets/Repository CR)
   แล้วทดสอบ: generate app → push → เห็น Tekton build → รัน Template 2 → ArgoCD sync → Route เข้าได้
5. **Deploy Backstage ลง cluster** ด้วย helm + ย้าย app-config

> จุดเริ่มที่แนะนำ: ข้อ 4 เพราะ template ทั้งสองพร้อมแล้ว เหลือแค่เตรียม cluster และทดสอบ

---

## 6. ไฟล์ที่ implement แล้ว

| ไฟล์ | สถานะ | หมายเหตุ |
|---|---|---|
| `quakus-app-template/template.yaml` | ✅ เขียนใหม่ | ชื่อ `quarkus-service`, OwnerPicker, namespace/domain params, ไม่มี step deploy |
| `quakus-app-template/skeleton/.tekton/push.yaml` | 🆕 | PipelineRun (PAC): clone → buildah build+push (tag = sha) → commit bump tag กลับ repo `[skip ci]` |
| `quakus-app-template/skeleton/.tekton/repository.yaml` | 🆕 | PAC Repository CR — admin ต้อง `oc apply` ตอน onboarding |
| `quakus-app-template/skeleton/.github/` | 🗑 ลบแล้ว | CI มีตัวเดียวคือ Tekton |
| `quakus-app-template/skeleton/k8s/deployment.yaml` | ✏️ แก้ | + Route (แทน NodePort), image จาก internal registry (tag `latest` ตั้งต้น) |
| `quakus-app-template/skeleton/catalog-info.yaml` | ✏️ แก้ | owner จาก OwnerPicker, + `backstage.io/source-location`, ลิงก์จาก cluster domain |
| `quakus-app-template/skeleton/argocd/application.yaml` | ✏️ แก้ | namespace `openshift-gitops`, destination ตาม param, ไว้ seed app-of-apps |
| `quakus-app-template/skeleton/application.properties` | ✏️ แก้ | + `quarkus.smallrye-openapi.store-schema-directory` |
| `deploy-service-template/template.yaml` | 🆕 | Template 2 (onboard): EntityPicker → catalog:fetch → สร้าง ArgoCD Application |

**ข้อจำกัดที่ควรรู้:** `github.com/project-slug` annotation เป็นข้อบังคับของ Template 2
(ตอนนี้ scaffolder v1beta3 เช็กเงื่อนไขก่อนข้าม step ไม่ได้) — component ที่ไม่มี annotation
นี้จะสร้าง repoURL ผิด ให้ใช้เฉพาะ component ที่เจนจาก Template 1 หรือใส่ annotation เอง

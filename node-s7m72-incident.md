# Incident Report: node `ocp420-v9xnf-worker-0-s7m72` — เครือข่ายและ I/O ผิดปกติ

> ผู้แจ้ง: ทีม platform (Backstage/GitOps demo)
> วันที่ตรวจพบ: 2026-10-09 → 2026-10-20 (อาการค้างหลายวัน)
> สถานะปัจจุบัน: **cordon ไว้แล้ว** (`oc cordon ocp420-v9xnf-worker-0-s7m72`) — ไม่รับ pod ใหม่
> ผลกระทบต่อระบบ: ไม่มี downtime (workload ทั้งหมดย้ายไป node อื่นแล้ว) — แต่ CI builds กระจุกอยู่ node เดียว

---

## ข้อมูล Node

| | |
|---|---|
| Hostname | `ocp420-v9xnf-worker-0-s7m72` |
| IP | `192.168.202.111` |
| Role | worker |
| Uptime ณ วันตรวจ | ~143 วัน |
| OS | RHCOS 9.6 (OpenShift 4.20, Kubernetes 1.33) |
| สถานะปัจจุบัน | Ready, SchedulingDisabled |

## อาการที่พบ (พร้อมหลักฐาน)

### 1. host-network → pod-network ตัน (ทำให้ Route 503)

Router (HAProxy, host network บน infra node) เชื่อมต่อ pod IP บน node นี้ไม่ได้
ขณะที่ pod→pod ข้าม node ปกติ:

```
# จาก router pod → pod IP บน s7m72 (10.131.0.64:8080)
curl → 000 (timeout, exit 28)          ❌
# จาก pod บน node อื่น → pod IP เดียวกัน
curl → 200 OK                          ✅
# ผลลัพธ์: Route ของ app ที่รันบน node นี้ตอบ 503 "Application is not available"
```

### 2. egress จาก pod บน node นี้ไม่สม่ำเสมอ

| ปลายทาง | ผล |
|---|---|
| github.com:443 (git clone) | ✅ ผ่าน |
| registry.access.redhat.com (dnf/pull) | ✅ ผ่าน |
| api.github.com:443 | ❌ ETIMEDOUT |
| repo.maven.apache.org / maven.repository.redhat.com | ❌ ETIMEDOUT |
| ผ่าน cluster proxy (proxy.ocp420.mbixtech.net:8080) | ✅ ผ่าน |

→ สงสัย egress allowlist ไม่สม่ำเสมอระหว่าง node หรือ OVN gateway ของ node นี้มีปัญหา

### 3. DNS ภายในล้มเหลวบางส่วนจาก pod บน node นี้

```
getent hosts kubernetes.default.svc  → ✅ resolved
getent hosts dex-server.openshift-gitops.svc → ❌ ล้มเหลว (timeout)
# (ทดสอบจาก pod ที่ pin ไว้ที่ node นี้)
```

### 4. I/O hang (D-state) ส่งผลให้ argocd-server crash-loop

- pod `openshift-gitops-server` เมื่อถูก schedule มาที่ node นี้: process เข้าสถานะ
  **D (uninterruptible sleep)**, ไม่ bind port, log เขียนไม่ออก → liveness kill วนซ้ำ
- ย้ายไป node อื่น (pin nodeName) → ทำงานปกติทันที
- รวม ๆ: สงสัย disk I/O ของ node ค้างเป็นช่วง ๆ

## การรับมือชั่วคราวที่ทำไปแล้ว

1. `oc cordon ocp420-v9xnf-worker-0-s7m72`
2. pin `openshift-gitops-server` deployment ไว้ที่ node `xfpdg` (nodeName)
3. CI (Tekton) builds ที่เคยรันบน node นี้ → จะไหลไป node อื่นเองเมื่อมี pod ใหม่

## สิ่งที่ขอให้ทีม infra ดำเนินการ

1. ตรวจ OVN-Kubernetes บน node (host→pod forwarding, gateway):
   - `oc debug node/ocp420-v9xnf-worker-0-s7m72` → ทดสอบ connect ไปยัง pod IP บน node เดียวกัน
   - สถานะ ovnkube pod ที่ schedule บน node นี้
2. ตรวจ disk I/O (D-state process + dmesg/nvme errors)
3. **Reboot node** (อาการหลายอย่างสอดคล้องกับ stuck state สะสม) แล้ว uncordon:
   ```bash
   oc uncordon ocp420-v9xnf-worker-0-s7m72
   ```
4. หลัง uncordon — แจ้งทีม platform เพื่อ:
   - ถอน pin ของ argocd-server:
     ```bash
     oc patch deployment/openshift-gitops-server -n openshift-gitops \
       --type json -p '[{"op":"remove","path":"/spec/template/spec/nodeName"}]'
     ```

## การตรวจยืนยันหลังแก้ (ทีม platform จะรันซ้ำ)

1. pod ทดสอบบน node นี้ → curl pod IP ข้าม node ได้ (คาด 200)
2. pod ทดสอบบน node นี้ → DNS ภายใน + api.github.com ผ่าน proxy (คาด 200)
3. argocd-server ถอน pin → รันปกติไม่ว่างโดยสุ่ม node

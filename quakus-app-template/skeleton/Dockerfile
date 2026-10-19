# Step 1: Build Quarkus app (fast-jar)
# หมายเหตุ: ต้องระบุ registry เต็ม — buildah ใน Tekton บังคับ short-name resolution โดยไม่มี TTY ให้ตอบ
# PROXY_URL: cluster ที่ egress ผ่าน cluster-wide proxy — ค่ามาจาก template param proxyUrl (ค่าว่าง = ไม่ใช้ proxy)
#   - buildah (Go) อ่านจาก env HTTP(S)_PROXY โดยตรง
#   - mvn (Java) ไม่อ่าน env proxy — ต้องเขียน settings.xml แทน
ARG PROXY_URL=""
# Nexus group repo (gsb-maven-group) — Maven mirror ทั้งหมดไปที่นี่ (แก้ที่นี่เมื่อ nexus เปลี่ยน)
ARG NEXUS_URL="https://nppsts-nexus.ocp420.mbixtech.net/repository/gsb-maven-group"
FROM docker.io/library/maven:3.9-eclipse-temurin-21 AS builder
ARG PROXY_URL
ARG NEXUS_URL
ENV PROXY_URL=${PROXY_URL} \
    NEXUS_URL=${NEXUS_URL} \
    HTTP_PROXY=${PROXY_URL} \
    HTTPS_PROXY=${PROXY_URL} \
    NO_PROXY=localhost,127.0.0.1,.svc,.svc.cluster.local,.cluster.local,image-registry.openshift-image-registry.svc,nppsts-nexus.ocp420.mbixtech.net
WORKDIR /app
COPY . .
# settings.xml ลำดับความสำคัญ: (1) Nexus mirror ถ้าระบุ (เร็ว/cache) (2) cluster proxy (3) direct
# หมายเหตุ: Java ไม่อ่าน env proxy — Maven ใช้ settings.xml เท่านั้น
RUN set -eux; \
    mkdir -p /root/.m2; \
    if [ -n "$NEXUS_URL" ]; then \
      printf '<settings><mirrors><mirror><id>nexus</id><name>Team Nexus mirror</name><mirrorOf>*</mirrorOf><url>%s</url></mirror></mirrors></settings>' "$NEXUS_URL" > /root/.m2/settings.xml; \
    elif [ -n "$PROXY_URL" ]; then \
      P_HOST="$(echo "$PROXY_URL" | sed -E 's#^[a-z]+://##; s#:.*##')"; \
      P_PORT="$(echo "$PROXY_URL" | sed -E 's#.*:([0-9]+)/?#\1#')"; \
      printf '<settings><proxies><proxy><id>cluster-proxy</id><active>true</active><protocol>http</protocol><host>%s</host><port>%s</port><nonProxyHosts>localhost|127.0.0.1|*.svc|*.svc.cluster.local|*.cluster.local|image-registry*</nonProxyHosts></proxy></proxies></settings>' "$P_HOST" "$P_PORT" > /root/.m2/settings.xml; \
    fi; \
    mvn -Dmaven.wagon.http.ssl.insecure=true -Dmaven.wagon.http.ssl.allowall=true -Dmaven.wagon.http.ssl.ignore.validity=true clean package -DskipTests

# Step 2: Create Runtime Image (runtime ไม่ต้องใช้ proxy — ไม่มี outbound)
FROM docker.io/library/eclipse-temurin:21-jre-jammy
WORKDIR /app
COPY --from=builder /app/target/quarkus-app /app
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "quarkus-run.jar"]

# Step 1: Build Quarkus app (fast-jar)
# หมายเหตุ: ต้องระบุ registry เต็ม — buildah ใน Tekton บังคับ short-name resolution โดยไม่มี TTY ให้ตอบ
# PROXY_URL: cluster ที่ egress ผ่าน cluster-wide proxy — ค่ามาจาก template param proxyUrl (ค่าว่าง = ไม่ใช้ proxy)
#   - buildah (Go) อ่านจาก env HTTP(S)_PROXY โดยตรง
#   - mvn (Java) ไม่อ่าน env proxy — ต้องเขียน settings.xml แทน
ARG PROXY_URL=""
FROM docker.io/library/maven:3.9-eclipse-temurin-21 AS builder
ARG PROXY_URL
ENV PROXY_URL=${PROXY_URL} \
    HTTP_PROXY=${PROXY_URL} \
    HTTPS_PROXY=${PROXY_URL} \
    NO_PROXY=localhost,127.0.0.1,.svc,.svc.cluster.local,.cluster.local,image-registry.openshift-image-registry.svc
WORKDIR /app
COPY . .
RUN set -eux; \
    if [ -n "$PROXY_URL" ]; then \
      P_HOST="$(echo "$PROXY_URL" | sed -E 's#^[a-z]+://##; s#:.*##')"; \
      P_PORT="$(echo "$PROXY_URL" | sed -E 's#.*:([0-9]+)/?#\1#')"; \
      mkdir -p /root/.m2; \
      printf '<settings><proxies><proxy><id>cluster-proxy</id><active>true</active><protocol>http</protocol><host>%s</host><port>%s</port><nonProxyHosts>localhost|127.0.0.1|*.svc|*.svc.cluster.local|*.cluster.local|image-registry*</nonProxyHosts></proxy></proxies></settings>' "$P_HOST" "$P_PORT" > /root/.m2/settings.xml; \
    fi; \
    mvn clean package -DskipTests

# Step 2: Create Runtime Image (runtime ไม่ต้องใช้ proxy — ไม่มี outbound)
FROM docker.io/library/eclipse-temurin:21-jre-jammy
WORKDIR /app
COPY --from=builder /app/target/quarkus-app /app
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "quarkus-run.jar"]

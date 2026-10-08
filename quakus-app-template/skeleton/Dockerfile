# Step 1: Build Quarkus app (fast-jar)
# หมายเหตุ: ต้องระบุ registry เต็ม — buildah ใน Tekton บังคับ short-name resolution โดยไม่มี TTY ให้ตอบ
FROM docker.io/library/maven:3.9-eclipse-temurin-21 AS builder
WORKDIR /app
COPY . .
RUN mvn clean package -DskipTests

# Step 2: Create Runtime Image
FROM docker.io/library/eclipse-temurin:21-jre-jammy
WORKDIR /app
COPY --from=builder /app/target/quarkus-app /app
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "quarkus-run.jar"]

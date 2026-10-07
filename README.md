# Migration Guide: Spring Boot Apache Camel -> Red Hat Apache Camel Quarkus

บันทึกสรุปประเด็นสำคัญ จุดที่ต้องระวัง และข้อควรรู้สำหรับการ migrate จาก Spring Boot Apache Camel ไปยัง Red Hat Build of Apache Camel for Quarkus โดยเนื้อหาเป็น general ใช้ได้กับทุกโปรเจกต์

---

## Table of Contents

- [ทำไมต้อง Migrate](#ทำไมต้อง-migrate)
- [สิ่งที่ต้องเตรียมก่อน Migrate](#สิ่งที่ต้องเตรียมก่อน-migrate)
- [ประเด็นสำคัญที่ต้องรู้](#ประเด็นสำคัญที่ต้องรู้)
  - [0. Create Project](#0-create-project--optional-กรณี-init-project-ใหม)
  - [1. Dependency & BOM Management](#1-dependency--bom-management)
  - [2. Java Namespace: javax -> jakarta](#2-java-namespace-javax---jakarta)
  - [3. Dependency Injection: Spring DI -> CDI](#3-dependency-injection-spring-di---cdi)
  - [4. Configuration Format & Prefix](#4-configuration-format--prefix)
  - [5. Profile-based Configuration](#5-profile-based-configuration)
  - [6. Camel Servlet / REST Configuration](#6-camel-servlet--rest-configuration)
    - [REST DSL route merging กับ direct consumer](#rest-dsl-route-merging-กับ-direct-consumer)
  - [7. JPA & Database Access](#7-jpa--database-access)
    - [ข้อมูลเริ่มต้น: import.sql vs import.sql](#ข้อมูลเริ่มต้น-datalsql-vs-importsql)
  - [8. Circuit Breaker: Hystrix -> MicroProfile Fault Tolerance](#8-circuit-breaker-hystrix---microprofile-fault-tolerance)
  - [9. AMQP / Messaging](#9-amqp--messaging)
  - [10. SSL / HTTPS / HTTP Component](#10-ssl--https--http-component)
  - [11. Bean Validation](#11-bean-validation)
  - [12. Caching](#12-caching)
  - [13. Logging](#13-logging)
  - [14. Health Check & Monitoring](#14-health-check--monitoring)
  - [15. Scheduling & Timer](#15-scheduling--timer)
  - [16. Exception Handling](#16-exception-handling)
- [จุดที่ต้องระวัง (Pitfalls)](#จุดที่ต้องระวัง-pitfalls)
- [Migration Checklist](#migration-checklist)

---

## ทำไมต้อง Migrate

| เหตุผล | รายละเอียด |
|--------|-----------|
| **Startup Speed** | Quarkus startup เร็วกว่า Spring Boot 10x+ (sub-second) เหมาะกับ container/serverless |
| **Memory Usage** | RSS memory ต่ำกว่ามาก โดยเฉพาะ native mode |
| **Native Compilation** | รองรับ GraalVM native image โดยตรง ได้ binary ที่รันได้เลยไม่ต้องมี JDK |
| **Red Hat Support** | มี commercial support จาก Red Hat สำหรับ production |
| **Cloud-Native** | ออกแบบมาสำหรับ Kubernetes / OpenShift ตั้งแต่แรก |

---

## สิ่งที่ต้องเตรียมก่อน Migrate

1. **Red Hat Maven Repository** -- เพิ่ม profile ใน `~/.m2/settings.xml` เพื่อดึง Red Hat artifacts ได้ (ดู README.md)
2. **เช็ค Camel components ที่ใช้** -- ตรวจสอบว่าทุก component ที่ใช้มี camel-quarkus extension รองรับ ที่ [Camel Quarkus Extensions List](https://docs.redhat.com/en/documentation/red_hat_build_of_apache_camel/4.14/html-single/red_hat_build_of_apache_camel_for_quarkus_reference/camel-quarkus-extensions-reference#camel-quarkus-supported-extensions)
3. **เช็ค third-party libraries** -- บาง lib อาจไม่รองรับ native image ต้องเช็ค GraalVM compatibility
4. **ทำความเข้าใจ CDI** -- Quarkus ใช้ ArC ซึ่งเป็น Implement ของมาตรฐาน CDI (Contexts and Dependency Injection)  แทน Spring IoC (Inversion of Control)
[ExceptionHandlingService.java](src/main/java/th/or/gsb/api/service/ExceptionHandlingService.java)
---

## ประเด็นสำคัญที่ต้องรู้

### 0. Create Project ( Optional กรณี init project ใหม่)

**Option A:** สร้างผ่าน [code.camel.redhat.com](https://code.camel.redhat.com/) (Red Hat Build of Apache Camel for Quarkus)

**Option B:** สร้างผ่าน Maven archetype:

```bash
mvn com.redhat.quarkus.platform:quarkus-maven-plugin:3.27.2.redhat-00002:create \
    -DprojectGroupId=th.or.gsb.api \
    -DprojectArtifactId=s15-payment-system-notification \
    -DplatformGroupId=com.redhat.quarkus.platform \
    -DplatformVersion=3.27.2.redhat-00002
```

### 1. Dependency & BOM Management

Spring Boot ใช้ parent POM / BOM เดียว Quarkus ต้องใช้ BOM 2 ตัว:

```xml
<!-- BOM หลักของ Quarkus -->
<dependency>
    <groupId>com.redhat.quarkus.platform</groupId>
    <artifactId>quarkus-bom</artifactId>
    <version>3.27.2.redhat-00002</version>
    <type>pom</type>
    <scope>import</scope>
</dependency>

<!-- BOM สำหรับ Camel extensions -->
<dependency>
    <groupId>com.redhat.quarkus.platform</groupId>
    <artifactId>quarkus-camel-bom</artifactId>
    <version>3.27.2.redhat-00002</version>
    <type>pom</type>
    <scope>import</scope>
</dependency>
```

> **สำคัญ:** ห้ามผสม version ของ Quarkus BOM และ Camel BOM ต่างกัน และห้ามใช้ community `io.quarkus:quarkus-bom` ผสมกับ Red Hat `com.redhat.quarkus.platform:quarkus-bom`

> **สำคัญ:** ทุก camel dependency เปลี่ยน groupId จาก `org.apache.camel.springboot` เป็น `org.apache.camel.quarkus` และ artifactId เปลี่ยนจาก `camel-xxx-starter` เป็น `camel-quarkus-xxx`

**ตัวอย่าง:**

| Spring Boot Camel | Red Hat Camel Quarkus |
|---|---|
| `org.apache.camel.springboot:camel-rest-starter` | `org.apache.camel.quarkus:camel-quarkus-rest` |
| `org.apache.camel.springboot:camel-jackson-starter` | `org.apache.camel.quarkus:camel-quarkus-jackson` |
| `org.apache.camel.springboot:camel-http-starter` | `org.apache.camel.quarkus:camel-quarkus-http` |
| `org.apache.camel.springboot:camel-jpa-starter` | `org.apache.camel.quarkus:camel-quarkus-jpa` |
| `org.apache.camel.springboot:camel-amqp-starter` | `org.apache.camel.quarkus:camel-quarkus-amqp` |
| `org.apache.camel.springboot:camel-bean-starter` | `org.apache.camel.quarkus:camel-quarkus-bean` |
| `org.apache.camel.springboot:camel-mail-starter` | `org.apache.camel.quarkus:camel-quarkus-mail` |
| `org.apache.camel.springboot:camel-jsonpath-starter` | `org.apache.camel.quarkus:camel-quarkus-jsonpath` |

**Build plugin:**

| Spring Boot | Quarkus |
|---|---|
| `spring-boot-maven-plugin` | `quarkus-maven-plugin` |
| `org.springframework.boot:spring-boot-maven-plugin` | `${quarkus.platform.group-id}:quarkus-maven-plugin` |

---

### 2. Java Namespace: javax -> jakarta

Quarkus 3.x+ ใช้ Jakarta EE namespace ทั้งหมด:

```java
// Before
import javax.persistence.*;
import javax.validation.*;
import javax.transaction.*;

// After
import jakarta.persistence.*;
import jakarta.validation.*;
import jakarta.transaction.*;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
```

> **Tip:** ใช้ IDE "Replace in Path" เปลี่ยน `javax.persistence` -> `jakarta.persistence` ทั้ง project ได้เลย แต่ระวัง `javax.net.ssl`, `javax.xml` บางตัวยังคงเดิม

---

### 3. Dependency Injection: Spring DI -> CDI

#### Annotation Mapping

| Spring | Quarkus (CDI) | หมายเหตุ |
|--------|---------------|----------|
| `@Service` | `@ApplicationScoped` | หรือ `@Singleton` |
| `@Component` | `@ApplicationScoped` | |
| `@Repository` | `@ApplicationScoped` | |
| `@Configuration` | `@ApplicationScoped` + `@Produces` | หรือใช้ Quarkus config |
| `@Autowired` | `@Inject` | ใช้ field injection หรือ constructor injection ได้ |
| `@Value("${key}")` | `@ConfigProperty(name = "key")` | จาก `org.eclipse.microprofile.config.inject` |
| `@Qualifier` | `@Named` หรือ custom CDI qualifier | |
| `@Scope("prototype")` | `@Dependent` | |
| `@Scope("request")` | `@RequestScoped` | |
| `@Scope("session")` | `@SessionScoped` | |
| `@PostConstruct` | `@PostConstruct` | เหมือนเดิม (jakarta.annotation) |
| `@PreDestroy` | `@PreDestroy` | เหมือนเดิม (jakarta.annotation) |

#### จุดที่ต่างจาก Spring

```java
// Spring: ใส่ @Service แล้ว Spring สร้าง bean ให้
@Service
public class PaymentService { }

// Quarkus CDI: ต้องใส่ scope annotation ชัดเจน
@ApplicationScoped
public class PaymentService { }
```

```java
// Spring: @Autowired ไม่จำเป็นต้องมี constructor
@Service
public class OrderService {
    @Autowired
    private PaymentService paymentService;
}

// Quarkus: แนะนำ constructor injection
@ApplicationScoped
public class OrderService {
    private final PaymentService paymentService;

    // CDI จะ inject ผ่าน constructor อัตโนมัติ (มี @Inject โดย implicit)
    public OrderService(PaymentService paymentService) {
        this.paymentService = paymentService;
    }
}
```

> **Note:** ใน Quarkus หาก class มีเพียง constructor เดียว CDI จะถือว่ามี `@Inject` โดยอัตโนมัติ (implicit injection)

#### การเรียก Bean ใน Camel Route

```java
// Spring: bean() ใช้ Spring bean name
.bean("paymentService", "methodName")

// Quarkus: bean() ใช้ Class type
.bean(PaymentService.class, "methodName")

// หรือใช้ instance ที่ inject มา
@ApplicationScoped
public class CamelRouter extends RouteBuilder {
    @Inject
    PaymentService paymentService;

    @Override
    public void configure() {
        from("direct:test")
            .bean(paymentService, "methodName");
    }
}
```

---

### 4. Configuration Format & Prefix

#### ค่า default: `.properties` ไม่ใช่ `.yml`

Quarkus อ่าน config จาก `application.properties` เท่านั้นโดย default **หากต้องการใช้ `application.yml` ต้องเพิ่ม:**

```xml
<dependency>
    <groupId>io.quarkus</groupId>
    <artifactId>quarkus-config-yaml</artifactId>
</dependency>
```

> **ห้ามลืม:** ถ้าไม่เพิ่ม dependency นี้ ไฟล์ `application.yml` จะไม่ถูกอ่าน และ Quarkus จะไม่ error แต่ config ทั้งหมดจะเป็น default หรือว่าง

#### Config Prefix

```yaml
# Spring Boot
spring:
  datasource:
    url: jdbc:postgresql://localhost:5432/mydb
  jpa:
    hibernate:
      ddl-auto: update
  cache:
    type: caffeine

# Quarkus
quarkus:
  datasource:
    db-kind: postgresql
    jdbc:
      url: jdbc:postgresql://localhost:5432/mydb
  hibernate-orm:
    database:
      generation: update
```

#### การอ่านค่า config ใน code

```java
// Spring
@Value("${my.config.key}")
private String configValue;

@Value("${my.config.key:defaultValue}")
private String configValueWithDefault;

// Quarkus
@Inject
@ConfigProperty(name = "my.config.key")
private String configValue;

@Inject
@ConfigProperty(name = "my.config.key", defaultValue = "defaultValue")
private String configValueWithDefault;

// หรือใช้ Optional
@Inject
@ConfigProperty(name = "my.config.key")
private Optional<String> configValue;
```

#### Custom config prefix

```java
// Spring: @ConfigurationProperties(prefix = "my.service")
@ConfigurationProperties(prefix = "my.service")
public class MyServiceConfig {
    private String endpoint;
    private int timeout;
}

// Quarkus: ใช้ SmallRye Config @ConfigMapping
@ConfigMapping(prefix = "my.service")
public interface MyServiceConfig {
    String endpoint();
    int timeout();
}
```

---

### 5. Profile-based Configuration

```yaml
# Spring Boot: แยกไฟล์ application-dev.yml, application-prod.yml

# Quarkus: ใช้ %{profile}. prefix ในไฟล์เดียวกัน
quarkus:
  datasource:
    jdbc:
      url: jdbc:h2:mem:testdb           # default

"%dev":
  quarkus:
    datasource:
      jdbc:
        url: jdbc:h2:mem:devdb           # dev profile

"%prod":
  quarkus:
    datasource:
      jdbc:
        url: jdbc:postgresql://prod-db:5432/mydb  # prod profile
```

> **Note:** ชื่อ profile ของ Quarkus มี built-in profiles: `dev`, `test`, `prod` และสามารถสร้าง custom profile ได้

---

### 6. Camel Servlet / REST Configuration

Spring Boot auto-configure Camel servlet ผ่าน `camel.component.servlet.mapping.context-path` แต่ Quarkus ต้องกำหนดเองใน `RouteBuilder.configure()`:

```java
@ApplicationScoped
public class CamelRouter extends RouteBuilder {

    @Override
    public void configure() throws Exception {
        // ต้องกำหนด restConfiguration เอง
        restConfiguration()
            .contextPath("/api")
            .bindingMode(RestBindingMode.json);

        rest("/payment")
            .post("/verify")
            .type(PaymentRq.class)
            .outType(PaymentRs.class)
            .to("direct:verify");
    }
}
```

> **Note:** Quarkus ใช้ Undertow/Vert.x เป็น HTTP server แทน Tomcat แต่ Camel REST ทำงานได้เหมือนกัน

#### REST DSL route merging กับ direct consumer

ใน Camel Quarkus เมื่อ REST DSL `.to("direct:X")` และ `from("direct:X")` อยู่ด้วยกันใน RouteBuilder เดียวกัน **Camel Quarkus จะ merge route เข้าด้วยกัน** เป็น REST route เดียว ทำให้ `direct://X` **ไม่ถูกลงทะเบียนเป็น direct consumer**

**ปัญหาที่เกิดขึ้น:**

```
# จาก startup log:
Started paymentVerificationInbound (rest://post:/payment:/verify)     ← เป็น REST แทนที่จะเป็น direct://
Started routeByPMTranCodeInbound (rest://post:/payment:/router)       ← เป็น REST แทนที่จะเป็น direct://

# เมื่อ routeByPMTranCode พยายาม .to("direct:paymentVerification"):
→ DirectConsumerNotAvailableException: No consumers available on endpoint: direct://paymentVerification
```

**สาเหตุ:** REST DSL `.to("direct:paymentVerification")` merge เข้ากับ `from("direct:paymentVerification")` ทำให้ consumer ถูกแปลงเป็น REST consumer แทน direct consumer เมื่อ route อื่นพยายามเรียก `.to("direct:paymentVerification")` จึงหา consumer ไม่เจอ

**วิธีแก้:** สร้าง intermediate direct routes คั่นกลาง ไม่ให้ REST DSL ไปยิงโดน shared direct route โดยตรง:

```java
// ❌ ผิด: REST DSL ยิงโดน shared direct route โดยตรง
rest("/payment")
    .post("/verify").to("direct:paymentVerification")      // merge กับ from("direct:paymentVerification")
    .post("/router").to("direct:routeByPMTranCode");       // merge กับ from("direct:routeByPMTranCode")

from("direct:paymentVerification") ...    // ถูก merge → ไม่มี direct consumer
from("direct:routeByPMTranCode")
    .to("direct:paymentVerification");    // ← Error: No consumers available


// ✅ ถูก: ใช้ intermediate routes คั่นกลาง
rest("/payment")
    .post("/verify").to("direct:restVerify")       // merge กับ intermediate (ไม่มีผลกระทบ)
    .post("/notify").to("direct:restNotify")
    .post("/router").to("direct:restRouter");

// Intermediate routes (ถูก merge แทน shared routes)
from("direct:restRouter").routeId("restRouter").to("direct:routeByPMTranCode");
from("direct:restVerify").routeId("restVerify").to("direct:paymentVerification");
from("direct:restNotify").routeId("restNotify").to("direct:enqueuePaymentNotification");

// Shared direct routes (ยังคงเป็น direct consumer ปกติ)
from("direct:routeByPMTranCode") ...
from("direct:paymentVerification") ...
from("direct:enqueuePaymentNotification") ...
```

> **สำคัญ:** ปัญหานี้เกิดเฉพาะเมื่อ **REST DSL และ `from("direct:X")` ใช้ endpoint ชื่อเดียวกัน** และต้องเรียก `direct:X` จาก route อื่นด้วย หาก REST เป็น consumer เพียงอย่างเดียวของ `direct:X` จะไม่มีปัญหา

---

### 7. JPA & Database Access

#### Option A: ใช้ Hibernate ORM + Panache (แนะนำสำหรับโปรเจกต์ใหม่)

```xml
<dependency>
    <groupId>io.quarkus</groupId>
    <artifactId>quarkus-hibernate-orm-panache</artifactId>
</dependency>
```

Panache มี 2 รูปแบบคือ **Active Record** (Entity extend `PanacheEntity`) และ **Repository** (แยก class implement `PanacheRepository`)

**Active Record Pattern:**

```java
// Spring Boot: Entity เป็น POJO ธรรมดา
@Entity
public class NotificationLookup {
    @Id @GeneratedValue
    private Long id;
    private String comCode;
    private String destUrl;
    // getter/setter ...
}

// Quarkus Panache: Entity extend PanacheEntity, field เป็น public
@Entity
public class NotificationLookup extends PanacheEntity {
    public String comCode;
    public String destUrl;
    // ไม่ต้องมี getter/setter, ไม่ต้องประกาศ id field (PanacheEntity มีให้)
}
```

**Repository Pattern (แนะนำ คล้าย Spring Data):**

```java
// Spring Boot: ใช้ Interface extends CrudRepository / JpaRepository
public interface NotificationLookupRepository extends CrudRepository<NotificationLookup, Long> {
    NotificationLookup findByComCode(String comCode);
}

// Quarkus Panache: ใช้ Class implements PanacheRepository
@ApplicationScoped
public class NotificationLookupRepository implements PanacheRepository<NotificationLookup> {

    public NotificationLookup findByComCode(String comCode) {
        return find("comCode", comCode).firstResult();
    }
}
```

#### CrudRepository vs PanacheRepository เปรียบเทียบ

| Feature | Spring `CrudRepository` / `JpaRepository` | Quarkus `PanacheRepository` |
|---------|------------------------------------------|----------------------------|
| **Define** | `interface extends CrudRepository<Entity, ID>` | `class implements PanacheRepository<Entity>` |
| **Annotation** | `@Repository` | `@ApplicationScoped` |
| **Find by ID** | `repository.findById(id)` | `repository.findById(id)` |
| **Find all** | `repository.findAll()` | `repository.listAll()` |
| **Save** | `repository.save(entity)` | `entity.persist()` หรือ `repository.persist(entity)` |
| **Update** | `repository.save(entity)` (dirty check) | `entity.persist()` (same method) |
| **Delete** | `repository.delete(entity)` | `repository.delete(entity)` หรือ `entity.delete()` |
| **Count** | `repository.count()` | `repository.count()` |
| **Exists by ID** | `repository.existsById(id)` | `repository.findById(id) != null` |
| **Custom query** | `findByFieldName(value)` (auto-derived) | `find("fieldName", value).firstResult()` |
| **JPQL query** | `@Query("SELECT e FROM ...")` | `find("FROM Entity WHERE field = ?1", value)` |
| **Native query** | `@Query(value="SELECT ...", nativeQuery=true)` | `find("SELECT ... ", value).project(Entity.class)` |
| **Pagination** | `repository.findAll(pageable)` | `findAll().page(Page.of(page, size))` |
| **Sort** | `repository.findAll(Sort.by("field"))` | `findAll(Sort.by("field"))` |
| **Transaction** | `@Transactional` (Spring) | `@Transactional` (Jakarta) |

#### ตัวอย่าง Migration ทีละ step

**Step 1: Entity**

```java
// Before (Spring Boot)
@Entity
@Table(name = "notification_lookup")
public class NotificationLookup {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "com_code", nullable = false)
    private String comCode;

    @Column(name = "dest_url")
    private String destUrl;

    // getters and setters ...
}

// After (Quarkus Panache)
@Entity
@Table(name = "notification_lookup")
public class NotificationLookup extends PanacheEntity {   // extends PanacheEntity แทน

    @Column(name = "com_code", nullable = false)
    public String comCode;                                 // public field, ไม่ต้องมี getter/setter

    @Column(name = "dest_url")
    public String destUrl;
}
```

**Step 2: Repository**

```java
// Before (Spring Boot)
@Repository
public interface NotificationLookupRepository extends CrudRepository<NotificationLookup, Long> {

    NotificationLookup findByComCode(String comCode);

    List<NotificationLookup> findByDestUrlContaining(String keyword);

    @Query("SELECT n FROM NotificationLookup n WHERE n.comCode IN :codes")
    List<NotificationLookup> findByComCodeIn(@Param("codes") List<String> codes);

    long countByDestUrlNotNull();

    void deleteByComCode(String comCode);
}

// After (Quarkus Panache)
@ApplicationScoped
public class NotificationLookupRepository implements PanacheRepository<NotificationLookup> {

    public NotificationLookup findByComCode(String comCode) {
        return find("comCode", comCode).firstResult();
    }

    public List<NotificationLookup> findByDestUrlContaining(String keyword) {
        return list("destUrl LIKE ?1", "%" + keyword + "%");
    }

    public List<NotificationLookup> findByComCodeIn(List<String> codes) {
        return list("comCode IN ?1", codes);
    }

    public long countByDestUrlNotNull() {
        return count("destUrl IS NOT NULL");
    }

    public long deleteByComCode(String comCode) {
        return delete("comCode", comCode);
    }
}
```

**Step 3: การใช้ใน Service**

```java
// Before (Spring Boot)
@Service
public class PaymentNotificationService {
    @Autowired
    private NotificationLookupRepository repository;

    public NotificationLookup lookup(String comCode) {
        return repository.findByComCode(comCode);
    }

    public NotificationLookup save(NotificationLookup entity) {
        return repository.save(entity);          // insert หรือ update อัตโนมัติ
    }

    public List<NotificationLookup> listAll() {
        return repository.findAll();              // return Iterable
    }
}

// After (Quarkus Panache)
@ApplicationScoped
public class PaymentNotificationService {
    @Inject
    NotificationLookupRepository repository;

    public NotificationLookup lookup(String comCode) {
        return repository.findByComCode(comCode);
    }

    @Transactional
    public NotificationLookup save(NotificationLookup entity) {
        entity.persist();                         // insert หรือ update อัตโนมัติ
        return entity;
    }

    public List<NotificationLookup> listAll() {
        return repository.listAll();              // return List โดยตรง
    }
}
```

> **สำคัญ:** ทุก method ที่ modify data (persist, delete) ต้องอยู่ใน `@Transactional` scope ไม่เช่นนั้นจะ error `javax.persistence.TransactionRequiredException`

#### Panache Query cheat sheet

```java
// find/list/count/delete รองรับ HQL/JPQL string
find("comCode", comCode).firstResult();                    // simple where
find("comCode = ?1 AND destUrl = ?2", code, url).firstResult();   // positional params
find("comCode = :code AND destUrl = :url")                // named params
    .parameter("code", code)
    .parameter("url", url)
    .firstResult();
find("comCode", code).page(Page.of(0, 10)).list();        // pagination
find("comCode", code).withProjection(Fields.with("comCode", "destUrl")).list(); // partial

// stream (สำหรับ dataset ขนาดใหญ่)
try (Stream<NotificationLookup> stream = repository.streamAll()) {
    stream.filter(e -> e.destUrl != null).forEach(...);
}
```

#### Option B: ใช้ Spring Data JPA compatibility (แนะนำสำหรับ migration เร่งด่วน)

```xml
<dependency>
    <groupId>io.quarkus</groupId>
    <artifactId>quarkus-spring-data-jpa</artifactId>
</dependency>
```

ช่วยให้ใช้ Spring Data repository interface เดิมได้โดยไม่ต้องแก้:

```java
// ยังใช้ Spring Data interface ได้เหมือนเดิม
public interface NotificationLookupRepository extends JpaRepository<NotificationLookup, Long> {
    NotificationLookup findByComCode(String comCode);
}
```

> **Note:** Option B เหมาะสำหรับลดแรงงาน migration ใน short term แต่ Option A (Panache) จะได้ประสิทธิภาพดีกว่าและรองรับ native image ได้ดีกว่า

#### ข้อมูลเริ่มต้น: import.sql vs import.sql

Spring Boot ใช้ `import.sql` (ผ่าน Spring `DataSource` initialization) แต่ Quarkus Hibernate ORM ใช้ **`import.sql`** (ตาม convention ของ Hibernate):

| | Spring Boot | Quarkus Hibernate ORM |
|---|---|---|
| **ไฟล์ default** | `import.sql` + `schema.sql` | `import.sql` |
| **ควบคุมด้วย** | `spring.sql.init.mode=always` | `quarkus.hibernate-orm.sql-load-script` |
| **ลำดับการทำงาน** | ขึ้นกับ config (อาจก่อน/หลัง Hibernate) | ชัดเจน: Drop → Create tables → Execute import.sql |
| **ปิดการโหลด** | `spring.sql.init.mode=never` | `quarkus.hibernate-orm.sql-load-script=no-file` |

```yaml
# Spring Boot
spring:
  sql:
    init:
      mode: always        # เปิดใช้ import.sql
  jpa:
    defer-datasource-initialization: true  # ให้ Hibernate สร้าง table ก่อน แล้วค่อยรัน import.sql

# Quarkus Hibernate ORM
quarkus:
  hibernate-orm:
    database:
      generation: drop-and-create   # ให้ Hibernate สร้าง table ให้อัตโนมัติ
    sql-load-script: import.sql     # default อยู่แล้ว ไม่ต้องระบุก็ได้ ถ้าชื่อไฟล์คือ import.sql
    # sql-load-script: no-file      # กรณีต้องการปิดการโหลดข้อมูล
```

> **สำคัญ:** เมื่อ migrate ต้องเปลี่ยนชื่อไฟล์จาก `import.sql` เป็น `import.sql` และลบ `import.sql` เก่าทิ้ง มิฉะนั้นอาจสับสนเพราะ Quarkus ไม่อ่าน `import.sql`

#### การ config datasource

```yaml
# Spring Boot
spring:
  datasource:
    url: jdbc:postgresql://localhost:5432/mydb
    username: user
    password: pass
    driver-class-name: org.postgresql.Driver
  jpa:
    hibernate:
      ddl-auto: update
    show-sql: true

# Quarkus
quarkus:
  datasource:
    db-kind: postgresql           # ใช้ db-kind แทน driver-class-name
    jdbc:
      url: jdbc:postgresql://localhost:5432/mydb
    username: user
    password: pass
  hibernate-orm:
    database:
      generation: update          # แทน ddl-auto
    log:
      sql: true                   # แทน show-sql
```

#### ตารางเปรียบเทียบ config key

| Spring Boot | Quarkus |
|---|---|
| `spring.datasource.url` | `quarkus.datasource.jdbc.url` |
| `spring.datasource.username` | `quarkus.datasource.username` |
| `spring.datasource.password` | `quarkus.datasource.password` |
| `spring.datasource.driver-class-name` | `quarkus.datasource.db-kind` |
| `spring.jpa.hibernate.ddl-auto` | `quarkus.hibernate-orm.database.generation` |
| `spring.jpa.show-sql` | `quarkus.hibernate-orm.log.sql` |
| `spring.jpa.properties.hibernate.dialect` | `quarkus.hibernate-orm.dialect` |

---

### 8. Circuit Breaker: Hystrix -> MicroProfile Fault Tolerance

Hystrix เลิกพัฒนาแล้ว ใน Quarkus ใช้ MicroProfile Fault Tolerance แทน:

#### Dependency

```xml
<dependency>
    <groupId>org.apache.camel.quarkus</groupId>
    <artifactId>camel-quarkus-microprofile-fault-tolerance</artifactId>
</dependency>
<dependency>
    <groupId>io.quarkus</groupId>
    <artifactId>quarkus-smallrye-fault-tolerance</artifactId>
</dependency>
```

#### Route DSL

```java
// Before: Hystrix DSL
from("direct:callBackend")
    .hystrix()
        .hystrixConfiguration()
            .executionTimeoutInMilliseconds(5000)
            .circuitBreakerSleepWindowInMilliseconds(60000)
            .circuitBreakerRequestVolumeThreshold(3)
            .circuitBreakerErrorThresholdPercentage(50)
        .end()
        .toD("http://${header.backendUrl}")
    .onFallback()
        .log("Fallback triggered")
        .setBody(constant("{\"status\":\"fallback\"}"))
    .end();

// After: Circuit Breaker DSL (MicroProfile Fault Tolerance)
from("direct:callBackend")
    .circuitBreaker()
        .faultToleranceConfiguration()
            .timeoutEnabled(true)
            .timeoutDuration(5000L)
            .delay(60000L)
            .requestVolumeThreshold(3)
            .failureRatio(50.0f)
        .end()
        .toD("http://${header.backendUrl}")
    .onFallback()
        .log("Fallback triggered")
        .setBody(constant("{\"status\":\"fallback\"}"))
    .end();
```

#### การใช้ Annotation บน method (นอก Camel Route)

```java
// Before: Hystrix annotation
@HystrixCommand(fallbackMethod = "fallback", commandProperties = {
    @HystrixProperty(name = "execution.isolation.thread.timeoutInMilliseconds", value = "5000")
})

// After: MicroProfile Fault Tolerance annotation
@Timeout(5000)
@CircuitBreaker(requestVolumeThreshold = 3, delay = 60000, failureRatio = 0.5)
@Fallback(fallbackMethod = "fallback")
```

---

### 9. AMQP / Messaging

```xml
<dependency>
    <groupId>org.apache.camel.quarkus</groupId>
    <artifactId>camel-quarkus-amqp</artifactId>
</dependency>
<!-- Connection pooling -->
<dependency>
    <groupId>io.quarkiverse.messaginghub</groupId>
    <artifactId>quarkus-pooled-jms</artifactId>
</dependency>
```

```java
// Camel route เหมือนเดิม
from("amqp:queue:my-queue?exchangePattern=InOnly")
    .log("Received: ${body}")
    .to("direct:process");
```

> **สำคัญ:** Spring Boot ใช้ `CachingConnectionFactory` จัดการ connection pooling อัตโนมัติ ใน Quarkus ต้องเพิ่ม `quarkus-pooled-jms` เพื่อให้มี connection pooling

---

### 10. SSL / HTTPS / HTTP Component

```java
// Spring Boot Camel: ใช้ http4 component
.to("http4://backend.example.com/api?sslContextParameters=#sslParams")

// Quarkus Camel: ใช้ http component (version เดียวทั้ง http/https)
.to("http://backend.example.com/api?sslContextParameters=#sslParams")
```

> **สำคัญ:** Camel Quarkus ใช้ `http` component เดียวทั้ง http และ https (ไม่มี `http4` แยก) และใช้ Vert.x HTTP client แทน Apache HttpClient

---

### 11. Bean Validation

```xml
<dependency>
    <groupId>org.apache.camel.quarkus</groupId>
    <artifactId>camel-quarkus-bean-validator</artifactId>
</dependency>
<dependency>
    <groupId>io.quarkus</groupId>
    <artifactId>quarkus-hibernate-validator</artifactId>
</dependency>
```

```java
// ใช้ใน route เหมือนเดิม
.to("bean-validator://dataValidation")
```

> **สำคัญ:** namespace เปลี่ยน `javax.validation.constraints.*` -> `jakarta.validation.constraints.*` สำหรับ annotation เช่น `@NotNull`, `@Size`, `@Pattern`

---

### 12. Caching

#### Option A: Quarkus Cache (native)

```xml
<dependency>
    <groupId>io.quarkus</groupId>
    <artifactId>quarkus-cache</artifactId>
</dependency>
```

```java
@CacheResult(cacheName = "myCache")
public String expensiveOperation(String key) {
    return computeResult(key);
}
```

#### Option B: Spring Cache compatibility

```xml
<dependency>
    <groupId>io.quarkus</groupId>
    <artifactId>quarkus-spring-cache</artifactId>
</dependency>
```

ช่วยให้ใช้ `@Cacheable`, `@CacheEvict`, `@CachePut` จาก Spring ได้เหมือนเดิม

> **Note:** Quarkus cache ใช้ Caffeine เป็น default provider เหมือน Spring Boot

---

### 13. Logging

| Spring Boot (SLF4J + Logback) | Quarkus (JBoss Logging) |
|---|---|
| `org.slf4j.Logger` | `org.jboss.logging.Logger` |
| `LoggerFactory.getLogger(MyClass.class)` | `Logger.getLogger(MyClass.class.getName())` |
| `log.info("msg")` | `Log.info("msg")` (ใช้ static `Log` ได้) |
| `log.debug("msg {}", var)` | `Log.debugf("msg %s", var)` |
| `application.yml: logging.level.root=INFO` | `application.yml: quarkus.log.level=INFO` |

```java
// Before
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

private static final Logger log = LoggerFactory.getLogger(MyService.class);
log.info("Processing payment: {}", paymentId);

// After
import org.jboss.logging.Logger;

private static final Logger log = Logger.getLogger(MyService.class.getName());
log.info("Processing payment: " + paymentId);

// หรือใช้ static import (สะดวกกว่า)
import io.quarkus.logging.Log;
Log.info("Processing payment: " + paymentId);
```

> **Note:** Quarkus ใช้ JBoss Log Manager ไม่ใช่ Logback การ config ทำผ่าน `quarkus.log.*` ใน application.yml

---

### 14. Health Check & Monitoring

| Spring Boot Actuator | Quarkus SmallRye |
|---|---|
| `/actuator/health` | `/q/health` |
| `/actuator/health/live` | `/q/health/live` |
| `/actuator/health/ready` | `/q/health/ready` |
| `/actuator/info` | `/q/info` |
| `/actuator/prometheus` | `/q/metrics` |
| `/actuator/metrics` | `/q/metrics` |
| Swagger UI (springdoc) | `/q/swagger-ui` |
| OpenAPI JSON | `/q/openapi` |

```xml
<dependency>
    <groupId>io.quarkus</groupId>
    <artifactId>quarkus-smallrye-health</artifactId>
</dependency>
<dependency>
    <groupId>io.quarkus</groupId>
    <artifactId>quarkus-smallrye-openapi</artifactId>
</dependency>
<dependency>
    <groupId>io.quarkus</groupId>
    <artifactId>quarkus-micrometer-registry-prometheus</artifactId>
</dependency>
```

---

### 15. Scheduling & Timer

```java
// Spring
@Scheduled(fixedRate = 5000)
public void periodicTask() { }

// Quarkus
@Scheduled(every = "5s")
public void periodicTask() { }

// หรือ cron
@Scheduled(cron = "0 0 2 * * ?")
public void cronTask() { }
```

---

### 16. Exception Handling

Spring Boot ใช้ `@ControllerAdvice` / `@ExceptionHandler` สำหรับ REST Quarkus ใช้:

```java
// Option A: JAX-RS ExceptionMapper
@Provider
@ApplicationScoped
public class GlobalExceptionHandler implements ExceptionMapper<Exception> {
    @Override
    public Response toResponse(Exception e) {
        return Response.status(500).entity(errorResponse).build();
    }
}

// Option B: Camel onException (ใช้ใน RouteBuilder เหมือนเดิม)
onException(DataValidationException.class)
    .handled(true)
    .process(exchange -> {
        // handle exception
    })
    .setHeader(Exchange.HTTP_RESPONSE_CODE, constant(400));
```

> **Note:** Camel `onException` ทำงานเหมือนเดิมไม่ต้องเปลี่ยน แต่ถ้ามี REST layer ที่ใช้ Spring `@ControllerAdvice` ต้องเปลี่ยนเป็น JAX-RS `ExceptionMapper`

---

## จุดที่ต้องระวัง (Pitfalls)

### 1. ลืมเพิ่ม `quarkus-config-yaml`
Quarkus ไม่อ่าน `application.yml` โดย default ถ้าไม่เพิ่ม dependency นี้ config ทั้งหมดจะเป็นค่า default โดยที่ **ไม่มี error ใดๆ**

### 2. ผสม community Quarkus กับ Red Hat Quarkus
ห้ามผสม `io.quarkus:quarkus-bom` (community) กับ `com.redhat.quarkus.platform:quarkus-bom` (Red Hat) ในโปรเจกต์เดียวกัน จะทำให้เกิด version conflict

### 3. ลืมใส่ `@ApplicationScoped` บน RouteBuilder
ใน Spring Boot ใส่ `@Component` หรือไม่ใส่อะไรก็ได้ถ้าอยู่ใน component scan path แต่ใน Quarkus **ต้องใส่ scope annotation ชัดเจน** ไม่งั้น CDI จะไม่สร้าง bean

### 4. Bean ที่ inject ใน RouteBuilder ต้องเป็น CDI bean
ถ้า service class ไม่มี scope annotation (`@ApplicationScoped`, `@Singleton`) การ `@Inject` ใน RouteBuilder จะได้ `null` หรือ error

### 5. `http4` component ไม่มีใน Camel Quarkus
ใช้ `http` component เดียวทั้ง http และ https

### 6. Spring `@Transactional` ยังใช้ได้แต่ต้องเพิ่ม `quarkus-spring-data-jpa`
ถ้าไม่เพิ่ม `@Transactional` จะไม่ทำงาน

### 7. `application-{profile}.yml` แยกไฟล์ไม่แนะนำ
Quarkus อ่านได้ แต่วิธีที่แนะนำคือใช้ `%{profile}.` prefix ใน `application.yml` ไฟล์เดียว

### 8. Native image ไม่รองรับ reflection ทุกอย่าง
หากใช้ native build ต้อง register reflection สำหรับ class ที่ถูก access แบบ reflective (เช่น Jackson deserialization, JAXB) ใช้ `@RegisterForReflection` annotation

### 9. Hot reload ต่างจาก Spring DevTools
Quarkus dev mode (`quarkus:dev`) รองรับ live reload โดยไม่ต้อง restart แต่การเปลี่ยน dependency หรือ config บางอย่างอาจต้อง restart manual

### 10. ไม่มี Spring Security auto-config
ถ้าโปรเจกต์ใช้ Spring Security ต้องเปลี่ยนเป็น Quarkus Security (`quarkus-security`, `elytron`) หรือใช้ `quarkus-spring-security` compatibility layer

### 11. REST DSL merge กับ direct consumer (Camel Quarkus)
เมื่อ REST DSL `.to("direct:X")` และ `from("direct:X")` อยู่ใน RouteBuilder เดียวกัน Camel Quarkus จะ merge เป็น REST route เดียว ทำให้ `direct://X` ไม่มี consumer วิธีแก้คือใช้ intermediate direct routes คั่นกลาง (ดูรายละเอียดที่หัวข้อ 6)

### 12. สับสนระหว่าง `import.sql` (Spring Boot) กับ `import.sql` (Quarkus)
Spring Boot ใช้ `import.sql` แต่ Quarkus Hibernate ORM ใช้ `import.sql` (ตาม Hibernate convention) ถ้ายังมี `import.sql` ค้างอยู่ใน `src/main/resources/` จะไม่ถูกใช้ และถ้าไม่มี `import.sql` ข้อมูลเริ่มต้นจะไม่ถูก insert

---

## Migration Checklist

- [ ] เพิ่ม Red Hat Maven Repository ใน `settings.xml`
- [ ] สร้างโปรเจกต์ Quarkus ใหม่ หรือแปลง `pom.xml`
- [ ] เปลี่ยน BOM จาก `spring-boot-dependencies` เป็น `quarkus-bom` + `quarkus-camel-bom`
- [ ] เปลี่ยน build plugin จาก `spring-boot-maven-plugin` เป็น `quarkus-maven-plugin`
- [ ] เปลี่ยน camel dependency จาก `camel-xxx-starter` เป็น `camel-quarkus-xxx`
- [ ] เพิ่ม `quarkus-config-yaml` ถ้าใช้ `application.yml`
- [ ] แปลง config prefix จาก `spring.*` เป็น `quarkus.*`
- [ ] เปลี่ยน annotation `@Service/@Component` -> `@ApplicationScoped`
- [ ] เปลี่ยน `@Autowired` -> `@Inject`
- [ ] เปลี่ยน `@Value` -> `@ConfigProperty`
- [ ] เปลี่ยน `javax.*` -> `jakarta.*` (persistence, validation, transaction)
- [ ] เพิ่ม `@ApplicationScoped` บน `RouteBuilder` class
- [ ] เปลี่ยน `restConfiguration()` จาก servlet config เป็นกำหนดใน `configure()`
- [ ] เปลี่ยน Hystrix -> MicroProfile Fault Tolerance
- [ ] เปลี่ยน `http4` -> `http` component
- [ ] เปลี่ยน SLF4J -> JBoss Logging
- [ ] เปลี่ยนไฟล์ `import.sql` เป็น `import.sql` (ลบ `import.sql` เก่าทิ้ง)
- [ ] ตรวจสอบ REST DSL `.to("direct:X")` ที่มี `from("direct:X")` อยู่ด้วย — ต้องใช้ intermediate routes คั่น
- [ ] ตรวจสอบทุก third-party library ว่ารองรับ Quarkus/GraalVM
- [ ] รัน `./mvnw quarkus:dev` ทดสอบ
- [ ] รัน integration tests


---

## References

- [Red Hat Build of Apache Camel for Quarkus - Getting Started](https://docs.redhat.com/en/documentation/red_hat_build_of_apache_camel/4.14/html-single/getting_started_with_red_hat_build_of_apache_camel_for_quarkus/index)
- [Red Hat Build of Apache Camel for Quarkus Reference](https://docs.redhat.com/en/documentation/red_hat_build_of_apache_camel/4.14/html-single/red_hat_build_of_apache_camel_for_quarkus_reference/)
- [Red Hat Build of Quarkus Getting Started](https://docs.redhat.com/en/documentation/red_hat_build_of_quarkus/3.27/html-single/getting_started_with_red_hat_build_of_quarkus/index)
- [Camel Quarkus Extensions Catalog](https://docs.redhat.com/en/documentation/red_hat_build_of_apache_camel/4.14/html-single/red_hat_build_of_apache_camel_for_quarkus_reference/camel-quarkus-extensions-reference)
- [Quarkus - Spring Compatibility Layer](https://quarkus.io/guides/spring)
- [Project Generator - code.camel.redhat.com](https://code.camel.redhat.com/)
- [Red Hat Maven Repository Access](https://access.redhat.com/articles/6507531)
- [Compatibility between Camel Quarkus and dependencies](https://camel.apache.org/camel-quarkus/3.33.x/index.html#_compatibility_matrix)
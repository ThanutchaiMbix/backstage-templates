package com.example.demo;

import jakarta.enterprise.context.ApplicationScoped;
import org.apache.camel.builder.RouteBuilder;
import org.eclipse.microprofile.config.inject.ConfigProperty;

/**
 * Demo Apache Camel route running on Quarkus.
 * Logs a heartbeat every ${app.camel.timer-period} so you can see Camel
 * working in the pod logs: kubectl logs -f deploy/<application_name>
 *
 * ข้อควรรู้จาก migration guide (ข้อ 6): ถ้าจะเพิ่ม Camel REST DSL ใน RouteBuilder
 * ต้องเรียก restConfiguration().contextPath(...) เองใน configure()
 * และอย่าให้ REST DSL .to("direct:X") ชี้ตรงเข้า from("direct:X") ชื่อเดียวกัน —
 * Camel Quarkus จะ merge route ทำให้ direct consumer หาย
 * (ให้สร้าง intermediate direct route คั่นกลาง)
 */
@ApplicationScoped
public class CamelRoute extends RouteBuilder {

    @ConfigProperty(name = "app.camel.timer-period", defaultValue = "10s")
    String timerPeriod;

    @Override
    public void configure() throws Exception {
        fromF("timer:heartbeat?period=%s", timerPeriod)
                .routeId("heartbeat")
                .setBody(simple("heartbeat from Camel on Quarkus at ${date:now:HH:mm:ss}"))
                .log("${body}");
    }
}

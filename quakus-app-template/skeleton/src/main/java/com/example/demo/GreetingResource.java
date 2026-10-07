package com.example.demo;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@Path("/hello")
public class GreetingResource {

    @ConfigProperty(name = "app.greeting", defaultValue = "Hello")
    String greeting;

    @GET
    @Produces(MediaType.TEXT_PLAIN)
    public String hello(@QueryParam("name") String name) {
        String who = (name == null || name.isBlank()) ? "Minikube" : name;
        return greeting + " " + who + "! Quarkus + Camel is running on Kubernetes.";
    }
}

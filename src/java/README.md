# Java - Kubernetes Testcontainers Examples

## Dependencies (Maven)

```xml
<dependencies>
    <!-- Testcontainers Core -->
    <dependency>
        <groupId>org.testcontainers</groupId>
        <artifactId>testcontainers</artifactId>
        <version>1.19.3</version>
        <scope>test</scope>
    </dependency>
    
    <!-- KindContainer -->
    <dependency>
        <groupId>com.dajudge.kindcontainer</groupId>
        <artifactId>kindcontainer</artifactId>
        <version>1.4.0</version>
        <scope>test</scope>
    </dependency>
    
    <!-- Fabric8 Kubernetes Client -->
    <dependency>
        <groupId>io.fabric8</groupId>
        <artifactId>kubernetes-client</artifactId>
        <version>6.9.2</version>
        <scope>test</scope>
    </dependency>
    
    <!-- JUnit 5 -->
    <dependency>
        <groupId>org.junit.jupiter</groupId>
        <artifactId>junit-jupiter</artifactId>
        <version>5.10.1</version>
        <scope>test</scope>
    </dependency>
</dependencies>
```

## Dependencies (Gradle)

```groovy
testImplementation 'org.testcontainers:testcontainers:1.19.3'
testImplementation 'com.dajudge.kindcontainer:kindcontainer:1.4.0'
testImplementation 'io.fabric8:kubernetes-client:6.9.2'
testImplementation 'org.junit.jupiter:junit-jupiter:5.10.1'
```

## Basic Example

```java
package com.example;

import com.dajudge.kindcontainer.KindContainer;
import io.fabric8.kubernetes.api.model.Pod;
import io.fabric8.kubernetes.api.model.PodBuilder;
import io.fabric8.kubernetes.client.ConfigBuilder;
import io.fabric8.kubernetes.client.KubernetesClient;
import io.fabric8.kubernetes.client.KubernetesClientBuilder;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.testcontainers.utility.DockerImageName;

import java.time.Duration;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.*;

class KubernetesIntegrationTest {

    private static KindContainer<?> k8s;
    private static KubernetesClient client;

    @BeforeAll
    static void setupCluster() {
        k8s = new KindContainer<>(DockerImageName.parse("kindest/node:v1.29.1"));
        k8s.start();
        
        client = new KubernetesClientBuilder()
            .withConfig(new ConfigBuilder()
                .withKubeconfig(k8s.getKubeconfig())
                .build())
            .build();
    }

    @AfterAll
    static void teardownCluster() {
        if (client != null) {
            client.close();
        }
        if (k8s != null) {
            k8s.stop();
        }
    }

    @Test
    void shouldCreateAndDeletePod() {
        String namespace = "default";
        String podName = "test-pod";
        
        Pod pod = new PodBuilder()
            .withNewMetadata()
                .withName(podName)
                .withNamespace(namespace)
            .endMetadata()
            .withNewSpec()
                .addNewContainer()
                    .withName("nginx")
                    .withImage("nginx:1.25")
                    .withNewResources()
                        .addToRequests("memory", "128Mi")
                        .addToRequests("cpu", "100m")
                        .addToLimits("memory", "256Mi")
                        .addToLimits("cpu", "500m")
                    .endResources()
                .endContainer()
            .endSpec()
            .build();

        Pod createdPod = client.resource(pod).create();
        assertNotNull(createdPod);
        assertEquals(podName, createdPod.getMetadata().getName());

        boolean podReady = client.pods()
            .inNamespace(namespace)
            .withName(podName)
            .waitUntilCondition(
                p -> p != null && 
                     "Running".equals(p.getStatus().getPhase()),
                2, TimeUnit.MINUTES
            );
        
        assertTrue(podReady, "Pod should be running");

        client.resource(createdPod).delete();
        
        client.pods()
            .inNamespace(namespace)
            .withName(podName)
            .waitUntilCondition(
                p -> p == null,
                1, TimeUnit.MINUTES
            );
    }
}
```

## Deployment Example

```java
package com.example;

import com.dajudge.kindcontainer.KindContainer;
import io.fabric8.kubernetes.api.model.apps.Deployment;
import io.fabric8.kubernetes.api.model.apps.DeploymentBuilder;
import io.fabric8.kubernetes.client.ConfigBuilder;
import io.fabric8.kubernetes.client.KubernetesClient;
import io.fabric8.kubernetes.client.KubernetesClientBuilder;
import org.junit.jupiter.api.*;
import org.testcontainers.utility.DockerImageName;

import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.*;

class DeploymentIntegrationTest {

    private static KindContainer<?> k8s;
    private static KubernetesClient client;

    @BeforeAll
    static void setup() {
        k8s = new KindContainer<>(DockerImageName.parse("kindest/node:v1.29.1"));
        k8s.start();
        
        client = new KubernetesClientBuilder()
            .withConfig(new ConfigBuilder()
                .withKubeconfig(k8s.getKubeconfig())
                .build())
            .build();
    }

    @AfterAll
    static void teardown() {
        if (client != null) client.close();
        if (k8s != null) k8s.stop();
    }

    @Test
    void shouldDeployApplication() {
        String namespace = "default";
        String deploymentName = "nginx-deployment";

        Deployment deployment = new DeploymentBuilder()
            .withNewMetadata()
                .withName(deploymentName)
                .withNamespace(namespace)
            .endMetadata()
            .withNewSpec()
                .withReplicas(2)
                .withNewSelector()
                    .addToMatchLabels("app", "nginx")
                .endSelector()
                .withNewTemplate()
                    .withNewMetadata()
                        .addToLabels("app", "nginx")
                    .endMetadata()
                    .withNewSpec()
                        .addNewContainer()
                            .withName("nginx")
                            .withImage("nginx:1.25")
                            .addNewPort()
                                .withContainerPort(80)
                            .endPort()
                            .withNewResources()
                                .addToRequests("memory", "128Mi")
                                .addToRequests("cpu", "100m")
                                .addToLimits("memory", "256Mi")
                                .addToLimits("cpu", "500m")
                            .endResources()
                        .endContainer()
                    .endSpec()
                .endTemplate()
            .endSpec()
            .build();

        client.apps().deployments()
            .inNamespace(namespace)
            .resource(deployment)
            .create();

        Deployment readyDeployment = client.apps().deployments()
            .inNamespace(namespace)
            .withName(deploymentName)
            .waitUntilCondition(
                d -> d != null && 
                     d.getStatus() != null &&
                     d.getStatus().getReadyReplicas() != null &&
                     d.getStatus().getReadyReplicas() == 2,
                3, TimeUnit.MINUTES
            );

        assertNotNull(readyDeployment);
        assertEquals(2, readyDeployment.getStatus().getReadyReplicas());
    }
}
```

## Service and Port Forward Example

```java
package com.example;

import com.dajudge.kindcontainer.KindContainer;
import io.fabric8.kubernetes.api.model.*;
import io.fabric8.kubernetes.api.model.apps.DeploymentBuilder;
import io.fabric8.kubernetes.client.*;
import org.junit.jupiter.api.*;
import org.testcontainers.utility.DockerImageName;

import java.net.HttpURLConnection;
import java.net.URL;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.*;

class ServiceIntegrationTest {

    private static KindContainer<?> k8s;
    private static KubernetesClient client;

    @BeforeAll
    static void setup() {
        k8s = new KindContainer<>(DockerImageName.parse("kindest/node:v1.29.1"));
        k8s.start();
        
        client = new KubernetesClientBuilder()
            .withConfig(new ConfigBuilder()
                .withKubeconfig(k8s.getKubeconfig())
                .build())
            .build();
    }

    @AfterAll
    static void teardown() {
        if (client != null) client.close();
        if (k8s != null) k8s.stop();
    }

    @Test
    void shouldExposeServiceViaPortForward() throws Exception {
        String namespace = "default";
        String appName = "nginx";

        client.apps().deployments().inNamespace(namespace)
            .resource(new DeploymentBuilder()
                .withNewMetadata()
                    .withName(appName)
                .endMetadata()
                .withNewSpec()
                    .withReplicas(1)
                    .withNewSelector()
                        .addToMatchLabels("app", appName)
                    .endSelector()
                    .withNewTemplate()
                        .withNewMetadata()
                            .addToLabels("app", appName)
                        .endMetadata()
                        .withNewSpec()
                            .addNewContainer()
                                .withName(appName)
                                .withImage("nginx:1.25")
                                .addNewPort()
                                    .withContainerPort(80)
                                .endPort()
                                .withNewResources()
                                    .addToRequests("memory", "128Mi")
                                    .addToRequests("cpu", "100m")
                                    .addToLimits("memory", "256Mi")
                                    .addToLimits("cpu", "500m")
                                .endResources()
                            .endContainer()
                        .endSpec()
                    .endTemplate()
                .endSpec()
                .build())
            .create();

        client.services().inNamespace(namespace)
            .resource(new ServiceBuilder()
                .withNewMetadata()
                    .withName(appName)
                .endMetadata()
                .withNewSpec()
                    .addToSelector("app", appName)
                    .addNewPort()
                        .withPort(80)
                        .withTargetPort(new IntOrString(80))
                    .endPort()
                .endSpec()
                .build())
            .create();

        Pod pod = client.pods()
            .inNamespace(namespace)
            .withLabel("app", appName)
            .list()
            .getItems()
            .get(0);

        client.pods()
            .inNamespace(namespace)
            .withName(pod.getMetadata().getName())
            .waitUntilCondition(
                p -> "Running".equals(p.getStatus().getPhase()),
                2, TimeUnit.MINUTES
            );

        try (PortForward portForward = client.pods()
                .inNamespace(namespace)
                .withName(pod.getMetadata().getName())
                .portForward(80, 8080)) {
            
            int localPort = portForward.getLocalPort();
            
            URL url = new URL("http://localhost:" + localPort + "/");
            HttpURLConnection connection = (HttpURLConnection) url.openConnection();
            connection.setRequestMethod("GET");
            connection.setConnectTimeout(5000);
            connection.setReadTimeout(5000);
            
            int responseCode = connection.getResponseCode();
            assertEquals(200, responseCode);
        }
    }
}
```

## Log Collection on Failure

```java
package com.example;

import com.dajudge.kindcontainer.KindContainer;
import io.fabric8.kubernetes.client.*;
import org.junit.jupiter.api.*;
import org.testcontainers.utility.DockerImageName;

import java.util.List;

class DebugHelperTest {

    private static KindContainer<?> k8s;
    private static KubernetesClient client;

    @BeforeAll
    static void setup() {
        k8s = new KindContainer<>(DockerImageName.parse("kindest/node:v1.29.1"));
        k8s.start();
        
        client = new KubernetesClientBuilder()
            .withConfig(new ConfigBuilder()
                .withKubeconfig(k8s.getKubeconfig())
                .build())
            .build();
    }

    @AfterAll
    static void teardown() {
        if (client != null) client.close();
        if (k8s != null) k8s.stop();
    }

    protected void collectDebugInfo(String namespace) {
        System.out.println("=== PODS ===");
        client.pods().inNamespace(namespace).list().getItems()
            .forEach(pod -> {
                System.out.println("Pod: " + pod.getMetadata().getName());
                System.out.println("Status: " + pod.getStatus().getPhase());
                System.out.println("Logs:");
                try {
                    String logs = client.pods()
                        .inNamespace(namespace)
                        .withName(pod.getMetadata().getName())
                        .getLog();
                    System.out.println(logs);
                } catch (Exception e) {
                    System.out.println("Could not get logs: " + e.getMessage());
                }
            });

        System.out.println("\n=== EVENTS ===");
        client.v1().events().inNamespace(namespace).list().getItems()
            .forEach(event -> {
                System.out.println(event.getType() + ": " + event.getMessage());
            });
    }
}
```
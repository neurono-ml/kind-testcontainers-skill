# Scala - Kubernetes Testcontainers Examples

## Dependencies (build.sbt)

```scala
val testcontainersVersion = "1.19.3"
val kindcontainerVersion = "1.4.0"
val fabric8Version = "6.9.2"

libraryDependencies ++= Seq(
  "org.testcontainers" % "testcontainers" % testcontainersVersion % Test,
  "com.dajudge.kindcontainer" % "kindcontainer" % kindcontainerVersion % Test,
  "io.fabric8" % "kubernetes-client" % fabric8Version % Test,
  "org.scalatest" %% "scalatest" % "3.2.17" % Test,
  "org.scalatestplus" %% "scalacheck-1-17" % "3.2.17.0" % Test
)
```

## Dependencies (build.sc - Mill)

```scala
object testDeps extends Deps {
  val ivyDeps = Agg(
    ivy"org.testcontainers:testcontainers:1.19.3",
    ivy"com.dajudge.kindcontainer:kindcontainer:1.4.0",
    ivy"io.fabric8:kubernetes-client:6.9.2",
    ivy"org.scalatest::scalatest:3.2.17"
  )
}
```

## KindCluster Trait

```scala
// src/test/scala/KindClusterSpec.scala

import com.dajudge.kindcontainer.KindContainer
import io.fabric8.kubernetes.client._
import io.fabric8.kubernetes.client.Config
import org.scalatest.{BeforeAndAfterAll, Suite}
import org.testcontainers.utility.DockerImageName

import scala.concurrent.duration._
import scala.util.Try

trait KindClusterSpec extends BeforeAndAfterAll { this: Suite =>
  
  private var kindContainer: KindContainer[_] = _
  protected var kubernetesClient: KubernetesClient = _
  
  override def beforeAll(): Unit = {
    super.beforeAll()
    
    kindContainer = new KindContainer<>(DockerImageName.parse("kindest/node:v1.29.1"))
    kindContainer.start()
    
    val config = new ConfigBuilder()
      .withKubeconfig(kindContainer.getKubeconfig)
      .build()
    
    kubernetesClient = new KubernetesClientBuilder()
      .withConfig(config)
      .build()
  }
  
  override def afterAll(): Unit = {
    Try(kubernetesClient.close())
    Try(kindContainer.stop())
    super.afterAll()
  }
  
  protected def waitForPodReady(
    namespace: String,
    podName: String,
    timeout: FiniteDuration = 2.minutes
  ): Boolean = {
    import scala.concurrent.blocking
    
    val startTime = System.currentTimeMillis()
    val timeoutMs = timeout.toMillis
    
    blocking {
      while (System.currentTimeMillis() - startTime < timeoutMs) {
        val pod = kubernetesClient.pods()
          .inNamespace(namespace)
          .withName(podName)
          .get()
        
        if (pod != null && "Running" == pod.getStatus.getPhase) {
          return true
        }
        
        Thread.sleep(2000)
      }
    }
    
    false
  }
  
  protected def waitForDeploymentReady(
    namespace: String,
    deploymentName: String,
    expectedReplicas: Int,
    timeout: FiniteDuration = 3.minutes
  ): Boolean = {
    val startTime = System.currentTimeMillis()
    val timeoutMs = timeout.toMillis
    
    while (System.currentTimeMillis() - startTime < timeoutMs) {
      val deployment = kubernetesClient.apps().deployments()
        .inNamespace(namespace)
        .withName(deploymentName)
        .get()
      
      if (deployment != null && deployment.getStatus != null) {
        val readyReplicas = Option(deployment.getStatus.getReadyReplicas).map(_.intValue()).getOrElse(0)
        if (readyReplicas == expectedReplicas) {
          return true
        }
      }
      
      Thread.sleep(3000)
    }
    
    false
  }
}
```

## Basic Test Example

```scala
// src/test/scala/PodIntegrationTest.scala

import io.fabric8.kubernetes.api.model._
import org.scalatest.flatspec.AnyFlatSpec
import org.scalatest.matchers.should.Matchers
import KindClusterSpec._

import java.util.concurrent.TimeUnit

class PodIntegrationTest extends AnyFlatSpec with Matchers with KindClusterSpec {

  it should "create and delete a pod" in {
    val namespace = "default"
    val podName = "test-pod"

    val pod = new PodBuilder()
      .withNewMetadata()
        .withName(podName)
        .withNamespace(namespace)
      .endMetadata()
      .withNewSpec()
        .addNewContainer()
          .withName("nginx")
          .withImage("nginx:1.25")
          .withNewResources()
            .addToRequests("memory", new Quantity("128Mi"))
            .addToRequests("cpu", new Quantity("100m"))
            .addToLimits("memory", new Quantity("256Mi"))
            .addToLimits("cpu", new Quantity("500m"))
          .endResources()
        .endContainer()
      .endSpec()
      .build()

    val createdPod = kubernetesClient.resource(pod).create()
    createdPod.getMetadata.getName shouldBe podName
    println(s"Created pod: ${createdPod.getMetadata.getName}")

    val isReady = waitForPodReady(namespace, podName)
    isReady shouldBe true
    println("Pod is running")

    kubernetesClient.resource(createdPod).delete()
    println("Deleted pod")
  }
}
```

## Deployment Example

```scala
// src/test/scala/DeploymentIntegrationTest.scala

import io.fabric8.kubernetes.api.model._
import io.fabric8.kubernetes.api.model.apps._
import org.scalatest.flatspec.AnyFlatSpec
import org.scalatest.matchers.should.Matchers
import KindClusterSpec._

class DeploymentIntegrationTest extends AnyFlatSpec with Matchers with KindClusterSpec {

  it should "create a deployment with replicas" in {
    val namespace = "default"
    val deploymentName = "nginx-deployment"

    val deployment = new DeploymentBuilder()
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
                .addToRequests("memory", new Quantity("128Mi"))
                .addToRequests("cpu", new Quantity("100m"))
                .addToLimits("memory", new Quantity("256Mi"))
                .addToLimits("cpu", new Quantity("500m"))
              .endResources()
            .endContainer()
          .endSpec()
        .endTemplate()
      .endSpec()
      .build()

    val created = kubernetesClient.apps().deployments()
      .inNamespace(namespace)
      .resource(deployment)
      .create()

    println(s"Created deployment: ${created.getMetadata.getName}")

    val isReady = waitForDeploymentReady(namespace, deploymentName, 2)
    isReady shouldBe true
    println("Deployment is ready with 2 replicas")

    kubernetesClient.apps().deployments()
      .inNamespace(namespace)
      .withName(deploymentName)
      .delete()
    println("Deleted deployment")
  }
}
```

## Debug Helper

```scala
// src/test/scala/DebugHelper.scala

import io.fabric8.kubernetes.client.KubernetesClient

object DebugHelper {
  
  def collectDebugInfo(client: KubernetesClient, namespace: String): Unit = {
    println("=== PODS ===")
    val pods = client.pods().inNamespace(namespace).list().getItems
    pods.forEach { pod =>
      println(s"Pod: ${pod.getMetadata.getName} - Phase: ${pod.getStatus.getPhase}")
      
      if (pod.getStatus.getPhase != "Running") {
        try {
          val logs = client.pods()
            .inNamespace(namespace)
            .withName(pod.getMetadata.getName)
            .getLog
          println(s"Logs for ${pod.getMetadata.getName}:")
          println(logs)
        } catch {
          case e: Exception => println(s"Could not get logs: ${e.getMessage}")
        }
      }
    }
    
    println("\n=== EVENTS ===")
    val events = client.v1().events().inNamespace(namespace).list().getItems
    events.forEach { event =>
      println(s"[${event.getType}] ${event.getInvolvedObject.getKind}/${event.getInvolvedObject.getName}: ${event.getMessage}")
    }
  }
  
  def describePod(client: KubernetesClient, namespace: String, name: String): Unit = {
    val pod = client.pods().inNamespace(namespace).withName(name).get()
    
    println("=== POD DETAILS ===")
    println(s"Name: ${pod.getMetadata.getName}")
    println(s"Namespace: ${pod.getMetadata.getNamespace}")
    println(s"Phase: ${pod.getStatus.getPhase}")
    println(s"Pod IP: ${pod.getStatus.getPodIP}")
    println(s"Host IP: ${pod.getStatus.getHostIP}")
    
    println("\n=== CONTAINER STATUSES ===")
    Option(pod.getStatus.getContainerStatuses).foreach { statuses =>
      statuses.forEach { cs =>
        println(s"Container: ${cs.getName}")
        println(s"  Ready: ${cs.getReady}")
        println(s"  Restarts: ${cs.getRestartCount}")
        Option(cs.getState).flatMap(s => Option(s.getWaiting)).foreach { waiting =>
          println(s"  Waiting: ${waiting.getReason} - ${waiting.getMessage}")
        }
      }
    }
  }
}
```

## Cats Effect Version

```scala
// src/test/scala/KindClusterF.scala

import cats.effect._
import com.dajudge.kindcontainer.KindContainer
import io.fabric8.kubernetes.client._
import org.testcontainers.utility.DockerImageName

import scala.concurrent.duration._

class KindClusterF[F[_]: Async] {

  def createCluster: Resource[F, KubernetesClient] = Resource.make {
    Async[F].blocking {
      val container = new KindContainer[Nothing](DockerImageName.parse("kindest/node:v1.29.1"))
      container.start()
      
      val config = new ConfigBuilder()
        .withKubeconfig(container.getKubeconfig)
        .build()
      
      val client = new KubernetesClientBuilder()
        .withConfig(config)
        .build()
      
      (container, client)
    }
  } { case (container, client) =>
    Async[F].blocking {
      client.close()
      container.stop()
    }
  }.map(_._2)
}

object KindClusterF {
  def apply[F[_]: Async]: KindClusterF[F] = new KindClusterF[F]
}
```

## Cats Effect Test

```scala
// src/test/scala/CatsEffectIntegrationTest.scala

import cats.effect._
import cats.effect.unsafe.implicits.global
import io.fabric8.kubernetes.api.model._
import KindClusterF._
import org.scalatest.flatspec.AnyFlatSpec
import org.scalatest.matchers.should.Matchers

class CatsEffectIntegrationTest extends AnyFlatSpec with Matchers {

  it should "create and delete a pod using Cats Effect" in {
    val result = KindClusterF[IO].createCluster.use { client =>
      IO {
        val namespace = "default"
        val podName = "test-pod-ce"

        val pod = new PodBuilder()
          .withNewMetadata()
            .withName(podName)
            .withNamespace(namespace)
          .endMetadata()
          .withNewSpec()
            .addNewContainer()
              .withName("nginx")
              .withImage("nginx:1.25")
            .endContainer()
          .endSpec()
          .build()

        val created = client.resource(pod).create()
        created.getMetadata.getName shouldBe podName

        client.resource(created).delete()
      }
    }

    result.unsafeRunSync()
  }
}
```

## Run Script

```bash
#!/bin/bash
# scripts/run-tests.sh

set -e

echo "Checking Docker..."
docker ps > /dev/null 2>&1 || { echo "Docker not running"; exit 1; }

echo "Running tests..."
sbt test

echo "Tests completed!"
```
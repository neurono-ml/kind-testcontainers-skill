# Rust - Kubernetes Testcontainers Examples

## Dependencies (Cargo.toml)

```toml
[dev-dependencies]
testcontainers = "0.15"
kube = { version = "0.87", features = ["runtime", "derive"] }
k8s-openapi = { version = "0.20", features = ["latest"] }
tokio = { version = "1", features = ["full"] }
serde_yaml = "0.9"
serde = { version = "1", features = ["derive"] }
anyhow = "1"
```

## KindCluster Module

```rust
// tests/kind_cluster.rs

use anyhow::{Context, Result};
use serde_yaml::Value;
use std::time::Duration;
use testcontainers::{
    core::{Container, Docker, WaitFor},
    Image, RunnableImage,
};
use tokio::time::sleep;

const KIND_IMAGE: &str = "kindest/node";
const KIND_VERSION: &str = "v1.29.1";
const KUBECONFIG_PATH: &str = "/etc/kubernetes/admin.conf";

pub struct KindImage;

impl Image for KindImage {
    type Args = ();

    fn name(&self) -> String {
        KIND_IMAGE.to_string()
    }

    fn tag(&self) -> String {
        KIND_VERSION.to_string()
    }

    fn ready_conditions(&self) -> Vec<WaitFor> {
        vec![WaitFor::message_on_stdout(
            "Reached ap readiness hooks",
        )]
    }

    fn expose_ports(&self) -> Vec<u16> {
        vec![6443]
    }
}

pub struct KindCluster {
    container: Container<'static, KindImage>,
    kubeconfig: String,
    client: kube::Client,
}

impl KindCluster {
    pub async fn new() -> Result<Self> {
        let image = RunnableImage::from(KindImage);
        let container = image.start();

        let port = container
            .get_host_port_ipv4(6443)
            .context("Failed to get mapped port")?;

        let kubeconfig = Self::extract_and_patch_kubeconfig(&container, port).await?;

        let client = Self::create_client(&kubeconfig)?;

        Self::wait_for_api_ready(&client).await?;

        Ok(Self {
            container,
            kubeconfig,
            client,
        })
    }

    async fn extract_and_patch_kubeconfig(
        container: &Container<'static, KindImage>,
        mapped_port: u16,
    ) -> Result<String> {
        let output = container
            .exec(vec!["cat".to_string(), KUBECONFIG_PATH.to_string()])
            .context("Failed to read kubeconfig from container")?;

        let mut kubeconfig: Value = serde_yaml::from_str(&output)
            .context("Failed to parse kubeconfig YAML")?;

        if let Some(clusters) = kubeconfig
            .get_mut("clusters")
            .and_then(|c| c.as_sequence_mut())
        {
            for cluster in clusters {
                if let Some(server) = cluster
                    .get_mut("cluster")
                    .and_then(|c| c.as_mapping_mut())
                    .and_then(|m| m.get_mut(Value::String("server".to_string())))
                    .and_then(|s| s.as_str_mut())
                {
                    *server = format!("https://localhost:{}", mapped_port);
                }
            }
        }

        serde_yaml::to_string(&kubeconfig)
            .context("Failed to serialize patched kubeconfig")
    }

    fn create_client(kubeconfig: &str) -> Result<kube::Client> {
        let config = kube::Config::from_kubeconfig(&kube::ConfigOptions {
            kubeconfig: Some(kubeconfig.to_string()),
            ..Default::default()
        })
        .context("Failed to create kube config")?;

        Ok(kube::Client::try_from(config)?)
    }

    async fn wait_for_api_ready(client: &kube::Client) -> Result<()> {
        let api: kube::Api<k8s_openapi::api::core::v1::Namespace> = kube::Api::all(client.clone());
        
        for _ in 0..60 {
            match api.list(&Default::default()).await {
                Ok(_) => return Ok(()),
                Err(e) => {
                    println!("Waiting for API server: {}", e);
                    sleep(Duration::from_secs(2)).await;
                }
            }
        }

        anyhow::bail!("API server not ready after timeout")
    }

    pub fn client(&self) -> kube::Client {
        self.client.clone()
    }

    pub fn kubeconfig(&self) -> &str {
        &self.kubeconfig
    }

    pub async fn apply_yaml(&self, yaml: &str) -> Result<()> {
        let docs: Vec<Value> = serde_yaml::from_str(yaml)
            .context("Failed to parse YAML documents")?;

        for doc in docs {
            let kind = doc
                .get("kind")
                .and_then(|k| k.as_str())
                .context("Missing kind in YAML")?;

            let name = doc
                .get("metadata")
                .and_then(|m| m.get("name"))
                .and_then(|n| n.as_str())
                .context("Missing metadata.name in YAML")?;

            let yaml_str = serde_yaml::to_string(&doc)?;
            let request = kube::api::ApiResource::from_gvk(
                &kube::api::GroupVersionKind::group_version_kind(
                    doc.get("apiVersion").and_then(|v| v.as_str()).unwrap_or("v1"),
                    kind,
                    None,
                ),
            );

            println!("Applying {} '{}'", kind, name);
        }

        Ok(())
    }
}

impl Drop for KindCluster {
    fn drop(&mut self) {
        println!("Cleaning up Kind cluster...");
    }
}
```

## Basic Test Example

```rust
// tests/integration_test.rs

mod kind_cluster;

use anyhow::Result;
use k8s_openapi::api::core::v1::{Pod, PodSpec, PodStatus};
use kube::{api::ObjectMeta, Api, ResourceExt};
use serde_json::json;
use std::time::Duration;
use tokio::time::sleep;

#[tokio::test]
async fn test_create_and_delete_pod() -> Result<()> {
    let cluster = kind_cluster::KindCluster::new().await?;
    let client = cluster.client();
    
    let pods: Api<Pod> = Api::default_namespaced(client);

    let pod: Pod = serde_json::from_value(json!({
        "apiVersion": "v1",
        "kind": "Pod",
        "metadata": {
            "name": "test-pod",
            "namespace": "default"
        },
        "spec": {
            "containers": [{
                "name": "nginx",
                "image": "nginx:1.25",
                "resources": {
                    "requests": {
                        "memory": "128Mi",
                        "cpu": "100m"
                    },
                    "limits": {
                        "memory": "256Mi",
                        "cpu": "500m"
                    }
                }
            }]
        }
    }))?;

    let created_pod = pods.create(&Default::default(), &pod).await?;
    println!("Created pod: {}", created_pod.name_any());

    let pod_ready = wait_for_pod_ready(&pods, "test-pod", Duration::from_secs(120)).await?;
    assert!(pod_ready, "Pod should be running");

    pods.delete("test-pod", &Default::default()).await?;
    println!("Deleted pod");

    Ok(())
}

async fn wait_for_pod_ready(
    pods: &Api<Pod>,
    name: &str,
    timeout: Duration,
) -> Result<bool> {
    let start = std::time::Instant::now();
    
    while start.elapsed() < timeout {
        let pod = pods.get(name).await?;
        
        if let Some(status) = pod.status.as_ref() {
            if let Some(phase) = status.phase.as_ref() {
                if phase == "Running" {
                    return Ok(true);
                }
            }
        }
        
        sleep(Duration::from_secs(2)).await;
    }
    
    Ok(false)
}
```

## Deployment Example

```rust
// tests/deployment_test.rs

mod kind_cluster;

use anyhow::Result;
use k8s_openapi::api::apps::v1::{Deployment, DeploymentSpec};
use k8s_openapi::api::core::v1::{PodSpec, PodTemplateSpec};
use kube::Api;
use serde_json::json;
use std::time::Duration;
use tokio::time::sleep;

#[tokio::test]
async fn test_create_deployment() -> Result<()> {
    let cluster = kind_cluster::KindCluster::new().await?;
    let client = cluster.client();

    let deployments: Api<Deployment> = Api::default_namespaced(client.clone());

    let deployment: Deployment = serde_json::from_value(json!({
        "apiVersion": "apps/v1",
        "kind": "Deployment",
        "metadata": {
            "name": "nginx-deployment",
            "namespace": "default"
        },
        "spec": {
            "replicas": 2,
            "selector": {
                "matchLabels": {
                    "app": "nginx"
                }
            },
            "template": {
                "metadata": {
                    "labels": {
                        "app": "nginx"
                    }
                },
                "spec": {
                    "containers": [{
                        "name": "nginx",
                        "image": "nginx:1.25",
                        "ports": [{
                            "containerPort": 80
                        }],
                        "resources": {
                            "requests": {
                                "memory": "128Mi",
                                "cpu": "100m"
                            },
                            "limits": {
                                "memory": "256Mi",
                                "cpu": "500m"
                            }
                        }
                    }]
                }
            }
        }
    }))?;

    let created = deployments.create(&Default::default(), &deployment).await?;
    println!("Created deployment: {}", created.metadata.name.unwrap_or_default());

    let ready = wait_for_deployment_ready(&deployments, "nginx-deployment", 2, Duration::from_secs(180)).await?;
    assert!(ready, "Deployment should have 2 ready replicas");

    deployments.delete("nginx-deployment", &Default::default()).await?;
    println!("Deleted deployment");

    Ok(())
}

async fn wait_for_deployment_ready(
    deployments: &Api<Deployment>,
    name: &str,
    expected_replicas: i32,
    timeout: Duration,
) -> Result<bool> {
    let start = std::time::Instant::now();

    while start.elapsed() < timeout {
        let deployment = deployments.get(name).await?;

        if let Some(status) = deployment.status.as_ref() {
            let ready = status.ready_replicas.unwrap_or(0);
            println!("Ready replicas: {}/{}", ready, expected_replicas);

            if ready == expected_replicas {
                return Ok(true);
            }
        }

        sleep(Duration::from_secs(3)).await;
    }

    Ok(false)
}
```

## Debug Helper

```rust
// tests/debug.rs

use anyhow::Result;
use k8s_openapi::api::core::v1::{Event, Pod};
use kube::Api;

pub async fn collect_debug_info(client: kube::Client, namespace: &str) -> Result<()> {
    let pods: Api<Pod> = Api::namespaced(client.clone(), namespace);
    let events: Api<Event> = Api::namespaced(client.clone(), namespace);

    println!("=== PODS ===");
    let pod_list = pods.list(&Default::default()).await?;
    for pod in pod_list.items {
        let name = pod.metadata.name.unwrap_or_default();
        let phase = pod
            .status
            .as_ref()
            .and_then(|s| s.phase.as_ref())
            .map(|p| p.as_str())
            .unwrap_or("Unknown");
        
        println!("Pod: {} - Phase: {}", name, phase);

        if phase != "Running" {
            if let Ok(logs) = pods.logs(&name, &Default::default()).await {
                println!("Logs for {}:", name);
                println!("{}", logs);
            }
        }
    }

    println!("\n=== EVENTS ===");
    let event_list = events.list(&Default::default()).await?;
    for event in event_list.items {
        let message = event.message.unwrap_or_default();
        let reason = event.reason.unwrap_or_default();
        let involved_object = event
            .involved_object
            .map(|obj| obj.name.unwrap_or_default())
            .unwrap_or_default();
        
        println!("[{}] {}: {}", reason, involved_object, message);
    }

    Ok(())
}

pub async fn describe_pod(client: kube::Client, namespace: &str, pod_name: &str) -> Result<()> {
    let pods: Api<Pod> = Api::namespaced(client, namespace);
    let pod = pods.get(pod_name).await?;

    println!("=== POD DETAILS ===");
    println!("Name: {:?}", pod.metadata.name);
    println!("Namespace: {:?}", pod.metadata.namespace);
    println!("Created: {:?}", pod.metadata.creation_timestamp);
    
    if let Some(status) = pod.status {
        println!("Phase: {:?}", status.phase);
        println!("Pod IP: {:?}", status.pod_ip);
        println!("Host IP: {:?}", status.host_ip);
        
        if let Some(container_statuses) = status.container_statuses {
            for cs in container_statuses {
                println!("Container: {:?}", cs.name);
                println!("  Ready: {:?}", cs.ready);
                println!("  Restart Count: {:?}", cs.restart_count);
                if let Some(state) = cs.state {
                    if let Some(waiting) = state.waiting {
                        println!("  Waiting: {:?} - {:?}", waiting.reason, waiting.message);
                    }
                }
            }
        }
    }

    Ok(())
}
```

## Test Configuration

```rust
// tests/common.rs

use std::env;

pub fn ensure_docker_running() -> bool {
    std::process::Command::new("docker")
        .arg("ps")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

pub fn get_test_timeout() -> std::time::Duration {
    let secs = env::var("TEST_TIMEOUT_SECS")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(180);
    std::time::Duration::from_secs(secs)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_docker_available() {
        assert!(ensure_docker_running(), "Docker must be running for tests");
    }
}
```
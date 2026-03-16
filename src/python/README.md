# Python - Kubernetes Testcontainers Examples

## Dependencies (requirements.txt)

```txt
testcontainers>=3.7.0
kubernetes>=28.1.0
pytest>=7.4.0
pytest-asyncio>=0.21.0
pyyaml>=6.0
```

## Dependencies (pyproject.toml)

```toml
[project]
name = "k8s-tests"
version = "0.1.0"
requires-python = ">=3.10"

[project.optional-dependencies]
dev = [
    "testcontainers>=3.7.0",
    "kubernetes>=28.1.0",
    "pytest>=7.4.0",
    "pytest-asyncio>=0.21.0",
    "pyyaml>=6.0",
]

[tool.pytest.ini_options]
asyncio_mode = "auto"
testpaths = ["tests"]
timeout = 300
```

## KindCluster Module

```python
# tests/kind_cluster.py

import subprocess
import time
import yaml
from typing import Optional
from testcontainers.core.container import DockerContainer
from testcontainers.core.waiting_utils import wait_for_logs
from kubernetes import client, config


KIND_IMAGE = "kindest/node:v1.29.1"
KUBECONFIG_PATH = "/etc/kubernetes/admin.conf"
INTERNAL_API_PORT = 6443


class KindCluster:
    def __init__(self, name: str = "test-cluster"):
        self.name = name
        self.container: Optional[DockerContainer] = None
        self.kubeconfig: Optional[str] = None
        self.api_client: Optional[client.ApiClient] = None
        self.core_v1: Optional[client.CoreV1Api] = None
        self.apps_v1: Optional[client.AppsV1Api] = None
        self._mapped_port: Optional[int] = None

    def start(self, timeout: int = 300) -> None:
        self.container = DockerContainer(KIND_IMAGE)
        self.container.with_exposed_ports(INTERNAL_API_PORT)
        self.container.with_privileged_mode(True)
        self.container.start()

        wait_for_logs(
            self.container,
            "Reached ap readiness hooks",
            timeout=timeout
        )

        self._mapped_port = int(
            self.container.get_exposed_port(INTERNAL_API_PORT)
        )

        self._extract_and_patch_kubeconfig()
        self._create_client()
        self._wait_for_api_ready()

    def _extract_and_patch_kubeconfig(self) -> None:
        exit_code, output = self.container.exec(f"cat {KUBECONFIG_PATH}")
        if exit_code != 0:
            raise RuntimeError(f"Failed to read kubeconfig: {output}")

        kubeconfig_dict = yaml.safe_load(output)

        for cluster in kubeconfig_dict.get("clusters", []):
            if "cluster" in cluster and "server" in cluster["cluster"]:
                cluster["cluster"]["server"] = f"https://localhost:{self._mapped_port}"

        self.kubeconfig = yaml.dump(kubeconfig_dict)

    def _create_client(self) -> None:
        kubeconfig_dict = yaml.safe_load(self.kubeconfig)
        config.load_kube_config_from_dict(kubeconfig_dict)
        self.api_client = client.ApiClient()
        self.core_v1 = client.CoreV1Api(self.api_client)
        self.apps_v1 = client.AppsV1Api(self.api_client)

    def _wait_for_api_ready(self, timeout: int = 120) -> None:
        start_time = time.time()
        while time.time() - start_time < timeout:
            try:
                self.core_v1.list_namespace()
                return
            except Exception as e:
                print(f"Waiting for API server: {e}")
                time.sleep(2)

        raise TimeoutError("API server not ready after timeout")

    @property
    def mapped_port(self) -> int:
        return self._mapped_port

    def stop(self) -> None:
        if self.container:
            self.container.stop()

    def __enter__(self):
        self.start()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.stop()
```

## Basic Test Example

```python
# tests/test_integration.py

import pytest
from .kind_cluster import KindCluster
from kubernetes import client
from kubernetes.client import V1Pod, V1ObjectMeta, V1PodSpec, V1Container, V1ResourceRequirements


@pytest.fixture(scope="module")
def kind_cluster():
    cluster = KindCluster()
    cluster.start()
    yield cluster
    cluster.stop()


def test_create_and_delete_pod(kind_cluster: KindCluster):
    pod = V1Pod(
        api_version="v1",
        kind="Pod",
        metadata=V1ObjectMeta(
            name="test-pod",
            namespace="default"
        ),
        spec=V1PodSpec(
            containers=[
                V1Container(
                    name="nginx",
                    image="nginx:1.25",
                    resources=V1ResourceRequirements(
                        requests={"memory": "128Mi", "cpu": "100m"},
                        limits={"memory": "256Mi", "cpu": "500m"}
                    )
                )
            ]
        )
    )

    created_pod = kind_cluster.core_v1.create_namespaced_pod(
        namespace="default",
        body=pod
    )
    assert created_pod.metadata.name == "test-pod"
    print(f"Created pod: {created_pod.metadata.name}")

    ready_pod = wait_for_pod_ready(
        kind_cluster.core_v1,
        "default",
        "test-pod",
        timeout=120
    )
    assert ready_pod.status.phase == "Running"
    print("Pod is running")

    kind_cluster.core_v1.delete_namespaced_pod(
        name="test-pod",
        namespace="default"
    )
    print("Deleted pod")


def wait_for_pod_ready(core_v1: client.CoreV1Api, namespace: str, name: str, timeout: int = 120):
    import time
    start_time = time.time()

    while time.time() - start_time < timeout:
        pod = core_v1.read_namespaced_pod(name=name, namespace=namespace)
        if pod.status.phase == "Running":
            return pod
        time.sleep(2)

    raise TimeoutError(f"Pod {name} not ready after {timeout} seconds")
```

## Deployment Example

```python
# tests/test_deployment.py

import pytest
from .kind_cluster import KindCluster
from kubernetes import client
from kubernetes.client import (
    V1Deployment, V1ObjectMeta, V1DeploymentSpec,
    V1PodTemplateSpec, V1PodSpec, V1Container, V1ResourceRequirements,
    V1LabelSelector, V1ContainerPort
)
import time


@pytest.fixture(scope="module")
def kind_cluster():
    cluster = KindCluster()
    cluster.start()
    yield cluster
    cluster.stop()


def test_create_deployment(kind_cluster: KindCluster):
    deployment = V1Deployment(
        api_version="apps/v1",
        kind="Deployment",
        metadata=V1ObjectMeta(
            name="nginx-deployment",
            namespace="default"
        ),
        spec=V1DeploymentSpec(
            replicas=2,
            selector=V1LabelSelector(
                match_labels={"app": "nginx"}
            ),
            template=V1PodTemplateSpec(
                metadata=V1ObjectMeta(
                    labels={"app": "nginx"}
                ),
                spec=V1PodSpec(
                    containers=[
                        V1Container(
                            name="nginx",
                            image="nginx:1.25",
                            ports=[V1ContainerPort(container_port=80)],
                            resources=V1ResourceRequirements(
                                requests={"memory": "128Mi", "cpu": "100m"},
                                limits={"memory": "256Mi", "cpu": "500m"}
                            )
                        )
                    ]
                )
            )
        )
    )

    created = kind_cluster.apps_v1.create_namespaced_deployment(
        namespace="default",
        body=deployment
    )
    print(f"Created deployment: {created.metadata.name}")

    ready_deployment = wait_for_deployment_ready(
        kind_cluster.apps_v1,
        "default",
        "nginx-deployment",
        expected_replicas=2,
        timeout=180
    )
    assert ready_deployment.status.ready_replicas == 2
    print(f"Deployment is ready with {ready_deployment.status.ready_replicas} replicas")

    kind_cluster.apps_v1.delete_namespaced_deployment(
        name="nginx-deployment",
        namespace="default"
    )
    print("Deleted deployment")


def wait_for_deployment_ready(apps_v1: client.AppsV1Api, namespace: str, name: str, expected_replicas: int, timeout: int = 180):
    start_time = time.time()

    while time.time() - start_time < timeout:
        deployment = apps_v1.read_namespaced_deployment(name=name, namespace=namespace)
        ready = deployment.status.ready_replicas or 0
        print(f"Ready replicas: {ready}/{expected_replicas}")

        if ready == expected_replicas:
            return deployment
        time.sleep(3)

    raise TimeoutError(f"Deployment {name} not ready after {timeout} seconds")
```

## Debug Helper

```python
# tests/debug.py

from kubernetes import client
from typing import Optional


def collect_debug_info(core_v1: client.CoreV1Api, namespace: str) -> None:
    print("=== PODS ===")
    pods = core_v1.list_namespaced_pod(namespace=namespace)
    for pod in pods.items:
        print(f"Pod: {pod.metadata.name} - Phase: {pod.status.phase}")

        if pod.status.phase != "Running":
            try:
                logs = core_v1.read_namespaced_pod_log(
                    name=pod.metadata.name,
                    namespace=namespace
                )
                print(f"Logs for {pod.metadata.name}:")
                print(logs)
            except Exception as e:
                print(f"Could not get logs: {e}")

    print("\n=== EVENTS ===")
    events = core_v1.list_namespaced_event(namespace=namespace)
    for event in events.items:
        print(f"[{event.type}] {event.involved_object.kind}/{event.involved_object.name}: {event.message}")


def describe_pod(core_v1: client.CoreV1Api, namespace: str, name: str) -> None:
    pod = core_v1.read_namespaced_pod(name=name, namespace=namespace)

    print("=== POD DETAILS ===")
    print(f"Name: {pod.metadata.name}")
    print(f"Namespace: {pod.metadata.namespace}")
    print(f"Phase: {pod.status.phase}")
    print(f"Pod IP: {pod.status.pod_ip}")
    print(f"Host IP: {pod.status.host_ip}")

    print("\n=== CONTAINER STATUSES ===")
    for cs in pod.status.container_statuses or []:
        print(f"Container: {cs.name}")
        print(f"  Ready: {cs.ready}")
        print(f"  Restarts: {cs.restart_count}")
        if cs.state.waiting:
            print(f"  Waiting: {cs.state.waiting.reason} - {cs.state.waiting.message}")


def get_pod_events(core_v1: client.CoreV1Api, namespace: str, pod_name: str) -> list:
    events = core_v1.list_namespaced_event(
        namespace=namespace,
        field_selector=f"involvedObject.name={pod_name}"
    )
    return events.items
```

## Conftest with Fixtures

```python
# tests/conftest.py

import pytest
from .kind_cluster import KindCluster
from .debug import collect_debug_info


@pytest.fixture(scope="session")
def kind_cluster_session():
    cluster = KindCluster(name="session-cluster")
    cluster.start()
    yield cluster
    cluster.stop()


@pytest.fixture(scope="function")
def kind_cluster(kind_cluster_session):
    yield kind_cluster_session


@pytest.fixture(scope="function")
def debug_on_failure(kind_cluster):
    yield
    if pytest.test_failed:
        collect_debug_info(kind_cluster.core_v1, "default")


@pytest.hookimpl(tryfirst=True, hookwrapper=True)
def pytest_runtest_makereport(item, call):
    outcome = yield
    report = outcome.get_result()
    setattr(item, f"rep_{call.setup}", report)
    if call.when == "call":
        pytest.test_failed = report.failed
```

## Run Script

```bash
#!/bin/bash
# scripts/run-tests.sh

set -e

echo "Checking Docker..."
docker ps > /dev/null 2>&1 || { echo "Docker not running"; exit 1; }

echo "Running tests..."
pytest tests/ -v --timeout=300

echo "Tests completed!"
```

## pytest.ini

```ini
[pytest]
testpaths = tests
python_files = test_*.py
python_classes = Test*
python_functions = test_*
asyncio_mode = auto
timeout = 300
markers =
    integration: marks tests as integration tests
    slow: marks tests as slow
```
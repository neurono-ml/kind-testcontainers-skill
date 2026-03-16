# Golang - Kubernetes Testcontainers Examples

## Dependencies (go.mod)

```go
module github.com/example/k8s-tests

go 1.21

require (
    github.com/testcontainers/testcontainers-go v0.27.0
    k8s.io/api v0.29.0
    k8s.io/apimachinery v0.29.0
    k8s.io/client-go v0.29.0
)
```

## KindCluster Package

```go
// pkg/kindcluster/cluster.go

package kindcluster

import (
    "context"
    "fmt"
    "io"
    "strings"
    "time"

    "github.com/testcontainers/testcontainers-go"
    "github.com/testcontainers/testcontainers-go/wait"
    "k8s.io/client-go/kubernetes"
    "k8s.io/client-go/rest"
    "k8s.io/client-go/tools/clientcmd"
    "k8s.io/client-go/tools/clientcmd/api"
)

const (
    KindImage       = "kindest/node:v1.29.1"
    KubeconfigPath  = "/etc/kubernetes/admin.conf"
    InternalAPIPort = 6443
)

type KindCluster struct {
    container testcontainers.Container
    client    *kubernetes.Clientset
    config    *rest.Config
    port      int
}

func NewKindCluster(ctx context.Context) (*KindCluster, error) {
    req := testcontainers.ContainerRequest{
        Image:        KindImage,
        ExposedPorts: []string{fmt.Sprintf("%d/tcp", InternalAPIPort)},
        WaitingFor:   wait.ForLog("Reached ap readiness hooks").WithStartupTimeout(5 * time.Minute),
        Privileged:   true,
    }

    container, err := testcontainers.GenericContainer(ctx, testcontainers.GenericContainerRequest{
        ContainerRequest: req,
        Started:          true,
    })
    if err != nil {
        return nil, fmt.Errorf("failed to start container: %w", err)
    }

    mappedPort, err := container.MappedPort(ctx, testcontainers.ContainerPort(InternalAPIPort))
    if err != nil {
        container.Terminate(ctx)
        return nil, fmt.Errorf("failed to get mapped port: %w", err)
    }

    kubeconfig, err := extractKubeconfig(ctx, container)
    if err != nil {
        container.Terminate(ctx)
        return nil, fmt.Errorf("failed to extract kubeconfig: %w", err)
    }

    config, err := patchKubeconfig(kubeconfig, mappedPort.Int())
    if err != nil {
        container.Terminate(ctx)
        return nil, fmt.Errorf("failed to patch kubeconfig: %w", err)
    }

    client, err := kubernetes.NewForConfig(config)
    if err != nil {
        container.Terminate(ctx)
        return nil, fmt.Errorf("failed to create client: %w", err)
    }

    if err := waitForAPIReady(ctx, client, 2*time.Minute); err != nil {
        container.Terminate(ctx)
        return nil, fmt.Errorf("API server not ready: %w", err)
    }

    return &KindCluster{
        container: container,
        client:    client,
        config:    config,
        port:      mappedPort.Int(),
    }, nil
}

func extractKubeconfig(ctx context.Context, container testcontainers.Container) ([]byte, error) {
    reader, _, err := container.Exec(ctx, []string{"cat", KubeconfigPath})
    if err != nil {
        return nil, err
    }

    output, err := io.ReadAll(reader)
    if err != nil {
        return nil, err
    }

    return output, nil
}

func patchKubeconfig(kubeconfig []byte, port int) (*rest.Config, error) {
    config, err := clientcmd.Load(kubeconfig)
    if err != nil {
        return nil, err
    }

    for _, cluster := range config.Clusters {
        cluster.Server = fmt.Sprintf("https://localhost:%d", port)
    }

    clientConfig := clientcmd.NewDefaultClientConfig(*config, &clientcmd.ConfigOverrides{})
    return clientConfig.ClientConfig()
}

func waitForAPIReady(ctx context.Context, client *kubernetes.Clientset, timeout time.Duration) error {
    ctx, cancel := context.WithTimeout(ctx, timeout)
    defer cancel()

    ticker := time.NewTicker(2 * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ctx.Done():
            return ctx.Err()
        case <-ticker.C:
            _, err := client.CoreV1().Namespaces().List(ctx, metav1.ListOptions{})
            if err == nil {
                return nil
            }
        }
    }
}

func (k *KindCluster) Client() *kubernetes.Clientset {
    return k.client
}

func (k *KindCluster) Config() *rest.Config {
    return k.config
}

func (k *KindCluster) Port() int {
    return k.port
}

func (k *KindCluster) Terminate(ctx context.Context) error {
    return k.container.Terminate(ctx)
}
```

## Basic Test Example

```go
// tests/integration_test.go

package tests

import (
    "context"
    "testing"
    "time"

    "github.com/example/k8s-tests/pkg/kindcluster"
    corev1 "k8s.io/api/core/v1"
    "k8s.io/apimachinery/pkg/api/resource"
    metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
    "k8s.io/apimachinery/pkg/util/wait"
)

func TestCreateAndDeletePod(t *testing.T) {
    ctx := context.Background()

    cluster, err := kindcluster.NewKindCluster(ctx)
    if err != nil {
        t.Fatalf("Failed to create cluster: %v", err)
    }
    defer cluster.Terminate(ctx)

    client := cluster.Client()

    pod := &corev1.Pod{
        ObjectMeta: metav1.ObjectMeta{
            Name:      "test-pod",
            Namespace: "default",
        },
        Spec: corev1.PodSpec{
            Containers: []corev1.Container{
                {
                    Name:  "nginx",
                    Image: "nginx:1.25",
                    Resources: corev1.ResourceRequirements{
                        Requests: corev1.ResourceList{
                            corev1.ResourceMemory: resource.MustParse("128Mi"),
                            corev1.ResourceCPU:    resource.MustParse("100m"),
                        },
                        Limits: corev1.ResourceList{
                            corev1.ResourceMemory: resource.MustParse("256Mi"),
                            corev1.ResourceCPU:    resource.MustParse("500m"),
                        },
                    },
                },
            },
        },
    }

    createdPod, err := client.CoreV1().Pods("default").Create(ctx, pod, metav1.CreateOptions{})
    if err != nil {
        t.Fatalf("Failed to create pod: %v", err)
    }
    t.Logf("Created pod: %s", createdPod.Name)

    err = wait.PollUntilContextTimeout(ctx, 2*time.Second, 2*time.Minute, true, func(ctx context.Context) (bool, error) {
        p, err := client.CoreV1().Pods("default").Get(ctx, "test-pod", metav1.GetOptions{})
        if err != nil {
            return false, err
        }
        return p.Status.Phase == corev1.PodRunning, nil
    })
    if err != nil {
        t.Fatalf("Pod did not become ready: %v", err)
    }
    t.Log("Pod is running")

    err = client.CoreV1().Pods("default").Delete(ctx, "test-pod", metav1.DeleteOptions{})
    if err != nil {
        t.Fatalf("Failed to delete pod: %v", err)
    }
    t.Log("Deleted pod")
}
```

## Deployment Example

```go
// tests/deployment_test.go

package tests

import (
    "context"
    "testing"
    "time"

    "github.com/example/k8s-tests/pkg/kindcluster"
    appsv1 "k8s.io/api/apps/v1"
    corev1 "k8s.io/api/core/v1"
    "k8s.io/apimachinery/pkg/api/resource"
    metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
    "k8s.io/apimachinery/pkg/util/intstr"
    "k8s.io/apimachinery/pkg/util/wait"
)

func TestCreateDeployment(t *testing.T) {
    ctx := context.Background()

    cluster, err := kindcluster.NewKindCluster(ctx)
    if err != nil {
        t.Fatalf("Failed to create cluster: %v", err)
    }
    defer cluster.Terminate(ctx)

    client := cluster.Client()

    replicas := int32(2)
    deployment := &appsv1.Deployment{
        ObjectMeta: metav1.ObjectMeta{
            Name:      "nginx-deployment",
            Namespace: "default",
        },
        Spec: appsv1.DeploymentSpec{
            Replicas: &replicas,
            Selector: &metav1.LabelSelector{
                MatchLabels: map[string]string{"app": "nginx"},
            },
            Template: corev1.PodTemplateSpec{
                ObjectMeta: metav1.ObjectMeta{
                    Labels: map[string]string{"app": "nginx"},
                },
                Spec: corev1.PodSpec{
                    Containers: []corev1.Container{
                        {
                            Name:  "nginx",
                            Image: "nginx:1.25",
                            Ports: []corev1.ContainerPort{{ContainerPort: 80}},
                            Resources: corev1.ResourceRequirements{
                                Requests: corev1.ResourceList{
                                    corev1.ResourceMemory: resource.MustParse("128Mi"),
                                    corev1.ResourceCPU:    resource.MustParse("100m"),
                                },
                                Limits: corev1.ResourceList{
                                    corev1.ResourceMemory: resource.MustParse("256Mi"),
                                    corev1.ResourceCPU:    resource.MustParse("500m"),
                                },
                            },
                        },
                    },
                },
            },
        },
    }

    created, err := client.AppsV1().Deployments("default").Create(ctx, deployment, metav1.CreateOptions{})
    if err != nil {
        t.Fatalf("Failed to create deployment: %v", err)
    }
    t.Logf("Created deployment: %s", created.Name)

    err = wait.PollUntilContextTimeout(ctx, 3*time.Second, 3*time.Minute, true, func(ctx context.Context) (bool, error) {
        d, err := client.AppsV1().Deployments("default").Get(ctx, "nginx-deployment", metav1.GetOptions{})
        if err != nil {
            return false, err
        }
        return d.Status.ReadyReplicas == replicas, nil
    })
    if err != nil {
        t.Fatalf("Deployment did not become ready: %v", err)
    }
    t.Logf("Deployment is ready with %d replicas", replicas)
}
```

## Debug Helper

```go
// pkg/debug/debug.go

package debug

import (
    "context"
    "fmt"

    corev1 "k8s.io/api/core/v1"
    metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
    "k8s.io/client-go/kubernetes"
)

func CollectDebugInfo(ctx context.Context, client *kubernetes.Clientset, namespace string) error {
    fmt.Println("=== PODS ===")
    pods, err := client.CoreV1().Pods(namespace).List(ctx, metav1.ListOptions{})
    if err != nil {
        return err
    }

    for _, pod := range pods.Items {
        fmt.Printf("Pod: %s - Phase: %s\n", pod.Name, pod.Status.Phase)

        if pod.Status.Phase != corev1.PodRunning {
            logs, err := client.CoreV1().Pods(namespace).GetLogs(pod.Name, &corev1.PodLogOptions{}).DoRaw(ctx)
            if err == nil {
                fmt.Printf("Logs for %s:\n%s\n", pod.Name, string(logs))
            }
        }
    }

    fmt.Println("\n=== EVENTS ===")
    events, err := client.CoreV1().Events(namespace).List(ctx, metav1.ListOptions{})
    if err != nil {
        return err
    }

    for _, event := range events.Items {
        fmt.Printf("[%s] %s/%s: %s\n",
            event.Type,
            event.InvolvedObject.Kind,
            event.InvolvedObject.Name,
            event.Message,
        )
    }

    return nil
}

func DescribePod(ctx context.Context, client *kubernetes.Clientset, namespace, name string) error {
    pod, err := client.CoreV1().Pods(namespace).Get(ctx, name, metav1.GetOptions{})
    if err != nil {
        return err
    }

    fmt.Println("=== POD DETAILS ===")
    fmt.Printf("Name: %s\n", pod.Name)
    fmt.Printf("Namespace: %s\n", pod.Namespace)
    fmt.Printf("Phase: %s\n", pod.Status.Phase)
    fmt.Printf("Pod IP: %s\n", pod.Status.PodIP)
    fmt.Printf("Host IP: %s\n", pod.Status.HostIP)

    fmt.Println("\n=== CONTAINER STATUSES ===")
    for _, cs := range pod.Status.ContainerStatuses {
        fmt.Printf("Container: %s\n", cs.Name)
        fmt.Printf("  Ready: %v\n", cs.Ready)
        fmt.Printf("  Restarts: %d\n", cs.RestartCount)
        if cs.State.Waiting != nil {
            fmt.Printf("  Waiting: %s - %s\n", cs.State.Waiting.Reason, cs.State.Waiting.Message)
        }
    }

    return nil
}
```

## TestMain for Global Setup

```go
// tests/main_test.go

package tests

import (
    "context"
    "log"
    "os"
    "testing"

    "github.com/example/k8s-tests/pkg/kindcluster"
)

var testCluster *kindcluster.KindCluster

func TestMain(m *testing.M) {
    ctx := context.Background()

    var err error
    testCluster, err = kindcluster.NewKindCluster(ctx)
    if err != nil {
        log.Fatalf("Failed to create cluster: %v", err)
    }

    code := m.Run()

    if err := testCluster.Terminate(ctx); err != nil {
        log.Printf("Warning: failed to terminate cluster: %v", err)
    }

    os.Exit(code)
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
go test ./... -v -timeout 10m

echo "Tests completed!"
```
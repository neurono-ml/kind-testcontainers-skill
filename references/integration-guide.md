# Integration Guide

This guide explains how to integrate the Kubernetes Testcontainers skill into your project.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Installation](#quick-installation)
3. [Integration by Language](#integration-by-language)
4. [CI/CD Configuration](#cicd-configuration)
5. [Troubleshooting](#troubleshooting)

## Prerequisites

### System
- Docker 20.10+ installed and running
- Minimum 4GB RAM available
- Access to Docker socket

### Quick Verification

```bash
# Check if Docker is running
docker ps

# Check available resources
docker info | grep -i memory
```

## Quick Installation

### Step 1: Copy AGENTS.md

```bash
# Copy the AGENTS.md file to your project root
cp kind-testcontainers-skill/AGENTS.md your-project/
```

### Step 2: Choose the Language

Navigate to your language folder in `src/<language>/` and follow the README instructions.

### Step 3: Configure CI/CD

Copy the appropriate template from `ci/templates/` to your project.

## Integration by Language

### Java

#### 1. Add Dependencies

```xml
<!-- pom.xml -->
<dependencies>
    <dependency>
        <groupId>org.testcontainers</groupId>
        <artifactId>testcontainers</artifactId>
        <version>1.19.3</version>
        <scope>test</scope>
    </dependency>
    <dependency>
        <groupId>com.dajudge.kindcontainer</groupId>
        <artifactId>kindcontainer</artifactId>
        <version>1.4.0</version>
        <scope>test</scope>
    </dependency>
    <dependency>
        <groupId>io.fabric8</groupId>
        <artifactId>kubernetes-client</artifactId>
        <version>6.9.2</version>
        <scope>test</scope>
    </dependency>
</dependencies>
```

#### 2. Create Base Test

```java
// src/test/java/AbstractKubernetesTest.java
import com.dajudge.kindcontainer.KindContainer;
import io.fabric8.kubernetes.client.*;
import org.junit.jupiter.api.*;

public abstract class AbstractKubernetesTest {
    protected static KindContainer<?> k8s;
    protected static KubernetesClient client;

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
        if (client != null) client.close();
        if (k8s != null) k8s.stop();
    }
}
```

### Rust

#### 1. Add Dependencies

```toml
# Cargo.toml
[dev-dependencies]
testcontainers = "0.15"
kube = { version = "0.87", features = ["runtime", "derive"] }
k8s-openapi = { version = "0.20", features = ["latest"] }
tokio = { version = "1", features = ["full"] }
serde_yaml = "0.9"
```

#### 2. Create Test Module

```rust
// tests/kind_cluster.rs
// See src/rust/README.md for complete implementation
```

### Python

#### 1. Add Dependencies

```txt
# requirements-dev.txt
testcontainers>=3.7.0
kubernetes>=28.1.0
pytest>=7.4.0
pytest-asyncio>=0.21.0
pyyaml>=6.0
```

#### 2. Create Fixtures

```python
# tests/conftest.py
# See src/python/README.md for complete implementation
```

### Go

#### 1. Initialize Module

```bash
go mod init your-project
go get github.com/testcontainers/testcontainers-go
go get k8s.io/client-go@v0.29.0
```

#### 2. Create Test Package

```go
// pkg/kindcluster/cluster.go
// See src/golang/README.md for complete implementation
```

### TypeScript

#### 1. Install Dependencies

```bash
npm install --save-dev testcontainers @kubernetes/client-node vitest typescript yaml
```

#### 2. Create Module

```typescript
// tests/kind-cluster.ts
// See src/typescript/README.md for complete implementation
```

## CI/CD Configuration

### GitHub Actions

```yaml
# .github/workflows/test.yml
name: Integration Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Docker Buildx
        uses: docker/setup-buildx-action@v3
      
      - name: Run Tests
        run: # your test command
        env:
          TESTCONTAINERS_RYUK_DISABLED: "false"
```

### GitLab CI

```yaml
# .gitlab-ci.yml
# See ci/templates/gitlab-ci.yml for complete template
```

### Jenkins

```groovy
// Jenkinsfile
// See ci/templates/jenkins.groovy for complete template
```

## Troubleshooting

### Container doesn't start

```bash
# Check logs
docker logs <container-id>

# Check resources
docker stats

# Check if image exists
docker images | grep kindest
```

### Connection refused

1. Check if port is mapped: `docker port <container-id>`
2. Check kubeconfig: use `getMappedPort()` instead of `6443`
3. Check if container is running: `docker ps`

### Timeout

1. Increase timeout in test
2. Check system resources
3. Check container logs

### Cleanup doesn't work

```bash
# Run cleanup script
./scripts/cleanup-testcontainers.sh --deep

# Check remaining containers
docker ps -a --filter "label=org.testcontainers=true"
```

### RYUK doesn't work

```bash
# Check if RYUK is running
docker ps | grep ryuk

# Check environment variable
echo $TESTCONTAINERS_RYUK_DISABLED

# Should be "false" or undefined
```

## Next Steps

1. Implement tests for your specific application
2. Configure CI/CD to run automatically
3. Monitor performance and adjust timeouts
4. Contribute with additional examples

## Support

- Open an issue on GitHub
- Check examples in `src/<language>/`
- Use the debug script: `./scripts/debug-kind.sh`
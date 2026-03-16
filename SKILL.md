---
name: kind-testcontainers-skill
description: Empowers AI agents to generate, validate, and maintain Kubernetes integration tests using Testcontainers and Kind (Kubernetes in Docker). Ensures tests are ephemeral, isolated, and executable in both local and CI/CD environments. Supports Java, Rust, Go, Python, TypeScript, Scala, and Ruby. Use when user needs to create or maintain Kubernetes integration tests, validate existing tests, or set up testing infrastructure for cloud-native applications.
license: MIT
metadata:
  version: "1.0.0"
  category: testing
  languages:
    - java
    - rust
    - golang
    - python
    - typescript
    - scala
    - ruby
---

# Skill: Kubernetes Testcontainers Integration Agent

## 1. Overview and Objective
This skill aims to empower AI agents to generate, validate, and maintain robust Kubernetes integration tests using **Testcontainers** and **Kind (Kubernetes in Docker)**. The skill ensures that tests are ephemeral, isolated, and executable in both local and CI/CD environments, covering multiple programming languages.

## 2. Skill Project Structure
The project should be structured as a public Skill on GitHub, containing documentation, templates, and standard configurations.

### 2.1. Required Files
- `README.md`: General skill documentation.
- `AGENTS.md`: Specific instructions for AI agents (see section 4).
- `src/`: Contains implementation examples by language.
- `ci/`: Contains pipeline templates (GitHub Actions, GitLab CI, Jenkins).
- `specs/`: Validation definitions and acceptance criteria.

## 3. Implementation Guidelines by Language
The skill should provide dependencies and specific patterns for each supported language. Below are the guidelines that AI should follow when generating code.

### 3.1. Java
- **Dependencies:** `org.testcontainers:testcontainers`, `com.dajudge.kindcontainer:kindcontainer`, `io.fabric8:kubernetes-client`.
- **Pattern:** Use `KindContainer` to start the cluster. Extract kubeconfig automatically via `getKubeconfig()`.
- **Code Block Example:**
  ```java
  KindContainer k8s = new KindContainer(DockerImageName.parse("kindest/node:v1.29.1"));
  k8s.start();
  KubernetesClient client = new KubernetesClientBuilder()
      .withConfig(new ConfigBuilder().withKubeconfig(k8s.getKubeconfig()).build())
      .build();
  ```

### 3.2. Rust
- **Dependencies:** `testcontainers`, `kube`, `tokio`, `serde_yaml`.
- **Pattern:** Implement `GenericImage` for Kind. **Critical:** AI must generate code to read kubeconfig from container, parse YAML, and replace the server `127.0.0.1:6443` with Testcontainers' `host:mapped_port`.
- **Attention:** There's no official mature `kindcontainer` module like in Java. Manual kubeconfig configuration is mandatory.

### 3.3. Golang
- **Dependencies:** `github.com/testcontainers/testcontainers-go`, `k8s.io/client-go`.
- **Pattern:** Use `testcontainers.GenericContainer` with Kind image. Use manipulated `rest.Config` to point to the port exposed by the container.
- **Validation:** Use `wait.PollImmediate` or timeout contexts to wait for resources.

### 3.4. Python
- **Dependencies:** `testcontainers`, `kubernetes`, `pytest`.
- **Pattern:** Use `DockerContainer` with Kind image. Read kubeconfig via `exec_in_container` and adjust the host.
- **Async:** Prefer async clients if available, but ensure the Docker event loop doesn't block.

### 3.5. JavaScript / TypeScript
- **Dependencies:** `testcontainers`, `@kubernetes/client-node`.
- **Pattern:** Similar to Go/Node. Manually configure `KubeConfig` with corrected endpoint (localhost:random_port).
- **Runtime:** Ensure the test doesn't finish before the container is brought down (correct await usage).

### 3.6. Scala
- **Dependencies:** Same as Java (`fabric8`, `testcontainers`).
- **Pattern:** Use Testcontainers Java interop. Ensure that `Future` or `IO` monad doesn't finalize the resource before validation.

### 3.7. Ruby
- **Dependencies:** `testcontainers-ruby`, `kubeclient`.
- **Pattern:** Configure client to point to the dynamically exposed Docker port.
- **Validation:** Use retry loops with exponential backoff for state validation.

## 4. Instructions for AGENTS.md File
The skill should create or update the `AGENTS.md` file in the target project root. This file serves as context for the AI agent.

### 4.1. Required AGENTS.md Content
- **Kind Connection:** Explicit instructions on how the agent should configure the Kubernetes client to connect to the ephemeral cluster (kubeconfig patch).
- **Lifecycle:** Cluster should start in `BeforeAll`/`Setup` and stop in `AfterAll`/`Teardown`. Never leave orphaned clusters.
- **Integration Tests:**
  - Differentiate "Tool with K8s Test" (e.g., an operator deploying resources) vs "Test in K8s Environment" (e.g., an application running inside the pod).
  - For both, the environment should be real (Kind), not mocked.
- **Ports and Networking:** Warn that port 6443 is internal and must be dynamically mapped.
- **Resource Limits:** Instruct the agent to define requests/limits on test pods to avoid OOMKills in CI.

### 4.2. AGENTS.md Automated Update
The skill should instruct the agent to update the project's `AGENTS.md` that is using the skill with the following sections:

```markdown
## How to Run Tests

### Local Execution
```bash
# Ensure Docker is running
docker ps

# Run tests
# Java
mvn test

# Rust
cargo test --test integration

# Go
go test ./... -v

# Python
pytest tests/integration/

# Node/TypeScript
npm run test:integration
```

### CI/CD Execution
Tests are automatically executed on each push/PR. Ensure:
1. The runner has access to Docker Socket
2. There is sufficient memory (minimum 4GB RAM)
3. Privileged mode is enabled if necessary

### Debug Commands
```bash
# List active Kind containers
docker ps | grep kind

# Clean up orphaned containers
docker rm -f $(docker ps -q --filter "label=org.testcontainers=true")

# View logs from last failed test
docker logs <container-id>
```
```

### 4.3. AGENTS.md Section Example
```markdown
## Kubernetes Testing with Testcontainers
To run integration tests:
1. The agent must start a Kind container via Testcontainers.
2. The agent must extract kubeconfig and fix the endpoint to `localhost:<PORT>`.
3. Do not use fixed `sleep`. Use wait conditions (e.g., Pod Running, Deployment Available).
4. In case of failure, collect pod logs and namespace events before tear down.
```

## 5. RYUK Management and Container Cleanup

### 5.1. RYUK Inclusion
RYUK is a Testcontainers service that ensures automatic container cleanup. The skill should instruct:

- **Default Activation:** RYUK should be **enabled by default** in all development and CI/CD environments.
- **Environment Variable:** `TESTCONTAINERS_RYUK_DISABLED=false` (or not set, since default is enabled).
- **RYUK Container:** The `testcontainers-ryuk` container should be started automatically on the first test execution.

### 5.2. Cleanup at End of Tests
The skill should ensure that ALL containers created during tests are removed from the system:

```markdown
## Container Cleanup Policy

### Scenario 1: Normal Test Execution
- At the end of the test suite, ALL Kind containers must be removed.
- ALL images pulled exclusively for tests must be removed (if not used in production).
- RYUK should perform this cleanup automatically via timeout or when the test process finishes.

### Scenario 2: Loop Execution (Recurrent Validation)
- If tests are running in loop (e.g., active development with `cargo watch` or `mvn test -Dtest=*#repeat`):
  - Containers can be reused between iterations for performance.
  - **IMPORTANT:** At the end of the loop (when the developer stops execution), ALL containers must be cleaned.
  - The agent must detect when the loop is interrupted and trigger cleanup.

### Scenario 3: Test Success
- In case of **SUCCESS** of all tests:
  - Remove all containers created.
  - Remove temporary images (tagged as `test-` or similar).
  - Release mapped ports.
  - Confirm via `docker ps` that there are no orphaned containers.

### Scenario 4: Test Failure
- In case of **FAILURE**:
  - **Do NOT immediately** remove containers to allow for debugging.
  - Generate a report with container IDs for manual inspection.
  - Provide an explicit cleanup command for the developer to run after debugging.
  - Example: `docker rm -f $(docker ps -q --filter "label=test-session=abc123")`
```

### 5.3. Cleanup Implementation by Language

#### Rust
```rust
// Implement Drop trait to ensure cleanup
impl Drop for KindCluster {
    fn drop(&mut self) {
        // Force removal via Docker API if RYUK fails
        self.container.stop().expect("Failed to stop container");
        self.container.remove().expect("Failed to remove container");
    }
}
```

#### Java
```java
@AfterAll
static void cleanup() {
    if (k8s != null) {
        k8s.stop(); // KindContainer integrates with RYUK
    }
    // Explicit image cleanup if needed
    DockerClientFactory.instance().client().removeImageCmd("kindest/node")
        .withForce(true).exec();
}
```

#### Golang
```go
func TestMain(m *testing.M) {
    code := m.Run()
    // Cleanup after all tests
    if err := container.Terminate(context.Background()); err != nil {
        log.Printf("Warning: failed to terminate container: %v", err)
    }
    os.Exit(code)
}
```

### 5.4. Global Cleanup Command
The skill should provide a cleanup script that can be executed manually:

```bash
#!/bin/bash
# cleanup-testcontainers.sh

echo "Stopping Ryuk..."
docker rm -f $(docker ps -q --filter "name=testcontainers-ryuk") 2>/dev/null

echo "Removing Kind containers..."
docker rm -f $(docker ps -q --filter "label=org.testcontainers=true") 2>/dev/null

echo "Removing temporary images..."
docker images --filter "reference=*test*" -q | xargs -r docker rmi -f

echo "Cleanup complete!"
```

## 6. CI/CD Support and Configuration
The skill should detect the project's CI/CD provider and suggest or apply the necessary configurations to support Testcontainers + Kind (Docker-in-Docker).

### 6.1. GitHub Actions
- Add step to setup Docker.
- Ensure content permissions if needed.
- Job Example:
  ```yaml
  jobs:
    test:
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@v3
        - name: Set up Docker Buildx
          uses: docker/setup-buildx-action@v2
        - name: Run Tests
          run: cargo test # or mvn test, go test, etc.
          env:
            TESTCONTAINERS_RYUK_DISABLED: "false"
            TESTCONTAINERS_RYUK_PORT: "8080"
  ```

### 6.2. GitLab CI
- Use `docker:dind` service.
- Set `DOCKER_HOST` and `DOCKER_TLS_CERTDIR` variables.
- Ensure the job runs in privileged mode if Kind requires nested containers.

### 6.3. Jenkins
- Use Docker agents with socket mount (`-v /var/run/docker.sock:/var/run/docker.sock`).
- Ensure the Jenkins user has Docker group permissions.

### 6.4. ArgoCD
- Although ArgoCD is for deployment, the skill should check if there are validation pipelines (e.g., Argo Workflows) that need Docker Socket access to run integration tests before sync.

### 6.5. General CI/CD Rules
- **Docker Socket:** The environment MUST have access to the Docker socket.
- **Memory:** Allocate minimum 4GB RAM for the CI runner, as Kind clusters consume significant resources.
- **Privileged:** In some cases, the test container needs to run as `privileged: true` to allow Kind to spin up its own containers (nested containers).
- **Post-Job Cleanup:** Always add a step for cleanup even if the job fails.

## 7. Validation and Acceptance Criteria
No test will be considered valid if it doesn't meet the following criteria. The AI should validate the generated code against these rules.

### 7.1. Environment Validation
- [ ] Does the test start a Docker container?
- [ ] Does the container use a valid Kubernetes image (Kind/K3s)?
- [ ] Is the Kubernetes client configured to point to the container, not a remote cluster?

### 7.2. Execution Validation
- [ ] Does the test not use fixed `Thread.sleep` or `time.Sleep` to wait for resources?
- [ ] Does the test use wait conditions (e.g., `waitUntilReady`, `awaitCondition`)?
- [ ] Does the test fail if the resource doesn't come up within a reasonable timeout (e.g., 2 minutes)?

### 7.3. Cleanup Validation
- [ ] Is the container brought down after the test (via `defer`, `@AfterAll`, `Drop` trait)?
- [ ] Is RYUK enabled and working?
- [ ] Are there no leaking containers listed via `docker ps` after the suite execution?
- [ ] In case of success, were temporary images removed?

### 7.4. Error Report
If the test fails, the skill should instruct the agent to generate a report containing:
1. **Kind Container Logs:** Standard output of the cluster container.
2. **Application Logs:** Logs of pods deployed during the test.
3. **Kubernetes Events:** Output of `kubectl get events` (or equivalent via API) in the test namespace.
4. **Generated Configuration:** The kubeconfig actually used (sanitized).
5. **Suggested Solution:** Based on the error (e.g., CrashLoopBackOff, ImagePullBackOff, Connection Refused), suggest corrections (e.g., check image name, verify port mapping, check RAM resources).

## 8. Skill Usage Examples

### 8.1. Case 1: Tool Integration Test with Kubernetes
**Description:** Test that your library/tool correctly interacts with the Kubernetes API (e.g., creating CRDs, operating resources, validating webhooks).

**Scenario:** You are developing a Kubernetes Operator in Rust and need to test that it reconciles resources correctly.

```markdown
## Example: Kubernetes Operator Test (Rust)

### Objective
Validate that the operator detects changes in CustomResources and performs correct reconciliation.

### Setup
```rust
#[tokio::test]
async fn test_operator_reconciliation() {
    // 1. Start Kind cluster
    let cluster = KindCluster::new("v1.29.1").await;
    
    // 2. Install your library's CRDs
    cluster.apply_crd("config/crd/myresource.yaml").await;
    
    // 3. Start the operator (as process or thread)
    let operator = Operator::start(cluster.kubeconfig()).await;
    
    // 4. Create test resource
    let resource = MyResourceBuilder::new()
        .name("test-resource")
        .spec( /* ... */ )
        .build();
    cluster.create_resource(resource).await;
    
    // 5. Wait for reconciliation
    let status = cluster.wait_for_condition(
        "test-resource",
        |r| r.status.reconciled == true,
        Duration::from_secs(60)
    ).await;
    
    // 6. Validate
    assert!(status.reconciled);
    assert_eq!(status.observed_generation, 1);
    
    // 7. Automatic cleanup via Drop
}
```

### Expected Validations
- CRD was registered in the cluster
- Operator received the creation event
- Resource status was updated
- No errors in operator logs

### Possible Errors and Solutions
| Error | Probable Cause | Solution |
|------|---------------|---------|
| CRD not found | CRD not applied before test | Add apply_crd step before creating resources |
| Connection refused | Kubeconfig with wrong endpoint | Check localhost:port patch |
| Timeout waiting | Operator not running | Verify operator was started in test |
```

### 8.2. Case 2: Test in Kubernetes Environment
**Description:** Test that your application/service runs correctly INSIDE Kubernetes, interacting with other services/pods.

**Scenario:** You are developing an API that depends on a database and a cache service, all running as pods in the same cluster.

```markdown
## Example: Application in Cluster Test (Java)

### Objective
Validate that the application can connect to dependent services when deployed in Kubernetes.

### Setup
```java
@Test
void test_application_with_dependencies() {
    // 1. Start Kind cluster
    KindContainer k8s = new KindContainer(DockerImageName.parse("kindest/node:v1.29.1"));
    k8s.start();
    
    // 2. Deploy dependencies (Postgres, Redis)
    k8s.apply("deps/postgres-deployment.yaml");
    k8s.apply("deps/redis-deployment.yaml");
    
    // 3. Wait for dependencies to be ready
    waitForDeployment("postgres", Duration.ofMinutes(2));
    waitForDeployment("redis", Duration.ofMinutes(2));
    
    // 4. Deploy your application
    k8s.apply("app/myapp-deployment.yaml");
    waitForDeployment("myapp", Duration.ofMinutes(2));
    
    // 5. Run integration test
    String response = httpClient.get("http://localhost:" + k8s.getMappedPort(8080) + "/health");
    
    // 6. Validate
    assertEquals(200, response.getStatusCode());
    assertTrue(response.getBody().contains("postgres: connected"));
    assertTrue(response.getBody().contains("redis: connected"));
    
    // 7. Cleanup
    k8s.stop();
}
```

### Expected Validations
- All pods are in Running state
- Services are responding on correct ports
- Application can resolve internal K8s DNS
- Health checks pass

### Possible Errors and Solutions
| Error | Probable Cause | Solution |
|------|---------------|---------|
| ImagePullBackOff | Image doesn't exist or private registry | Use public images or configure imagePullSecrets |
| CrashLoopBackOff | Application fails to start | Check pod logs, validate configmaps/secrets |
| DNS resolution failed | CoreDNS not working | Check kube-system pods, restart CoreDNS |
| Connection timeout | Network policies blocking | Check for restrictive NetworkPolicies |
```

### 8.3. Positive Example (Success Case)
**Context:** Test of a Kubernetes operator in Rust.
**AI Action:**
1. Generates `KindImage` struct implementing `Image` trait.
2. Starts container, maps port 6443.
3. Reads `/etc/kubernetes/admin.conf`, replaces `server` with `localhost:<PORT>`.
4. Creates `kube::Client`.
5. Applies CRD and Instance.
6. Waits for `Status.Conditions` where `Type=Ready` and `Status=True`.
7. Asserts success.
8. Drops container.

### 8.4. Negative Example (Common Failure Case)
**Context:** Test in Java trying to connect to fixed `localhost:6443`.
**Error:** `ConnectionRefused`.
**Skill Correction:** AI should identify that Testcontainers maps to a random port. Should instruct to use `container.getMappedPort(6443)` and update kubeconfig dynamically.

### 8.5. Negative Example (Weak Validation)
**Context:** Test in Python with `time.sleep(10)`.
**Error:** Flaky test. Sometimes 10s is not enough.
**Skill Correction:** Replace with retry loop checking resource status via API until maximum timeout.

## 9. Skill Maintenance Instructions
- **Image Updates:** Keep standard Kind versions updated (e.g., track Kubernetes LTS versions).
- **Security:** Don't commit real kubeconfigs in examples. Use placeholders.
- **Compatibility:** Test the skill periodically on Linux, macOS, and Windows (where Docker socket may vary).
- **RYUK Version:** Keep RYUK version updated with Testcontainers version.

## 10. Final Checklist for Agent
Before finalizing test code generation, the agent should mentally answer:

1. [ ] Is the cluster ephemeral?
2. [ ] Is the kubeconfig corrected for dynamic port?
3. [ ] Are there appropriate wait conditions?
4. [ ] Is CI/CD configured to support Docker-in-Docker?
5. [ ] Will error logs be useful for debugging?
6. [ ] Is RYUK enabled for automatic cleanup?
7. [ ] In case of success, will all containers be removed?
8. [ ] Has the project's AGENTS.md been updated with execution instructions?
9. [ ] Do the examples cover the correct test type (tool integration VS test in environment)?
10. [ ] Are there debugging instructions for when tests fail?

If all answers are "Yes", the code can be presented to the user.

## 11. Test Execution Report Template
The skill should generate a standardized report after test execution:

```markdown
## Kubernetes Test Execution Report

### Summary
- **Date:** 2024-01-15 14:30:00 UTC
- **Language:** Rust
- **Total Tests:** 15
- **Success:** 14
- **Failure:** 1

### Environment
- **Kind Version:** v1.29.1
- **Testcontainers Version:** 0.15.0
- **RYUK:** Enabled
- **Docker Host:** Linux (Ubuntu 22.04)

### Failed Tests
| Test | Error | Container ID | Logs |
|-------|------|--------------|------|
| test_operator_crud | Timeout waiting for condition | abc123def | [See full logs] |

### Created Containers
| Name | Image | Port | Status |
|------|--------|-------|--------|
| kind-control-plane | kindest/node:v1.29.1 | 32768 | Removed |
| testcontainers-ryuk | testcontainers/ryuk:0.5.1 | 8080 | Removed |

### Cleanup
- [x] Containers removed
- [x] Temporary images removed
- [x] Ports released

### Next Steps
1. Investigate timeout in test `test_operator_crud`
2. Check if there are insufficient resource limits
3. Increase wait condition timeout if necessary
```

## 12. Useful Debug Commands

```bash
# View all Testcontainers
docker ps --filter "label=org.testcontainers=true"

# View logs from specific container
docker logs <container-id>

# Inspect container network
docker inspect <container-id> | jq .[0].NetworkSettings

# Check mapped ports
docker port <container-id>

# Force cleanup (use with caution)
docker rm -f $(docker ps -aq --filter "label=org.testcontainers=true")

# Check if RYUK is running
docker ps | grep ryuk
```

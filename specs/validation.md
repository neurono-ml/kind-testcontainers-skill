# Validation Criteria

This document defines the criteria that must be validated to ensure Kubernetes integration tests are correctly implemented.

## 1. Environment Validation

### 1.1. Docker Container
- [ ] The test starts a Docker container
- [ ] The container uses a valid Kubernetes image (Kind/K3s)
- [ ] The container is configured to expose the API port (6443)
- [ ] Privileged mode is enabled when necessary

### 1.2. Kubernetes Client
- [ ] The Kubernetes client is configured correctly
- [ ] The client points to the local container, not a remote cluster
- [ ] Credentials/kubeconfig are properly configured

### 1.3. Connectivity
- [ ] Port 6443 is dynamically mapped
- [ ] The kubeconfig uses `localhost` with the mapped port
- [ ] There are no hardcoded ports in the code

## 2. Execution Validation

### 2.1. Wait Conditions
- [ ] There is no use of fixed `sleep()`
- [ ] Wait conditions are implemented with timeout
- [ ] The test fails if the resource doesn't become ready within the timeout

### 2.2. Timeout Configuration
- [ ] Cluster initialization timeout: 5 minutes
- [ ] Pod timeout: 2 minutes
- [ ] Deployment timeout: 3 minutes
- [ ] Overall test timeout: 10 minutes

### 2.3. Resource Management
- [ ] Resource limits are defined
- [ ] Requests are defined
- [ ] Minimum values: 128Mi RAM, 100m CPU

## 3. Lifecycle Validation

### 3.1. Setup
- [ ] Cluster is created at the beginning of the test/suite
- [ ] Client is configured after the cluster is ready
- [ ] API server is accessible before proceeding

### 3.2. Teardown
- [ ] Cluster is destroyed at the end of the test/suite
- [ ] Client is properly closed
- [ ] Cleanup is guaranteed even in case of failure

### 3.3. Isolation
- [ ] Each test uses isolated namespace or cleanup between tests
- [ ] There are no dependencies between tests
- [ ] Resources are unique per execution

## 4. Log and Debug Validation

### 4.1. Log Collection
- [ ] Container logs are collected in case of failure
- [ ] Pod logs are collected
- [ ] Kubernetes events are collected

### 4.2. Debug Information
- [ ] Container name is logged
- [ ] Resource status is verified
- [ ] Error messages are descriptive

## 5. RYUK Validation

### 5.1. Configuration
- [ ] RYUK is enabled (`TESTCONTAINERS_RYUK_DISABLED=false`)
- [ ] RYUK port is configured

### 5.2. Operation
- [ ] RYUK container is started
- [ ] Containers are cleaned up after tests
- [ ] There are no orphaned containers after execution

## 6. Validation Checklist by Language

### Java
```java
// Validate:
// - KindContainer is being used
// - getKubeconfig() is called
// - @AfterAll cleans up resources
// - waitUntilCondition is used
```

### Rust
```rust
// Validate:
// - GenericImage for Kind
// - kubeconfig is read and patched
// - Drop trait implements cleanup
// - wait_for_condition is used
```

### Golang
```go
// Validate:
// - GenericContainer for Kind
// - MappedPort is obtained
// - defer container.Terminate()
// - wait.PollUntilContextTimeout
```

### Python
```python
# Validate:
# - DockerContainer for Kind
# - exec to read kubeconfig
# - __exit__ for cleanup
# - loops with timeout
```

### TypeScript
```typescript
// Validate:
// - GenericContainer for Kind
// - getMappedPort()
// - afterAll for cleanup
// - wait loops with timeout
```

## 7. Validation Report

```markdown
## Validation Report

### Environment
- Docker Container: [PASS/FAIL]
- Kind Image: [PASS/FAIL]
- Mapped Port: [PASS/FAIL]

### Execution
- Wait Conditions: [PASS/FAIL]
- Timeouts: [PASS/FAIL]
- Resources: [PASS/FAIL]

### Lifecycle
- Setup: [PASS/FAIL]
- Teardown: [PASS/FAIL]
- Isolation: [PASS/FAIL]

### Debug
- Logs: [PASS/FAIL]
- Events: [PASS/FAIL]

### RYUK
- Enabled: [PASS/FAIL]
- Cleanup: [PASS/FAIL]

### Final Result: [PASS/FAIL]
```

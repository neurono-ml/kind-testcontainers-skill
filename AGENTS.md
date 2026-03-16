# AGENTS.md - Instructions for AI Agents

This file contains specific instructions for AI agents working on this project.

## Kubernetes Testing with Testcontainers

### Fundamental Principles

1. **Ephemeral Clusters**: Every cluster must be created in setup and destroyed in teardown
2. **No Hardcoded Ports**: Port 6443 is internal; use `getMappedPort()` or equivalent
3. **Wait Conditions**: Never use fixed `sleep()`; use wait conditions
4. **RYUK Enabled**: Keep RYUK enabled for automatic cleanup

### Connection with Kind

```markdown
The agent must:
1. Start Kind container via Testcontainers
2. Extract kubeconfig from container
3. Fix the endpoint from `127.0.0.1:6443` to `localhost:<MAPPED_PORT>`
4. Configure Kubernetes client with the fixed kubeconfig
```

### Test Lifecycle

| Phase | Action | Responsibility |
|-------|--------|----------------|
| Setup | Start Kind cluster | `BeforeAll` / `setUp` |
| Test | Execute validations | Test method |
| Teardown | Destroy cluster | `AfterAll` / `tearDown` |

### Test Types

#### Tool with Kubernetes Test
Test that your library/operator interacts correctly with the Kubernetes API.

#### Test in Kubernetes Environment
Test that your application runs correctly INSIDE the cluster.

### Resource Limits

Always define in test manifests:
```yaml
resources:
  requests:
    memory: "128Mi"
    cpu: "100m"
  limits:
    memory: "256Mi"
    cpu: "500m"
```

---

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

# View all Testcontainers
docker ps --filter "label=org.testcontainers=true"

# Inspect container network
docker inspect <container-id> | jq .[0].NetworkSettings

# Check mapped ports
docker port <container-id>

# Check if RYUK is running
docker ps | grep ryuk
```

---

## Validation Checklist

Before considering a test complete, verify:

- [ ] Cluster is ephemedral (starts and stops automatically)
- [ ] Kubeconfig is corrected for dynamic port
- [ ] Wait conditions implemented (no fixed sleep)
- [ ] RYUK enabled
- [ ] Resource limits defined
- [ ] Logs collected in case of failure
- [ ] Cleanup guaranteed even with failure

---

## In Case of Failure

Collect debug information:

1. **Kind Container Logs**
   ```bash
   docker logs <container-id>
   ```

2. **Pod Logs**
   ```bash
   kubectl logs -n <namespace> <pod-name>
   ```

3. **Kubernetes Events**
   ```bash
   kubectl get events -n <namespace> --sort-by='.lastTimestamp'
   ```

4. **Describe problematic resources**
   ```bash
   kubectl describe pod <pod-name> -n <namespace>
   ```

---

## Environment Variables

| Variable | Default Value | Description |
|----------|-------------|-------------|
| `TESTCONTAINERS_RYUK_DISABLED` | `false` | Keep `false` for automatic cleanup |
| `TESTCONTAINERS_RYUK_PORT` | `8080` | RYUK port |
| `DOCKER_HOST` | `unix:///var/run/docker.sock` | Docker socket |

---

## Common Errors and Solutions

| Error | Cause | Solution |
|-------|-------|----------|
| `ConnectionRefused` | Fixed port instead of mapped | Use `getMappedPort(6443)` |
| `CrashLoopBackOff` | Insufficient resources | Increase memory limits |
| `ImagePullBackOff` | Image not found | Check name/registry |
| `Timeout` | Fixed sleep insufficient | Use wait conditions |
| `DNS resolution failed` | CoreDNS not ready | Wait for CoreDNS to be healthy |

---

## Language Rule for Code

**All code must be written in English**, including:
- Variable names
- Function names
- Class names
- Method names
- Comments
- Documentation
- Error messages
- Log messages

Even though we interact in Brazilian Portuguese, all code implementations should follow English programming conventions. This ensures consistency with international coding standards and makes the code more accessible to the global development community.

Examples of good practice:
```python
# Good: English comments and variable names
def create_deployment(namespace: str, replicas: int) -> Deployment:
    """Create a Kubernetes deployment with specified replicas."""
    
# Bad: Portuguese in code
def criar_deployment(namespace: str, replicas: int) -> Deployment:
    """Cria um deployment Kubernetes com réplicas especificadas."""
```

This rule applies to all source code files, examples, and implementations generated for this skill.

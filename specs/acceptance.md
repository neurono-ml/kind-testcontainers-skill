# Acceptance Criteria

This document defines the acceptance criteria that must be met for a Kubernetes integration test to be considered valid.

## 1. Functional Criteria

### 1.1. Ephemeral Cluster
**Given** an integration test is being executed  
**When** the test starts  
**Then** an ephemeral Kubernetes cluster must be created  
**And** the cluster must be destroyed at the end of the test

**Acceptance Criteria:**
- Cluster is created automatically
- Cluster does not persist after the test
- Multiple executions do not cause conflicts

### 1.2. Dynamic Connection
**Given** a Kind cluster is running  
**When** the Kubernetes client is configured  
**Then** the dynamically mapped port must be used  
**And** no hardcoded port should exist

**Acceptance Criteria:**
- Port 6443 is mapped to a random port
- Kubeconfig uses localhost:random_port
- Code does not contain hardcoded `:6443`

### 1.3. Wait Conditions
**Given** a Kubernetes resource is being created  
**When** the test waits for the resource  
**Then** wait conditions must be used  
**And** fixed sleep should not be used

**Acceptance Criteria:**
- No calls to `sleep()`, `Thread.sleep()`, `time.Sleep()`
- Wait conditions with timeout are implemented
- Timeout is configurable

## 2. Quality Criteria

### 2.1. Non-Flaky Tests
**Given** tests are executed multiple times  
**When** the environment is stable  
**Then** tests should pass consistently

**Acceptance Criteria:**
- 10 consecutive executions pass
- Timing variations do not cause failures
- External resources do not cause instability

### 2.2. Test Isolation
**Given** multiple tests exist  
**When** tests are run in parallel or sequence  
**Then** there should be no interference between tests

**Acceptance Criteria:**
- Unique namespaces per test
- Unique resource names
- State is not shared

### 2.3. Resource Cleanup
**Given** a test creates resources  
**When** the test ends (success or failure)  
**Then** all resources must be cleaned up

**Acceptance Criteria:**
- Containers are removed
- Temporary images are removed
- Ports are released
- `docker ps` does not show orphaned containers

## 3. Performance Criteria

### 3.1. Startup Time
**Acceptance Criteria:**
- Cluster starts in less than 5 minutes
- API server responds in less than 2 minutes after container starts
- Complete test runs in less than 10 minutes

### 3.2. Resource Usage
**Acceptance Criteria:**
- Container uses less than 4GB RAM
- CPU usage is reasonable during execution
- Disk is cleaned after execution

## 4. Debug Criteria

### 4.1. Logs on Failure
**Given** a test fails  
**When** the failure is reported  
**Then** relevant logs must be available

**Acceptance Criteria:**
- Kind container logs are collected
- Pod logs are collected
- Namespace events are collected
- Error is clearly identified

### 4.2. Context Information
**Acceptance Criteria:**
- Container ID is logged
- Mapped port is logged
- Test namespace is logged
- Execution time is measured

## 5. CI/CD Criteria

### 5.1. CI Execution
**Given** the test is in a CI pipeline  
**When** the pipeline is executed  
**Then** the test should work correctly

**Acceptance Criteria:**
- Docker socket is accessible
- Privileged mode is enabled (if needed)
- Sufficient memory is available (minimum 4GB)
- Job timeout is appropriate

### 5.2. Cleanup in CI
**Given** the pipeline ends (success or failure)  
**When** execution is finalized  
**Then** cleanup must be executed

**Acceptance Criteria:**
- Cleanup step always executes
- Containers are removed
- Runner is clean for next execution

## 6. Criteria by Test Type

### 6.1. Tool with Kubernetes Test
**Context:** Testing that your library/operator works with K8s

**Acceptance Criteria:**
- CRDs are applied correctly
- Reconciliation works
- Status are updated
- Webhooks respond (if applicable)

### 6.2. Test in Kubernetes Environment
**Context:** Testing that your application runs inside K8s

**Acceptance Criteria:**
- Deployment is created
- Pods go to Running
- Services are accessible
- Internal DNS works
- Health checks pass

## 7. Acceptance Matrix

| Criterion | Priority | Required |
|-----------|----------|----------|
| Ephemeral cluster | High | Yes |
| Dynamic port | High | Yes |
| Wait conditions | High | Yes |
| RYUK enabled | High | Yes |
| Cleanup guaranteed | High | Yes |
| Logs on failure | Medium | Yes |
| Test isolation | Medium | Yes |
| Resource limits | Medium | Yes |
| CI/CD compatible | Medium | Yes |
| Performance | Low | No |

## 8. Acceptance Signature

```markdown
## Final Acceptance

- [ ] All functional criteria have been met
- [ ] All quality criteria have been met
- [ ] All debug criteria have been met
- [ ] Test passes in CI
- [ ] Cleanup is verified

**Approved by:** ________________
**Date:** ________________
**Version:** ________________
```
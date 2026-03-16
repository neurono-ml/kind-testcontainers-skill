# TypeScript/JavaScript - Kubernetes Testcontainers Examples

## Dependencies (package.json)

```json
{
  "name": "k8s-tests",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "test": "vitest run",
    "test:watch": "vitest",
    "test:integration": "vitest run --config vitest.integration.ts"
  },
  "devDependencies": {
    "testcontainers": "^10.0.0",
    "@kubernetes/client-node": "^0.20.0",
    "vitest": "^1.0.0",
    "typescript": "^5.3.0",
    "@types/node": "^20.10.0",
    "yaml": "^2.3.0"
  }
}
```

## KindCluster Module

```typescript
// tests/kind-cluster.ts

import { GenericContainer, StartedTestContainer, Wait } from 'testcontainers';
import * as k8s from '@kubernetes/client-node';
import * as yaml from 'yaml';

const KIND_IMAGE = 'kindest/node:v1.29.1';
const KUBECONFIG_PATH = '/etc/kubernetes/admin.conf';
const INTERNAL_API_PORT = 6443;

export class KindCluster {
  private container: StartedTestContainer | null = null;
  private kc: k8s.KubeConfig | null = null;
  private coreV1Api: k8s.CoreV1Api | null = null;
  private appsV1Api: k8s.AppsV1Api | null = null;
  private mappedPort: number = 0;

  async start(timeout: number = 300000): Promise<void> {
    this.container = await new GenericContainer(KIND_IMAGE)
      .withExposedPorts({ container: INTERNAL_API_PORT, host: 0 })
      .withPrivilegedMode()
      .withWaitStrategy(Wait.forLogMessage('Reached ap readiness hooks', 1))
      .withStartupTimeout(timeout)
      .start();

    this.mappedPort = this.container.getMappedPort(INTERNAL_API_PORT);
    
    await this.extractAndPatchKubeconfig();
    await this.createClient();
    await this.waitForApiReady();
  }

  private async extractAndPatchKubeconfig(): Promise<void> {
    if (!this.container) throw new Error('Container not started');

    const result = await this.container.exec(['cat', KUBECONFIG_PATH]);
    if (result.exitCode !== 0) {
      throw new Error(`Failed to read kubeconfig: ${result.output}`);
    }

    const kubeconfigDoc = yaml.parse(result.output);

    for (const cluster of kubeconfigDoc.clusters || []) {
      if (cluster.cluster?.server) {
        cluster.cluster.server = `https://localhost:${this.mappedPort}`;
      }
    }

    this.kc = new k8s.KubeConfig();
    this.kc.loadFromOptions(kubeconfigDoc);
  }

  private async createClient(): Promise<void> {
    if (!this.kc) throw new Error('KubeConfig not loaded');

    this.coreV1Api = this.kc.makeApiClient(k8s.CoreV1Api);
    this.appsV1Api = this.kc.makeApiClient(k8s.AppsV1Api);
  }

  private async waitForApiReady(timeout: number = 120000): Promise<void> {
    if (!this.coreV1Api) throw new Error('Client not created');

    const startTime = Date.now();
    
    while (Date.now() - startTime < timeout) {
      try {
        await this.coreV1Api.listNamespace();
        return;
      } catch (e) {
        console.log(`Waiting for API server: ${e}`);
        await this.sleep(2000);
      }
    }

    throw new Error('API server not ready after timeout');
  }

  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  get CoreV1Api(): k8s.CoreV1Api {
    if (!this.coreV1Api) throw new Error('API not initialized');
    return this.coreV1Api;
  }

  get AppsV1Api(): k8s.AppsV1Api {
    if (!this.appsV1Api) throw new Error('API not initialized');
    return this.appsV1Api;
  }

  get MappedPort(): number {
    return this.mappedPort;
  }

  get KubeConfig(): k8s.KubeConfig {
    if (!this.kc) throw new Error('KubeConfig not loaded');
    return this.kc;
  }

  async stop(): Promise<void> {
    if (this.container) {
      await this.container.stop();
      this.container = null;
    }
  }
}
```

## Basic Test Example

```typescript
// tests/integration.test.ts

import { describe, it, beforeAll, afterAll, expect } from 'vitest';
import { KindCluster } from './kind-cluster';
import { V1Pod, V1ObjectMeta, V1PodSpec, V1Container, V1ResourceRequirements } from '@kubernetes/client-node';

describe('Kubernetes Integration Tests', () => {
  let cluster: KindCluster;

  beforeAll(async () => {
    cluster = new KindCluster();
    await cluster.start();
  }, 300000);

  afterAll(async () => {
    await cluster.stop();
  });

  it('should create and delete a pod', async () => {
    const pod: V1Pod = {
      apiVersion: 'v1',
      kind: 'Pod',
      metadata: {
        name: 'test-pod',
        namespace: 'default',
      } as V1ObjectMeta,
      spec: {
        containers: [
          {
            name: 'nginx',
            image: 'nginx:1.25',
            resources: {
              requests: {
                memory: '128Mi',
                cpu: '100m',
              },
              limits: {
                memory: '256Mi',
                cpu: '500m',
              },
            } as V1ResourceRequirements,
          } as V1Container,
        ],
      } as V1PodSpec,
    };

    const createdPod = await cluster.CoreV1Api.createNamespacedPod({
      namespace: 'default',
      body: pod,
    });

    expect(createdPod.body.metadata?.name).toBe('test-pod');
    console.log(`Created pod: ${createdPod.body.metadata?.name}`);

    const readyPod = await waitForPodReady(
      cluster.CoreV1Api,
      'default',
      'test-pod',
      120000
    );

    expect(readyPod.status?.phase).toBe('Running');
    console.log('Pod is running');

    await cluster.CoreV1Api.deleteNamespacedPod({
      name: 'test-pod',
      namespace: 'default',
    });
    console.log('Deleted pod');
  });
});

async function waitForPodReady(
  api: k8s.CoreV1Api,
  namespace: string,
  name: string,
  timeout: number
): Promise<V1Pod> {
  const startTime = Date.now();

  while (Date.now() - startTime < timeout) {
    const response = await api.readNamespacedPod({ name, namespace });
    if (response.body.status?.phase === 'Running') {
      return response.body;
    }
    await new Promise(resolve => setTimeout(resolve, 2000));
  }

  throw new Error(`Pod ${name} not ready after ${timeout}ms`);
}
```

## Deployment Example

```typescript
// tests/deployment.test.ts

import { describe, it, beforeAll, afterAll, expect } from 'vitest';
import { KindCluster } from './kind-cluster';
import {
  V1Deployment,
  V1ObjectMeta,
  V1DeploymentSpec,
  V1PodTemplateSpec,
  V1PodSpec,
  V1Container,
  V1ResourceRequirements,
  V1LabelSelector,
  V1ContainerPort,
} from '@kubernetes/client-node';

describe('Deployment Tests', () => {
  let cluster: KindCluster;

  beforeAll(async () => {
    cluster = new KindCluster();
    await cluster.start();
  }, 300000);

  afterAll(async () => {
    await cluster.stop();
  });

  it('should create a deployment', async () => {
    const deployment: V1Deployment = {
      apiVersion: 'apps/v1',
      kind: 'Deployment',
      metadata: {
        name: 'nginx-deployment',
        namespace: 'default',
      } as V1ObjectMeta,
      spec: {
        replicas: 2,
        selector: {
          matchLabels: { app: 'nginx' },
        } as V1LabelSelector,
        template: {
          metadata: {
            labels: { app: 'nginx' },
          } as V1ObjectMeta,
          spec: {
            containers: [
              {
                name: 'nginx',
                image: 'nginx:1.25',
                ports: [{ containerPort: 80 }] as V1ContainerPort[],
                resources: {
                  requests: {
                    memory: '128Mi',
                    cpu: '100m',
                  },
                  limits: {
                    memory: '256Mi',
                    cpu: '500m',
                  },
                } as V1ResourceRequirements,
              } as V1Container,
            ],
          } as V1PodSpec,
        } as V1PodTemplateSpec,
      } as V1DeploymentSpec,
    };

    const created = await cluster.AppsV1Api.createNamespacedDeployment({
      namespace: 'default',
      body: deployment,
    });

    console.log(`Created deployment: ${created.body.metadata?.name}`);

    const readyDeployment = await waitForDeploymentReady(
      cluster.AppsV1Api,
      'default',
      'nginx-deployment',
      2,
      180000
    );

    expect(readyDeployment.status?.readyReplicas).toBe(2);
    console.log(`Deployment is ready with ${readyDeployment.status?.readyReplicas} replicas`);

    await cluster.AppsV1Api.deleteNamespacedDeployment({
      name: 'nginx-deployment',
      namespace: 'default',
    });
    console.log('Deleted deployment');
  });
});

async function waitForDeploymentReady(
  api: k8s.AppsV1Api,
  namespace: string,
  name: string,
  expectedReplicas: number,
  timeout: number
): Promise<V1Deployment> {
  const startTime = Date.now();

  while (Date.now() - startTime < timeout) {
    const response = await api.readNamespacedDeployment({ name, namespace });
    const ready = response.body.status?.readyReplicas || 0;
    console.log(`Ready replicas: ${ready}/${expectedReplicas}`);

    if (ready === expectedReplicas) {
      return response.body;
    }
    await new Promise(resolve => setTimeout(resolve, 3000));
  }

  throw new Error(`Deployment ${name} not ready after ${timeout}ms`);
}
```

## Debug Helper

```typescript
// tests/debug.ts

import * as k8s from '@kubernetes/client-node';

export async function collectDebugInfo(
  coreV1Api: k8s.CoreV1Api,
  namespace: string
): Promise<void> {
  console.log('=== PODS ===');
  const pods = await coreV1Api.listNamespacedPod({ namespace });
  
  for (const pod of pods.body.items) {
    console.log(`Pod: ${pod.metadata?.name} - Phase: ${pod.status?.phase}`);

    if (pod.status?.phase !== 'Running') {
      try {
        const logs = await coreV1Api.readNamespacedPodLog({
          name: pod.metadata?.name || '',
          namespace,
        });
        console.log(`Logs for ${pod.metadata?.name}:`);
        console.log(logs.body);
      } catch (e) {
        console.log(`Could not get logs: ${e}`);
      }
    }
  }

  console.log('\n=== EVENTS ===');
  const events = await coreV1Api.listNamespacedEvent({ namespace });
  
  for (const event of events.body.items) {
    console.log(
      `[${event.type}] ${event.involvedObject?.kind}/${event.involvedObject?.name}: ${event.message}`
    );
  }
}

export async function describePod(
  coreV1Api: k8s.CoreV1Api,
  namespace: string,
  name: string
): Promise<void> {
  const pod = await coreV1Api.readNamespacedPod({ name, namespace });

  console.log('=== POD DETAILS ===');
  console.log(`Name: ${pod.body.metadata?.name}`);
  console.log(`Namespace: ${pod.body.metadata?.namespace}`);
  console.log(`Phase: ${pod.body.status?.phase}`);
  console.log(`Pod IP: ${pod.body.status?.podIP}`);
  console.log(`Host IP: ${pod.body.status?.hostIP}`);

  console.log('\n=== CONTAINER STATUSES ===');
  for (const cs of pod.body.status?.containerStatuses || []) {
    console.log(`Container: ${cs.name}`);
    console.log(`  Ready: ${cs.ready}`);
    console.log(`  Restarts: ${cs.restartCount}`);
    if (cs.state?.waiting) {
      console.log(`  Waiting: ${cs.state.waiting.reason} - ${cs.state.waiting.message}`);
    }
  }
}
```

## Vitest Configuration

```typescript
// vitest.integration.ts

import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['tests/**/*.test.ts'],
    testTimeout: 300000,
    hookTimeout: 300000,
    pool: 'forks',
    poolOptions: {
      forks: {
        singleFork: true,
      },
    },
  },
});
```

## Fixtures

```typescript
// tests/fixtures.ts

import { KindCluster } from './kind-cluster';
import { collectDebugInfo } from './debug';

let cluster: KindCluster | null = null;

export async function getCluster(): Promise<KindCluster> {
  if (!cluster) {
    cluster = new KindCluster();
    await cluster.start();
  }
  return cluster;
}

export async function cleanupCluster(): Promise<void> {
  if (cluster) {
    await cluster.stop();
    cluster = null;
  }
}

export async function debugOnFailure(
  coreV1Api: k8s.CoreV1Api,
  namespace: string,
  testFailed: boolean
): Promise<void> {
  if (testFailed) {
    await collectDebugInfo(coreV1Api, namespace);
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
npm run test:integration

echo "Tests completed!"
```
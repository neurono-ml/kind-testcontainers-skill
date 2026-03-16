# Ruby - Kubernetes Testcontainers Examples

## Dependências (Gemfile)

```ruby
source 'https://rubygems.org'

gem 'testcontainers', '~> 0.2'
gem 'kubeclient', '~> 4.11'
gem 'rspec', '~> 3.12'
gem 'recursive-open-struct', '~> 2.0'
```

## Módulo KindCluster

```ruby
# spec/support/kind_cluster.rb

require 'testcontainers'
require 'kubeclient'
require 'yaml'
require 'logger'

class KindCluster
  KIND_IMAGE = 'kindest/node:v1.29.1'
  KUBECONFIG_PATH = '/etc/kubernetes/admin.conf'
  INTERNAL_API_PORT = 6443
  DEFAULT_TIMEOUT = 300

  attr_reader :client, :mapped_port

  def initialize(name: 'test-cluster')
    @name = name
    @container = nil
    @client = nil
    @mapped_port = nil
    @logger = Logger.new($stdout)
  end

  def start(timeout: DEFAULT_TIMEOUT)
    @logger.info "Starting Kind cluster..."
    
    @container = Testcontainers::DockerContainer.new(KIND_IMAGE)
      .with_exposed_ports(INTERNAL_API_PORT)
      .with_privileged(true)

    @container.start

    @logger.info "Waiting for cluster to be ready..."
    wait_for_logs('Reached ap readiness hooks', timeout: timeout)

    @mapped_port = @container.mapped_port(INTERNAL_API_PORT).to_i
    @logger.info "API server port: #{@mapped_port}"

    extract_and_patch_kubeconfig
    create_client
    wait_for_api_ready

    @logger.info "Cluster is ready!"
    self
  end

  def stop
    return unless @container

    @logger.info "Stopping Kind cluster..."
    @container.stop
    @container = nil
  end

  private

  def wait_for_logs(pattern, timeout:)
    start_time = Time.now

    while Time.now - start_time < timeout
      logs = @container.logs
      return if logs.include?(pattern)

      sleep 2
    end

    raise Timeout::Error, "Timeout waiting for logs pattern: #{pattern}"
  end

  def extract_and_patch_kubeconfig
    result = @container.exec("cat #{KUBECONFIG_PATH}")
    raise "Failed to read kubeconfig: #{result[2]}" unless result[2] == 0

    kubeconfig = YAML.safe_load(result[0])

    kubeconfig['clusters'].each do |cluster|
      cluster['cluster']['server'] = "https://localhost:#{@mapped_port}" if cluster['cluster']['server']
    end

    @kubeconfig = kubeconfig
  end

  def create_client
    @client = Kubeclient::Client.new(
      @kubeconfig['clusters'].first['cluster']['server'],
      'v1',
      ssl_options: {
        ca_file: write_ca_cert,
        verify_ssl: OpenSSL::SSL::VERIFY_PEER
      },
      auth_options: {
        bearer_token: extract_token
      }
    )
  end

  def write_ca_cert
    ca_file = Tempfile.new('kube-ca')
    ca_file.write(@kubeconfig['clusters'].first['cluster']['certificate-authority-data'])
    ca_file.close
    ca_file.path
  end

  def extract_token
    user = @kubeconfig.dig('users', 0, 'user')
    user['token'] || user['exec']&.dig('apiVersion')
  end

  def wait_for_api_ready(timeout: 120)
    start_time = Time.now

    while Time.now - start_time < timeout
      begin
        @client.get_namespaces
        return
      rescue StandardError => e
        @logger.debug "Waiting for API server: #{e.message}"
        sleep 2
      end
    end

    raise Timeout::Error, "API server not ready after #{timeout} seconds"
  end
end
```

## RSpec Configuration

```ruby
# spec/spec_helper.rb

require 'rspec'
require_relative 'support/kind_cluster'
require_relative 'support/debug_helper'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.warnings = true

  config.default_formatter = "doc" if config.files_to_run.one?

  config.order = :random
  Kernel.srand config.seed

  config.around(:each, :integration) do |example|
    cluster = KindCluster.new
    cluster.start
    @kind_cluster = cluster
    example.run
    cluster.stop
  ensure
    @kind_cluster = nil
  end
end
```

## Exemplo Básico de Teste

```ruby
# spec/integration/pod_spec.rb

require 'spec_helper'
require 'kubeclient'

RSpec.describe 'Pod Integration Tests', :integration do
  let(:client) { @kind_cluster.client }

  def wait_for_pod_ready(namespace, name, timeout: 120)
    start_time = Time.now

    while Time.now - start_time < timeout
      pod = client.get_pod(name, namespace)
      return pod if pod.status.phase == 'Running'

      sleep 2
    end

    raise Timeout::Error, "Pod #{name} not ready after #{timeout} seconds"
  end

  it 'creates and deletes a pod' do
    namespace = 'default'
    pod_name = 'test-pod'

    pod = {
      apiVersion: 'v1',
      kind: 'Pod',
      metadata: {
        name: pod_name,
        namespace: namespace
      },
      spec: {
        containers: [{
          name: 'nginx',
          image: 'nginx:1.25',
          resources: {
            requests: {
              memory: '128Mi',
              cpu: '100m'
            },
            limits: {
              memory: '256Mi',
              cpu: '500m'
            }
          }
        }]
      }
    }

    created_pod = client.create_pod(pod)
    expect(created_pod.metadata.name).to eq(pod_name)
    puts "Created pod: #{created_pod.metadata.name}"

    ready_pod = wait_for_pod_ready(namespace, pod_name)
    expect(ready_pod.status.phase).to eq('Running')
    puts 'Pod is running'

    client.delete_pod(pod_name, namespace)
    puts 'Deleted pod'
  end
end
```

## Exemplo com Deployment

```ruby
# spec/integration/deployment_spec.rb

require 'spec_helper'

RSpec.describe 'Deployment Integration Tests', :integration do
  let(:client) { @kind_cluster.client }

  def wait_for_deployment_ready(namespace, name, expected_replicas:, timeout: 180)
    start_time = Time.now

    while Time.now - start_time < timeout
      deployment = client.get_deployment(name, namespace)
      
      ready_replicas = deployment.status&.readyReplicas || 0
      puts "Ready replicas: #{ready_replicas}/#{expected_replicas}"
      
      return deployment if ready_replicas == expected_replicas

      sleep 3
    end

    raise Timeout::Error, "Deployment #{name} not ready after #{timeout} seconds"
  end

  it 'creates a deployment with replicas' do
    namespace = 'default'
    deployment_name = 'nginx-deployment'

    deployment = {
      apiVersion: 'apps/v1',
      kind: 'Deployment',
      metadata: {
        name: deployment_name,
        namespace: namespace
      },
      spec: {
        replicas: 2,
        selector: {
          matchLabels: { app: 'nginx' }
        },
        template: {
          metadata: {
            labels: { app: 'nginx' }
          },
          spec: {
            containers: [{
              name: 'nginx',
              image: 'nginx:1.25',
              ports: [{ containerPort: 80 }],
              resources: {
                requests: {
                  memory: '128Mi',
                  cpu: '100m'
                },
                limits: {
                  memory: '256Mi',
                  cpu: '500m'
                }
              }
            }]
          }
        }
      }
    }

    created = client.create_deployment(deployment)
    puts "Created deployment: #{created.metadata.name}"

    ready_deployment = wait_for_deployment_ready(
      namespace,
      deployment_name,
      expected_replicas: 2
    )

    expect(ready_deployment.status.readyReplicas).to eq(2)
    puts "Deployment is ready with #{ready_deployment.status.readyReplicas} replicas"

    client.delete_deployment(deployment_name, namespace)
    puts 'Deleted deployment'
  end
end
```

## Helper de Debug

```ruby
# spec/support/debug_helper.rb

require 'logger'

module DebugHelper
  def collect_debug_info(client, namespace)
    logger = Logger.new($stdout)

    logger.info '=== PODS ==='
    pods = client.get_pods(namespace: namespace)
    pods.each do |pod|
      logger.info "Pod: #{pod.metadata.name} - Phase: #{pod.status.phase}"

      if pod.status.phase != 'Running'
        begin
          logs = client.get_pod_log(pod.metadata.name, namespace)
          logger.info "Logs for #{pod.metadata.name}:"
          logger.info logs
        rescue StandardError => e
          logger.warn "Could not get logs: #{e.message}"
        end
      end
    end

    logger.info "\n=== EVENTS ==="
    events = client.get_events(namespace: namespace)
    events.each do |event|
      logger.info "[#{event.type}] #{event.involvedObject&.kind}/#{event.involvedObject&.name}: #{event.message}"
    end
  end

  def describe_pod(client, namespace, name)
    logger = Logger.new($stdout)
    pod = client.get_pod(name, namespace)

    logger.info '=== POD DETAILS ==='
    logger.info "Name: #{pod.metadata.name}"
    logger.info "Namespace: #{pod.metadata.namespace}"
    logger.info "Phase: #{pod.status.phase}"
    logger.info "Pod IP: #{pod.status.podIP}"
    logger.info "Host IP: #{pod.status.hostIP}"

    logger.info "\n=== CONTAINER STATUSES ==="
    pod.status.containerStatuses&.each do |cs|
      logger.info "Container: #{cs.name}"
      logger.info "  Ready: #{cs.ready}"
      logger.info "  Restarts: #{cs.restartCount}"
      
      if cs.state&.waiting
        logger.info "  Waiting: #{cs.state.waiting.reason} - #{cs.state.waiting.message}"
      end
    end
  end

  def retry_with_backoff(max_retries: 5, initial_delay: 1)
    retries = 0
    delay = initial_delay

    begin
      yield
    rescue StandardError => e
      retries += 1
      raise e if retries > max_retries

      puts "Retry #{retries}/#{max_retries} after error: #{e.message}"
      sleep delay
      delay *= 2
      retry
    end
  end
end

RSpec.configure do |config|
  config.include DebugHelper
end
```

## Wait Conditions Helper

```ruby
# spec/support/wait_conditions.rb

module WaitConditions
  def wait_for(condition, timeout: 120, interval: 2, message: nil)
    start_time = Time.now

    loop do
      result = condition.call
      return result if result

      if Time.now - start_time > timeout
        raise Timeout::Error, message || "Condition not met after #{timeout} seconds"
      end

      sleep interval
    end
  end

  def wait_for_pod_phase(client, namespace, name, expected_phase, timeout: 120)
    wait_for(
      -> { client.get_pod(name, namespace).status.phase == expected_phase },
      timeout: timeout,
      message: "Pod #{name} did not reach phase #{expected_phase}"
    )
  end

  def wait_for_deployment_replicas(client, namespace, name, expected_replicas, timeout: 180)
    wait_for(
      -> do
        deployment = client.get_deployment(name, namespace)
        (deployment.status&.readyReplicas || 0) == expected_replicas
      end,
      timeout: timeout,
      message: "Deployment #{name} did not reach #{expected_replicas} ready replicas"
    )
  end
end

RSpec.configure do |config|
  config.include WaitConditions
end
```

## Script de Execução

```bash
#!/bin/bash
# scripts/run-tests.sh

set -e

echo "Checking Docker..."
docker ps > /dev/null 2>&1 || { echo "Docker not running"; exit 1; }

echo "Running tests..."
bundle exec rspec spec/integration/ --format documentation

echo "Tests completed!"
```

## Rake Task

```ruby
# lib/tasks/test.rake

namespace :test do
  desc 'Run integration tests with Kind cluster'
  task :integration do
    require 'rspec/core/runner'
    
    puts 'Starting integration tests...'
    
    begin
      RSpec::Core::Runner.run(['spec/integration/', '--format', 'documentation'])
    rescue SystemExit => e
      raise unless e.status == 0
    end
  end
end
```

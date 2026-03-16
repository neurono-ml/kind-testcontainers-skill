#!/usr/bin/env groovy

pipeline {
    agent {
        docker {
            image 'docker:24'
            args '-v /var/run/docker.sock:/var/run/docker.sock --privileged'
        }
    }

    environment {
        TESTCONTAINERS_RYUK_DISABLED = 'false'
        TESTCONTAINERS_RYUK_PORT = '8080'
    }

    options {
        timeout(time: 30, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Test Java') {
            agent {
                docker {
                    image 'maven:3.9-eclipse-temurin-21'
                    args '-v /var/run/docker.sock:/var/run/docker.sock --privileged'
                }
            }
            steps {
                dir('src/java') {
                    sh 'mvn test -B'
                }
            }
            post {
                failure {
                    sh '''
                        echo "=== Docker containers ==="
                        docker ps -a || true
                        echo "=== Container logs ==="
                        docker logs $(docker ps -q --filter "label=org.testcontainers=true") 2>/dev/null || true
                    '''
                }
            }
        }

        stage('Test Rust') {
            agent {
                docker {
                    image 'rust:1.75'
                    args '-v /var/run/docker.sock:/var/run/docker.sock --privileged'
                }
            }
            steps {
                dir('src/rust') {
                    sh 'cargo test --test integration'
                }
            }
            post {
                failure {
                    sh '''
                        echo "=== Docker containers ==="
                        docker ps -a || true
                        echo "=== Container logs ==="
                        docker logs $(docker ps -q --filter "label=org.testcontainers=true") 2>/dev/null || true
                    '''
                }
            }
        }

        stage('Test Go') {
            agent {
                docker {
                    image 'golang:1.21'
                    args '-v /var/run/docker.sock:/var/run/docker.sock --privileged'
                }
            }
            steps {
                dir('src/golang') {
                    sh 'go test ./... -v -timeout 10m'
                }
            }
            post {
                failure {
                    sh '''
                        echo "=== Docker containers ==="
                        docker ps -a || true
                        echo "=== Container logs ==="
                        docker logs $(docker ps -q --filter "label=org.testcontainers=true") 2>/dev/null || true
                    '''
                }
            }
        }

        stage('Test Python') {
            agent {
                docker {
                    image 'python:3.11'
                    args '-v /var/run/docker.sock:/var/run/docker.sock --privileged'
                }
            }
            steps {
                dir('src/python') {
                    sh '''
                        pip install -r requirements.txt
                        pip install -r requirements-dev.txt
                        pytest tests/integration/ -v --timeout=300
                    '''
                }
            }
            post {
                failure {
                    sh '''
                        echo "=== Docker containers ==="
                        docker ps -a || true
                        echo "=== Container logs ==="
                        docker logs $(docker ps -q --filter "label=org.testcontainers=true") 2>/dev/null || true
                    '''
                }
            }
        }

        stage('Test TypeScript') {
            agent {
                docker {
                    image 'node:20'
                    args '-v /var/run/docker.sock:/var/run/docker.sock --privileged'
                }
            }
            steps {
                dir('src/typescript') {
                    sh '''
                        npm ci
                        npm run test:integration
                    '''
                }
            }
            post {
                failure {
                    sh '''
                        echo "=== Docker containers ==="
                        docker ps -a || true
                        echo "=== Container logs ==="
                        docker logs $(docker ps -q --filter "label=org.testcontainers=true") 2>/dev/null || true
                    '''
                }
            }
        }
    }

    post {
        always {
            sh '''
                echo "Stopping Ryuk..."
                docker rm -f $(docker ps -q --filter "name=testcontainers-ryuk") 2>/dev/null || true
                
                echo "Removing Kind containers..."
                docker rm -f $(docker ps -q --filter "label=org.testcontainers=true") 2>/dev/null || true
                
                echo "Removing temporary images..."
                docker images --filter "reference=*test*" -q | xargs -r docker rmi -f 2>/dev/null || true
                
                echo "Cleanup complete!"
            '''
        }
        success {
            echo 'All tests passed!'
        }
        failure {
            echo 'Some tests failed. Check the logs above.'
        }
    }
}

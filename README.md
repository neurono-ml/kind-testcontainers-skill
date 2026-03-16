# Kubernetes Testcontainers Integration Skill

A skill for AI agents that facilitates creation, validation, and maintenance of Kubernetes integration tests using **Testcontainers** and **Kind (Kubernetes in Docker)**.

## TLDR

### Quick Installation

Install skill from GitHub repository

```bash
npx skills add https://github.com/neurono-ml/kind-testcontainers-skill
```

```bash
npx skills add neurono-ml/kind-testcontainers-skill
```

## Overview

This skill empowers AI agents to generate robust Kubernetes integration tests that are:
- **Ephemeral** - Clusters are created and destroyed automatically
- **Isolated** - Each test runs in its own environment
- **Executable** - Works both locally and in CI/CD

## Supported Languages

| Language | Status | Test Framework |
|----------|--------|---------------|
| Java | ✅ Complete | JUnit 5 |
| Rust | ✅ Complete | cargo test |
| Golang | ✅ Complete | go test |
| Python | ✅ Complete | pytest |
| TypeScript/JavaScript | ✅ Complete | Jest/Vitest |
| Scala | ✅ Complete | MUnit/ScalaTest |
| Ruby | ✅ Complete | RSpec |

## Project Structure

```
kind-testcontainers-skill/
├── SKILL.md              # Main skill instructions
├── README.md             # This file
├── AGENTS.md             # Template for target projects
├── src/
│   ├── java/             # Java examples and templates
│   ├── rust/             # Rust examples and templates
│   ├── golang/           # Go examples and templates
│   ├── python/           # Python examples and templates
│   ├── typescript/       # TypeScript examples and templates
│   ├── scala/            # Scala examples and templates
│   └── ruby/             # Ruby examples and templates
├── ci/
│   └── templates/        # CI/CD templates
│       ├── github-actions.yml
│       ├── gitlab-ci.yml
│       └── jenkins.groovy
├── specs/
│   ├── validation.md     # Validation criteria
│   └── acceptance.md     # Acceptance criteria
└── scripts/
    ├── cleanup-testcontainers.sh
    └── debug-kind.sh
```

## Quick Start

### For AI Agents

1. Read the `SKILL.md` file for complete instructions
2. Check examples in `src/<language>/` for implementation patterns
3. Use templates in `ci/templates/` to configure pipelines
4. Validate against criteria in `specs/`

### For Developers

```bash
# Clone the skill
git clone https://github.com/your-username/kind-testcontainers-skill.git

# Run the cleanup script (useful during development)
./scripts/cleanup-testcontainers.sh

# Check active containers
docker ps --filter "label=org.testcontainers=true"
```

## Prerequisites

- Docker 20.10+ installed and running
- Minimum 4GB RAM available
- Access to Docker socket

## Key Features

### RYUK enabled by default
Ensures automatic container cleanup even in case of failures.

### Dynamic kubeconfig
Port 6443 is dynamically mapped - no hardcoded ports.

### Wait Conditions
Use wait conditions instead of fixed sleep for more reliable tests.

### Debug Helpers
Automatic log and event collection in case of failure.

## Contributing

1. Fork the repository
2. Create a branch for your feature (`git checkout -b feature/new-language`)
3. Commit your changes (`git commit -am 'Add support for NewLanguage'`)
4. Push to the branch (`git push origin feature/new-language`)
5. Open a Pull Request

## License

MIT License - see [LICENSE](LICENSE) for details.

## Resources

- [Testcontainers Documentation](https://testcontainers.com/)
- [Kind Documentation](https://kind.sigs.k8s.io/)
- [Integration Guide](./references/integration-guide.md)

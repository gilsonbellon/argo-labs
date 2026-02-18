# Jenkins to Argo Workflows Migration Examples

This directory contains CI/CD pipeline examples migrated from Jenkins to Argo Workflows.

## Files

### `jenkins-iot-build-push.yaml`
- **Source**: `iot-pipelines/Jenkinsfile.build`
- **Purpose**: Build and push Docker images to Harbor registry
- **Features**:
  - Git checkout from Bitbucket
  - Docker build with optional NPM token build args
  - Push to Harbor registry (`harborngp.34-147-139-99.sslip.io/iot-pipelines/...`)
  - Image tagging: `{env}-{prefix}:{short-sha}`

### `jenkins-helm-charts-ci.yaml`
- **Source**: `helm-charts/Jenkinsfile.build` and `Jenkinsfile.push`
- **Purpose**: CI pipeline for Helm charts - lint, validate, package, and push
- **Features**:
  - Detect changed Helm charts between branches
  - YAML linting with `yamllint`
  - Kubernetes schema validation with `kubeconform`
  - Version bump validation
  - Helm package and push to Harbor OCI registry

## Usage

These are example templates migrated from Jenkins. They can be used as reference or adapted for your needs.

**Note**: These templates are separate from the main workflows directory to avoid mixing with existing pipelines.

## Requirements

- Harbor credentials secret: `harbor-credentials` (for Docker/Helm registry access)
- Git repository access (configured in parameters)
- For Helm charts: `ci-k8s-tools` image with helm, yamllint, kubeconform

## Differences from Jenkins

- Uses Argo Workflows instead of Jenkins pipelines
- Uses Kubernetes secrets instead of Jenkins credentials
- Uses Argo artifacts instead of Jenkins workspace
- Parameters instead of Jenkins environment variables

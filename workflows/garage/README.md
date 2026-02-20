# Garage object storage for Argo Workflows

This folder contains everything you need to deploy **Garage** (S3-compatible object storage) and use it as the artifact repository for Argo Workflows, as an alternative to MinIO.

- **MinIO** (used by the main `install.sh` and template `02-moderate-build-test.yaml`) is kept as-is for reference.
- **Garage** is deployed and configured here; use the **Garage** workflow template when your artifact repository is Garage.

## Contents

| File | Purpose |
|------|--------|
| **TUTORIAL-GARAGE-DEPLOY-AND-CONFIGURE.md** | Step-by-step tutorial: deploy and configure Garage yourself (recommended read first). |
| **install-garage.sh** | Script: clone Garage Helm chart, install Garage, configure layout, create bucket and API key, create K8s secret for Argo. |
| **values-override.yaml** | Helm values override for Garage (replication, replica count, persistence). |
| **configure-argo-for-garage.sh** | Script: point Argo Workflows artifact repository to Garage and restart the controller. |
| **setup-garage-bucket-and-key.sh** | Optional: only configure layout, create bucket and key, and secret (run after a manual Helm install). |

## Quick path (after tutorial)

1. Run the tutorial in **TUTORIAL-GARAGE-DEPLOY-AND-CONFIGURE.md** (recommended so you understand each step).
2. Or run in order (from `workflows/garage/`):
   - `chmod +x install-garage.sh configure-argo-for-garage.sh setup-garage-bucket-and-key.sh`  # if needed
   - `./install-garage.sh`
   - `./configure-argo-for-garage.sh`
3. Apply the Garage workflow template and submit a workflow (see **Part 5** in the tutorial for the full `kubectl create` example).

## Switching back to MinIO

To use MinIO again as the artifact repository, re-run the main install script (it re-creates the MinIO config), or manually patch `workflow-controller-configmap` in the `argo` namespace back to the MinIO endpoint and `my-minio-cred` secret, then restart the workflow-controller.

# Tutorial: Deploy and configure Garage for Argo Workflows

This tutorial walks you through deploying **Garage** (S3-compatible object storage) on your Kubernetes cluster and configuring **Argo Workflows** to use it as the artifact repository. By the end, you will have done the steps yourself and understand what each part does.

**Prerequisites:** `kubectl` and `helm` installed, a running Kubernetes cluster (e.g. Kind), and Argo Workflows already installed (e.g. via the main `install.sh` in this repo, which uses MinIO by default).

---

## Part 1: Understand the goal

- **Garage** provides an S3-compatible API (default port **3900**) and stores objects.
- **Argo Workflows** needs an artifact repository (S3-compatible) to store workflow outputs (e.g. build artifacts). Today it’s configured for MinIO; we will add Garage and switch Argo to it.
- You will: deploy Garage with Helm, configure its cluster layout, create a bucket and an API key, store the key in a Kubernetes secret, then point Argo’s artifact repository to Garage.

---

## Part 2: Deploy Garage with Helm

### 2.1 Get the Garage Helm chart

The official chart lives in the Garage repo. Clone it (you can use a temporary directory):

```bash
git clone https://git.deuxfleurs.fr/Deuxfleurs/garage
cd garage/script/helm
```

You will install from `./garage` in this directory.

### 2.2 (Optional) Override Helm values

For a small cluster (e.g. Kind), you may want fewer replicas and lower replication. We provide a `values-override.yaml` in the `workflows/garage/` folder of this repo. Copy it next to the chart or pass it with `-f`:

```bash
# From the repo root (e.g. uabsd/argo-labs/workflows/garage)
cp values-override.yaml /path/to/garage/script/helm/values.override.yaml
```

Then install with:

```bash
helm install --create-namespace --namespace garage garage ./garage -f values.override.yaml
```

Without override:

```bash
helm install --create-namespace --namespace garage garage ./garage
```

### 2.3 Verify the deployment

- Wait for Garage pods to be ready:
  ```bash
  kubectl get pods -n garage -w
  ```
- Check the Garage service (S3 API is on port 3900):
  ```bash
  kubectl get svc -n garage
  ```
  You should see a service (e.g. `garage`) with port **3900**. The full in-cluster endpoint will be something like: `garage.garage.svc:3900`.

---

## Part 3: Configure Garage (layout, bucket, key)

Garage needs a **cluster layout** (which nodes store data), then a **bucket** and an **API key** that Argo will use.

### 3.1 Open a shell on the first Garage pod

Use the first pod (e.g. `garage-0`):

```bash
kubectl exec -it -n garage garage-0 -- /bin/sh
```

(If your image has no `sh`, try `/bin/bash` or use `kubectl exec ... -- ./garage status` from the host instead.)

### 3.2 Get the node ID

Inside the pod, run:

```bash
./garage status
```

Note the **node ID** (first column, hex string). Example: `563e1ac825ee3323`.

### 3.3 Assign a role and apply the layout

Still inside the pod (replace `<NODE_ID>` with the ID from the previous step, or a short prefix like `563e`):

```bash
./garage layout assign -z dc1 -c 1G <NODE_ID>
./garage layout apply --version 1
```

For multiple Garage pods, you would assign each node and then apply once. For one node, this is enough.

### 3.4 Create the bucket and API key

Create the bucket Argo will use and a key with access:

```bash
./garage bucket create argo-workflows
./garage key create argo-garage-key
```

The last command prints something like:

```
Key name: argo-garage-key
Key ID: GKxxxxxxxxxxxxxxxxxxxxxxxx
Secret key: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Copy the **Key ID** and **Secret key**; you will put them in a Kubernetes secret for Argo.

Give the key read/write/owner on the bucket:

```bash
./garage bucket allow --read --write --owner argo-workflows --key argo-garage-key
```

Exit the pod (`exit`).

### 3.5 Create a Kubernetes secret for Argo

Argo expects a secret with `accesskey` and `secretkey` (same as for MinIO). Create it in the **argo** namespace (use the Key ID and Secret key from above):

```bash
kubectl create secret generic my-garage-cred -n argo \
  --from-literal=accesskey='GKxxxxxxxxxxxxxxxxxxxxxxxx' \
  --from-literal=secretkey='your-secret-key-here'
```

Replace the placeholders with the real values from `garage key create`.

---

## Part 4: Point Argo Workflows to Garage

Argo reads the artifact repository from the **workflow-controller** ConfigMap.

### 4.1 See the current config

```bash
kubectl get configmap workflow-controller-configmap -n argo -o yaml
```

You’ll see `artifactRepository` with an `s3` block (endpoint, bucket, secret refs).

### 4.2 Switch to Garage

Patch the ConfigMap so that:

- **endpoint** is the Garage S3 API: `garage.garage.svc:3900`
- **bucket** is `argo-workflows`
- **accessKeySecret** and **secretKeySecret** point to the secret you created, e.g. `my-garage-cred` with keys `accesskey` and `secretkey`
- **insecure: true** if you’re not using TLS inside the cluster

Example (replace if your ConfigMap structure differs):

```bash
kubectl patch configmap workflow-controller-configmap -n argo --type merge -p '{
  "data": {
    "config": "artifactRepository:\n  archiveLogs: true\n  s3:\n    bucket: argo-workflows\n    endpoint: garage.garage.svc:3900\n    insecure: true\n    accessKeySecret:\n      name: my-garage-cred\n      key: accesskey\n    secretKeySecret:\n      name: my-garage-cred\n      key: secretkey\n"
  }
}'
```

Or edit the ConfigMap manually:

```bash
kubectl edit configmap workflow-controller-configmap -n argo
```

Set the `config` field to something like (YAML, then stored as a string):

```yaml
artifactRepository:
  archiveLogs: true
  s3:
    bucket: argo-workflows
    endpoint: garage.garage.svc:3900
    insecure: true
    accessKeySecret:
      name: my-garage-cred
      key: accesskey
    secretKeySecret:
      name: my-garage-cred
      key: secretkey
```

### 4.3 Restart the workflow controller

So it reloads the config:

```bash
kubectl rollout restart deployment workflow-controller -n argo
kubectl rollout status deployment workflow-controller -n argo --timeout=60s
```

---

## Part 5: Run a workflow that uses Garage

We provide a workflow template that is identical to the “moderate build test” but intended for use when the artifact repository is Garage: **moderate-build-test-garage**.

### 5.1 Apply the template

From the repo root (e.g. `uabsd/argo-labs`):

```bash
kubectl apply -f workflows/02-moderate-build-test-garage.yaml
```

### 5.2 Submit a workflow

```bash
kubectl create -n argo -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: build-test-garage-
spec:
  workflowTemplateRef:
    name: moderate-build-test-garage
    clusterScope: false
  arguments:
    parameters:
    - name: repo-url
      value: "https://github.com/gilsonbellon/argo-labs.git"
    - name: revision
      value: "main"
    - name: image-name
      value: "test-app"
EOF
```

### 5.3 Verify

- List workflows: `kubectl get workflows -n argo`
- Watch the one you created until it completes. Artifacts will be stored in Garage (bucket `argo-workflows`).

If something fails (e.g. “artifact not found”), check that the ConfigMap endpoint is `garage.garage.svc:3900`, the secret `my-garage-cred` exists in `argo`, and that you ran `garage layout apply` and `garage bucket allow`.

---

## Part 6: Scripts provided in this folder

To save repetition, we provide scripts that do the same steps you did above:

| Script | What it does |
|--------|------------------|
| **install-garage.sh** | Clones the Garage repo, runs `helm install`, configures layout, creates bucket and key, creates the `my-garage-cred` secret in `argo`. Run once. |
| **configure-argo-for-garage.sh** | Patches `workflow-controller-configmap` to use Garage and restarts the workflow-controller. Run after Garage is installed and the secret exists. |
| **setup-garage-bucket-and-key.sh** | Only layout + bucket + key + secret; use if you already installed Garage with Helm yourself. |

You can run the tutorial steps by hand first, then use the scripts next time or to automate.

---

## Summary

- **Garage** = S3-compatible object store (port 3900); you deployed it with Helm and configured layout, bucket `argo-workflows`, and key `argo-garage-key`.
- **Argo** = uses the artifact repository defined in `workflow-controller-configmap`; you pointed it to `garage.garage.svc:3900` and `my-garage-cred`.
- The **moderate-build-test-garage** template is the same pipeline as the MinIO-based one, but meant to be used when the default artifact repository is Garage.

The original MinIO setup and **moderate-build-test** template are unchanged; you can switch back to MinIO by restoring the MinIO endpoint and `my-minio-cred` in the ConfigMap and restarting the workflow-controller.

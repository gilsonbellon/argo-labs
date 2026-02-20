# Argo Events + Argo Workflows: Tutorial

This tutorial explains how **Argo Events** (EventSource, Sensor, webhooks) work together with **Argo Workflows** in this repo, using the GitHub polling → CI pipeline as a concrete example.

---

## Table of Contents

1. [Big picture: what happens end-to-end](#1-big-picture-what-happens-end-to-end)
2. [EventSource: receiving events (webhook)](#2-eventsource-receiving-events-webhook)
3. [Sensor: reacting to events and triggering workflows](#3-sensor-reacting-to-events-and-triggering-workflows)
4. [Poller CronJob: sending events to the webhook](#4-poller-cronjob-sending-events-to-the-webhook)
5. [WorkflowTemplate: the CI pipeline that runs](#5-workflowtemplate-the-ci-pipeline-that-runs)
6. [RBAC: why the Sensor can submit workflows](#6-rbac-why-the-sensor-can-submit-workflows)
7. [Summary diagram and file map](#7-summary-diagram-and-file-map)
8. [Quick reference: URLs and names](#8-quick-reference-urls-and-names)

---

## 1. Big picture: what happens end-to-end

```
┌─────────────────┐     HTTP POST      ┌──────────────────────────┐     event      ┌─────────────┐     submit      ┌─────────────────────┐
│  CronJob        │  ───────────────► │  EventSource (webhook)    │  ────────────► │   Sensor    │  ────────────► │  Argo Workflow       │
│  github-poller  │   /github         │  webhook-eventsource-svc  │                │  polling-   │                │  (vote-ci-template)  │
│  (every minute) │                   │  :12000                   │                │  sensor     │                │  in namespace: argo  │
└─────────────────┘                   └──────────────────────────┘                 └─────────────┘                 └─────────────────────┘
        │                                        │
        │ 1. Polls GitHub API                    │ 2. Argo Events creates
        │    for new commits                    │    a Service named
        │ 2. If new commit → POST                │    webhook-eventsource-svc
        │    to webhook URL                      │    (from EventSource name)
        └──────────────────────────────────────┘
```

- **CronJob** runs every minute, checks GitHub for new commits, and if there’s something new it sends an HTTP POST to the webhook.
- **EventSource (webhook)** exposes an HTTP server; Argo Events creates a **Service** so other pods (like the CronJob) can call it. That service is `webhook-eventsource-svc`.
- **Sensor** is subscribed to events from that EventSource. When an event arrives (e.g. on the `github` webhook), the Sensor runs its **triggers**.
- One trigger **submits an Argo Workflow** from the `vote-ci-template` WorkflowTemplate with fixed parameters (repo, branch, image name, etc.).

So: **poll GitHub → POST to webhook → EventSource emits event → Sensor runs → Workflow is submitted.**

---

## 2. EventSource: receiving events (webhook)

**File:** `webhook-eventsource.yaml`

An **EventSource** tells Argo Events *how to receive* events. Here we use the **webhook** type: an HTTP server that accepts POST requests.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: EventSource
metadata:
  name: webhook
  namespace: argo-events
spec:
  service:
    ports:
    - port: 12000
      targetPort: 12000
  webhook:
    example:
      port: "12000"
      endpoint: /example
      method: POST
    github:
      port: "12000"
      endpoint: /github
      method: POST
```

What this does:

- **`metadata.name: webhook`**  
  This is the EventSource name. Argo Events will create a **Service** named **`webhook-eventsource-svc`** in the same namespace (`argo-events`). So the full internal URL is:
  - `http://webhook-eventsource-svc.argo-events.svc.cluster.local:12000`
- **`spec.service.ports`**  
  The Service listens on port **12000** (same as the webhook server).
- **`spec.webhook`**  
  Each key (e.g. `example`, `github`) defines one **webhook route**:
  - **`github`**: path **`/github`**, method **POST**, port **12000**.

So when the CronJob (or anything in the cluster) does:

- `POST http://webhook-eventsource-svc.argo-events.svc.cluster.local:12000/github`

…the EventSource receives the request and emits an event with **eventName: github** (the key under `webhook`). The Sensor is configured to listen for that.

---

## 3. Sensor: reacting to events and triggering workflows

**File:** `sensor.yaml`

A **Sensor** defines:
- **Dependencies:** which EventSource and event name it listens to.
- **Triggers:** what to do when that event occurs (here: submit an Argo Workflow).

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Sensor
metadata:
  name: polling-sensor
  namespace: argo-events
spec:
  template:
    serviceAccountName: operate-workflow-sa
  dependencies:
    - name: poll-github
      eventSourceName: webhook
      eventName: github
  triggers:
    - template:
        name: launch-vote-ci
        argoWorkflow:
          operation: submit-from
          source:
            resource:
              apiVersion: argoproj.io/v1alpha1
              kind: WorkflowTemplate
              metadata:
                name: vote-ci-template
                namespace: argo
          parameters:
            - src:
                dependencyName: poll-github
                dataTemplate: "https://github.com/gilsonbellon/argo-labs.git"
              dest: workflow.parameters.repo-url
            - src:
                dependencyName: poll-github
                dataTemplate: "main"
              dest: workflow.parameters.branch
            # ... more parameters (image, harbor-username, harbor-password)
```

Explanation:

- **`dependencies`**
  - **`name: poll-github`** – logical name for this dependency (used in `parameters[].src.dependencyName`).
  - **`eventSourceName: webhook`** – must match the EventSource `metadata.name` (the one that creates `webhook-eventsource-svc`).
  - **`eventName: github`** – must match the webhook key in the EventSource (`webhook.github` → event name `github`).

- **`triggers`**
  - **`argoWorkflow`** – “when this dependency fires, submit an Argo Workflow.”
  - **`operation: submit-from`** – create a new Workflow **from** a WorkflowTemplate.
  - **`source.resource`** – the WorkflowTemplate: `vote-ci-template` in namespace `argo`.
  - **`parameters`** – map values into `workflow.parameters.*`. Here we use **`dataTemplate`** with fixed strings (repo URL, branch, image name, etc.). Each `dest` is a workflow parameter (e.g. `workflow.parameters.repo-url`).

- **`template.serviceAccountName: operate-workflow-sa`**  
  The Sensor runs the trigger as this ServiceAccount; that account needs RBAC to create Workflows from the template (see RBAC section).

So: **when the EventSource receives a POST on `/github`, it emits a `github` event → the Sensor’s dependency `poll-github` is satisfied → the trigger runs and submits a Workflow from `vote-ci-template` with the given parameters.**

---

## 4. Poller CronJob: sending events to the webhook

**File:** `poller-cronjob.yaml`

The CronJob is what actually **sends** the HTTP request to the webhook. It runs on a schedule and, if it finds a new commit, POSTs to the EventSource’s service.

```yaml
spec:
  schedule: "* * * * *"   # Every minute
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: poller
            image: schoolofdevops/github-poller:latest
            env:
            - name: GITHUB_API_URL
              value: "https://api.github.com/repos/gilsonbellon/argo-labs/commits"
            - name: GITHUB_TOKEN
              valueFrom:
                secretKeyRef:
                  name: github-token-secret
                  key: token
            - name: LAST_COMMIT_FILE
              value: "/data/last_commit.txt"
            - name: ARGO_EVENT_SOURCE_URL
              value: "http://webhook-eventsource-svc.argo-events.svc.cluster.local:12000/github"
```

Important parts:

- **`ARGO_EVENT_SOURCE_URL`** – full URL where the poller must POST when it detects a new commit. This **must** match:
  - **Host:** the EventSource Service: **`webhook-eventsource-svc.argo-events.svc.cluster.local`**
  - **Port:** **12000**
  - **Path:** **`/github`** (the webhook endpoint name in the EventSource).
- **`GITHUB_API_URL`** – which repo to poll.
- **`GITHUB_TOKEN`** – from a Secret (needed for higher rate limits / private repos).
- **`LAST_COMMIT_FILE`** – stored on a PVC so the job remembers the last seen commit and only fires when there’s something new.

So: **CronJob runs every minute → poller checks GitHub → if new commit → POST to `webhook-eventsource-svc:12000/github` → EventSource emits `github` event → Sensor runs → Workflow is submitted.**

---

## 5. WorkflowTemplate: the CI pipeline that runs

**File:** `vote-ci-template.yaml`

The **WorkflowTemplate** is the reusable CI pipeline. The Sensor submits a **Workflow** from this template and passes parameters (repo-url, branch, image, etc.).

High-level flow of the template:

1. **checkout** – clone repo and branch (using `repo-url`, `branch`).
2. **build** – build Docker image (e.g. with Dockerfile; has a default if none exists).
3. **push-harbor** – push image to Harbor (using `image` name and workflow name as tag).

Parameters the Sensor fills (from `sensor.yaml`):

- `workflow.parameters.repo-url` → e.g. `https://github.com/gilsonbellon/argo-labs.git`
- `workflow.parameters.branch` → e.g. `main`
- `workflow.parameters.image` → e.g. `argo-labs`
- `workflow.parameters.harbor-username` / `workflow.parameters.harbor-password` → can be empty if the workflow uses a Kubernetes secret for Harbor

So the **EventSource + Sensor** are the “trigger”; the **WorkflowTemplate** is the “what runs” when that trigger fires.

---

## 6. RBAC: why the Sensor can submit workflows

**File:** `sensor-rbac.yaml`

The Sensor runs as ServiceAccount **`operate-workflow-sa`** in `argo-events`. To create Workflows (and read WorkflowTemplates), that ServiceAccount needs permissions.

```yaml
# ClusterRole: what the SA is allowed to do
rules:
- apiGroups: [argoproj.io]
  resources: [workflows, workflowtemplates]
  verbs: [create, get, list, watch, update, patch, delete]

# ClusterRoleBinding: who gets that role
subjects:
- kind: ServiceAccount
  name: operate-workflow-sa
  namespace: argo-events
```

Without this, the Sensor would get “forbidden” when trying to submit the Workflow from `vote-ci-template`.

---

## 7. Summary diagram and file map

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│  argo-events namespace                                                                   │
│  ┌─────────────────────┐    POST /github     ┌─────────────────────────────────────┐   │
│  │ CronJob             │ ─────────────────► │ EventSource "webhook"                │   │
│  │ github-polling-job  │                     │ → Service: webhook-eventsource-svc  │   │
│  │ (poller-cronjob)    │                     │   :12000                             │   │
│  └─────────────────────┘                     └──────────────────┬──────────────────┘   │
│           │                                                    │                        │
│           │                                                    │ event "github"        │
│           │                                                    ▼                        │
│           │                                          ┌─────────────────────────────────┐│
│           │                                          │ Sensor "polling-sensor"         ││
│           │                                          │ SA: operate-workflow-sa         ││
│           │                                          │ trigger: submit-from template  ││
│           │                                          └──────────────────┬──────────────┘│
│           │                                                             │               │
└───────────┼─────────────────────────────────────────────────────────────┼───────────────┘
            │                                                             │
            │  poller-cronjob.yaml                                        │  sensor.yaml
            │  webhook-eventsource.yaml                                  │  sensor-rbac.yaml
            │                                                             │
            │                                                             │ submit Workflow
            │                                                             ▼
            │  ┌─────────────────────────────────────────────────────────────────────┐
            │  │ argo namespace                                                        │
            │  │  WorkflowTemplate: vote-ci-template  (vote-ci-template.yaml)         │
            │  │  → Workflow runs: checkout → build → push-harbor                      │
            │  └─────────────────────────────────────────────────────────────────────┘
```

| What you have | File | Purpose |
|---------------|------|--------|
| EventSource (webhook) | `webhook-eventsource.yaml` | Exposes HTTP server; Argo creates `webhook-eventsource-svc:12000` |
| Sensor | `sensor.yaml` | Listens for `webhook` / `github` events; submits Workflow from `vote-ci-template` |
| CronJob + PVC | `poller-cronjob.yaml` | Polls GitHub; POSTs to `webhook-eventsource-svc:12000/github` on new commit |
| WorkflowTemplate | `vote-ci-template.yaml` | CI pipeline: clone → build → push to Harbor |
| RBAC | `sensor-rbac.yaml` | Lets `operate-workflow-sa` create/watch Workflows and use WorkflowTemplates |

---

## 8. Quick reference: URLs and names

- **Webhook base URL (in-cluster):**  
  `http://webhook-eventsource-svc.argo-events.svc.cluster.local:12000`
- **GitHub webhook endpoint (used by CronJob):**  
  `http://webhook-eventsource-svc.argo-events.svc.cluster.local:12000/github`
- **EventSource name:** `webhook` → Service name: **`webhook-eventsource-svc`**
- **Event name** the Sensor depends on: **`github`**
- **Sensor name:** `polling-sensor`
- **WorkflowTemplate:** `vote-ci-template` (namespace: `argo`)
- **ServiceAccount used by Sensor:** `operate-workflow-sa` (namespace: `argo-events`)

---

## Optional: manual test of the webhook

You can trigger the same flow without waiting for the CronJob by posting to the webhook from inside the cluster:

```bash
kubectl run curl --rm -it --restart=Never --image=curlimages/curl -- \
  -X POST "http://webhook-eventsource-svc.argo-events.svc.cluster.local:12000/github" \
  -H "Content-Type: application/json" \
  -d '{}'
```

Then check that a new Workflow was created in the `argo` namespace (e.g. from the Argo Workflows UI or `kubectl get workflows -n argo`).

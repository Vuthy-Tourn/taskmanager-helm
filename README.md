# Helm Umbrella Chart — TaskManager

The umbrella chart is the **single entry point** to deploy the entire TaskManager stack
(Next.js frontend + Spring Boot backend + PostgreSQL) into Kubernetes with one command.

---

## Chart Structure

```
helm/
└── umbrella-chart                  ← You deploy this
    ├── Chart.yaml                  ← Declares frontend/backend/postgresql as dependencies
    ├── charts
    │   ├── backend/                ← Child chart (Deployment + Service + HPA)
    │   ├── frontend/               ← Child chart (Deployment + Service + Ingress + HPA)
    │   └── postgresql/             ← Child chart (StatefulSet + PVC + Service)
    ├── templates
    │   ├── NOTES.txt
    │   ├── _helpers.tpl
    │   ├── deployment.yaml
    │   ├── hpa.yaml
    │   ├── ingress.yaml
    │   ├── service.yaml
    │   └──serviceaccount.yaml
    ├── values-prod.yaml            ← Single file to configure the whole stack
    └── values-staging.yaml         ← Staging overrides
```

---

## Prerequisites

- Kubernetes cluster (v1.25+)
- Helm 3.x installed
- `kubectl` configured and pointing at your cluster
- Nginx Ingress Controller installed in cluster
- A Kubernetes secret named `db-secret` already created (see below)

---

## values.yaml Reference

All child charts are configured from a single `values.yaml`.
The top-level key matches the child chart name.

```yaml
# ── Frontend ─────────────────────────────────────────────────
frontend:
  replicaCount: 2

  image:
    repository: ghcr.io/YOUR_ORG/taskmanager-frontend
    tag: "latest"           # overridden by Jenkins on every deploy

  ingress:
    enabled: true
    className: nginx
    host: app.example.com   # your public domain

  env:
    NEXT_PUBLIC_API_URL: "http://taskmanager-backend:8080"

# ── Backend ──────────────────────────────────────────────────
backend:
  replicaCount: 2

  image:
    repository: ghcr.io/YOUR_ORG/taskmanager-backend
    tag: "latest"

  env:
    DB_HOST: "taskmanager-postgresql"   # K8s service name
    DB_PORT: "5432"
    DB_NAME: "taskdb"

  existingSecret: "db-secret"           # reads DB_USER + DB_PASSWORD from here

# ── PostgreSQL ───────────────────────────────────────────────
postgresql:
  auth:
    username: "postgres"
    database: "taskdb"
    existingSecret: "db-secret"         # reads DB_PASSWORD from here

  storage:
    size: 5Gi
```

> **Note:** The backend has **no Ingress**. It is a `ClusterIP` service only reachable
> inside the cluster. The frontend calls it via the internal DNS name
> `taskmanager-backend:8080`. This is intentional — the backend is not exposed to the internet.

---

## Useful Commands

```bash
# Check release status
helm status taskmanager

# See all deployed values
helm get values taskmanager

# List all releases
helm list

# Dry-run to preview changes before applying
helm upgrade --install taskmanager helm/umbrella \
  --reuse-values \
  --dry-run

# Render templates locally (no cluster needed)
helm template taskmanager helm/umbrella 

# Rollback to previous release
helm rollback taskmanager

# Rollback to a specific revision
helm rollback taskmanager 2

# View release history
helm history taskmanager

# Uninstall (keeps PVC by default)
helm uninstall taskmanager

# Delete the PVC too (WARNING: destroys database data)
kubectl delete pvc -l app.kubernetes.io/instance=taskmanager
```

---

## How --atomic and --reuse-values Work Together

| Flag | Purpose |
|------|---------|
| `--atomic` | Automatically rolls back if the upgrade fails or pods don't become ready |
| `--reuse-values` | Keeps all existing values and only applies what you pass via `--set` |
| `--wait` | Waits until all pods are Running and Ready before marking success |
| `--timeout 5m0s` | How long to wait before considering the deploy failed |

Jenkins uses all four flags on every deploy, so a failed rollout automatically
rolls back to the last good release without manual intervention.

---

## Troubleshooting

**Dependency build fails**
```bash
# Delete the charts/ folder and rebuild
rm -rf helm/umbrella/charts helm/umbrella/Chart.lock
helm dependency build helm/umbrella
```

**Pods stuck in ImagePullBackOff**
```bash
# Check image name and tag are correct
kubectl describe pod -l app.kubernetes.io/name=frontend

# Verify registry credentials exist
kubectl get secret registry-credentials
```

**Backend can't connect to PostgreSQL**
```bash
# Check db-secret exists with correct keys
kubectl get secret db-secret -o jsonpath='{.data}' | base64 -d

# Check PostgreSQL pod is ready
kubectl get pods -l app.kubernetes.io/name=postgresql
```

**Ingress not routing traffic**
```bash
# Check ingress is created
kubectl get ingress

# Confirm nginx ingress controller is running
kubectl get pods -n ingress-nginx
```
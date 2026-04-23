# 🚀 next-kubernetes

Production-ready **Next.js 16** app containerised with a lean multi-stage Docker build and deployed to **Google Kubernetes Engine (GKE)** via Kustomize.

This repo is a reference architecture for shipping a Next.js frontend to production on Kubernetes — covering image optimisation, non-root container security, resource budgeting, and a versioned CI-friendly release workflow.

---

## 🧰 Stack

| Layer | Tech | Why |
|---|---|---|
| 🖼️ Framework | Next.js 16 — `standalone` output | Emits a self-contained `server.js` with no `node_modules` needed at runtime |
| ⚙️ Runtime | Node.js 24 Alpine | Smallest official Node image; ~194 MB final image |
| 📦 Package manager | pnpm (via corepack) | Faster installs, strict hoisting, deterministic lockfile |
| 🎨 Styling | Tailwind CSS v4 | Zero-runtime utility CSS |
| 🐳 Container | Docker multi-stage build | Separates install / build / run concerns; build artefacts never leak into the runner |
| ☸️ Orchestration | Kubernetes + Kustomize | Declarative manifests, easy overlay patching without Helm |
| 🗂️ Registry | Google Artifact Registry | Private registry co-located with GKE for fast pulls |

---

## ✅ Prerequisites

Before you begin, make sure you have:

- **Node.js ≥ 20** + pnpm (`npm i -g pnpm` or `corepack enable pnpm`)
- **Docker** Desktop or Docker Engine
- **`kubectl`** configured against your cluster (`gcloud container clusters get-credentials …`)
- **`gcloud`** CLI authenticated (`gcloud auth configure-docker asia-southeast1-docker.pkg.dev`)

---

## 💻 Local development

```bash
pnpm install       # install dependencies
pnpm dev           # starts dev server at http://localhost:3000 with Fast Refresh
pnpm build         # production build (outputs to .next/)
pnpm start         # serve the production build locally
```

---

## 🐳 Docker

### 🤔 Why a multi-stage build?

The Dockerfile has **3 named stages** to keep the final image as small and secure as possible:

| Stage | Base image | Purpose |
|---|---|---|
| `deps` | `node:24.13.0-slim` | Install dependencies only; leverages BuildKit layer cache for the pnpm store |
| `builder` | `node:24.13.0-slim` | Run `next build`; produces `.next/standalone` + `.next/static` |
| `runner` | `node:24-alpine` | Final ~194 MB image — copies only the standalone bundle, nothing else |

🔒 **Security decisions in the runner stage:**
- Runs as the built-in **non-root `node` user** — no `--privileged`, no `root`
- Only compiled output is present — no source files, no dev dependencies

### 🧪 Run with Docker Compose (recommended for local production testing)

```bash
docker compose up --build
# ✅ App available at http://localhost:3000
# Ctrl-C to stop; add -d to run in background
```

> `compose.yml` passes the same `NODE_ENV=production` and `PORT=3000` env vars that the Kubernetes deployment uses, so behaviour is identical to production.

### 🔨 Build the image manually

```bash
bash scripts/build-docker.sh
# Tags the image as:
# <YOUR_REGISTRY>/<YOUR_PROJECT>/<YOUR_IMAGE>:<version>
# 📌 Version is read from package.json → "version" field automatically
```

---

## ☸️ Kubernetes deployment

### 🗺️ How it works

```
scripts/build-docker.sh    →  🔨 builds & tags the image
scripts/push-artifact.sh   →  📤 pushes to Google Artifact Registry
kubectl apply -k manifests/ →  🚀 creates/updates Deployment + Service on GKE
```

### 📋 Manifest overview

| File | Kind | Description |
|---|---|---|
| `manifests/nextjs-app.yaml` | `Deployment` | Runs **2 replicas** of the Next.js container. Requests 300 m CPU / 500 Mi RAM; limits 500 m CPU / 1 Gi RAM. |
| `manifests/nextjs-svc.yaml` | `Service` | `LoadBalancer` type — provisions a GCP external load balancer and exposes port 3000. |
| `manifests/kustomization.yaml` | `Kustomization` | Ties the above two resources together and applies `app: nextjs-app` labels to both. |

### 📊 Resource limits explained

```yaml
resources:
  requests:
    cpu: "300m"      # scheduler uses this to place the pod on a node
    memory: "500Mi"  # guaranteed memory floor
  limits:
    cpu: "500m"      # pod is throttled (not killed) if it exceeds this
    memory: "1Gi"    # ⚠️ pod is OOM-killed if it exceeds this — tune carefully
```

### 🚢 First deploy

```bash
# 1️⃣ Authenticate Docker with Artifact Registry (one-time)
gcloud auth configure-docker asia-southeast1-docker.pkg.dev

# 2️⃣ Build the production image
bash scripts/build-docker.sh

# 3️⃣ Push to Google Artifact Registry
bash scripts/push-artifact.sh

# 4️⃣ Apply all manifests via Kustomize
kubectl apply -k manifests/

# 5️⃣ Watch the rollout
kubectl rollout status deployment/nextjs-app
```

### 🔁 Releasing a new version

1. Bump `"version"` in `package.json` (e.g. `"0.1.0"` → `"0.2.0"`)
2. Rebuild and push:

```bash
bash scripts/build-docker.sh
bash scripts/push-artifact.sh
```

3. Update the image tag in `manifests/nextjs-app.yaml`:

```yaml
image: <YOUR_REGISTRY>/<YOUR_PROJECT>/<YOUR_IMAGE>:0.2.0
```

4. Apply and confirm:

```bash
kubectl apply -k manifests/
kubectl rollout status deployment/nextjs-app   # ✅ confirms zero-downtime rollout
```

> 💡 **Tip:** Kubernetes performs a **rolling update** by default — new pods come up before old ones are terminated, so there is no downtime.

### ⏪ Rollback

Made a bad deploy? One command to go back:

```bash
kubectl rollout undo deployment/nextjs-app
```

---

## 📁 Project structure

```
app/
  layout.tsx          Root layout (fonts, global CSS)
  page.tsx            Home page
  globals.css         Tailwind base styles

manifests/
  nextjs-app.yaml     Kubernetes Deployment
  nextjs-svc.yaml     Kubernetes Service (LoadBalancer)
  kustomization.yaml  Kustomize root — ties resources together

scripts/
  build-docker.sh     Build & tag Docker image (reads version from package.json)
  push-artifact.sh    Push image to Google Artifact Registry

Dockerfile            Multi-stage production image (deps → builder → runner)
compose.yml           Local production preview via Docker Compose
next.config.ts        Next.js config — enables standalone output
```

---

## 🌱 Environment variables

The following variables are set inside the Docker image and Kubernetes manifests:

| Variable | Value | Purpose |
|---|---|---|
| `NODE_ENV` | `production` | Enables Next.js production optimisations |
| `PORT` | `3000` | Port the server listens on |
| `HOSTNAME` | `0.0.0.0` | Binds to all interfaces (required inside containers) |

> 🔐 To add secrets (API keys, DB URLs), use a Kubernetes `Secret` and mount it as an env var — **never bake secrets into the image.**

---

## 🪙 Token-efficient AI workflow with rtk

This repo ships with [`rtk`](https://github.com/rullyrull/rtk) — a CLI proxy that filters and compresses command outputs before they reach your AI assistant context window, saving **60–90% tokens** on typical shell commands.

### Why it matters

Every time you paste a raw `git log`, `docker ps`, or `kubectl get pods` output into your AI chat, you burn hundreds of tokens on noise. `rtk` strips that noise at the source.

### Setup

```bash
# Initialise config in this repo
rtk init
```

### Usage

Simply prefix any shell command with `rtk`:

```bash
# Instead of:             Use:
git status                rtk git status
git log -10               rtk git log -10
docker ps                 rtk docker ps
kubectl get pods          rtk kubectl get pods
kubectl rollout status …  rtk kubectl rollout status …
```

### Check your savings

```bash
rtk gain           # token savings dashboard
rtk gain --history # per-command breakdown
```

> 💡 When working with an AI assistant (Copilot, Claude, ChatGPT), always use `rtk` — your context window will thank you.

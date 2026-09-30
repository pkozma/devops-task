# Formlabs DevOps home assignment

This repository contains a home assignment code for DevOps applicants for Formlabs.

See all open jobs at https://careers.formlabs.com/


## Task

0. Fork this repo.
1. Create a deployable docker image for the application.
    - Feel free to switch up technologies. For example you can use `buildah` instead of Docker.
2. Create a Kubernetes deployment and service for the application.
    - Just aim for the simplest setup, no ingress deployment is needed. Feel free to use Helm.
    - You can use [Minikube](https://minikube.sigs.k8s.io/docs/start/) or [k3s](https://k3s.io/) or any other Kubernetes distribution you are familiar with.
3. Create automation to build, test and deploy the application when a change happens in git.
    - Feel free to switch up technologies. For example you can use an Ansible playbook or a Jenkins pipeline.
4. Send us the fork where you did your work.

### Notes

- Explain as much as possible in the commit message(s) and/or comments if needed. See more on commit messages [here](https://chris.beams.io/posts/git-commit/).
- It would be great if you'd also write about why you choose a certain technology if there are alternatives to consider.


## Solution

| Path | What |
|------|------|
| [`Dockerfile`](Dockerfile) | Multi-stage image: `base` → `test` (runs unit tests) → final runtime image |
| [`chart/`](chart/) | Helm chart: Deployment, Service and a `helm test` smoke test |
| [`.github/workflows/ci.yml`](.github/workflows/ci.yml) | CI/CD: test → build → push → deploy → smoke test |

### Run it locally

Requires Docker, [kind](https://kind.sigs.k8s.io/) and Helm (Minikube works the same way with `minikube image load`).

```sh
docker build --target test .            # run the unit tests inside the image
docker build -t helloapp:dev .

kind create cluster
kind load docker-image helloapp:dev
helm upgrade --install helloapp ./chart --set image.tag=dev --wait
helm test helloapp --logs

kubectl port-forward svc/helloapp 8080:80
curl localhost:8080
```

### Pipeline

- **Pull request:** unit tests run in the `test` image stage, then the runtime image is built. Nothing is pushed or deployed.
- **Push to `master`:** the image is also pushed to GHCR as `ghcr.io/<owner>/devops-task:<git-sha>`, then the `deploy` job
  creates a kind cluster, installs the chart with `helm upgrade --install --wait --atomic`, and runs `helm test`.

### Decisions

- **Tests run inside the image.** The `test` stage reuses the exact layers of the runtime image, so tests run against the
  same Python and dependencies that ship. CI and local runs use the same `docker build --target test` command.
- **`python:3.13-slim`.** Debian-based, so the pip wheels just work (Alpine's musl often means building from source).
  3.13 is the newest Python that the pinned Flask 2.0.1 supports; it uses `ast.Str`, which Python 3.14 removed.
  Distroless would be smaller, but has no shell for debugging and ships its own Python version.
- **gunicorn bumped to 26.2.0.** 20.1.0 imports `pkg_resources`, which isn't installed on Python ≥ 3.12 slim images. It also
  has known request smuggling CVEs. I kept the application's own dependencies (Flask, Werkzeug) as they were.
- **Hardened by default.** The container runs as UID 65534 with a read-only root filesystem, all capabilities dropped and
  the `RuntimeDefault` seccomp profile, so it passes the `restricted` Pod Security Standard. That's why gunicorn uses
  `--worker-tmp-dir=/dev/shm` and `--no-control-socket`: it can't write to `/tmp` or `$HOME`.
- **Helm over plain manifests or Kustomize.** The only thing that changes per deploy is the image tag, and
  `--set image.tag=<sha>` handles it cleanly. `--atomic` rolls back a failed rollout, and `helm test` gives a smoke test
  that works both in CI and on a laptop. `image.tag` is required, so nothing is ever deployed as `:latest` by accident.
- **GitHub Actions over Jenkins or Ansible.** The code already lives on GitHub, so there's no CI server to run or maintain.
  The steps are plain `docker`, `helm` and `kind` commands (preinstalled on the runner), so they're easy to reproduce
  locally or port to another CI system.
- **Images tagged by git SHA.** Tags are immutable, and you can always trace a running pod back to the commit it came from.
- **Deploy target is an ephemeral kind cluster.** The assignment has no shared cluster. The deploy job still does
  everything a real deploy does: the cluster pulls from the registry with a pull secret, Helm waits for the rollout, and a
  smoke test runs against the Service. To target a real cluster, replace the `kind create cluster` step with a kubeconfig
  from a repository secret (or, better, OIDC-based cloud auth).

### What I'd add for production

- GitOps (e.g. Argo CD) instead of pushing from CI: CI bumps the image tag in a config repo, and the cluster pulls the change.
- Image scanning (e.g. Trivy) in CI, and dependency updates via Dependabot or Renovate, with GitHub Actions pinned to commit SHAs.
- A dedicated `/healthz` endpoint for probes, plus a PodDisruptionBudget, HPA and Ingress as traffic requires.
- Upgrading Flask and Werkzeug. The pinned 2.0.1 versions have known CVEs, but upgrading them is an application change.

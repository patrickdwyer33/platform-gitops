# platform-gitops

Public GitOps repo reconciled by Argo CD into the `eks-substrate` cluster (app-of-apps).
- `apps/` — Argo CD Application manifests (the app-of-apps children).
- `infra/crossplane-config/` — Crossplane providers, ProviderConfig, and the ECR repository.
- `workloads/` — application manifests (Kustomize base + overlays).

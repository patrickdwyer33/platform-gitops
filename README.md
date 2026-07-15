# platform-gitops

Public GitOps repo reconciled by Argo CD into the `eks-substrate` cluster (app-of-apps).
- `apps/` — Argo CD Application manifests (the app-of-apps children).
- `infra/crossplane-config/` — Crossplane core: the `function-patch-and-transform` package, the `provider-aws-ecr` Provider (+ its IRSA `DeploymentRuntimeConfig`), and the `ProviderConfig`.
- `infra/platform/` — the `AppInfra` platform API: a `cloud.patrickdwyer.com/v1alpha1` XRD plus its Composition, built with `function-patch-and-transform`. Each `AppInfra` composes an ECR repository and a lifecycle policy.
- `infra/app-infra/` — one small `AppInfra` claim per site (`patrickdwyer-com.yaml`, `cwdmdc.yaml`), each producing that site's ECR repo + lifecycle policy via the platform API above.
- `workloads/<site>/` — Kustomize base plus `dev`/`prod` overlays per site. Only `dev` has a matching Argo CD Application in `apps/`; `prod` overlays are authored but deliberately left undeployed (see the header comment in each `overlays/prod/kustomization.yaml`).

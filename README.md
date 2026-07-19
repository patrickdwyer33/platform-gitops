# platform-gitops

Public GitOps repo reconciled by Argo CD into the `eks-substrate` cluster (app-of-apps).

> ### ⚠️ This belongs to AWS account `048751351548` (Patrick's personal account) — and only ever that one.
>
> The ARNs and ECR registry URLs below are hardcoded to it. On 2026-07-15 this whole substrate
> was mistakenly built in a **company** account because a `[default]` AWS profile silently pointed
> there and nothing objected. It was destroyed and rebuilt here. Before touching the cluster:
>
> ```bash
> aws-switch-personal    # AWS_PROFILE=personal -> 048751351548, prints the account
> aws-who                # which account am I in?
> ```
>
> `personal` is keyless (`aws login`; temporary creds, ≤12h). If credentials are missing or
> expired: `aws login --profile personal`. Guards live in the `aws-infra` repo —
> see its README's "AWS accounts" section.
## Layout

- `apps/` — Argo CD Application manifests (the app-of-apps children): the ingress stack (`aws-load-balancer-controller`, `cert-manager`, `cert-manager-config`, `traefik`) and one `<site>-dev` app per site. No prod apps exist (see below).
- `workloads/<site>/` — Kustomize base plus `dev`/`prod` overlays per site. Each overlay pins an ECR image by `newTag`. Only `dev` has a matching Argo CD Application in `apps/`; `prod` overlays are authored but deliberately left undeployed (see the header comment in each `overlays/prod/kustomization.yaml`).
- `deploy` — the deploy tool (bash). `./deploy <site> [<sha>]` picks a built image from ECR (the menu shows each tag's commit message), adds a `deployed-<env>-<sha>` protective tag, rewrites the dev overlay's `newTag`, and commits + pushes — Argo CD then rolls dev. `deploy.test.sh` unit-tests its `bump_tag`. **This is the only supported deploy path** — hand-editing an overlay skips the lifecycle protection (see below).

## Where images come from

This repo does **not** build images. Each site's own repo (`patrickdwyer33/<site>`) builds and pushes `<ecr-repo>:<git-sha>` to ECR on push to `main`, keyless via GitHub OIDC (the `github-ecr-push` role — defined in `aws-infra/substrate/github-ci.tf`). **CI stops at "image in ECR"; it never writes to this repo.** Promotion is the deliberate, manual `./deploy` step above.

The ECR repos and their lifecycle policy are Terraform (`aws-infra/resources/ecr.tf`) — **Crossplane was removed**; there is no longer an `infra/` tree here. The lifecycle policy keeps images tagged `deployed-prod-*` / `deployed-dev-*` (per-env budgets) shielded from expiry, which is why the running image must carry a `deployed-<env>-<sha>` tag — added only by the `deploy` script.

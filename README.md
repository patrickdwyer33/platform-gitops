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

- `apps/` — Argo CD Application manifests (the app-of-apps children): the ingress stack (`aws-load-balancer-controller`, `cert-manager`, `cert-manager-config`, `traefik`), the secrets stack (`storage`, `vault`, `vault-config-operator`, `external-secrets`, `vault-config` — see **Secrets** below), plus per-site apps: every site has a `-dev` app; draw and todo also run `-prod` apps. The static sites' prod overlays stay authored-but-undeployed (no `apps/<site>-prod.yaml`).
- `workloads/<site>/` — Kustomize base plus `dev`/`prod` overlays per site. Each overlay pins an ECR image by `newTag`. `draw` and `todo` have matching Argo CD Applications in `apps/` for both `dev` and `prod`; the static sites remain dev-only — their `prod` overlays are authored but deliberately left undeployed (see the header comment in each `overlays/prod/kustomization.yaml`).
- `vault-bootstrap` — one-time Vault ceremonies (bash): `grant` wires the config operator's admin role after `vault operator init`; `migrate` was the original todo-secrets cutover. Day-to-day secret writes don't use it — see **Secrets** below.
- `deploy` — the deploy tool (bash). `./deploy <site> [<sha>]` picks a built image from ECR (the menu shows each tag's commit message), adds a `deployed-<env>-<sha>` protective tag, rewrites the dev overlay's `newTag`, and commits + pushes — Argo CD then rolls dev. `deploy.test.sh` unit-tests its `bump_tag`. **This is the only supported deploy path** — hand-editing an overlay skips the lifecycle protection (see below).

## Secrets

Truth lives in **Vault** (in-cluster, single replica, Raft on a gp3 PVC, KMS auto-unseal so
Spot reclaims self-heal); workloads never talk to it. **External Secrets Operator** materializes
Vault paths (`secret/<app>/<env>`) into ordinary k8s Secrets via each overlay's
`externalsecret.yaml` — so app Deployments keep their plain `envFrom` contract, and a Vault
outage is a non-event (the synced Secret persists). Vault's *configuration* (KV mount, policies,
auth roles) is GitOps too: CRs in `infra/vault-config/`, reconciled into Vault API calls by the
**vault-config-operator**. AWS-side pieces (unseal KMS key, IRSA roles, EBS CSI addon) are
Terraform in `aws-infra` (`bootstrap/vault-unseal-key.tf`, `substrate/{vault-irsa,ebs-csi}.tf`).

Three things are deliberately manual (the irreducible residue — everything else reconciles):

1. `vault operator init` — once per Vault lifetime; recovery keys + root token go to the
   password manager, nowhere else.
2. `./vault-bootstrap grant` — the hand-cranked first turn: enables k8s auth and creates the
   config operator's admin role using the root token. After it, git owns Vault config.
3. Secret **values** — `vault kv put secret/<app>/<env> ...` (or `./vault-bootstrap migrate`
   for the original todo cutover). Git carries the *shape* of secrets, never their contents —
   this repo is public.

Rotation = write new values to Vault; ESO refreshes within the hour (`kubectl annotate
externalsecret ... force-sync=$(date +%s)` to hurry). No standing write credential exists —
mint a ≤15-min one first via the git-managed `secrets-admin` role:
`TOKEN=$(kubectl create token vault-admin -n vault-admin --duration=10m)` then
`kubectl -n vault exec -i vault-0 -- vault write -field=token auth/kubernetes/login
role=secrets-admin jwt="$TOKEN"` → use as `VAULT_TOKEN` for `vault kv put`. Full-teardown posture is
**secrets-are-cattle**: Vault data dies with the cluster (teardown.sh deletes the PVC on
purpose) and is re-created from git + the shared password + cheap re-enrollment; the KMS key
survives in `bootstrap/` so any raft snapshot ever taken stays restorable.

Key-ceremony gotcha (bit us 2026-08-04): Vault ≥2.0 authenticates the rekey and
generate-root endpoints by default. To run one (e.g. `vault operator rekey -target=recovery`),
temporarily add `enable_unauthenticated_access = ["rekey"]` to the server config in
`apps/vault.yaml`, restart the pod, do the ceremony **in a real terminal** (key material must
never land in a session transcript), then revert. Recovery keys are 3-of-5 Shamir shares —
save all five; fewer than three saved is the same as zero.

## Where images come from

This repo does **not** build images. Each site's own repo (`patrickdwyer33/<site>`) builds and pushes `<ecr-repo>:<git-sha>` to ECR on push to `main`, keyless via GitHub OIDC (the `github-ecr-push` role — defined in `aws-infra/substrate/github-ci.tf`). **CI stops at "image in ECR"; it never writes to this repo.** Promotion is the deliberate, manual `./deploy` step above.

The ECR repos and their lifecycle policy are Terraform (`aws-infra/resources/ecr.tf`) — **Crossplane was removed**; there is no longer an `infra/` tree here. The lifecycle policy keeps images tagged `deployed-prod-*` / `deployed-dev-*` (per-env budgets) shielded from expiry, which is why the running image must carry a `deployed-<env>-<sha>` tag — added only by the `deploy` script.

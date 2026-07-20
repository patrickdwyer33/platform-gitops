#!/usr/bin/env bash
# Unit test for the deploy script's pure bump_tag rewrite.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./deploy   # defines functions; guarded so main does NOT run when sourced

fixture="$(mktemp)"
cat > "$fixture" <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
images:
  - name: patrickdwyer-com
    newName: 048751351548.dkr.ecr.us-east-2.amazonaws.com/patrickdwyer-com
    newTag: 561e5d2
YAML

bump_tag "$fixture" abc1234

fail=0
grep -q '^    newTag: "abc1234"$' "$fixture" || { echo "FAIL: newTag not rewritten (quoted)"; fail=1; }
grep -q '561e5d2' "$fixture" && { echo "FAIL: old tag still present"; fail=1; }

# All-digit SHA must be quoted so kustomize/YAML treats it as a string, not a number.
bump_tag "$fixture" 0089514
grep -q '^    newTag: "0089514"$' "$fixture" || { echo "FAIL: all-digit tag not quoted"; fail=1; }
grep -q 'newName: 048751351548.dkr.ecr.us-east-2.amazonaws.com/patrickdwyer-com' "$fixture" \
  || { echo "FAIL: newName line corrupted"; fail=1; }

rm -f "$fixture"
[ "$fail" -eq 0 ] && echo "PASS" || exit 1

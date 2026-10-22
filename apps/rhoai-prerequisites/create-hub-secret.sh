#!/usr/bin/env bash

set -Eeuo pipefail

namespace="${NAMESPACE:-rhoai-prerequisites}"
context="${HUB_CONTEXT:-}"

usage() {
  cat <<'EOF'
Create or update the hub-side RHOAI Quay pull Secret used by the
rhoai-prerequisites ACM policy.

Required environment:
  RHOAI_QUAY_PULL_SECRET  Base64-encoded "username:password" for quay.io/rhoai.

Optional environment:
  HUB_CONTEXT             Hub kubeconfig context.
  NAMESPACE               Hub namespace; defaults to rhoai-prerequisites.
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

[ -n "${RHOAI_QUAY_PULL_SECRET:-}" ] || {
  usage >&2
  die "RHOAI_QUAY_PULL_SECRET must be set"
}

for required_command in kubectl jq base64; do
  command -v "$required_command" >/dev/null 2>&1 || die "required command not found: $required_command"
done

decoded_credentials="$(printf '%s' "$RHOAI_QUAY_PULL_SECRET" | base64 -d 2>/dev/null || true)"
[ -n "$decoded_credentials" ] || die "RHOAI_QUAY_PULL_SECRET is not valid base64"
[[ "$decoded_credentials" == *:* ]] || die "decoded RHOAI_QUAY_PULL_SECRET must be username:password"

kubectl_args=()
if [ -n "$context" ]; then
  kubectl_args+=(--context "$context")
fi

if ! kubectl "${kubectl_args[@]}" get namespace "$namespace" >/dev/null 2>&1; then
  kubectl "${kubectl_args[@]}" create namespace "$namespace"
fi

docker_config_json="$(jq -n '{auths: {"quay.io": {auth: env.RHOAI_QUAY_PULL_SECRET}}}')"
docker_config_json_b64="$(printf '%s' "$docker_config_json" | base64 -w0)"

kubectl "${kubectl_args[@]}" apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: rhoai-quay-pull-secret
  namespace: $namespace
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: $docker_config_json_b64
EOF

printf 'Created or updated %s/%s.\n' "$namespace" rhoai-quay-pull-secret

#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: docs/maas-oidc-smoke/scripts/maas-oidc-smoke.sh USER

USER must be "alice" or "bob".

Required environment:
  REDIRECT_URI    Redirect URI registered for the OIDC client.

Environment overrides:
  GATEWAY_HOST          MaaS Gateway hostname. Defaults to the Gateway status address.
  GATEWAY_PROTOCOL      Gateway protocol. Defaults to http.
  KEYCLOAK_NAMESPACE    Namespace containing the Keycloak secret. Defaults to maas-db.
  KEYCLOAK_SECRET_NAME  Secret containing Keycloak runtime values. Defaults to keycloak-secrets.
  GATEWAY_NAMESPACE     Namespace containing the MaaS Gateway. Defaults to openshift-ingress.
  GATEWAY_NAME          MaaS Gateway resource name. Defaults to maas-default-gateway.
  OIDC_CLIENT_ID        OIDC client ID. Defaults to tenant-demo.
EOF
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

print_section() {
  printf '\n== %s ==\n' "$1"
}

redirect_location() {
  awk 'tolower($1)=="location:" {
    sub(/^[Ll]ocation: */, "")
    sub(/\r$/, "")
    print
    exit
  }' "$1"
}

form_action() {
  sed -n 's/.*action="\([^"]*\)".*/\1/p' "$1" | head -1 | sed 's/&amp;/\&/g'
}

user="${1:-}"
[[ -n "$user" ]] || { usage >&2; exit 2; }
if [[ "$user" == "--help" || "$user" == "-h" ]]; then
  usage
  exit 0
fi

case "$user" in
  alice)
    broker_hint=grid-tenant-1
    password_key=GRID_TENANT_1_TEST_USER_PASSWORD
    ;;
  bob)
    broker_hint=grid-tenant-2
    password_key=GRID_TENANT_2_TEST_USER_PASSWORD
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

for cmd in kubectl curl jq sed awk; do
  require_cmd "$cmd"
done

keycloak_namespace="${KEYCLOAK_NAMESPACE:-maas-db}"
keycloak_secret_name="${KEYCLOAK_SECRET_NAME:-keycloak-secrets}"
gateway_namespace="${GATEWAY_NAMESPACE:-openshift-ingress}"
gateway_name="${GATEWAY_NAME:-maas-default-gateway}"
client_id="${OIDC_CLIENT_ID:-tenant-demo}"
gateway_protocol="${GATEWAY_PROTOCOL:-http}"
redirect_uri="${REDIRECT_URI:-}"

[[ -n "$redirect_uri" ]] || fail "REDIRECT_URI must be set to the registered OIDC redirect URI"
case "$gateway_protocol" in
  http|https) ;;
  *) fail "GATEWAY_PROTOCOL must be http or https" ;;
esac

keycloak_url=$(
  kubectl get secret "$keycloak_secret_name" -n "$keycloak_namespace" \
    -o jsonpath='{.data.KEYCLOAK_PUBLIC_URL}' | base64 -d
)
client_secret=$(
  kubectl get secret "$keycloak_secret_name" -n "$keycloak_namespace" \
    -o jsonpath='{.data.KEYCLOAK_CLIENT_SECRET}' | base64 -d
)
password=$(
  kubectl get secret "$keycloak_secret_name" -n "$keycloak_namespace" \
    -o jsonpath="{.data.$password_key}" | base64 -d
)

[[ -n "$keycloak_url" ]] || fail "KEYCLOAK_PUBLIC_URL is empty in $keycloak_secret_name"
[[ -n "$client_secret" ]] || fail "KEYCLOAK_CLIENT_SECRET is empty in $keycloak_secret_name"
[[ -n "$password" ]] || fail "$password_key is empty in $keycloak_secret_name"
keycloak_url="${keycloak_url%/}"

if [[ -n "${GATEWAY_HOST:-}" ]]; then
  gateway_host="$GATEWAY_HOST"
else
  gateway_host=$(
    kubectl get gateway "$gateway_name" -n "$gateway_namespace" \
      -o jsonpath='{.status.addresses[0].value}'
  )
fi
[[ -n "$gateway_host" ]] || fail "could not determine the MaaS Gateway hostname"
base_url="${gateway_protocol}://${gateway_host}"

umask 077
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
cookie_jar="$tmpdir/cookies.txt"
headers="$tmpdir/headers"
body="$tmpdir/body"

print_section "Runtime configuration"
printf '  user: %s\n' "$user"
printf '  Keycloak issuer: %s\n' "$keycloak_url/realms/saas"
printf '  Gateway: %s\n' "$base_url"
printf '  OIDC client: %s\n' "$client_id"
printf '  Redirect URI: %s\n' "$redirect_uri"

redirect_uri_encoded=$(jq -rn --arg value "$redirect_uri" '$value | @uri')
auth_url="$keycloak_url/realms/saas/protocol/openid-connect/auth?client_id=$client_id&redirect_uri=$redirect_uri_encoded&response_type=code&scope=openid%20profile%20email&kc_idp_hint=$broker_hint"

request_url="$auth_url"
while :; do
  curl -sS -k --max-time 20 \
    -b "$cookie_jar" -c "$cookie_jar" \
    -D "$headers" -o "$body" "$request_url"

  if grep -q '<form' "$body"; then
    break
  fi

  location=$(redirect_location "$headers")
  [[ -n "$location" ]] || fail "expected a login form or redirect from $request_url"
  request_url="$location"
done

action=$(form_action "$body")
[[ -n "$action" ]] || fail "could not extract the Keycloak login form action"

login_status=$(
  curl -sS -k --max-time 20 -X POST \
    -b "$cookie_jar" -c "$cookie_jar" \
    --data-urlencode "username=$user" \
    --data-urlencode "password=$password" \
    --data-urlencode 'credentialId=' \
    --data-urlencode 'login=Sign In' \
    -D "$headers" -o /dev/null -w '%{http_code}' "$action"
)
[[ "$login_status" == 2* || "$login_status" == 3* ]] || fail "Keycloak login returned HTTP $login_status"

location=$(redirect_location "$headers")
[[ -n "$location" ]] || fail "login did not return a redirect"

while [[ "$location" != "$redirect_uri"* ]]; do
  curl -sS -k --max-time 20 \
    -b "$cookie_jar" -c "$cookie_jar" \
    -D "$headers" -o /dev/null "$location"
  location=$(redirect_location "$headers")
  [[ -n "$location" ]] || fail "broker login stopped before the registered redirect URI"
done

code=$(printf '%s' "$location" | sed -n 's/.*[?&]code=\([^&]*\).*/\1/p')
[[ -n "$code" ]] || fail "the callback did not contain an authorization code"

token_response="$tmpdir/token-response.json"
token_status=$(
  curl -sS -k --max-time 20 -X POST \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data 'grant_type=authorization_code' \
    --data "client_id=$client_id" \
    --data-urlencode "client_secret=$client_secret" \
    --data-urlencode "code=$code" \
    --data-urlencode "redirect_uri=$redirect_uri" \
    -o "$token_response" -w '%{http_code}' \
    "$keycloak_url/realms/saas/protocol/openid-connect/token"
)

print_section "OIDC token exchange"
printf '  HTTP status: %s\n' "$token_status"
if [[ "$token_status" != 2* ]] || ! jq -e 'has("access_token") and (.token_type == "Bearer")' "$token_response" >/dev/null; then
  jq . "$token_response" >&2
  fail "token exchange failed"
fi

token_file="/tmp/maas-${user}-access-token"
jq -r '.access_token' "$token_response" > "$token_file"
claims="$tmpdir/claims.json"
jq -R 'split(".") | .[1] | @base64d | fromjson' "$token_file" > "$claims"

printf '  token file: %s\n' "$token_file"
printf '  subject: %s\n' "$(jq -r '.sub' "$claims")"
printf '  preferred username: %s\n' "$(jq -r '.preferred_username' "$claims")"
printf '  audience: %s\n' "$(jq -r '.aud | if type == "array" then join(", ") else . end' "$claims")"
printf '  authorized party: %s\n' "$(jq -r '.azp' "$claims")"

while IFS=$'\t' read -r organization roles; do
  printf '  organization: %s (roles: %s)\n' "$organization" "$roles"
done < <(jq -r '."https://redhat.com/maas/orgs"[]? | [.organization_id, (.roles // [] | join(", "))] | @tsv' "$claims")

mapfile -t groups < <(jq -r '.groups[]?' "$claims")
if (( ${#groups[@]} > 0 )); then
  printf '  groups:\n'
  for group in "${groups[@]}"; do
    printf '    - %s\n' "$group"
  done
fi

me_response="$tmpdir/me-response.json"
me_status=$(
  curl -sS --max-time 20 \
    -H "Authorization: Bearer $(cat "$token_file")" \
    -o "$me_response" -w '%{http_code}' \
    "$base_url/v1/me"
)

print_section "GET /v1/me"
printf '  HTTP status: %s\n' "$me_status"
if [[ "$me_status" != 2* ]]; then
  jq . "$me_response" >&2
  fail "/v1/me returned HTTP $me_status"
fi

printf '  user: %s (%s)\n' "$(jq -r '.name' "$me_response")" "$(jq -r '.preferred_username' "$me_response")"
printf '  email: %s\n' "$(jq -r '.email' "$me_response")"
while IFS=$'\t' read -r organization roles; do
  printf '  organization: %s (roles: %s)\n' "$organization" "$roles"
done < <(jq -r '."https://redhat.com/maas/orgs"[]? | [.organization_id, (.roles // [] | join(", "))] | @tsv' "$me_response")

subscriptions_response="$tmpdir/subscriptions-response.json"
subscriptions_status=$(
  curl -sS --max-time 20 \
    -H "Authorization: Bearer $(cat "$token_file")" \
    -o "$subscriptions_response" -w '%{http_code}' \
    "$base_url/v1/subscriptions"
)

print_section "GET /v1/subscriptions"
printf '  HTTP status: %s\n' "$subscriptions_status"
if [[ "$subscriptions_status" != 2* ]]; then
  jq . "$subscriptions_response" >&2
  fail "/v1/subscriptions returned HTTP $subscriptions_status"
fi

subscription_count=$(jq 'length' "$subscriptions_response")
printf '  subscription count: %s\n' "$subscription_count"
if (( subscription_count == 0 )); then
  printf '  subscriptions: none\n'
else
  while IFS=$'\t' read -r subscription roles organization models; do
    printf '  %s\n' "$subscription"
    printf '    organization: %s\n' "$organization"
    printf '    roles: %s\n' "$roles"
    printf '    models: %s\n' "$models"
  done < <(jq -r '.[] | [.subscription_id_header, (.roles // [] | join(", ")), (.organization_id // ""), (.model_refs // [] | map(.name) | join(", "))] | @tsv' "$subscriptions_response")
fi

api_key_id=""
if (( subscription_count > 0 )); then
  key_name="smoke-${user}-$(date +%s)"
  api_key_request=$(jq -n \
    --arg name "$key_name" \
    --arg user "$user" \
    '{
      name: $name,
      description: "Generated by the MaaS OIDC smoke test",
      expiresIn: "1h",
      ephemeral: true,
      labels: {
        smoke: "true",
        user: $user
      }
    }')

  api_key_response="$tmpdir/api-key-response.json"
  api_key_status=$(
    curl -sS --max-time 20 \
      -H "Authorization: Bearer $(cat "$token_file")" \
      -H 'Content-Type: application/json' \
      -d "$api_key_request" \
      -o "$api_key_response" -w '%{http_code}' \
      "$base_url/v1/api-keys"
  )

  print_section "POST /v1/api-keys"
  printf '  HTTP status: %s\n' "$api_key_status"
  if [[ "$api_key_status" != 2* ]] || ! jq -e 'has("key") and has("id") and has("keyPrefix") and has("expiresAt")' "$api_key_response" >/dev/null; then
    jq . "$api_key_response" >&2
    fail "API key creation failed"
  fi

  api_key_id=$(jq -r '.id' "$api_key_response")
  api_key_file="/tmp/maas-${user}-api-key"
  jq -r '.key' "$api_key_response" > "$api_key_file"
  printf '  id: %s\n' "$api_key_id"
  printf '  name: %s\n' "$key_name"
  printf '  prefix: %s\n' "$(jq -r '.keyPrefix' "$api_key_response")"
  printf '  subscription: %s\n' "$(jq -r '.subscription' "$api_key_response")"
  printf '  expires at: %s\n' "$(jq -r '.expiresAt' "$api_key_response")"
  printf '  key file: %s\n' "$api_key_file"
else
  print_section "POST /v1/api-keys"
  printf '  skipped: no accessible subscription\n'
fi

api_key_list_request=$(jq -n '{
  filters: {
    includeEphemeral: true
  },
  pagination: {
    limit: 10,
    offset: 0
  }
}')

api_key_list_response="$tmpdir/api-key-list-response.json"
api_key_list_status=$(
  curl -sS --max-time 20 \
    -H "Authorization: Bearer $(cat "$token_file")" \
    -H 'Content-Type: application/json' \
    -d "$api_key_list_request" \
    -o "$api_key_list_response" -w '%{http_code}' \
    "$base_url/v1/api-keys/search"
)

print_section "POST /v1/api-keys/search"
printf '  HTTP status: %s\n' "$api_key_list_status"
if [[ "$api_key_list_status" != 2* ]] || ! jq -e 'type == "object" and ((.data == null) or (.data | type == "array"))' "$api_key_list_response" >/dev/null; then
  jq . "$api_key_list_response" >&2
  fail "API key listing failed"
fi

api_key_count=$(jq '.data // [] | length' "$api_key_list_response")
printf '  key count: %s\n' "$api_key_count"
printf '  has more: %s\n' "$(jq -r '.has_more' "$api_key_list_response")"
if (( api_key_count == 0 )); then
  printf '  keys: none\n'
else
  printf '  keys:\n'
  while IFS=$'\t' read -r name id status expires ephemeral; do
    printf '    - %s\n' "$name"
    printf '        id: %s\n' "$id"
    printf '        status: %s\n' "$status"
    printf '        expires: %s\n' "$expires"
    printf '        ephemeral: %s\n' "$ephemeral"
  done < <(jq -r '(.data // [])[] | [.name, (.id // ""), (.status // ""), (.expirationDate // ""), ((.ephemeral // false) | tostring)] | @tsv' "$api_key_list_response")
fi

if [[ -n "$api_key_id" ]]; then
  jq -e --arg id "$api_key_id" 'any(.data[]?; .id == $id)' "$api_key_list_response" >/dev/null ||
    fail "the newly created API key was not returned by listing"
  printf '  newly created key: found\n'
fi

print_section "Smoke result"
printf '  result: passed\n'

# MaaS OIDC smoke test

This directory contains a browserless smoke test for the MaaS external-OIDC
flow through the single-broker `saas` realm.

## Prerequisites

- Access to the cluster through `kubectl`.
- `kubectl`, `curl`, `jq`, `sed`, and `awk` installed locally.
- A MaaS subscription that is synchronized and healthy.
- A test user provisioned by the Keycloak setup (`alice` or `bob`).
- The exact redirect URI registered for the `tenant-demo` OIDC client.

## Run

Set the registered OIDC redirect URI:

```sh
export REDIRECT_URI='<registered-redirect-uri>'
```

Run the smoke test for an administrator:

```sh
docs/maas-oidc-smoke/scripts/maas-oidc-smoke.sh alice
```

Run it for a user without an accessible subscription:

```sh
docs/maas-oidc-smoke/scripts/maas-oidc-smoke.sh bob
```

By default, the script discovers the Keycloak issuer from the
`keycloak-secrets` Secret and the MaaS Gateway hostname from the
`maas-default-gateway` Gateway status. Set `GATEWAY_HOST` only when using an
explicit hostname. The host must be a hostname, not a complete URL.

All other cluster resource names and namespaces can be overridden with the
environment variables listed by the script's usage output:

```sh
docs/maas-oidc-smoke/scripts/maas-oidc-smoke.sh --help
```

## What the test verifies

The script:

1. Discovers the Keycloak and MaaS Gateway endpoints from cluster resources.
2. Authenticates the selected user through the configured identity broker.
3. Exchanges the authorization code for an OIDC access token.
4. Calls `/v1/me` and `/v1/subscriptions`.
5. Creates a one-hour ephemeral API key when the user has a subscription.
6. Calls `/v1/api-keys/search` and verifies that a newly created key is listed.

For `alice`, the test expects one accessible subscription, creates an
ephemeral API key, and verifies that the key appears in the search result.
For `bob`, it expects no accessible subscription and no API keys.

## Runtime files

Successful runs write private runtime credentials under `/tmp`:

- `/tmp/maas-alice-access-token`
- `/tmp/maas-bob-access-token`
- `/tmp/maas-alice-api-key`

Remove these files when they are no longer needed. API keys created by the
script expire after one hour.

## GitOps and secret safety

The script does not change Kubernetes desired state and does not commit
cluster endpoints, API URLs, kubeconfig contexts, client secrets, user
passwords, tokens, or API keys. It only reads Kubernetes resources and invokes
the MaaS APIs. The ephemeral API key is runtime application data, not GitOps
configuration.

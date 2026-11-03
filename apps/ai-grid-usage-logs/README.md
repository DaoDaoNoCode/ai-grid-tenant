# ai-grid-usage-logs

The delivery half of AI Grid MaaS usage logs. Each site's RHOAI collector
forwards usage records off-cluster; this app tells it where to send them and
gives it the credential to do so.

It renders no store, and keeps no copy of the store's settings.
`apps/ai-grid-o11y` owns all of it:

| Owned by `apps/ai-grid-o11y` | Where |
|---|---|
| the LokiStack — name, size, storage class, schemas, 30-day retention, the seven promoted stream labels | `manifests/lokistack.yaml` |
| the bucket | `manifests/obc-usage-logs-bucket.yaml` |
| the S3 Secret it is translated into | `manifests/job-provision-loki-key.yaml` + `manifests/rbac-provision-loki-key.yaml` |
| the writer identity | `manifests/sa-usage-logs-writer.yaml`, `clusterrole-…`, `clusterrolebinding-…` |
| the Perses datasource and dashboard | `manifests/datasource-usage-logs-all.yaml`, `manifests/usage-logs-admin-dashboard.yaml` |

`values.yaml` here deliberately does **not** restate any of those. The chart can
render a store, so the toggles it would need are turned off explicitly —
`lokiStack.enabled`, `ingest.writer.create`, `ingest.reader.create` — while
`objectStorage` is left out altogether, since the chart already defaults
`obc.create` to false. Every other store key is absent too: a second copy would
diverge from that app silently while having no effect on what this app renders.

What this app adds is what that one lacks:

| | |
|---|---|
| `manifests/00-loki-operator.yaml` | The Loki operator. `apps/ai-grid-o11y` renders a LokiStack but ships no Subscription, and on a dedicated hub nothing else installs one — it otherwise arrives with the RHOAI chart's `dependencies.loki`, which a hub running no RHOAI never pulls in. |
| the chart's spoke Policy | Ships the writer token and patches each site's `DSCInitialization` with the exporter configuration. |
| `manifests/20-hub-template-rbac.yaml` | Lets ACM resolve the Policy's hub templates: the ingest Route in `redhat-ods-monitoring`, and the credential in `ai-grid-policies`. |

The ingest endpoint is an ACM hub template rather than a literal, because it is
the hub's own Route host and differs per fleet. `helm lookup` cannot supply it:
the Argo CD repo-server renders without cluster access.

## Mint the writer token

The chart does not create it, because a ServiceAccount token is not a
declarative object. ACM reads the Secret with `fromSecret` and ships
`$ocm_encrypted` ciphertext, so the token never appears in a managed cluster's
manifest.

Run this after the Application has synced, so the ServiceAccount exists:

```sh
export HUB_CONTEXT=<hub context>

apps/ai-grid-usage-logs/create-writer-token.sh
```

Re-running rotates the token. The Policy re-resolves the Secret and each site
picks up the new value, so rotation is the same operation as creation. The
default lifetime is one year; `TOKEN_DURATION` overrides it, and the cluster's
`--service-account-max-token-expiration` may cap what is actually issued.

## Verify

Metadata-only, so the credential is not displayed:

```sh
# the hub credential exists and is non-empty
kubectl get secret usage-logs-hub-credential -n ai-grid-policies \
  -o go-template='{{.metadata.name}} {{.type}} {{len .data.token}} bytes (encoded){{"\n"}}'

# how long the issued token is good for
kubectl get secret usage-logs-hub-credential -n ai-grid-policies \
  -o jsonpath='{.data.token}' | base64 -d | cut -d. -f2 | base64 -d 2>/dev/null | \
  python3 -c 'import json,sys,datetime; print(datetime.datetime.fromtimestamp(json.load(sys.stdin)["exp"], datetime.UTC))'

# the Policy is delivering it
kubectl get policy ai-grid-maas-remote-usage-logs -n ai-grid-policies \
  -o jsonpath='{.status.compliant}{"\n"}'

# a site received it, and knows where to write
kubectl --context <site> get secret hub-usage-logs-auth -n redhat-ods-monitoring \
  -o jsonpath='{.metadata.name}{"\n"}'
kubectl --context <site> get dsci default-dsci \
  -o jsonpath='{.spec.monitoring.usageLogs.exporters.otlphttp/hub.endpoint}{"\n"}'
```

A record pushed at a site collector's receiver should arrive in the hub store
with `cluster_name`, `model` and `service_name` promoted as stream labels.

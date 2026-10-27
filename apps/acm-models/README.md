# Internal model deployments

This app owns the internal `LLMInferenceService` deployment and its
model-facing MaaS resources. Supporting namespaces, NetworkPolicies, and the
Grid `ExternalProvider` are owned by the RHOAI apps.

## Scheduler metrics

Without them a provider reports `Ready=Unknown`, reason
`MetricsNotConfigured`, and its candidate publishes no load. The RHOAI
prerequisites policy admits `redhat-ai-grid` to the scheduler's metrics port:

```yaml
spec:
  metricsConfig:
    endpoint: http://<model>-epp-service.ai-grid-internal-models.svc.cluster.local:9090
    path: /metrics
    timeout: 2s
    auth:
      type: serviceAccountToken
      allowPlaintext: true
```

Set by hand: provider names carry the source UID and change on every recreate.
[odh-model-controller#986](https://github.com/opendatahub-io/odh-model-controller/pull/986)
generates it once it ships, enabled by `publishMetrics: true` in the Gateway's
serving configuration. Do not set that key before the controller supports it;
the annotation is strict-unmarshalled, so an unknown key publishes no provider
at all.

`allowPlaintext` is lab-only. The metrics port declares no `appProtocol`, so the
token crosses in the clear; declaring `appProtocol: https` is the fix.

Scraping looks like `Ready=True` with a ready-endpoint count and
`MetricsAvailable=True`, reason `ScrapeSucceeded`.

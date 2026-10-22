# AI Grid enrollment

This app installs one Grid enrollment service on `local-cluster` and generates one
site-configuration app for every ACM-registered cluster. The site app runs on the hub,
creates a `SiteInvite` for each remote cluster, and uses ACM policy to configure that
cluster's platform-owned Grid operator.

## New cluster onboarding

When ACM admits a cluster into the `global` cluster set, `apps/acm-models` creates its
Argo CD cluster secret. Both the Grid enrollment and RHOAI ApplicationSets then generate
their per-cluster Applications automatically.

The enrollment service reconciles the new `SiteInvite` into a one-time token Secret. ACM
copies that token, the Grid CA bundle, and the SWIM key to the new cluster, while the
RHOAI Application installs the platform Grid operator. Once the operator Deployment
appears, the site policy configures enrollment and the Submariner service endpoints. The
operator redeems the invite, discovers the other sites, and the routing policy updates
`fromProviders` from the discovered `GridSite` resources.

No manual enrollment step is required. If an invite expires before the new cluster's
operator becomes ready, follow the reissue procedure below.

## Chart pin

Grid runtime charts are pinned to `v0.2.2`. The RHOAI chart vendors only `0.2.0`
versions of `grid-enrollment` and `praxis-gateway`, and it does not vendor `grid-site`.
The pinned release adds `SiteInvite` reconciliation, hardened invite Secret grants, the
`grid-site` chart, operator-generated gateway configuration, and provider-derived
topology.

## Topology

- RHOAI remains on the `maas` profile and keeps KServe/MaaS enabled.
- The RHOAI chart enables only the platform AI Grid operator and CRDs; its vendored
  enrollment and gateway runtimes are disabled.
- `apps/grid-enrollment` installs the `grid-enrollment` chart from `praxis-proxy/grid`
  `v0.2.2` on the hub.
- `apps/rhoai` installs the `grid-site` and `praxis-gateway` charts from
  `praxis-proxy/grid` `v0.2.2` on every cluster.
- SWIM, signals, and gateway Services use unique per-site names and are exported through
  Submariner. The stable local MaaS alias is `grid-gateway.redhat-ai-grid.svc.cluster.local`.
- Each site policy copies the OpenShift service CA into `grid-backend-ca`. The Grid
  network uses it to trust local HTTPS KServe backends.
- Each site policy sets ODH-managed `InferenceProvider.spec.clusterName` to the site name.
  The routing policy then derives `fromProviders` from the locally discovered `GridSite`
  names, so adding or removing an ACM cluster updates the topology without static endpoint
  lists.

## Invite lifecycle

`SiteInvite.spec` is immutable and the maximum lifetime is `168h`. A token only needs to
remain valid until the remote site enrolls; rotation afterward uses the issued site
identity and does not consume the invite.

To reissue an expired or consumed invitation for `<site>`:

```sh
kubectl delete siteinvite <site>
kubectl -n grid-enrollment-invites delete secret grid-invite-<site>
```

Argo CD recreates the Git-declared `SiteInvite`, and the enrollment service mints a new
token Secret. Do not change the invite fields in Git to rotate it; the API rejects spec
updates.

## Checks

```sh
kubectl -n openshift-gitops get applications
kubectl get gridnetwork grid -o yaml
kubectl get gridsite
kubectl get inferenceproviders
kubectl -n redhat-ai-grid get configmap praxis-consumer-config -o yaml
kubectl -n redhat-ai-grid get deployment grid-operator
kubectl get policy -A | grep grid-site-
```

The consumer gateway is ready only after `GridNetwork.status.praxisConfigStatus` reports
`Rendered` and `mountReconciliationStatus` reports `Ready`. The chart intentionally keeps
`mountReconciliation.releaseHelmMounts: false`; changing it to `true` is an operational
cleanup after those statuses and a successful inference request.

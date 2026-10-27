# RHOAI Nightly Updater

This app deploys the [RHOAI Nightly Updater](https://github.com/DaoDaoNoCode/rhoai-nightly-updater)
to every cluster that runs RHOAI, in the `rhoai-nightly-updater` namespace. The
ApplicationSet uses the same cluster selector as the `rhoai` ApplicationSet,
so a cluster gets the updater when it gets RHOAI.

It renders the updater's Helm chart (`deploy/chart`) at a release tag with the
`gitops` profile: the updater only installs the build that the Git-managed
`rhoai-catalog-dev` catalog (`apps/rhoai/nightly.yaml`) serves, and shows
Status, Components and Diagnostics to cluster-admins. Its RBAC is read-only
apart from its own ConfigMaps and the RHOAI Subscription, InstallPlans and
CSVs in `redhat-ods-operator`, and a ValidatingAdmissionPolicy limits the
writes in `redhat-ods-operator`. The chart's
[GITOPS.md](https://github.com/DaoDaoNoCode/rhoai-nightly-updater/blob/v2.2.0/docs/GITOPS.md)
describes the chart, its hooks and the profile.

## Values

- `values.yaml` is shared by every cluster. Every image is pinned by digest.
- `values-<cluster>.yaml` is optional and overrides it for one cluster. The
  oauth-proxy tag should match the cluster's OCP minor version, so a cluster on
  another minor version sets its own image:

```yaml
parameters:
  OAUTH_PROXY_IMAGE: registry.redhat.io/openshift4/ose-oauth-proxy-rhel9:v4.<minor>@sha256:<manifest list digest>
```

To read a digest, log in to `registry.redhat.io` and run
`skopeo inspect --raw docker://registry.redhat.io/openshift4/ose-oauth-proxy-rhel9:v4.<minor> | sha256sum`.
The Red Hat Ecosystem Catalog shows the same manifest list digest.

## Upgrading

Change the chart's `targetRevision` in `hub/01-applicationset.yaml` and
`parameters.IMAGE` in `values.yaml` in one commit. The chart refuses an image
whose tag names another release, but it does not verify the digest. Check that
the image's `org.opencontainers.image.revision` label is the tag's commit:

```sh
skopeo inspect docker://quay.io/juntao_wang/rhoai-nightly-updater@sha256:<digest> \
  | jq -r '.Labels["org.opencontainers.image.revision"]'
git ls-remote https://github.com/DaoDaoNoCode/rhoai-nightly-updater.git 'refs/tags/<tag>^{}'
```

Renovate groups both into one `rhoai-nightly-updater` pull request. For a new
release, merge it only when it changes both: with only one changed the render
fails, and Argo CD leaves the running release in place. A new digest for the
same tag needs nothing else. Renovate has no
`registry.redhat.io` credentials, so it does not update the oauth-proxy digest.

## Verify

```sh
kubectl --context "$HUB_CONTEXT" -n openshift-gitops get applications -o name | grep rhoai-nightly-updater-
kubectl --context "$CLUSTER_CONTEXT" -n rhoai-nightly-updater get deploy,route
kubectl --context "$CLUSTER_CONTEXT" get validatingadmissionpolicy,validatingadmissionpolicybinding \
  -l app.kubernetes.io/instance=rhoai-nightly-updater-rhoai-nightly-updater
```

When a cluster leaves the selector, its Application is deleted with its
resources. The namespace and the `rhoai-nightly-updater-rhoai-nightly-updater`
ConsoleLink stay; GITOPS.md section 7 lists what to remove by hand.

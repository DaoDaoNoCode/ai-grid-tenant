# ACM managed-cluster onboarding

This directory documents the recommended way to import an existing OpenShift
cluster into ACM without putting cluster-specific data in this repository.

## Recommendation

Use a one-time, parameterized `clusteradm` import for the initial cluster
registration. After ACM accepts the cluster, the existing GitOps resources
discover it dynamically:

1. `../../apps/acm-models/hub/facebook-opt-125m-01-placement.yaml`
   selects clusters in the reserved `global` cluster set.
2. `../../apps/acm-models/hub/facebook-opt-125m-02-gitops-cluster.yaml`
   registers selected clusters with Argo CD.
3. The repository's ApplicationSets generate applications for each registered
   cluster.

No `ManagedCluster`, join token, kubeconfig, API URL, or cluster name needs to
be committed to this repository.

## Prerequisites

- Access to an ACM hub cluster and the target managed cluster in one
  kubeconfig.
- `kubectl`, `clusteradm`, and `jq` installed locally.
- A short, stable cluster name that follows DNS-1123 label rules. Avoid using
  a kubeconfig context or infrastructure hostname as the ACM cluster name.
- Enough capacity on the target cluster for the applications that the
  ApplicationSets deploy there.

## Import a cluster

Set the runtime inputs in your shell. For example:

```sh
export HUB_CONTEXT='<existing-hub-kubeconfig-context>'
export SPOKE_CONTEXT='<target-cluster-kubeconfig-context>'
export CLUSTER_NAME='<stable-acm-cluster-name>'
```

Preview and run the import:

```sh
docs/acm-cluster-onboarding/import-managed-cluster.sh \
  --hub-context "$HUB_CONTEXT" \
  --spoke-context "$SPOKE_CONTEXT" \
  --cluster-name "$CLUSTER_NAME"
```

After reviewing the summary, rerun the command with `--yes`. The script:

1. Validates that both kubeconfig contexts exist and the cluster name is
   DNS-1123 compliant.
2. Detects an existing `ManagedCluster` and resumes its registration instead
   of reinstalling the klusterlet.
3. Gets a hub join token only for a new import.
4. Installs the klusterlet on the target cluster.
5. Waits for the `ManagedCluster` to be created.
6. Accepts the cluster on the hub when `spec.hubAcceptsClient` is false.
7. Approves the cluster CSR when needed, including Red Hat ACM's
   `multicluster-engine` registration service account.
8. Waits for the `ManagedClusterJoined` condition.
9. Enables the `application-manager` add-on required by this repository's
   legacy `GitOpsCluster` integration.
10. Waits for Argo CD's cluster secret to be created.

The script is safe to rerun after a partial import. If the cluster is already
accepted and joined, it performs no registration changes and returns after
verifying the joined condition.

The script automatically requests a short-lived token from
`agent-registration-bootstrap` in either the upstream OCM namespace
(`open-cluster-management`) or the Red Hat ACM namespace
(`multicluster-engine`). Use `--registration-sa-namespace` only if your hub
stores that service account in another namespace.

For a hub behind a load balancer or NAT where the public `cluster-info`
endpoint is not usable, add `--force-internal-endpoint-lookup`.

## Verify GitOps discovery

After the script succeeds, check the hub:

```sh
kubectl --context "$HUB_CONTEXT" get managedclusters
kubectl --context "$HUB_CONTEXT" -n openshift-gitops get placementdecisions
kubectl --context "$HUB_CONTEXT" -n openshift-gitops get applications
```

The new cluster should appear in the
`acm-models-facebook-opt-125m` placement decision and receive generated
applications such as `acm-models-facebook-opt-125m-<cluster-name>`,
`rhoai-<cluster-name>`, and `maas-db-<cluster-name>`.

## Security and repeatability

- Do not commit kubeconfig contexts, cluster names, API URLs, or join tokens.
- Treat the join token as a short-lived secret.
- The script does not write the token to disk, but `clusteradm join` accepts
  the token as a command-line argument, so it can be visible in the local
  process list while that command runs.
- Prefer a separate kubeconfig for onboarding if that reduces credential
  exposure.

## Why the initial import is outside Git

Before a cluster is registered, the hub has no ACM agent or credentials for
that cluster. The initial trust exchange therefore requires unique runtime
material. Git can own the generic onboarding process and all post-registration
desired state, but it should not own the initial cluster-specific trust
secret.

For fleet-scale onboarding, alternatives include a parameterized pipeline that
calls this script, ACM Discovery with cloud credentials, or full
Hive/SiteConfig provisioning when ACM creates the cluster. Those alternatives
still require a careful decision about where credentials and cluster inventory
live; none of them is needed for a one-time import of an existing cluster.

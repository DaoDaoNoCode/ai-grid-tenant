# Cluster config

Cluster-level configuration managed separately from the workload apps under
`apps/`. The `apps` ApplicationSet discovers this directory through
`cluster-config/application.yaml`.

## Cluster admins

Grants `cluster-admin` to a Git-managed list of users through per-user
`ClusterRoleBinding` objects (`cluster-admin-<user>`), managed by the
`cluster-admins` Argo CD Application.

## Submariner gateway nodes

The `submariner-gateway-nodes` policy is distributed to every cluster in the
global cluster set. On each cluster, it discovers Nodes whose only role is
`worker` and enforces the `submariner.io/gateway` label. New and replacement
worker Nodes are therefore labeled without cluster-specific Node names in Git.
The policy lives in its own namespace so its `ManagedClusterSetBinding` can be
named `global`, as required by ACM, without colliding with the existing binding
in `openshift-gitops`.
Submariner is configured for two gateways because cross-cluster connectivity
is required by the shared database and model-serving topology. Each managed
cluster therefore needs at least two pure worker Nodes.

### Adding or removing an admin

Edit [`values.yaml`](values.yaml) and commit. The Application syncs
automatically (prune and self-heal are enabled):

- Adding a username to `cluster_admins` creates its `ClusterRoleBinding` on
  the next sync.
- Removing a username prunes its `ClusterRoleBinding`, revoking cluster-admin.

The chart is stored in this repository at [`chart/`](chart/); the Application
uses the same multi-source pattern as the OSAC apps (chart path plus a
`values` ref for the value file).

### Constraints

- `cluster_admins` entries must be Kubernetes usernames that are also valid
  in a DNS-1123 resource name, because the username is embedded in the
  binding name. IdP-qualified usernames such as `user@domain` require a
  sanitized binding-name scheme before they can be listed.
- Bindings reference `kind: User` subjects. A subject that has never
  authenticated is inert until its first login; the binding itself is created
  regardless.
- All resources are cluster-scoped, so `spec.destination.namespace` is only
  present to satisfy the ApplicationSet template; no namespace is created.

### Validation

Local: `helm lint` and `helm template` with the tracked values file (see
repository history for the exact invocation used). Live: after pushing, the
ApplicationSet generates the `cluster-admins` Application; confirm
`oc get clusterrolebindings cluster-admin-khowell cluster-admin-aballant`
exists on the cluster.

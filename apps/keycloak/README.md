# Keycloak

This app migrates the Keycloak component from
`lphiri/maas-portal-integration-poc` into a dedicated Argo CD Application. The
bootstrap ApplicationSet discovers `apps/keycloak/application.yaml` automatically.

## Topology

- Keycloak runs in `maas-db` on the GitOps hub cluster, while remaining a
  separate Argo CD Application from `maas-db`.
- The app reuses the healthy `maas-db` CloudNativePG cluster. Its
  `DatabaseRole` and `Database` resources create a dedicated `keycloak` role
  and database without sharing credentials with the API database user.
- Keycloak connects to `maas-db-rw` with TLS and verifies the server against
  the existing `maas-db-ca` Secret.
- The Deployment imports the `saas`, `grid-tenant-1-idp`, and
  `grid-tenant-2-idp` realms on first startup.
- The upstream example `AITenant` resource is intentionally not applied by this
  app; the tenant-facing application should own its consumer configuration.

The app intentionally does not create the `maas-db` namespace or a second
PostgreSQL cluster. It can initially report missing namespace or resource
errors until the `maas-db` Application has created the namespace and installed
the CloudNativePG CRDs. Its retry policy refreshes and retries automatically.

## Required Secret

Git does not store Keycloak, client, broker, test-user, or database secrets.
Before the first sync, create two Secrets in `maas-db`:

- `keycloak-db`, from `database-secret-template.yaml`, holds the dedicated
  PostgreSQL role credentials consumed by CloudNativePG and Keycloak.
- `keycloak-secrets`, from `secret-template.yaml`, holds Keycloak bootstrap,
  client, broker, and test-user values.

For example:

```sh
cp apps/keycloak/secret-template.yaml /tmp/keycloak-secrets.yaml
$EDITOR /tmp/keycloak-secrets.yaml
oc apply -f /tmp/keycloak-secrets.yaml
rm /tmp/keycloak-secrets.yaml
cp apps/keycloak/database-secret-template.yaml /tmp/keycloak-db.yaml
$EDITOR /tmp/keycloak-db.yaml
oc apply -f /tmp/keycloak-db.yaml
rm /tmp/keycloak-db.yaml
```

`KEYCLOAK_PUBLIC_URL` must exactly match the Route host in
`manifests/route.yaml`. Update both files together when deploying to another
cluster or apps domain.

Realm imports replace `${KEYCLOAK_PUBLIC_URL}` and the broker/client/test-user
secret keys with values from this Secret. Keycloak skips realms that already
exist in PostgreSQL, so later edits to an import file do not update those
realms. Use a planned Keycloak export/import for changes to existing realms.

## Validation

```sh
kubectl get applications.argoproj.io -n openshift-gitops
kubectl get databaseroles,databases -n maas-db
kubectl rollout status deployment/keycloak -n maas-db
kubectl get route keycloak -n maas-db
```

The Keycloak database inherits the availability and storage characteristics of
the existing `maas-db` CloudNativePG cluster. Database backups remain the
responsibility of that shared database app.

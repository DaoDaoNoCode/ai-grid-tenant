# External Secrets Operator

This app installs the Red Hat build of External Secrets Operator cluster-wide in
the `external-secrets-operator` namespace.
The operator provides GitOps-managed Secret generation and synchronization
without storing plaintext Secret values in Git.

Consumers can use `ExternalSecret` resources with generator references. The
Keycloak app uses the Password generator to create its database and application
Secrets once.

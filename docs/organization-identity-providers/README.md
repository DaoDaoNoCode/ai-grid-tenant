# Organization identity providers

An organization's users sign in to the MaaS portal with their own identity provider: the organization's Microsoft Entra ID, Okta, Keycloak or similar. The provider admin connects it once, in the provider console. Keycloak (realm `saas` on the hub) brokers the sign-in; AI Grid never manages the organization's users.

- [Microsoft Entra ID](entra-id.md)
- [Google](google.md): testing only, it can't send groups or roles.

## What the identity provider must send

The identity provider's ID token must carry these claims ([ODH-ADR-MS-0007](https://github.com/opendatahub-io/architecture-decision-records/blob/main/architecture-decision-records/model-serving/ODH-ADR-MS-0007-ai-grid-shared-oidc-identity-contract.md)):

| Claim | Value | Used for |
| --- | --- | --- |
| `sub` | A stable id for the user | Links the user's account in `saas` to the identity provider. It must never change. |
| `email` | The user's email | The user's account in `saas`. Its domain also routes the user to the identity provider at sign-in. |
| `groups` | The user's group names, plain (`ai-grid-users`) | Subscriptions grant models to group names. |
| `roles` | `admins` for the organization's admins | Admin features in the MaaS portal. |

Keycloak copies `groups` and `roles` on every sign-in, so a change at the identity provider takes effect at the user's next sign-in. The provider console adds `org_id` and `org_name` itself: the identity provider doesn't send them.

`email_verified`: Keycloak trusts the identity provider's email. When the ID token has no `email_verified`, Keycloak treats the email as verified. When it has one, it must be `true`, and the same goes for the user info response when a User info URL is set: the MaaS portal refuses an unverified email.

## Connect an identity provider in the provider console

Do these steps for every organization. The identity provider's own guide says which values to use.

### 1. Choose the organization's name

The name becomes the Keycloak identity provider's alias, and the alias is part of the redirect URI that the identity provider must allow:

```
https://<keycloak-host>/realms/saas/broker/<organization-name>/endpoint
```

- `<organization-name>` is a lowercase DNS label, for example `acme`. It can't be changed later.
- `<keycloak-host>` is the host of the hub's Keycloak Route: `oc -n maas-db get route keycloak -o jsonpath='{.spec.host}'`.

### 2. Register the client at the identity provider

Create an OIDC client (a confidential web application) with the redirect URI from step 1, and set it up to send the claims above. Keep its client ID and client secret.

### 3. Store the client secret on the hub

The console's backend reads identity provider client secrets from Secrets in namespace `ai-grid-idp-secrets`, key `client-secret`. As a hub admin, with the secret in a file:

```sh
oc whoami --show-server   # must be the hub
oc -n ai-grid-idp-secrets create secret generic <organization-name>-idp --from-file=client-secret=<file>
rm <file>
```

### 4. Create the organization

In the provider console: Organizations, Create organization.

| Field | Value |
| --- | --- |
| Name | `<organization-name>` from step 1 |
| Domains | The email domains of the organization's users, for example `acme.com`. Keycloak sends a user who enters an email with one of these domains to this identity provider. A domain belongs to one organization only. |
| Title | The sign-in button's label, for example `Acme`. |
| Description | Optional. |
| Client ID | From step 2 |
| Client secret reference | `<organization-name>-idp`, the Secret from step 3 |
| Issuer | The identity provider's issuer |
| Default scopes | `openid email profile` |
| Validate signature | On |
| Authorization URL, Token URL, User info URL, JWKS URL, Logout URL | From the identity provider's OpenID configuration: the issuer followed by `/.well-known/openid-configuration` |

The console creates the organization in Keycloak, the identity provider linked to it, and the mappers that put `org_id`, `org_name`, `groups` and `roles` in the user's token. Every user who signs in through the identity provider joins the organization.

The identity provider's settings can't be changed in the console after the organization is created, and the backend copies the client secret into Keycloak once, at creation. To change a setting later, such as a rotated client secret, change it in Keycloak's admin console (realm `saas`, Identity providers, `<organization-name>`), and update the Secret on the hub to match.

Don't edit the identity provider's Keycloak mappers by hand: the console writes its four mappers again when the organization is saved.

### 5. Sign in

Open the MaaS portal on an ingress cluster (`https://maas.<cluster-apps-domain>/maas-portal`), enter an email with one of the organization's domains, and sign in at the identity provider.

To check the user's claims, in the Keycloak admin console (realm `saas`): Users, the user, Attributes. `maas_org_id`, `maas_org_name`, `maas_groups` and `maas_roles` are what the token's `org_id`, `org_name`, `groups` and `roles` come from.

### 6. Grant models

In the provider console, create a subscription for the organization with the group names its identity provider sends. Users in those groups see the subscription's models in the MaaS portal.

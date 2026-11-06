# Microsoft Entra ID

Connect an organization's Microsoft Entra ID tenant, so its users sign in to the MaaS portal with their Entra accounts. Entra sends everything AI Grid needs: `roles` from app roles and `groups` from group claims. The steps follow [the general ones](README.md#connect-an-identity-provider-in-the-provider-console); this page fills in Entra's side and values.

Placeholders:

| Placeholder | Example | Where it comes from |
| --- | --- | --- |
| `<organization-name>` | `acme` | You choose it ([step 1](README.md#1-choose-the-organizations-name)). |
| `<keycloak-host>` | `keycloak-maas-db.apps.hub.example.com` | `oc -n maas-db get route keycloak -o jsonpath='{.spec.host}'` on the hub |
| `<tenant-id>` | `00000000-0000-0000-0000-000000000000` | Entra admin center: Overview, Tenant ID |
| `<client-id>` | `11111111-1111-1111-1111-111111111111` | The app registration's Application (client) ID |
| `<email-domain>` | `acme.com` | The domain of the organization's users' emails |

## In the Entra admin center

The organization's Entra admin does these steps, with at least the Cloud Application Administrator role.

### Register the application

Entra ID, App registrations, New registration:

- **Name:** for example `AI Grid MaaS`.
- **Supported account types:** accounts in this organizational directory only (single tenant). The issuer below names this one tenant.
- **Redirect URI:** platform **Web**, `https://<keycloak-host>/realms/saas/broker/<organization-name>/endpoint`.

Then, in the registration:

- **Certificates & secrets:** New client secret. Copy its **Value** (not its ID): Entra shows it once. It expires; note when, and rotate it before then ([Rotate the client secret](#rotate-the-client-secret)).
- **Overview:** copy the Application (client) ID and the Directory (tenant) ID.

### Send `roles`: app roles

App roles, Create app role, twice:

| Display name | Allowed member types | Value |
| --- | --- | --- |
| AI Grid admins | Users/Groups | `admins` |
| AI Grid users | Users/Groups | `users` |

The **Value** is what appears in the token's `roles` claim, so it must be exactly `admins`. Entra puts the app roles of a user who signs in to the application in the ID token's `roles` claim.

Assign them in Entra ID, Enterprise applications, the application, Users and groups, Add user/group: choose users or groups and a role. The organization's admins get `AI Grid admins`.

### Send `groups`: group claims

Token configuration, Add groups claim. Choose one:

- **Groups assigned to the application** (recommended). Only the groups assigned to the application in Enterprise applications, Users and groups, are sent. With the manifest's optional claim `groups` and additional property `cloud_displayname` on the ID token, Entra sends cloud-only groups by **display name**, such as `ai-grid-users`. Nested groups aren't included: a user must be a direct member.
- **Security groups.** Every security group the user belongs to is sent, by **object id**, not by name. A subscription then has to name the group by its object id, such as `22222222-2222-2222-2222-222222222222`.

With more than 200 groups in a token, Entra leaves the `groups` claim out entirely, and the user gets no groups in AI Grid. Groups assigned to the application avoid that.

### Send `email`

The `email` scope makes Entra put the user's email in the ID token, when the user has one. Entra sends no `email_verified` claim, which Keycloak then treats as verified ([what the identity provider must send](README.md#what-the-identity-provider-must-send)). That's also why the User info URL stays empty below: Entra's user info response has no `email_verified` either, and Keycloak would read it as unverified.

## On the hub

Store the client secret's **Value** ([step 3](README.md#3-store-the-client-secret-on-the-hub)):

```sh
oc -n ai-grid-idp-secrets create secret generic <organization-name>-idp --from-file=client-secret=<file>
```

## In the provider console

Organizations, Create organization ([step 4](README.md#4-create-the-organization)):

| Field | Value |
| --- | --- |
| Name | `<organization-name>` |
| Domains | `<email-domain>` |
| Title | For example `Acme (Microsoft)` |
| Client ID | `<client-id>` |
| Client secret reference | `<organization-name>-idp` |
| Issuer | `https://login.microsoftonline.com/<tenant-id>/v2.0` |
| Default scopes | `openid email profile` |
| Validate signature | On |
| Authorization URL | `https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/authorize` |
| Token URL | `https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token` |
| User info URL | Leave empty |
| JWKS URL | `https://login.microsoftonline.com/<tenant-id>/discovery/v2.0/keys` |
| Logout URL | `https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/logout` |

These come from `https://login.microsoftonline.com/<tenant-id>/v2.0/.well-known/openid-configuration`.

## Check

1. Sign in to the MaaS portal as one of the organization's admins ([step 5](README.md#5-sign-in)).
2. In Keycloak's admin console (realm `saas`), the user's attributes show `maas_roles` = `admins` and `maas_groups` = their groups.
3. Create a subscription for the organization with those group names ([step 6](README.md#6-grant-models)), and check the portal lists its models.

If `maas_groups` is empty: the user isn't in a group assigned to the application, or has more than 200 groups with Security groups chosen. If `maas_roles` is empty: the user has no app role assignment.

## Rotate the client secret

The backend copies the client secret into Keycloak only when it creates the organization, so a new secret goes into Keycloak directly:

1. In the app registration, Certificates & secrets: create a new client secret and copy its Value.
2. In Keycloak's admin console (realm `saas`): Identity providers, `<organization-name>`, Client secret: paste the new value and save.
3. On the hub, update the Secret to match, so the hub keeps the current value:

   ```sh
   oc -n ai-grid-idp-secrets create secret generic <organization-name>-idp --from-file=client-secret=<file> \
     --dry-run=client -o yaml | oc apply -f -
   ```

4. Once sign-ins work, delete the old secret in Entra.

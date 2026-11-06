# Google

**For testing only.** Google signs users in, but its ID tokens never carry `groups` or `roles`: Google can't put Workspace groups in a token. A Google user joins the organization with no groups and no roles, so no subscription matches them and none of them is an admin. To test with Google anyway, give every Google user one fixed group and role in Keycloak ([Fixed group and role](#fixed-group-and-role)).

The steps follow [the general ones](README.md#connect-an-identity-provider-in-the-provider-console).

## In Google Cloud Console

Google Auth Platform, in a Google Cloud project:

1. **Audience:** Internal, if the project belongs to your Google Workspace organization: only its accounts can sign in. Otherwise External in Testing mode, with each test account added as a test user.
2. **Clients, Create client:**
   - Application type: **Web application**.
   - Authorized JavaScript origins: none.
   - Authorized redirect URIs: `https://<keycloak-host>/realms/saas/broker/<organization-name>/endpoint`.
3. Create, and download the client's JSON. `web.client_id` is the client ID and `web.client_secret` the secret. If `.web` is missing, the client isn't a Web application.

Google can take a few minutes to apply the redirect URI: a `redirect_uri_mismatch` right away usually means to wait.

## On the hub

```sh
F=<downloaded JSON>
jq -j .web.client_secret "$F" | oc -n ai-grid-idp-secrets create secret generic <organization-name>-idp --from-file=client-secret=/dev/stdin
jq -r .web.client_id "$F"   # for the console
rm "$F"
```

## In the provider console

| Field | Value |
| --- | --- |
| Name | `<organization-name>` |
| Domains | The domain of the Google accounts, for example `example.com` for a Workspace. Not `gmail.com` on a shared hub: every `@gmail.com` user would be sent to this organization. Not `google.com`: it only matches Google's own employees. |
| Title | `Google` |
| Client ID | `web.client_id` |
| Client secret reference | `<organization-name>-idp` |
| Issuer | `https://accounts.google.com` |
| Default scopes | `openid email profile` |
| Validate signature | On |
| Authorization URL | `https://accounts.google.com/o/oauth2/v2/auth` |
| Token URL | `https://oauth2.googleapis.com/token` |
| User info URL | `https://openidconnect.googleapis.com/v1/userinfo` |
| JWKS URL | `https://www.googleapis.com/oauth2/v3/certs` |
| Logout URL | Leave empty: Google has none |

These come from `https://accounts.google.com/.well-known/openid-configuration`. Google sends `email_verified` in the ID token and from its user info endpoint.

## Fixed group and role

A Keycloak admin on the hub, in realm `saas`: Identity providers, `<organization-name>`, Mappers.

1. Delete `AI Grid groups` and `AI Grid roles`. They copy the `groups` and `roles` claims on every sign-in, and Google sends neither, so they'd clear anything set by hand. Keep `AI Grid org id` and `AI Grid org name`.
2. Add two mappers of type **Hardcoded attribute**, sync mode **Force**:
   - user attribute `maas_groups`, value `ai-grid-users`;
   - user attribute `maas_roles`, value `admins`.
3. Sign out of the MaaS portal and sign in with Google again. The user's attributes now include `maas_groups` and `maas_roles`.
4. Create a subscription for the organization with group `ai-grid-users`.

Limits:

- Every Google user of the organization is an admin in `ai-grid-users`.
- Saving the organization in the provider console writes `AI Grid groups` and `AI Grid roles` again, which then clear the attributes at the next sign-in. Repeat step 1 after any save.
- Nothing tracks this change: it's a hand edit on the hub.

Using Google for a real organization needs a per-organization setting in the provider console and its backend, such as a default group and role, or a list of admin emails.

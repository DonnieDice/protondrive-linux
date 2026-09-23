---
title: "ProtonMail Accounts, Aliases, DNS, and Recovery"
created: 2026-09-23
updated: 2026-09-23
type: guide
tags: [auth, protonmail, accounts]
sources: []
---

# ProtonMail Accounts, Aliases, DNS, and Recovery

This guide documents how ProtonMail account concepts — accounts, aliases,
custom-domain DNS, and recovery — relate to signing in to ProtonDrive Linux.
ProtonDrive Linux authenticates against a Proton account; it does not manage
mailboxes, aliases, DNS records, or recovery settings itself. All account
changes described here are made in the Proton web settings, not in this
desktop client.

## Accounts

A Proton account is the single identity used across Proton services (Mail,
Drive, Calendar, VPN). Signing in to ProtonDrive Linux uses the same
credentials and the same SRP authentication flow described in the
[Auth Module](auth-module) and [SSO Authentication](sso-authentication)
guides.

Key points:

- Sign in with your Proton account email address (or username) and password.
  Two-factor authentication, when enabled on the account, is required during
  login in the desktop client as well.
- Both free and paid Proton accounts can use Proton Drive. Storage quota
  depends on the account plan and is enforced server-side; the client only
  displays it.
- Changing your account password invalidates existing sessions. After a
  password change you must sign in again in ProtonDrive Linux.

## Aliases

Proton accounts may have multiple addresses (aliases): additional
`@proton.me`/`@pm.me` addresses on paid plans, or addresses on a custom
domain.

Key points:

- You can sign in with any address on the account; all aliases resolve to the
  same underlying account and the same Drive storage.
- An alias is a receiving address, not a separate identity for Drive. Drive
  has a single root per account regardless of how many aliases exist.
- Adding or removing aliases is done in Proton Account settings on the web.
  The desktop client does not list or manage aliases.

## Custom Domain DNS

Using your own domain with Proton Mail requires DNS records published by you
at your DNS provider. Proton's settings page shows the exact records to
create; this section summarizes the record types and their purpose so the
settings page output is easier to verify.

Always copy the exact values from Proton Account settings (Domain names
section) for your domain — do not guess values from this table.

| Record type | Purpose |
|-------------|---------|
| TXT (verification) | Proves you control the domain |
| MX | Routes inbound mail for the domain to Proton's servers |
| SPF (TXT) | Authorizes Proton's servers to send mail for the domain |
| DKIM (CNAME, several) | Cryptographically signs outbound mail |
| DMARC (TXT) | Policy and reporting for SPF/DKIM failures |

Operational notes:

- DNS changes propagate on the order of minutes to hours depending on TTL.
  Proton re-checks records and marks the domain verified once they match.
- Keep Proton's TXT verification record in place after verification; removing
  it can cause the domain to become unverified.
- Do not place a CNAME on the apex (bare) domain for these records — MX/TXT
  must not be shadowed by a CNAME. Use Proton's documented records verbatim.

## Account Recovery

Proton accounts support recovery methods configured in Proton Account
settings: a recovery email address, a recovery phone number, or (on some
plans) pre-generated recovery codes.

Key points:

- Recovery methods are managed entirely on the web in Proton Account
  settings (Security / Recovery section), not in ProtonDrive Linux.
- Store recovery codes offline. Anyone with a valid recovery method can
  reset the account password.
- Because Proton applies end-to-end encryption, a password reset without a
  working recovery path can make previously encrypted data (including some
  Mail and Drive data) unrecoverable. Configure at least one recovery method
  before you need it.
- After completing recovery and setting a new password, sign in again in
  ProtonDrive Linux; previous sessions remain revoked.

## Where Each Setting Lives

| Concern | Managed in ProtonDrive Linux | Managed in Proton web settings |
|---------|------------------------------|-------------------------------|
| Sign in / sign out of this device | Yes | — |
| Password change | No | Yes (Account settings) |
| Two-factor authentication | Entered at login | Yes (Security settings) |
| Aliases / extra addresses | No | Yes (Identity and addresses) |
| Custom domain + DNS records | No | Yes (Domain names) |
| Recovery email/phone/codes | No | Yes (Security / Recovery) |

## Troubleshooting

### "Invalid credentials" at login

- Confirm you are using the password for the Proton account, not a mailbox
  password for an alias — aliases share the account password.
- If you recently changed your password, all sessions were revoked; sign in
  again with the new password.
- If two-factor authentication is enabled, complete the 2FA prompt; a stale
  TOTP from a different device clock is a common failure.

### Custom domain shows "unverified" in Proton settings

- Re-check that every record type listed above exists with the exact value
  shown in Proton settings; a missing DKIM CNAME is the most common cause.
- Allow DNS propagation time after edits, then use the settings page's
  re-check action.

### Locked out of the account

- Use account recovery on the Proton web sign-in page with your configured
  recovery email, phone, or recovery codes.
- After recovery, sign in to ProtonDrive Linux again with the new password.

## See Also

- [Auth Module](auth-module) — Rust-side SRP login, sessions, and token refresh
- [SSO Authentication](sso-authentication) — web-wide SSO navigation and CAPTCHA handling

---
title: "Security Policy"
created: 2026-05-28
updated: 2026-05-28
type: meta
tags: [security]
sources:
  - []
---


# Security Policy

The security of the ProtonDrive Linux client is a top priority. We appreciate your efforts to responsibly disclose your findings, and we will make every effort to acknowledge your contributions.

## Reporting a Vulnerability

We are committed to working with the community to verify and address any potential vulnerabilities that are reported to us. Please do not report security vulnerabilities through public GitHub issues.

Instead, please use the **private vulnerability reporting feature** provided by GitHub:

**https://github.com/DonnieDice/protondrive-linux/security/advisories/new**

To submit a report:

1. Navigate to the link above, or go to the repository's **Security** tab → **Report a Vulnerability**.
2. Fill out the form with the details of the vulnerability. Please provide as much information as possible, including:
    *   The type of issue (e.g., buffer overflow, SQL injection, cross-site scripting, etc.).
    *   Full paths of source file(s) related to the manifestation of the issue.
    *   The location of the affected source code (tag/branch/commit or direct URL).
    *   Any special configuration required to reproduce the issue.
    *   Step-by-step instructions to reproduce the issue.
    *   Proof-of-concept or exploit code.
    *   Impact of the issue, including how an attacker might exploit it.

This will allow us to assess the risk and work on a fix in a private setting.

## Our Commitment

You may also email the maintainer directly at **donniedice@proton.me** if you prefer non-GitLab/GitHub channels.

If you use this process, we commit to:

- Responding to your report promptly, typically within 72 hours.
- Providing an estimated timeline for addressing the vulnerability within 7 business days.
- Aiming to ship a fix or mitigation within 90 days of confirmed receipt.
- Notifying you when the vulnerability is fixed.
- Publicly acknowledging your responsible disclosure (if you wish).

Thank you for helping keep ProtonDrive Linux and its users safe.

## Supported Versions

| Version | Supported |
| ------- | --------- |
| 2.0.x   | Yes       |
| < 2.0   | No        |

Only the latest release line receives security patches. Older versions should be upgraded.

## Known Upstream Alert

We currently track a Dependabot alert on the Linux desktop dependency stack for `glib` through the Tauri / gtk-rs / WebKitGTK chain.

This alert is being monitored as an upstream blocker. A local lockfile refresh does not close it because the affected versions are still the latest published crates in the current runtime line.

We will revisit the alert when the upstream stack publishes a patched dependency path that Cargo can resolve without changing the application architecture.

> **Last reviewed:** 2026-05-27. If you have details on a specific CVE or a patched crate version, please open a GitHub Security Advisory or email the maintainer.

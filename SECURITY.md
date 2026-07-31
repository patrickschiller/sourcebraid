# Security Policy

## Reporting a vulnerability

If you believe you have found a security vulnerability in SourceBraid,
**please do not open a public GitHub issue, discussion, or pull request**.
Public disclosure before a fix is available may put users and private archives
at risk.

Instead, send a private report by email to:

> **p@trickschiller.de**

Use the subject prefix `[SourceBraid Security]` so the report is not lost in
spam. Encrypted email is welcome; request a PGP key in your initial message.

Please include:

- A description of the issue and its likely impact.
- The SourceBraid version, commit hash, or release tag you tested.
- The affected client or component and its environment.
- Step-by-step reproduction instructions or a proof of concept that uses only
  accounts and data you are authorized to access.
- Whether the vulnerability is already public or has been disclosed elsewhere.
- Whether and how you would like to be credited.

## Response process

The following are best-effort targets, not a contractual service-level
agreement:

- **Acknowledgement:** within three working days of receipt.
- **Triage and assessment:** within ten working days, including an initial
  severity assessment and tentative remediation plan.
- **Fix and coordinated disclosure:** a patch will be developed and reviewed
  privately where practical. For critical issues, the project aims to publish a
  fix within 30 days; lower-severity issues may take longer.
- **Public advisory:** after a fix is available, a GitHub Security Advisory may
  document the issue, impact, and mitigation and credit the reporter unless
  anonymity was requested.

## Scope

In scope:

- The SourceBraid Chrome extension and its GitHub integration.
- The iOS app and Share Extension, including local credential handling.
- The ChatGPT/Codex plugin, local index, and archive-management scripts.
- Workflows, source adapters, and other code in the public repository.
- The official `sourcebraid.com` website when the issue is specific to that
  deployment.

Out of scope:

- Vulnerabilities in GitHub, browsers, iOS, ChatGPT, Codex, Docling, source
  websites, or other third-party products, unless SourceBraid's integration is
  itself flawed.
- User-operated archive repositories or modified SourceBraid deployments;
  contact their operator unless the problem also affects the official code.
- Social engineering, physical attacks, destructive testing, denial of service
  by resource exhaustion without a security flaw, or issues requiring a fully
  compromised device.
- Captured source content and disputes about a user's right to store it.

## Safe harbor

Good-faith security research conducted in line with this policy will not be
pursued legally by the project maintainer. Do not access, modify, retain, or
destroy data that does not belong to you; do not pivot to systems outside this
scope; and do not run automated scanners against systems you do not own or have
permission to test.

Thank you for helping keep SourceBraid and its users safe.

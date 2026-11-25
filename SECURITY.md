# Security

- The widget talks to a server **you** run (see `docs/API.md`). The server link is the only access control in the simplest setup, so keep it secret and never post it in issues or screenshots.
- Updates are downloaded only from this repository's GitHub Releases, verified against `SHA256SUMS.txt` and syntax-checked before they replace the old version. The previous version is kept as a backup in the program folder.
- Report vulnerabilities privately through GitHub's "Report a vulnerability" feature on the Security tab.
- Downloads: the in-app updater only accepts the release ZIP of this repository, compares its SHA-256 with `SHA256SUMS.txt` and runs a syntax check before replacing the program. You can verify a download yourself with `Get-FileHash`.
- Secrets: the Home Assistant token is stored encrypted for your Windows account (DPAPI) in `ha-token.bin`, never in `config.json`, the log, diagnostics or pictures. The repository checks fail if token-like text is committed.
- Network: the widget talks to your Home Assistant (or your own server) and to `api.github.com` for update checks. There is no telemetry.
- Supported version: the latest release. Please update before reporting a problem.

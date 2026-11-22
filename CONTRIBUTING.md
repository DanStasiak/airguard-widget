# Contributing

Contributions are welcome: bug reports, ideas, translations, backends for other systems, pull requests.

- The app is a single PowerShell 5.1 + WPF script (`src/Luftwaechter.ps1`). Keep the UTF-8 **BOM** and **CRLF** line endings.
- Test on Windows 10/11 before opening a pull request. Do not use `GetNewClosure()` in event handlers (script functions are not visible inside closures); put data into `.Tag` instead.
- Beware: PowerShell variable names are case-insensitive (`$I` and `$i` are the same variable).
- All UI text lives in the `$script:Strings` table (German and English). Add both languages.
- Never commit server links, tokens, entity IDs or other personal data. `config.json` is git-ignored.

## Releasing (maintainer)
1. Update `$appVersion` in `src/Luftwaechter.ps1`, `VERSION`, and add a section to `CHANGELOG.md`.
2. Commit and push to `main`.
3. Push to `main`. The GitHub Action sees the new `VERSION`, builds the ZIP + SHA256SUMS.txt and publishes the release (it also works when you push a `vX.Y.Z` tag). The changelog section becomes the release notes shown in the in-app update dialog.

By contributing you agree that your contribution is licensed under the MIT License.

# Quality checks for Luftwaechter. Run locally:  powershell -File tools\check.ps1
# Also runs in GitHub Actions before every release. Needs Windows PowerShell 5.1 or newer.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$script = Join-Path $root 'src\Luftwaechter.ps1'
$fail = New-Object System.Collections.ArrayList
function Bad([string]$m) { [void]$fail.Add($m); Write-Host ('FAIL  ' + $m) -ForegroundColor Red }
function Ok([string]$m) { Write-Host ('ok    ' + $m) -ForegroundColor Green }

# 1. The script must parse without errors (a syntax error would break every installed copy after an update)
$tokens = $null; $errs = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$tokens, [ref]$errs)
if ($errs -and $errs.Count -gt 0) { foreach ($e in $errs) { Bad ('syntax line ' + $e.Extent.StartLineNumber + ': ' + $e.Message) } } else { Ok 'Luftwaechter.ps1 parses' }

# 2. UTF-8 with BOM (Windows PowerShell 5.1 needs it for umlauts)
$bytes = [System.IO.File]::ReadAllBytes($script)
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { Ok 'UTF-8 BOM present' } else { Bad 'Luftwaechter.ps1 has no UTF-8 BOM' }

# 3. Versions agree: VERSION, $appVersion, newest CHANGELOG section
$text = [System.IO.File]::ReadAllText($script, [System.Text.Encoding]::UTF8)
$ver = ([System.IO.File]::ReadAllText((Join-Path $root 'VERSION'))).Trim()
$m = [regex]::Match($text, "(?m)^\`$appVersion = '([^']+)'")
if (-not $m.Success) { Bad 'appVersion not found' } elseif ($m.Groups[1].Value -ne $ver) { Bad ('appVersion ' + $m.Groups[1].Value + ' differs from VERSION ' + $ver) } else { Ok ('VERSION = appVersion = ' + $ver) }
$cl = [System.IO.File]::ReadAllText((Join-Path $root 'CHANGELOG.md'), [System.Text.Encoding]::UTF8)
$c = [regex]::Match($cl, '(?m)^## \[([^\]]+)\]')
if (-not $c.Success -or $c.Groups[1].Value -ne $ver) { Bad ('newest CHANGELOG section is not ' + $ver) } else { Ok 'CHANGELOG has a section for this version' }

# 4. Every control the code looks up by name exists in the window (catches FindName returning nothing)
$nm = [regex]::Match($text, '(?s)\$names = @\((.*?)\)')
if ($nm.Success) {
    $list = [regex]::Matches($nm.Groups[1].Value, "'([A-Za-z0-9_]+)'") | ForEach-Object { $_.Groups[1].Value }
    $missing = @($list | Where-Object { $text -notmatch ('x:Name="' + $_ + '"') -and $text -notmatch ('x:Name=\\"' + $_ + '\\"') })
    if ($missing.Count -gt 0) { Bad ('names without x:Name in the window: ' + ($missing -join ', ')) } else { Ok ($list.Count.ToString() + ' named controls found') }
}

# 5. No secrets or personal files in the repository
$bad = @(Get-ChildItem -Path $root -Recurse -File -Force | Where-Object { $_.FullName -notmatch '\\\.git\\' -and ($_.Name -ieq 'config.json' -or $_.Name -ieq 'ha-token.bin' -or $_.Name -ieq 'state.json') })
if ($bad.Count -gt 0) { Bad ('private file in repository: ' + ($bad.Name -join ', ')) } else { Ok 'no private files' }
$hits = @(Get-ChildItem -Path $root -Recurse -File -Force -Include *.ps1, *.md, *.json, *.bat, *.vbs, *.yml | Where-Object { $_.FullName -notmatch '\\\.git\\' -and (Select-String -Path $_.FullName -Pattern 'eyJ[A-Za-z0-9_-]{30,}' -Quiet) })
if ($hits.Count -gt 0) { Bad ('token-like text in: ' + ($hits.Name -join ', ')) } else { Ok 'no token-like text' }

# 5b. Every literal T 'key' used in the code exists in the translation table, and the script keeps Windows line endings
$haveKeys = @([regex]::Matches($text, '(?m)^\s+([A-Za-z0-9_]+) = @\(') | ForEach-Object { $_.Groups[1].Value })
$usedKeys = @([regex]::Matches($text, "\bT '([A-Za-z0-9_]+)'") | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
$unknown = @($usedKeys | Where-Object { $haveKeys -notcontains $_ })
if ($unknown.Count -gt 0) { Bad ('T keys without a translation: ' + ($unknown -join ', ')) } else { Ok ($usedKeys.Count.ToString() + ' translation keys all defined') }
if ([regex]::IsMatch($text, "(?<!\r)\n")) { Bad 'Luftwaechter.ps1 has lines without CRLF line endings' } else { Ok 'CRLF line endings' }
# 5c. The newest CHANGELOG section has German lines (the in-app update dialog shows them to German users)
$sec = [regex]::Match($cl, '(?s)^## \[[^\]]+\][^\r\n]*(.*?)(?=^## \[|\z)', 'Multiline')
if ($sec.Success -and $sec.Groups[1].Value -match '(?m)^- DE: ') { Ok 'newest CHANGELOG section has DE lines' } else { Bad 'newest CHANGELOG section has no "- DE:" lines' }

# 5d. Relative links in the Markdown files point to files that exist
$brokenLinks = @()
foreach ($md in @(Get-ChildItem -Path $root -Filter *.md -File)) {
    $body = [System.IO.File]::ReadAllText($md.FullName, [System.Text.Encoding]::UTF8)
    foreach ($lm in [regex]::Matches($body, '\]\(([^)#\s]+)(#[^)]*)?\)')) {
        $target = $lm.Groups[1].Value
        if ($target -match '^(https?:|mailto:)') { continue }
        if (-not (Test-Path (Join-Path $root $target))) { $brokenLinks += ($md.Name + ' -> ' + $target) }
    }
}
if ($brokenLinks.Count -gt 0) { Bad ('broken document links: ' + ($brokenLinks -join ', ')) } else { Ok 'document links resolve' }
if (Test-Path (Join-Path $root '.gitattributes')) { Ok '.gitattributes present' } else { Bad '.gitattributes missing (line endings are not protected)' }

# 5e. Self-test names are unique (a copy-paste duplicate would hide a missing test)
$smokeNames = @([regex]::Matches($text, "(?m)^\s*Smoke '([^']+)'") | ForEach-Object { $_.Groups[1].Value })
$dupes = @($smokeNames | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
if ($dupes.Count -gt 0) { Bad ('duplicate self-test names: ' + ($dupes -join ', ')) } else { Ok ($smokeNames.Count.ToString() + ' self-tests, names unique') }

# 6. Smoke test: start the widget with demo data, walk through every view, fail on any error (Windows only)
if ($env:OS -eq 'Windows_NT' -and -not $env:LUFT_SKIP_SMOKE) {
    $tmp = Join-Path $env:TEMP ('luft-check-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    Copy-Item -Path (Join-Path $root 'src\*') -Destination $tmp -Recurse
    Copy-Item -Path (Join-Path $root 'CHANGELOG.md') -Destination $tmp
    $out = Join-Path $tmp 'smoke.txt'
    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $tmp 'Luftwaechter.ps1') + '"'), '-SmokeTest') -RedirectStandardOutput $out -PassThru -WindowStyle Hidden
    $null = $p.Handle   # keeps the exit code readable after WaitForExit(timeout)
    if (-not $p.WaitForExit(180000)) { try { $p.Kill() } catch {}; Bad 'smoke test hung (over 3 minutes)' }
    else {
        if (Test-Path $out) { Get-Content $out | ForEach-Object { Write-Host ('      ' + $_) } }
        $p.WaitForExit()
        $passed = (Test-Path $out) -and ((Get-Content $out -Raw) -match 'Smoke test passed')
        if ($p.ExitCode -eq 0 -and $passed) { Ok 'smoke test: widget runs with demo data in every view' } else { Bad ('smoke test failed, exit code ' + $p.ExitCode) }
    }
}

if ($fail.Count -gt 0) { Write-Host ('')
    Write-Host ($fail.Count.ToString() + ' check(s) failed') -ForegroundColor Red; exit 1 }
Write-Host 'All checks passed' -ForegroundColor Green

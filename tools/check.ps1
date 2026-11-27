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

# 3b. The date shown next to the version matches the date of the newest CHANGELOG section
$dm = [regex]::Match($cl, '(?m)^## \[[^\]]+\] - (\d{4})-(\d{2})-(\d{2})')
$ad = [regex]::Match($text, "(?m)^\`$appDate = '([^']+)'")
if ($dm.Success -and $ad.Success) { $want = $dm.Groups[3].Value + '.' + $dm.Groups[2].Value + '.' + $dm.Groups[1].Value; if ($ad.Groups[1].Value -eq $want) { Ok ('release date ' + $want + ' matches') } else { Bad ('appDate ' + $ad.Groups[1].Value + ' differs from the newest CHANGELOG date ' + $want) } } else { Bad 'could not read appDate or the CHANGELOG date' }

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

# 5d2. Every menu text (m_*) in the translation table is used somewhere (no dead menu entries)
$mKeys = @($haveKeys | Where-Object { $_ -like 'm_*' })
$deadM = @($mKeys | Where-Object { $text -notmatch ("T '" + $_ + "'") })
if ($deadM.Count -gt 0) { Bad ('menu texts never used: ' + ($deadM -join ', ')) } else { Ok ($mKeys.Count.ToString() + ' menu texts all used') }

# 5e. Self-test names are unique (a copy-paste duplicate would hide a missing test)
$smokeNames = @([regex]::Matches($text, "(?m)^\s*Smoke '([^']+)'") | ForEach-Object { $_.Groups[1].Value })
$dupes = @($smokeNames | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
if ($dupes.Count -gt 0) { Bad ('duplicate self-test names: ' + ($dupes -join ', ')) } else { Ok ($smokeNames.Count.ToString() + ' self-tests, names unique') }

# 5f. CITATION.cff names the same version as VERSION
$citFile = Join-Path $root 'CITATION.cff'
if (Test-Path $citFile) {
    $cm = [regex]::Match([System.IO.File]::ReadAllText($citFile), '(?m)^version:\s*"([^"]+)"')
    if ($cm.Success -and $cm.Groups[1].Value -eq $ver) { Ok 'CITATION.cff version matches' } else { Bad ('CITATION.cff version differs from VERSION ' + $ver) }
}

# 5g. The command line switch -ShowVersion prints the version (works without Windows)
try {
    $pwExe = (Get-Process -Id $PID).Path
    $sv = (& $pwExe -NoProfile -ExecutionPolicy Bypass -File $script -ShowVersion 2>&1 | Out-String)
    if ($sv -match [regex]::Escape($ver)) { Ok '-ShowVersion prints the version' } else { Bad ('-ShowVersion printed: ' + $sv.Trim()) }
} catch { Bad ('-ShowVersion failed: ' + $_.Exception.Message) }

# 5h. Every letter key handled by the keyboard code is in the README key table
$kd = [regex]::Match($text, '(?s)\$win\.Add_KeyDown\(\{.*?\r?\n\}\)')
$readme = [System.IO.File]::ReadAllText((Join-Path $root 'README.md'), [System.Text.Encoding]::UTF8)
$ks = [regex]::Match($readme, '(?s)## Keyboard shortcuts(.*?)\r?\n## ')
if ($kd.Success -and $ks.Success) {
    $keys = @([regex]::Matches($kd.Value, "(?m)^\s+'([A-Z])' \{") | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    $undoc = @($keys | Where-Object { $ks.Groups[1].Value -notmatch ('\|\s*(?:Ctrl\+(?:Shift\+)?)?' + $_ + '\s*\|') })
    if ($undoc.Count -gt 0) { Bad ('keys missing in the README key table: ' + ($undoc -join ', ')) } else { Ok ($keys.Count.ToString() + ' letter keys all in the README key table') }
} else { Bad 'could not find the key handler or the README key table' }

# 5i. Every setting that is saved in the settings backup is described in docs/SETTINGS.md
$sk = [regex]::Match($text, '(?m)^\$script:settingKeys = @\((.*?)\)')
$setDoc = [System.IO.File]::ReadAllText((Join-Path $root 'docs\SETTINGS.md'), [System.Text.Encoding]::UTF8)
if ($sk.Success) {
    $names = @([regex]::Matches($sk.Groups[1].Value, "'([A-Za-z0-9_]+)'") | ForEach-Object { $_.Groups[1].Value })
    $undocS = @($names | Where-Object { $setDoc -notmatch ('`' + $_ + '`') })
    if ($undocS.Count -gt 0) { Bad ('settings missing in docs/SETTINGS.md: ' + ($undocS -join ', ')) } else { Ok ($names.Count.ToString() + ' backed-up settings all documented') }
} else { Bad 'could not read the settingKeys list' }

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

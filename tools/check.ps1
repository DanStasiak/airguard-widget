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

if ($fail.Count -gt 0) { Write-Host ('')
    Write-Host ($fail.Count.ToString() + ' check(s) failed') -ForegroundColor Red; exit 1 }
Write-Host 'All checks passed' -ForegroundColor Green

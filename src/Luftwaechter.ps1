# Luftwächter / Airguard – indoor air quality, ventilation advice, weather and room devices (Windows widget)
# Copyright (c) 2026 Dan Stasiak. Licensed under the MIT License (see LICENSE). SPDX-License-Identifier: MIT
# Source: https://github.com/DanStasiak/airguard-widget
param([switch]$Install, [switch]$Uninstall, [switch]$SmokeTest)

$appName = 'Luftwaechter'
$appVersion = '5.25.0'
$appDate = '26.11.2026'
$version = 'v' + $appVersion + ' · ' + $appDate
$repoOwner = 'DanStasiak'
$repoName = 'airguard-widget'
$repoUrl = 'https://github.com/' + $repoOwner + '/' + $repoName
$copyright = '© 2026 Dan Stasiak · MIT'
$installDir = Join-Path $env:LOCALAPPDATA $appName
$stateDir = Join-Path $env:APPDATA $appName
if ($SmokeTest) { $stateDir = Join-Path $env:TEMP ('luft-smoke-' + [guid]::NewGuid().ToString('N')) }
$startupLnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'Luftwaechter.lnk'

# ---------- Home Assistant: Verbindung (Adresse in config.json, Token verschlüsselt per Windows-Konto) ----------
function Normalize-HaUrl([string]$u) {
    $u = ([string]$u).Trim().TrimEnd('/')
    if ($u -and $u -notmatch '^https?://') { $u = 'http://' + $u }
    return $u
}
function Get-HaTokenFile { return (Join-Path $stateDir 'ha-token.bin') }
function Save-HaToken([string]$t) {
    Add-Type -AssemblyName System.Security
    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    $b = [System.Security.Cryptography.ProtectedData]::Protect([System.Text.Encoding]::UTF8.GetBytes($t), $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    [System.IO.File]::WriteAllBytes((Get-HaTokenFile), $b)
}
function Get-HaToken {
    try {
        $f = Get-HaTokenFile
        if (-not (Test-Path $f)) { return '' }
        Add-Type -AssemblyName System.Security
        $p = [System.Security.Cryptography.ProtectedData]::Unprotect([System.IO.File]::ReadAllBytes($f), $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
        return [System.Text.Encoding]::UTF8.GetString($p)
    } catch { return '' }
}
function Invoke-Ha([string]$base, [string]$tok, [string]$method, [string]$path, [string]$body) {
    $req = [System.Net.HttpWebRequest]::Create($base + $path)
    $req.Method = $method; $req.Timeout = 15000; $req.ReadWriteTimeout = 15000
    $req.UserAgent = 'Luftwaechter/4'
    $req.Headers.Add('Authorization', 'Bearer ' + $tok)
    if ($body) {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        $req.ContentType = 'application/json; charset=utf-8'; $req.ContentLength = $bytes.Length
        $st = $req.GetRequestStream(); $st.Write($bytes, 0, $bytes.Length); $st.Close()
    }
    $resp = $req.GetResponse()
    try {
        $sr = New-Object System.IO.StreamReader($resp.GetResponseStream(), [System.Text.Encoding]::UTF8)
        $txt = $sr.ReadToEnd(); $sr.Close()
    } finally { $resp.Close() }
    return $txt
}
function Test-Ha([string]$base, [string]$tok) {
    try {
        $t = Invoke-Ha $base $tok 'GET' '/api/' ''
        if ($t -match 'API running') { return 'ok' }
        return 'net'
    } catch [System.Net.WebException] {
        try { if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 401) { return 'auth' } } catch {}
        return 'net'
    } catch { return 'net' }
}
function Save-HaUrl([string]$cfgPath, [string]$u) {
    $c = $null
    try { if (Test-Path $cfgPath) { $c = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json } } catch {}
    if (-not $c) { $c = [pscustomobject]@{ url = ''; switchUrl = ''; defaultRoom = ''; refreshSeconds = 10 } }
    $c | Add-Member -NotePropertyName haUrl -NotePropertyValue $u -Force
    ($c | ConvertTo-Json -Depth 6) | Set-Content -Path $cfgPath -Encoding UTF8
}
function Test-HaHost([string]$base) {
    try {
        $req = [System.Net.HttpWebRequest]::Create($base + '/manifest.json')
        $req.Timeout = 3000; $req.ReadWriteTimeout = 3000; $req.UserAgent = 'Luftwaechter/4'
        $resp = $req.GetResponse()
        try { $sr = New-Object System.IO.StreamReader($resp.GetResponseStream()); $txt = $sr.ReadToEnd(); $sr.Close() } finally { $resp.Close() }
        return ($txt -match 'Home Assistant')
    } catch {
        try { if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 401) { return $true } } catch {}
        return $false
    }
}
function Find-Ha {
    $found = @()
    foreach ($h in 'homeassistant.local', 'homeassistant') {
        try {
            $c = New-Object System.Net.Sockets.TcpClient
            $ar = $c.BeginConnect($h, 8123, $null, $null)
            if ($ar.AsyncWaitHandle.WaitOne(1500) -and $c.Connected) { $u = 'http://' + $h + ':8123'; if ((Test-HaHost $u) -and ($found -notcontains $u)) { $found += $u } }
            $c.Close()
        } catch {}
    }
    $nets = @()
    try {
        foreach ($ni in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
            if ($ni.OperationalStatus -ne 'Up' -or $ni.NetworkInterfaceType -eq 'Loopback') { continue }
            foreach ($ua in $ni.GetIPProperties().UnicastAddresses) {
                if ($ua.Address.AddressFamily -eq 'InterNetwork') {
                    $o = $ua.Address.GetAddressBytes()
                    if ($o[0] -eq 169) { continue }
                    $pre = ([string]$o[0] + '.' + [string]$o[1] + '.' + [string]$o[2] + '.')
                    if ($nets -notcontains $pre) { $nets += $pre }
                }
            }
        }
    } catch {}
    foreach ($pre in $nets) {
        $cl = @(); $ars = @()
        for ($n = 1; $n -le 254; $n++) {
            $c = New-Object System.Net.Sockets.TcpClient
            $cl += $c; $ars += $c.BeginConnect(($pre + [string]$n), 8123, $null, $null)
        }
        Start-Sleep -Milliseconds 1500
        for ($n = 0; $n -lt 254; $n++) {
            try {
                if ($ars[$n].IsCompleted -and $cl[$n].Connected) {
                    $u = 'http://' + $pre + [string]($n + 1) + ':8123'
                    if ((Test-HaHost $u) -and ($found -notcontains $u)) { $found += $u }
                }
            } catch {}
            try { $cl[$n].Close() } catch {}
        }
    }
    return $found
}
function Install-AskHa([string]$cfgPath) {
    Write-Host ''
    Write-Host '=== Home Assistant verbinden / Connect to Home Assistant ==='
    Write-Host 'Adresse z. B. http://homeassistant.local:8123 - leer lassen = spaeter im Widget (Rechtsklick).'
    Write-Host 'Address e.g. http://homeassistant.local:8123 - leave empty = set up later in the widget (right-click).'
    Write-Host 'Suche Home Assistant im Netzwerk ... / Searching the network for Home Assistant ...'
    $cands = @(Find-Ha)
    $pick = ''
    if ($cands.Count -eq 1) {
        Write-Host ('Gefunden / Found: ' + $cands[0])
        $a = Read-Host 'Diese Adresse verwenden? / Use this address? [J/y = Ja/Yes, n = andere / other]'
        if ($a -notmatch '^[nN]') { $pick = $cands[0] }
    } elseif ($cands.Count -gt 1) {
        for ($k = 0; $k -lt $cands.Count; $k++) { Write-Host ('  ' + [string]($k + 1) + ') ' + $cands[$k]) }
        $a = Read-Host 'Nummer waehlen oder Enter fuer manuell / Pick a number or Enter for manual'
        $ix = 0
        if ([int]::TryParse($a, [ref]$ix) -and $ix -ge 1 -and $ix -le $cands.Count) { $pick = $cands[$ix - 1] }
    } else {
        Write-Host 'Nichts gefunden - bitte Adresse eingeben. / Nothing found - please enter the address.'
    }
    for ($try = 1; $try -le 3; $try++) {
        if ($pick) { $u = $pick; $pick = '' } else { $u = Normalize-HaUrl (Read-Host 'Adresse / Address') }
        if (-not $u) { return }
        Write-Host 'Token: Home Assistant > Profil > Sicherheit > Langlebige Zugangstoken > Token erstellen.'
        Write-Host 'Token: Home Assistant > Profile > Security > Long-lived access tokens > Create token.'
        $sec = Read-Host 'Token' -AsSecureString
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        $tok = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        $tok = $tok.Trim()
        $r = Test-Ha $u $tok
        if ($r -eq 'ok') {
            Save-HaUrl $cfgPath $u; Save-HaToken $tok
            Write-Host 'Verbindung OK - Token verschluesselt gespeichert. / Connection OK - token stored encrypted.'
            return
        }
        if ($r -eq 'auth') { Write-Host 'Token abgelehnt. / Token rejected.' } else { Write-Host 'Keine Verbindung (Adresse/Netzwerk?). / No connection (address/network?).' }
    }
    Write-Host 'Nicht eingerichtet - das geht spaeter im Widget per Rechtsklick. / Not set up - you can do it later in the widget via right-click.'
}

function Show-InstallWizard([string]$cfgPath) {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    $script:wzDe = ((Get-Culture).TwoLetterISOLanguageName -eq 'de')
    $x = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Luftwächter" Width="540" SizeToContent="Height" WindowStartupLocation="CenterScreen" Topmost="True" ResizeMode="NoResize" Background="#FF1B222D" FontFamily="Segoe UI">
  <StackPanel Margin="26">
    <DockPanel><Button x:Name="WLang" DockPanel.Dock="Right" Padding="10,2" VerticalAlignment="Top"/><TextBlock Text="Luftwächter" Foreground="White" FontSize="30" FontWeight="Bold"/></DockPanel>
    <TextBlock x:Name="WIntro" Foreground="#FFB3BECD" FontSize="13" TextWrapping="Wrap" Margin="0,4,0,18"/>
    <TextBlock x:Name="WStep1" Foreground="White" FontSize="14" FontWeight="SemiBold"/>
    <DockPanel Margin="0,6,0,0"><Button x:Name="WFind" DockPanel.Dock="Right" Padding="12,4" Margin="8,0,0,0"/><TextBox x:Name="WUrl" Padding="6,5" FontSize="13"/></DockPanel>
    <ComboBox x:Name="WFound" Margin="0,6,0,0" Padding="6,4" FontSize="13" Visibility="Collapsed"/>
    <TextBlock x:Name="WStep2" Foreground="White" FontSize="14" FontWeight="SemiBold" Margin="0,16,0,0"/>
    <PasswordBox x:Name="WTok" Padding="6,5" FontSize="13" Margin="0,6,0,4"/>
    <TextBlock x:Name="WOpen" Foreground="#FF7CB7FF" FontSize="12" Cursor="Hand"/>
    <TextBlock x:Name="WStep3" Foreground="White" FontSize="14" FontWeight="SemiBold" Margin="0,16,0,0"/>
    <CheckBox x:Name="WAuto" Foreground="#FFDFE5EE" FontSize="13" Margin="0,6,0,0" IsChecked="True"/>
    <CheckBox x:Name="WMenu" Foreground="#FFDFE5EE" FontSize="13" Margin="0,4,0,0" IsChecked="True"/>
    <TextBlock x:Name="WMsg" Foreground="#FFFFD27A" FontSize="13" TextWrapping="Wrap" Margin="0,16,0,0" MinHeight="20"/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,14,0,0"><Button x:Name="WSkip" Padding="16,7" Margin="0,0,8,0"/><Button x:Name="WGo" Padding="22,7" IsDefault="True" FontWeight="SemiBold"/></StackPanel>
  </StackPanel>
</Window>
"@
    $d = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$x)))
    $script:wzWin = $d
    $script:wzCfg = $cfgPath
    $script:wzRes = $null
    foreach ($nm in 'WLang', 'WIntro', 'WStep1', 'WFind', 'WUrl', 'WFound', 'WStep2', 'WTok', 'WOpen', 'WStep3', 'WAuto', 'WMenu', 'WMsg', 'WSkip', 'WGo') { Set-Variable -Scope Script -Name ('wz' + $nm) -Value ($d.FindName($nm)) }
    $script:wzApply = {
        $de = $script:wzDe
        $script:wzWLang.Content = $(if ($de) { 'DE | EN' } else { 'EN | DE' })
        $script:wzWIntro.Text = $(if ($de) { 'Willkommen! Hier verbindest du das Widget mit deinem Home Assistant. Räume, Sensoren und Geräte werden danach automatisch gefunden.' } else { 'Welcome! Connect the widget to your Home Assistant here. Rooms, sensors and devices are found automatically afterwards.' })
        $script:wzWStep1.Text = $(if ($de) { '1  Adresse von Home Assistant' } else { '1  Home Assistant address' })
        $script:wzWFind.Content = $(if ($de) { 'Im Netzwerk suchen' } else { 'Search network' })
        $script:wzWStep2.Text = $(if ($de) { '2  Langlebiger Zugangstoken' } else { '2  Long-lived access token' })
        $script:wzWOpen.Text = $(if ($de) { 'Token-Seite in Home Assistant öffnen (Profil → Sicherheit → Token erstellen)' } else { 'Open the token page in Home Assistant (Profile → Security → Create token)' })
        $script:wzWStep3.Text = $(if ($de) { '3  Optionen' } else { '3  Options' })
        $script:wzWAuto.Content = $(if ($de) { 'Mit Windows starten' } else { 'Start with Windows' })
        $script:wzWMenu.Content = $(if ($de) { 'Eintrag im Startmenü anlegen' } else { 'Add a Start menu entry' })
        $script:wzWSkip.Content = $(if ($de) { 'Später einrichten' } else { 'Set up later' })
        $script:wzWGo.Content = $(if ($de) { 'Verbinden und installieren' } else { 'Connect and install' })
    }
    & $script:wzApply
    $script:wzWUrl.Text = 'http://homeassistant.local:8123'
    $script:wzWLang.Add_Click({ $script:wzDe = -not $script:wzDe; & $script:wzApply })
    $script:wzWOpen.Add_MouseLeftButtonDown({ try { $u0 = Normalize-HaUrl $script:wzWUrl.Text; if ($u0) { Start-Process ($u0 + '/profile/security') } } catch {} })
    $script:wzWFound.Add_SelectionChanged({ if ($script:wzWFound.SelectedItem) { $script:wzWUrl.Text = [string]$script:wzWFound.SelectedItem } })
    $script:wzWFind.Add_Click({
        $script:wzWMsg.Text = $(if ($script:wzDe) { 'Suche Home Assistant im Netzwerk …' } else { 'Searching the network for Home Assistant …' })
        $script:wzWin.Dispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::Render)
        $f = @(Find-Ha)
        $script:wzWFound.Items.Clear(); $script:wzWFound.Visibility = 'Collapsed'
        if ($f.Count -eq 0) { $script:wzWMsg.Text = $(if ($script:wzDe) { 'Nichts gefunden. Bitte die Adresse selbst eintragen.' } else { 'Nothing found. Please type the address yourself.' }); return }
        $script:wzWUrl.Text = $f[0]
        if ($f.Count -gt 1) { foreach ($u in $f) { [void]$script:wzWFound.Items.Add($u) }; $script:wzWFound.Visibility = 'Visible' }
        $script:wzWMsg.Text = $(if ($script:wzDe) { 'Gefunden: ' + $f[0] } else { 'Found: ' + $f[0] })
    })
    $script:wzWSkip.Add_Click({ $script:wzRes = [pscustomobject]@{ ok = $false; auto = [bool]$script:wzWAuto.IsChecked; menu = [bool]$script:wzWMenu.IsChecked }; $script:wzWin.DialogResult = $false })
    $script:wzWGo.Add_Click({
        $de = $script:wzDe
        $u1 = Normalize-HaUrl $script:wzWUrl.Text; $t1 = ([string]$script:wzWTok.Password).Trim()
        if (-not $u1 -or -not $t1) { $script:wzWMsg.Text = $(if ($de) { 'Bitte Adresse und Token eintragen, oder „Später einrichten“ wählen.' } else { 'Please enter the address and the token, or choose "Set up later".' }); return }
        $script:wzWMsg.Text = $(if ($de) { 'Teste die Verbindung …' } else { 'Testing the connection …' })
        $script:wzWin.Dispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::Render)
        $r1 = Test-Ha $u1 $t1
        if ($r1 -eq 'auth') { $script:wzWMsg.Text = $(if ($de) { 'Der Token wurde abgelehnt. Bitte einen neuen erstellen.' } else { 'The token was rejected. Please create a new one.' }); return }
        if ($r1 -ne 'ok') { $script:wzWMsg.Text = $(if ($de) { 'Keine Verbindung. Stimmen Adresse und Netzwerk?' } else { 'No connection. Are the address and network correct?' }); return }
        Save-HaUrl $script:wzCfg $u1; Save-HaToken $t1
        $n = ''
        try {
            $tpl = '{% set ns = namespace(n=0) %}{% for a in areas() %}{% set ok = namespace(v=false) %}{% for e in area_entities(a) %}{% if state_attr(e, "device_class") in ["carbon_dioxide", "pm25"] and states[e] is not none %}{% set ok.v = true %}{% endif %}{% endfor %}{% if ok.v %}{% set ns.n = ns.n + 1 %}{% endif %}{% endfor %}{{ ns.n }}'
            $n = (Invoke-Ha $u1 $t1 'POST' '/api/template' (@{ template = $tpl } | ConvertTo-Json -Compress)).Trim()
        } catch {}
        $script:wzRes = [pscustomobject]@{ ok = $true; auto = [bool]$script:wzWAuto.IsChecked; menu = [bool]$script:wzWMenu.IsChecked; rooms = $n }
        if ($n -match '^\d+$') { $script:wzWMsg.Text = $(if ($de) { 'Verbunden. ' + $n + ' Räume mit Luftsensor gefunden.' } else { 'Connected. Found ' + $n + ' rooms with an air sensor.' }) } else { $script:wzWMsg.Text = $(if ($de) { 'Verbunden.' } else { 'Connected.' }) }
        $script:wzWin.Dispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::Render)
        Start-Sleep -Milliseconds 1400
        $script:wzWin.DialogResult = $true
    })
    [void]$d.ShowDialog()
    return $script:wzRes
}
$startMenuLnk = Join-Path ([Environment]::GetFolderPath('Programs')) 'Luftwächter.lnk'
function New-StartMenuShortcut {
    try {
        $sh = New-Object -ComObject WScript.Shell
        $l = $sh.CreateShortcut($startMenuLnk)
        $l.TargetPath = 'wscript.exe'
        $l.Arguments = '"' + (Join-Path $installDir 'Start.vbs') + '"'
        $l.WorkingDirectory = $installDir
        $l.Description = 'Luftwächter / Airguard'
        $l.Save()
    } catch {}
}

if ($Install) {
    $src = Split-Path -Parent $MyInvocation.MyCommand.Path
    New-Item -ItemType Directory -Force -Path $installDir | Out-Null
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*Luftwaechter.ps1*' -and $_.ProcessId -ne $PID } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
    foreach ($f in 'Luftwaechter.ps1', 'Start.vbs', 'Installieren.bat', 'Deinstallieren.bat', 'config.example.json', 'LICENSE', 'README.md', 'CHANGELOG.md', 'VERSION') {
        $sf = Join-Path $src $f
        if (Test-Path $sf) { Copy-Item -Force $sf $installDir }
    }
    $sc = Join-Path $src 'config.json'; $dc = Join-Path $installDir 'config.json'
    $haOld = ''
    try { $haOld = [string]((Get-Content $dc -Raw -Encoding UTF8 | ConvertFrom-Json).haUrl) } catch {}
    if (Test-Path $sc) { Copy-Item -Force $sc $dc } elseif (-not (Test-Path $dc)) { Copy-Item -Force (Join-Path $src 'config.example.json') $dc }
    if ($haOld) { try { $nc = Get-Content $dc -Raw -Encoding UTF8 | ConvertFrom-Json; if (-not $nc.haUrl) { Save-HaUrl $dc $haOld } } catch {} }
    $haCur = ''
    try { $haCur = [string]((Get-Content $dc -Raw -Encoding UTF8 | ConvertFrom-Json).haUrl) } catch {}
    $wiz = [pscustomobject]@{ ok = $false; auto = $true; menu = $true }
    if (-not ($haCur -and (Test-Path (Get-HaTokenFile)))) {
        try { $w0 = Show-InstallWizard $dc; if ($w0) { $wiz = $w0 } }
        catch { Write-Host ('Fenster nicht verfügbar, Text-Einrichtung: ' + $_.Exception.Message); Install-AskHa $dc }
    }
    if ($wiz.auto) {
        $sh = New-Object -ComObject WScript.Shell
        $lnk = $sh.CreateShortcut($startupLnk)
        $lnk.TargetPath = 'wscript.exe'
        $lnk.Arguments = '"' + (Join-Path $installDir 'Start.vbs') + '"'
        $lnk.WorkingDirectory = $installDir
        $lnk.Save()
    } else { Remove-Item -Force $startupLnk -ErrorAction SilentlyContinue }
    if ($wiz.menu) { New-StartMenuShortcut }
    Start-Process 'wscript.exe' -ArgumentList ('"' + (Join-Path $installDir 'Start.vbs') + '"')
    exit 0
}
if ($Uninstall) {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*Luftwaechter.ps1*' -and $_.ProcessId -ne $PID } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
    Remove-Item -Force $startupLnk, $startMenuLnk -ErrorAction SilentlyContinue
    exit 0
}

# nur eine Instanz
$created = $false
$mutex = New-Object System.Threading.Mutex($true, $(if ($SmokeTest) { 'Local\LuftwaechterSmoke' } else { 'Local\LuftwaechterWidget' }), [ref]$created)
if (-not $created) { if ($SmokeTest) { exit 3 }; exit 0 }

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
try { Add-Type -AssemblyName System.Windows.Forms, System.Drawing; Add-Type -Namespace LW -Name Native -MemberDefinition '[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool DestroyIcon(System.IntPtr h);' } catch {}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$inv = [Globalization.CultureInfo]::InvariantCulture

$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfgFile = Join-Path $dir 'config.json'
$cfg = $null
try { if (Test-Path $cfgFile) { $cfg = Get-Content $cfgFile -Raw -Encoding UTF8 | ConvertFrom-Json } } catch {}
if (-not $cfg) { $cfg = [pscustomobject]@{ url = ''; switchUrl = ''; defaultRoom = ''; refreshSeconds = 10 } }
$place = [string]$cfg.place
$footerCfg = [string]$cfg.footer
$url = [string]$cfg.url
$switchUrl = [string]$cfg.switchUrl
$script:haUrl = Normalize-HaUrl ([string]$cfg.haUrl)
$script:haTok = Get-HaToken
$script:haMode = [bool]($script:haUrl -and $script:haTok)
$script:canSwitch = [bool]($script:haMode -or $switchUrl)
$script:haDevs = @{}
$interval = 10
$updMinutes = 60
if ($cfg.updateCheckMinutes) { $updMinutes = [Math]::Max(15, [Math]::Min([int]$cfg.updateCheckMinutes, 1440)) }
if ($cfg.refreshSeconds) { $interval = [Math]::Max(2, [Math]::Min([int]$cfg.refreshSeconds, 10)) }

# ---------- gespeicherter Zustand ----------
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
$stateFile = Join-Path $stateDir 'state.json'
$logFile = Join-Path $stateDir 'protokoll.txt'
function Write-Log([string]$m) {
    try {
        if ((Test-Path $logFile) -and ((Get-Item $logFile).Length -gt 100000)) { Remove-Item $logFile -Force }
        Add-Content -Path $logFile -Value ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + '  ' + $m) -Encoding UTF8
    } catch {}
}
$state = @{ left = $null; top = $null; topmost = $false; topmostSet = $false; popup = $true; tray = $true; room = [string]$cfg.defaultRoom; size = 'M'; weatherOpen = $false; drawerOpen = $false; sound = $true; sparkHours = 3; metric = 0; hidden = @(); lang = 'de'; hist = @{}; hist7 = @{}; sensors = @{}; simple = $true; tourDone = $false; demo = $false; theme = 'auto'; seenVer = ''; opacity = 1.0; locked = $false; taskbar = $true; hoverFull = $true }
try { if ((Get-Culture).TwoLetterISOLanguageName -ne 'de') { $state.lang = 'en' } } catch {}
if (Test-Path $stateFile) {
    try {
        $s = Get-Content $stateFile -Raw | ConvertFrom-Json
        if ($null -ne $s.left) { $state.left = [double]$s.left }
        if ($null -ne $s.top) { $state.top = [double]$s.top }
        if ($s.topmostSet -and $null -ne $s.topmost) { $state.topmost = [bool]$s.topmost; $state.topmostSet = $true }
        if ($null -ne $s.popup) { $state.popup = [bool]$s.popup }
        if ($null -ne $s.tray) { $state.tray = [bool]$s.tray }
        if ($s.room) { $state.room = [string]$s.room }
        if ($s.size) { $state.size = [string]$s.size }
        if ($null -ne $s.weatherOpen) { $state.weatherOpen = [bool]$s.weatherOpen }
        if ($null -ne $s.drawerOpen) { $state.drawerOpen = [bool]$s.drawerOpen }
        if ($null -ne $s.sound) { $state.sound = [bool]$s.sound }
        if ($s.sparkHours -eq 24 -or $s.sparkHours -eq 168) { $state.sparkHours = [int]$s.sparkHours }
        if ($s.seenVer) { $state.seenVer = [string]$s.seenVer }
        if ($null -ne $s.opacity -and [double]$s.opacity -ge 0.5 -and [double]$s.opacity -le 1.0) { $state.opacity = [double]$s.opacity }
        if ($null -ne $s.locked) { $state.locked = [bool]$s.locked }
        if ($null -ne $s.taskbar) { $state.taskbar = [bool]$s.taskbar }
        if ($null -ne $s.hoverFull) { $state.hoverFull = [bool]$s.hoverFull }
        if ($s.snooze) { $state.snooze = [string]$s.snooze }
        if ($s.theme) { $state.theme = [string]$s.theme }
        if ($null -ne $s.demo) { $state.demo = [bool]$s.demo }
        if ($null -ne $s.tourDone) { $state.tourDone = [bool]$s.tourDone }
        if ($null -ne $s.simple) { $state.simple = [bool]$s.simple }
        if ($s.hist7) { foreach ($p in $s.hist7.PSObject.Properties) { $state.hist7[$p.Name] = @($p.Value) } }
        if ($s.hidden) { $state.hidden = @($s.hidden | ForEach-Object { [string]$_ }) }
        if ($null -ne $s.metric -and [int]$s.metric -ge 0 -and [int]$s.metric -le 3) { $state.metric = [int]$s.metric }
        if ($s.lang -eq 'en' -or $s.lang -eq 'de') { $state.lang = [string]$s.lang }
        if ($s.sensors) { foreach ($p in $s.sensors.PSObject.Properties) { $h0 = @{}; foreach ($q in $p.Value.PSObject.Properties) { if ($q.Value) { $h0[$q.Name] = [string]$q.Value } }; $state.sensors[$p.Name] = $h0 } }
        if ($s.hist) { foreach ($p in $s.hist.PSObject.Properties) { $state.hist[$p.Name] = @($p.Value) } }
    } catch {}
}

# ---------- Oberfläche ----------
$chipXaml = ''
for ($i = 1; $i -le 4; $i++) {
    $r = [Math]::Floor(($i - 1) / 2); $c = ($i - 1) % 2
    $chipXaml += @"
<Border x:Name="C$i" Cursor="Hand" Grid.Row="$r" Grid.Column="$c" CornerRadius="12" Background="#FF3C424C" Margin="3" Padding="9,5">
  <DockPanel>
    <Ellipse x:Name="D$i" Width="9" Height="9" Fill="#FF7A8594" DockPanel.Dock="Left" Margin="0,0,8,0"/>
    <StackPanel><TextBlock x:Name="V$i" Foreground="White" FontSize="19" FontWeight="Bold"/><TextBlock x:Name="K$i" Foreground="#FFB3BECD" FontSize="11"/></StackPanel>
  </DockPanel>
</Border>
"@
}
$tileXaml = ''
for ($i = 1; $i -le 4; $i++) {
    $r = [Math]::Floor(($i - 1) / 2); $c = ($i - 1) % 2
    $tileXaml += @"
<Border Grid.Row="$r" Grid.Column="$c" CornerRadius="10" Background="#33000000" Margin="3" Padding="9,4">
  <StackPanel><TextBlock x:Name="WK$i" Foreground="#FFB3BECD" FontSize="11"/><TextBlock x:Name="WV$i" Foreground="White" FontSize="14" FontWeight="SemiBold"/></StackPanel>
</Border>
"@
}

$script:Strings = @{
    sz_c = @('kompakt', 'compact')
    sz_p = @('Pille', 'Pill')
    more = @('▾ Mehr', '▾ More')
    less = @('▴ Weniger', '▴ Less')
    outside = @('DRAUSSEN', 'OUTSIDE')
    now = @('jetzt', 'now')
    spark = @('{0} Std · Linie = 1000 ppm', '{0} h · line = 1000 ppm')
    spark_dust = @('Feinstaub · {0} Std · Linie 20', 'Fine dust · {0} h · line 20')
    spark_temp = @('Temperatur · {0} Std', 'Temperature · {0} h')
    spark_hum = @('Feuchte · {0} Std · 30–60 %', 'Humidity · {0} h · 30–60 %')
    spark_co2 = @('CO₂ · {0} Std · Linie 1000', 'CO₂ · {0} h · line 1000')
    spark_wait = @('Der Verlauf wird ab jetzt gesammelt …', 'History is being collected from now on …')
    dev_hide = @('Ausblenden', 'Hide')
    dev_unhide = @('{0} ausgeblendet · alle anzeigen', '{0} hidden · show all')
    mm = @('Heute: Min {0} · Max {1} {2}', 'Today: min {0} · max {1} {2}')
    chip_tip_1 = @('CO₂: gut unter 1000 ppm, mittel bis 1500, darüber schlecht. Tippen: Kurve. Rechtsklick: Erklärung.', 'CO₂: good below 1000 ppm, fair up to 1500, poor above. Tap: curve. Right-click: explanation.')
    chip_tip_2 = @('Feinstaub: gut unter 20 µg/m³, mittel bis 50, darüber schlecht. Tippen: Kurve. Rechtsklick: Erklärung.', 'Fine dust: good below 20 µg/m³, fair up to 50, poor above. Tap: curve. Right-click: explanation.')
    chip_tip_3 = @('Temperatur: gut 17 bis 23 °C, mittel 13 bis 25 °C, sonst schlecht. Tippen: Kurve. Rechtsklick: Erklärung.', 'Temperature: good 17 to 23 °C, fair 13 to 25 °C, otherwise poor. Tap: curve. Right-click: explanation.')
    chip_tip_4 = @('Luftfeuchte: gut 30 bis 60 %, mittel 25 bis 70 %, sonst schlecht. Tippen: Kurve. Rechtsklick: Erklärung.', 'Humidity: good 30 to 60 %, fair 25 to 70 %, otherwise poor. Tap: curve. Right-click: explanation.')
    mm2 = @('Heute: Min {0} {2} um {3} · Max {1} {2} um {4}', 'Today: min {0} {2} at {3} · max {1} {2} at {4}')
    tray_worst = @('⚠ Schlechter: {0}', '⚠ Worse: {0}')
    chip_tip = @('Tippen: Verlauf dieses Werts anzeigen', 'Tap: show the history of this value')
    spark_tip = @('Tippen: 3 Std / 24 Std / 7 Tage', 'Tap: 3 h / 24 h / 7 days')
    pill_tip = @('Doppelklick: wieder groß', 'Double-click: expand')
    help_tip = @('Hilfe', 'Help')
    lang_tip = @('Sprache / Language', 'Language / Sprache')
    tr_up = @('steigt seit {0} Min', 'rising for {0} min')
    tr_dn = @('sinkt seit {0} Min', 'falling for {0} min')
    tr_flat = @('stabil', 'steady')
    fc_good = @('Luft wieder gut in ca. {0} Min', 'Air good again in about {0} min')
    fc_over = @('Über 1000 ppm in ca. {0} Min', 'Above 1000 ppm in about {0} min')
    peak = @('Heute: Höchstwert {0} ppm um {1}', 'Today: peak {0} ppm at {1}')
    avg = @('Ø {0} ppm · {1} % der Zeit unter 1000 ppm', 'Avg {0} ppm · {1} % of the time below 1000 ppm')
    grp_Licht = @('Licht', 'Light')
    grp_Strom = @('Strom', 'Power')
    grp_Heizung = @('Heizung', 'Heating')
    grp_Rollo = @('Rollo', 'Blinds')
    no_dev = @('Für diesen Raum sind keine Geräte freigegeben.', 'No devices are enabled for this room.')
    no_switch = @('Schalten ist noch nicht eingerichtet (nur Anzeige).', 'Switching is not set up yet (display only).')
    aired = @('Gelüftet: {0} → {1} ppm', 'Ventilated: {0} → {1} ppm')
    dev_title = @('Geräte · ', 'Devices · ')
    lv_good = @('Gut', 'Good')
    lv_mid = @('Mittel', 'Fair')
    lv_bad = @('Schlecht', 'Poor')
    no_vals = @('Keine Werte', 'No data')
    pill_no = @('keine Werte', 'no data')
    rem = @('Noch ca. {0} Minuten.', 'About {0} more minutes.')
    vent_ok = @('Lange genug gelüftet. Fenster kann jetzt zu.', 'Ventilated long enough. You can close the window now.')
    vent_run = @('Lüften läuft', 'Ventilating')
    vent_left = @('Noch ca. {0} Min. Tippen zum Abbrechen.', 'About {0} min left. Tap to cancel.')
    vent_close = @('Fenster jetzt schließen', 'Close the window now')
    vent_over = @('Die Lüftungszeit ist um.', 'Ventilation time is over.')
    tap_timer = @(' Tippen startet den Timer.', ' Tap to start the timer.')
    k_pm = @('Staub', 'Dust')
    k_t = @('Temp.', 'Temp.')
    k_h = @('Feuchte', 'Humidity')
    w_hum = @('Feuchte', 'Humidity')
    w_cl = @('Wolken', 'Clouds')
    w_pr = @('Druck', 'Pressure')
    w_na = @('Wetter gerade nicht verfügbar', 'Weather currently unavailable')
    footer = @('Daten: Home Assistant', 'Data: Home Assistant')
    offline = @('Offline', 'Offline')
    no_conn = @('Keine Verbindung', 'No connection')
    stale = @('Die Werte können veraltet sein. Es wird weiter versucht.', 'Values may be outdated. Still trying.')
    no_air = @('Die Luftwerte können gerade nicht geladen werden. Es wird weiter versucht.', 'The air readings cannot be loaded right now. Still trying.')
    asof = @('Stand ', 'As of ')
    rooms_loading = @('Räume werden geladen …', 'Loading rooms …')
    m_refresh = @('Jetzt aktualisieren', 'Refresh now')
    m_tray = @('Symbol im Infobereich (neben der Uhr)', 'Icon in the notification area (next to the clock)')
    tray_open = @('Luftwächter öffnen', 'Open Luftwächter')
    tray_none = @('Keine Daten', 'No data')
    h15 = @('Infobereich-Symbol (neben der Uhr)', 'Tray icon (next to the clock)')
    b15 = @('Neben der Uhr zeigt ein farbiger Punkt die Luft im Raum: grün gut, gelb mittel, rot schlecht. Fahr mit der Maus darüber für CO₂ und Rat. Ein Klick holt das Widget nach vorn, auch wenn es hinter anderen Fenstern oder minimiert ist. Wenn gelüftet werden soll, erscheint dort zusätzlich eine kleine Windows-Meldung (7–22 Uhr, höchstens alle 30 Minuten). Abschaltbar per Rechtsklick: "Symbol im Infobereich".', 'Next to the clock a colored dot shows the room air: green good, yellow fair, red poor. Hover for CO₂ and advice. One click brings the widget to the front, even when it is behind other windows or minimized. When ventilation is needed a small Windows notification appears as well (07:00-22:00, at most every 30 minutes). Switch it off via right-click: "Icon in the notification area".')
    m_pop = @('Beim Lüften kurz nach vorn holen', 'Bring to front briefly when ventilation is needed')
    m_top = @('Immer im Vordergrund', 'Always on top')
    m_sound = @('Hinweiston beim Lüften', 'Sound when ventilating')
    m_reset = @('Fenster zurücksetzen (oben rechts)', 'Reset window (top right)')
    m_log = @('Protokoll öffnen (bei Problemen)', 'Open log (for problems)')
    m_help = @('Hilfe', 'Help')
    m_exit = @('Beenden', 'Quit')
    no_errors = @('Keine Fehler protokolliert.', 'No errors logged.')
    setup = @('Noch nicht eingerichtet', 'Not set up yet')
    setup_d = @('Rechtsklick, dann "Mit Home Assistant verbinden…" – oder zum Ausprobieren "Demo ausprobieren". Siehe Hilfe.', 'Right-click, then "Connect to Home Assistant…" – or "Try the demo" to look around. See Help.')
    ha_norooms = @('Keine Räume gefunden', 'No rooms found')
    ha_norooms_d = @('In Home Assistant braucht ein Bereich (Area) einen CO₂- oder Feinstaub-Sensor (Geräteklasse carbon_dioxide oder pm25). Siehe Hilfe.', 'In Home Assistant an area needs a CO₂ or fine-dust sensor (device class carbon_dioxide or pm25). See Help.')
    m_sens = @('Sensoren für diesen Raum wählen…', 'Choose sensors for this room…')
    sens_title = @('Sensoren · {0}', 'Sensors · {0}')
    sens_intro = @('Woher kommen die vier Messwerte? „Automatisch“ bildet den Mittelwert aller passenden Sensoren im Raum (Taupunkt, Geräte-Temperatur und veraltete Sensoren werden ausgelassen).', 'Where do the four readings come from? "Automatic" averages all suitable sensors in the room (dew point, device temperature and stale sensors are skipped).')
    sens_co2 = @('CO₂', 'CO₂')
    sens_pm = @('Feinstaub', 'Fine dust')
    sens_t = @('Temperatur', 'Temperature')
    sens_h = @('Luftfeuchte', 'Humidity')
    sens_none = @('keine Sensoren', 'no sensors')
    sens_save = @('Speichern', 'Save')
    m_mode_full = @('Alle Details anzeigen', 'Show all details')
    m_mode_simple = @('Einfache Ansicht', 'Simple view')
    tour_h = @('Willkommen bei Luftwächter', 'Welcome to Luftwächter')
    tour_t = @('Das Gesicht zeigt, wie die Luft in deinem Raum ist. Der große Satz sagt dir, was zu tun ist, zum Beispiel „Bitte Fenster öffnen“. Mit „Details“ oben links siehst du alle Messwerte.', 'The face shows how the air in your room is. The big sentence tells you what to do, for example "Please open the window". With "Details" at the top left you can see all the readings.')
    tour_ok = @('Verstanden', 'Got it')
    mode_more = @('Details', 'Details')
    mode_simple = @('Einfach', 'Simple')
    mode_tip = @('Zwischen einfacher Ansicht und allen Details wechseln', 'Switch between the simple view and all details')
    tab_lbl = @('Lampen & Steckdosen', 'Lamps & plugs')
    m_ha = @('Mit Home Assistant verbinden…', 'Connect to Home Assistant…')
    ha_title = @('Mit Home Assistant verbinden', 'Connect to Home Assistant')
    ha_intro = @('Trage die Adresse deines Home Assistant und einen langlebigen Zugangstoken ein. Den Token erstellst du in Home Assistant unter Profil → Sicherheit → Langlebige Zugangstoken. Er wird verschlüsselt auf diesem PC gespeichert (nur für dein Windows-Konto).', 'Enter the address of your Home Assistant and a long-lived access token. Create the token in Home Assistant under Profile → Security → Long-lived access tokens. It is stored encrypted on this PC (only for your Windows account).')
    ha_url = @('Adresse (z. B. http://homeassistant.local:8123)', 'Address (e.g. http://homeassistant.local:8123)')
    ha_tok = @('Zugangstoken', 'Access token')
    ha_open = @('Token-Seite in Home Assistant öffnen', 'Open the token page in Home Assistant')
    ha_find = @('Suchen', 'Find')
    ha_go = @('Verbinden', 'Connect')
    ha_cancel = @('Abbrechen', 'Cancel')
    ha_searching = @('Suche im Netzwerk … (ca. 5 Sekunden)', 'Searching the network … (about 5 seconds)')
    ha_found = @('Gefunden: {0}', 'Found: {0}')
    ha_nofind = @('Nichts gefunden. Bitte die Adresse selbst eintragen.', 'Nothing found. Please enter the address yourself.')
    ha_empty = @('Bitte Adresse und Token eingeben.', 'Please enter the address and the token.')
    ha_testing = @('Prüfe die Verbindung …', 'Checking the connection …')
    ha_auth = @('Der Token wurde abgelehnt. Bitte neu erstellen und einfügen.', 'The token was rejected. Please create a new one and paste it.')
    ha_net = @('Keine Verbindung. Adresse und Netzwerk prüfen.', 'No connection. Check the address and the network.')
    h17 = @('♥ Dank an Home Assistant', '♥ Thanks to Home Assistant')
    b17 = @('Luftwächter funktioniert dank Home Assistant, der freien, lokalen Smart-Home-Software, die dein Zuhause steuert. Wenn dir Home Assistant gefällt, kannst du das Projekt unterstützen: Besuche home-assistant.io (Rechtsklick → „Home Assistant unterstützen“), spende an die Open Home Foundation oder abonniere Home Assistant Cloud. Luftwächter ist ein unabhängiges Projekt und steht in keiner Verbindung zu Home Assistant oder zur Open Home Foundation und wird von ihnen nicht empfohlen oder unterstützt. „Home Assistant“ ist eine Marke der jeweiligen Inhaber.', 'Luftwächter works thanks to Home Assistant, the free, local smart-home software that runs your home. If you like Home Assistant, you can support the project: visit home-assistant.io (right-click → "Support Home Assistant"), donate to the Open Home Foundation or subscribe to Home Assistant Cloud. Luftwächter is an independent project and is not affiliated with, endorsed by or sponsored by Home Assistant or the Open Home Foundation. "Home Assistant" is a trademark of its respective owners.')
    m_ha_support = @('♥ Home Assistant unterstützen', '♥ Support Home Assistant')
    h16 = @('Home Assistant direkt', 'Home Assistant direct')
    b16 = @('Das Widget spricht direkt mit deinem Home Assistant. Jeder Bereich (Area) mit einem CO₂- oder Feinstaub-Sensor wird ein Raum. Messwerte, Fensterkontakte (Geräteklasse "window"), Lichter, Steckdosen, Heizungen und Rollos des Bereichs werden automatisch gefunden. Das Wetter kommt aus der ersten Wetter-Entität. Stört ein Gerät: Rechtsklick auf die Zeile, Ausblenden (unten bringt "ausgeblendet · alle anzeigen" sie zurück). Typische Einstellungs-Schalter (Kindersicherung, Internetzugang, Kalibrierung) blendet das Widget selbst aus. Nur bestimmte Geräte anzeigen: In Home Assistant das Label "airguard" an diese Entitäten hängen. Verbindung ändern: Rechtsklick, "Mit Home Assistant verbinden…".', 'The widget talks directly to your Home Assistant. Every area with a CO₂ or fine-dust sensor becomes a room. Readings, window contacts (device class "window"), lights, plugs, heaters and blinds of the area are found automatically. Weather comes from the first weather entity. If a device is in the way: right-click its row and choose Hide ("{0} hidden · show all" at the bottom brings them back). Typical setting switches (child lock, internet access, calibration) are hidden automatically. To show only certain devices: give those entities the label "airguard" in Home Assistant. Change the connection: right-click, "Connect to Home Assistant…".')
    m_cfg = @('Konfiguration öffnen', 'Open configuration')
    m_upd = @('Nach Updates suchen', 'Check for updates')
    day_good = @('Heute: {0} % der Zeit gute Luft ⭐', 'Today: good air {0} % of the time ⭐')
    day_ok = @('Heute: {0} % der Zeit gute Luft 👍', 'Today: good air {0} % of the time 👍')
    day_low = @('Heute: nur {0} % gute Luft – lüfte öfter 🌬', 'Today: only {0} % good air – ventilate more often 🌬')
    m_demo = @('Demo ausprobieren', 'Try the demo')
    m_ha_open = @('Home Assistant im Browser öffnen', 'Open Home Assistant in the browser')
    m_ha_panel = @('Luftwächter-Ansicht in Home Assistant öffnen', 'Open the Luftwächter panel in Home Assistant')
    m_news = @('Was ist neu? (Versionshinweise)', 'What''s new? (release notes)')
    m_bug = @('Problem melden oder Idee vorschlagen (GitHub)', 'Report a problem or suggest an idea (GitHub)')
    m_data = @('Datenordner öffnen', 'Open the data folder')
    tray_ha = @('Home Assistant öffnen', 'Open Home Assistant')
    m_pic_save = @('Bild vom Widget speichern (PNG)', 'Save a picture of the widget (PNG)')
    m_pic_copy = @('Bild vom Widget kopieren', 'Copy a picture of the widget')
    m_about = @('Über Luftwächter…', 'About Luftwächter…')
    about_t = @('Luftwächter {0}\nEin kleines Widget, das zeigt, wie gut die Luft in deinen Räumen ist.\n\nKostenlos und quelloffen (MIT-Lizenz) · © 2026 Dan Stasiak\nhttps://github.com/DanStasiak/airguard-widget\n\nLuftwächter ist ein unabhängiges Community-Projekt und nicht mit Home Assistant, Nabu Casa oder der Open Home Foundation verbunden.\n\nDatenschutz: Das Widget spricht nur mit deinem Home Assistant und prüft bei GitHub auf neue Versionen. Es gibt keine Telemetrie.', 'Luftwächter {0}\nA small widget that shows how good the air is in your rooms.\n\nFree and open source (MIT licence) · © 2026 Dan Stasiak\nhttps://github.com/DanStasiak/airguard-widget\n\nLuftwächter is an independent community project and is not affiliated with Home Assistant, Nabu Casa or the Open Home Foundation.\n\nPrivacy: the widget only talks to your Home Assistant and checks GitHub for new versions. There is no telemetry.')
    pic_saved = @('Bild gespeichert: {0}', 'Picture saved: {0}')
    offline_hint = @('Keine Verbindung. Prüfe, ob Home Assistant läuft und der PC im Heimnetz ist. Bleibt es so: Rechtsklick → Erweitert → „Diagnose kopieren“.', 'No connection. Check that Home Assistant is running and this PC is on your home network. If it stays like this: right-click → More → “Copy diagnostics”.')
    m_lock = @('Position sperren', 'Lock position')
    m_opacity = @('Durchsichtigkeit: {0} %', 'Transparency: {0} %')
    m_taskbar = @('In der Taskleiste anzeigen', 'Show in the taskbar')
    m_hover = @('Bei Mausberührung voll deckend', 'Fully opaque on hover')
    m_export = @('Einstellungen sichern…', 'Back up settings…')
    m_import = @('Einstellungen wiederherstellen…', 'Restore settings…')
    m_auto = @('Mit Windows starten', 'Start with Windows')
    m_diag = @('Diagnose kopieren (für Support)', 'Copy diagnostics (for support)')
    m_demo_off = @('Demo beenden', 'Stop the demo')
    demo_tag = @('Demo', 'Demo')
    m_theme_auto = @('Design: Automatisch (Tag/Nacht)', 'Theme: Automatic (day/night)')
    m_theme_day = @('Design: Tag', 'Theme: Day')
    m_theme_night = @('Design: Nacht', 'Theme: Night')
    m_snooze = @('Ruhe für 1 Stunde', 'Quiet for 1 hour')
    m_snooze_m = @('Ruhe bis morgen früh', 'Quiet until tomorrow morning')
    m_snooze_off = @('Ruhe beenden (bis {0})', 'End quiet time (until {0})')
    m_export = @('Verlauf als CSV speichern (7 Tage)', 'Save history as CSV (7 days)')
    stale2 = @('Letzte Werte von {0} (vor {1} Min). Es wird weiter versucht.', 'Last values from {0} ({1} min ago). Still trying.')
    offline_tip = @('Luftwächter · offline', 'Luftwächter · offline')
    quiet_tag = @('🔕 Ruhe bis {0}', '🔕 Quiet until {0}')
    h18 = @('Tastatur', 'Keyboard')
    b18 = @('Klicke einmal auf das Widget, dann: ← / → anderer Raum · D einfache Ansicht oder Details · + / − größer oder kleiner · F5 sofort aktualisieren · Strg+C Werte kopieren · Strg+Umschalt+C alle Räume · G Home Assistant öffnen · L Sprache · O Durchsichtigkeit · P immer im Vordergrund · U Updates suchen · Pos1 / Ende erster / letzter Raum · Strg+Umschalt+S Bild speichern · Strg+Umschalt+D Diagnose kopieren · 1–9 Raum wählen · Maus über die Kurve zeigt Uhrzeit und Wert · Q Ruhe an/aus · T Design wechseln · F1 Hilfe · Esc schließt Hilfe und Geräte-Fenster. Beim Verschieben rastet das Widget an den Bildschirmrändern ein.', 'Click the widget once, then: ← / → other room · D simple view or details · + / − bigger or smaller · F5 refresh now · Ctrl+C copy readings · Ctrl+Shift+C all rooms · G open Home Assistant · L language · O transparency · P always on top · U check for updates · Home / End first / last room · Ctrl+Shift+S save picture · Ctrl+Shift+D copy diagnostics · 1–9 pick a room · hover the curve for time and value · Q quiet on/off · T switch theme · F1 help · Esc closes help and the device panel. When you move the widget it snaps to the screen edges.')
    week_tag = @(' · Woche: {0} %', ' · week: {0} %')
    sz_tip_s = @('Klein', 'Small')
    sz_tip_m = @('Normal', 'Normal')
    sz_tip_l = @('Groß (Strg + Mausrad: noch größer)', 'Large (Ctrl + mouse wheel: even larger)')
    sz_tip_c = @('Kompakt: nur Ring und Rat', 'Compact: ring and advice only')
    sz_tip_p = @('Pille: ganz klein, bleibt sichtbar', 'Pill: tiny, stays visible')
    time_tip = @('Zeit der letzten Aktualisierung · F5 aktualisiert sofort', 'Time of the last refresh · F5 refreshes now')
    drawer_close_tip = @('Geräte-Fenster schließen (Esc)', 'Close the device panel (Esc)')
    tab_tip = @('Geräte öffnen', 'Open devices')
    help_close_tip = @('Hilfe schließen (Esc)', 'Close help (Esc)')
    m_adv = @('Erweitert', 'More')
    m_copy_all = @('Alle Räume kopieren', 'Copy all rooms')
    house_bad = @('{0} von {1} Räumen schlecht', '{0} of {1} rooms poor')
    house_mid = @('{0} von {1} Räumen mittel', '{0} of {1} rooms fair')
    house_ok = @('alle {1} Räume gut', 'all {1} rooms good')
    sr_card = @('Luftwächter, {0}: {1}. {2}', 'Luftwächter, {0}: {1}. {2}')
    m_copy = @('Werte kopieren', 'Copy readings')
    news_h = @('Neu in Version {0}', 'New in version {0}')
    m_bigger = @('Größer anzeigen', 'Make bigger')
    m_smaller = @('Kleiner anzeigen', 'Make smaller')
    upd_tip = @('Zuletzt geprüft: {0} · nächste Prüfung in ca. {1} Min.', 'Last checked: {0} · next check in about {1} min')
    upd_tip_new = @('Neue Version {0} wartet · Klicken zum Ansehen', 'New version {0} is waiting · click to view')
    upd_tip_never = @('Noch nicht geprüft · Klicken zum Prüfen', 'Not checked yet · click to check')
    upd_balloon = @('Luftwächter {0} ist da. Auf „Update“ klicken.', 'Luftwächter {0} is available. Click Update.')
    upd_btn = @('⟳ Update', '⟳ Update')
    upd_new = @('⬆ {0} verfügbar', '⬆ {0} available')
    upd_title = @('Neue Version verfügbar', 'New version available')
    upd_sub = @('Installiert: {0}   ·   Neu: {1}', 'Installed: {0}   ·   New: {1}')
    upd_hist = @('Versionsverlauf', 'Version history')
    upd_cur = @('Version {0}.x · alle Änderungen', 'Version {0}.x · all changes')
    upd_prev = @('Frühere Hauptversionen', 'Earlier major versions')
    upd_close = @('Schließen', 'Close')
    upd_what = @('Das ist neu:', 'What is new:')
    upd_nonotes = @('(Keine Änderungsnotizen angegeben.)', '(No release notes provided.)')
    upd_yes = @('Jetzt aktualisieren', 'Update now')
    upd_no = @('Später', 'Later')
    upd_none = @('Du hast die neueste Version ({0}).', 'You are on the latest version ({0}).')
    upd_fail = @('Die Update-Suche hat nicht geklappt. Bitte später erneut versuchen.', 'The update check failed. Please try again later.')
    upd_dlfail = @('Das Update konnte nicht geladen oder geprüft werden. Es wurde nichts geändert.', 'The update could not be downloaded or verified. Nothing was changed.')
    upd_notinst = @('Updates funktionieren nur in der installierten Version. Bitte zuerst Installieren.bat ausführen.', 'Updates only work in the installed copy. Please run Installieren.bat first.')
    ver_tip = @('Version · Klick: alle Versionen auf GitHub', 'Version · click: all versions on GitHub')
    tagline = @('frei & quelloffen · von Dan Stasiak', 'free & open source · by Dan Stasiak')
    copy_tip = @('Freie Software (MIT) · Quellcode auf GitHub', 'Free software (MIT) · source code on GitHub')
    h12 = @('Über Luftwächter · freie Software', 'About Luftwächter · free software')
    b12 = @('Luftwächter ist freie Software unter der MIT-Lizenz: Du darfst es kostenlos nutzen, ändern und weitergeben. Der Hinweis auf den Urheber (Dan Stasiak) muss dabei erhalten bleiben. Quellcode, Änderungsliste (Changelog), Fehlermeldungen und Verbesserungsvorschläge: {0}', 'Luftwächter is free software under the MIT License: you may use, modify and share it free of charge. The notice crediting the author (Dan Stasiak) must be kept. Source code, changelog, bug reports and ideas: {0}')
    h13 = @('Updates', 'Updates')
    b13 = @('Der Knopf "⟳ Update" unten rechts fragt GitHub, ob es eine neuere Version gibt. Du siehst die Änderungen und entscheidest, ob aktualisiert wird. Danach tauscht sich das Programm selbst aus und startet neu. Deine Einstellungen und dein Zustand bleiben erhalten; die alte Version liegt als Sicherung im Programmordner. Alle paar Stunden wird still im Hintergrund geprüft, der Knopf wird dann grün.', 'The "⟳ Update" button at the bottom right asks GitHub whether a newer version exists. You see the changes and decide whether to update. The program then replaces itself and restarts. Your settings and state are kept; the old version is stored as a backup in the program folder. A silent check runs every few hours; the button then turns green.')
    h14 = @('Einrichtung (config.json)', 'Setup (config.json)')
    b14 = @('Normalerweise reicht der Assistent (Rechtsklick, "Mit Home Assistant verbinden…"). Weitere Einstellungen in config.json (Rechtsklick, "Konfiguration öffnen"): defaultRoom = Startraum, place = Ort für die Wetterzeile, footer = Quellenhinweis, roomShort = Kurznamen der Räume, weatherEntity = bestimmte Wetter-Entität. Alternativ zum Direktanschluss: url und switchUrl für einen eigenen Server. Nach dem Speichern das Programm neu starten.', 'Normally the assistant is enough (right-click, "Connect to Home Assistant…"). More settings in config.json (right-click, "Open configuration"): defaultRoom = start room, place = location for the weather row, footer = source note, roomShort = short room names, weatherEntity = a specific weather entity. As an alternative to the direct connection: url and switchUrl for your own server. Restart the program after saving.')
    help_title = @('Hilfe', 'Help')
    h1 = @('Wofür ist das?', 'What is this?')
    b1 = @('Luftwächter zeigt dir, wie gut die Luft in einem Raum ist, und sagt dir in einfachen Worten, ob du lüften sollst. Dazu kommen das Wetter draußen und die Geräte im Raum. Es zeigt alle Räume, die dein Server liefert.', 'Luftwächter shows how good the air in a room is and tells you in plain words whether you should ventilate. It also shows the weather outside and the devices in the room. It shows all rooms your server provides.')
    h2 = @('Farben und Ring', 'Colors and ring')
    b2 = @('Grün = gut, gelb = mittel, rot = schlecht. Die Farbe richtet sich nach dem schlechtesten der vier Messwerte. Der Ring zeigt den CO₂-Wert: je voller, desto besser. Grenzen: CO₂ unter 1000 ppm ist gut, bis 1500 mittel, darüber schlecht. Feinstaub unter 20 µg ist gut, bis 50 mittel. Temperatur 17–23 °C und Luftfeuchte 30–60 % sind gut. In allen Räumen gelten dieselben Grenzen.', 'Green = good, yellow = fair, red = poor. The color follows the worst of the four readings. The ring shows the CO₂ value: the fuller, the better. Limits: CO₂ below 1000 ppm is good, up to 1500 fair, above that poor. Fine dust below 20 µg is good, up to 50 fair. Temperature 17–23 °C and humidity 30–60 % are good. The same limits apply in every room.')
    h3 = @('Der Rat: lüften oder nicht', 'The advice: ventilate or not')
    b3 = @('Oben links wechselt der Knopf „Details“ / „Einfach“ zwischen der ruhigen Ansicht (nur Gesicht, Satz und Räume) und allen Werten. Das große Feld sagt, was zu tun ist: Fenster öffnen, offen lassen, schließen oder noch warten (z. B. bei Unwetter). Ist das Fenster offen, zeigt ein Balken, wie lange noch gelüftet werden soll. In Räumen ohne Fensterkontakt tippst du auf das Feld: Dann startet ein Lüftungs-Timer, und am Ende kommt ein Ton. Nach dem Lüften steht kurz da, wie sich der CO₂-Wert verbessert hat. Nachts (22–7 Uhr) ist das Fenster abgedunkelt, und es gibt keinen Hinweiston.', 'The button at the top left ("Details" / "Simple") switches between the calm view (just the face, one sentence and the rooms) and all values. The large panel tells you what to do: open the window, keep it open, close it, or wait a bit (for example during a storm). When the window is open, a bar shows how much longer to ventilate. In rooms without a window contact, tap the panel: a ventilation timer starts and a sound plays at the end. After ventilating, the panel briefly shows how the CO₂ value improved. At night (22:00–07:00) the window is dimmed and there is no alert sound.')
    h4 = @('Kurve, Trend und Tagesbilanz', 'Curve, trend and daily summary')
    b4 = @('Die Kurve zeigt den CO₂-Verlauf der letzten 3 Stunden; die Linie markiert 1000 ppm. Ein Tipp auf die Kurve wechselt zu 24 Stunden, ein weiterer zu 7 Tagen und dann wieder zurück. Links daneben steht der Trend (steigt, sinkt, stabil) und, wenn möglich, eine Prognose, z. B. wann die Luft wieder gut ist. Die Tagesbilanz nennt Höchstwert, Durchschnitt und den Anteil der Zeit unter 1000 ppm. Die Werte werden auf deinem PC gesammelt und bleiben beim Neustart erhalten. Tippe auf einen der vier Werte (CO₂, Feinstaub, Temperatur, Luftfeuchte), dann zeigt die Kurve diesen Wert. Rechtsklick auf einen Wert öffnet seine Erklärung.', 'The curve shows the CO₂ history of the last 3 hours; the line marks 1000 ppm. Tap the curve to switch to 24 hours, again for 7 days, and once more to go back. The trend (rising, falling, steady) and, when possible, a forecast such as when the air will be good again, appear under the ring. The daily summary gives the peak, the average and the share of time below 1000 ppm. The data is collected on your PC and kept across restarts. Tap one of the four values (CO₂, fine dust, temperature, humidity) and the curve shows that value instead. Right-click a value to open its explanation.')
    h19 = @('CO₂ (Kohlendioxid)', 'CO₂ (carbon dioxide)')
    b19 = @('Was es ist: CO₂ entsteht beim Atmen. Draußen liegt es bei etwa 420 ppm. In Räumen steigt es, wenn Menschen atmen und frische Luft fehlt. In diesen Mengen ist es nicht giftig, aber ein guter Anzeiger für verbrauchte Luft: Ab etwa 1000 ppm werden viele müde und unkonzentriert, Kopfschmerzen sind möglich.
Im Widget: unter 1000 ppm gut, bis 1500 mittel, darüber schlecht.
Häufige Ursachen für schlechte Werte: mehrere Personen im Raum, geschlossene Fenster und Türen (besonders nachts im Schlafzimmer), ein kleiner Raum, Gasherd oder offene Flamme, Kerzen, Kamin oder Holzofen, zu seltenes Lüften.
Was hilft: Stoßlüften, also Fenster ganz öffnen, 5 bis 10 Minuten, am besten gegenüberliegende Fenster für Durchzug. Im Schlafzimmer nachts ein Fenster gekippt oder die Tür einen Spalt offen lassen.', 'What it is: CO₂ is produced when we breathe. Outdoors it is about 420 ppm. Indoors it rises when people breathe and fresh air is missing. At these levels it is not toxic, but it is a good indicator of stale air: from about 1000 ppm many people feel tired and unfocused, and headaches are possible.
In the widget: below 1000 ppm good, up to 1500 fair, above that poor.
Common causes of poor readings: several people in the room, closed windows and doors (especially in a bedroom at night), a small room, a gas stove or open flame, candles, a fireplace or wood stove, ventilating too rarely.
What helps: air out in bursts, meaning open the window fully for 5 to 10 minutes, ideally opposite windows for a draft. In a bedroom at night, leave a window tilted or the door slightly open.')
    h20 = @('Feinstaub (PM2.5)', 'Fine dust (PM2.5)')
    b20 = @('Was es ist: winzige Partikel in der Luft, kleiner als 2,5 Tausendstel Millimeter, gemessen in µg pro m³. Sie dringen tief in die Lunge ein und können die Atemwege reizen; bei Dauerbelastung steigt das Risiko für Herz und Lunge.
Im Widget: unter 20 µg gut, bis 50 mittel, darüber schlecht. Zum Vergleich: Die WHO empfiehlt im Tagesmittel höchstens 15 µg.
Häufige Ursachen für schlechte Werte: Kochen und Braten, Toasten, Backofen, Kerzen, Räucherstäbchen, Kamin oder Holzofen, Rauchen und Dampfen, Staubsaugen (vor allem ohne gutes Filter), Staubwischen und Bettenmachen, Reinigungs- und Haarsprays, 3D-Drucker und Laserdrucker. Auch von draußen kann Staub kommen: Verkehr, Holzfeuer in der Nachbarschaft, Silvesterfeuerwerk, Pollen oder Saharastaub.
Hinweis: Optische Sensoren können Wasserdampf (Duschen, Kochen) manchmal als Staub messen. Kurze Spitzen sind dann nicht immer echter Staub.
Was hilft: beim Kochen Dunstabzug an und Fenster auf, auf Kerzen und Räucherwerk verzichten, bei hoher Belastung draußen die Fenster zu lassen (genau das rät dir das Widget), einen Staubsauger mit HEPA-Filter nutzen, bei Bedarf ein Luftreiniger mit HEPA-Filter.', 'What it is: tiny particles in the air, smaller than 2.5 thousandths of a millimeter, measured in µg per m³. They reach deep into the lungs and can irritate the airways; with long exposure the risk to heart and lungs rises.
In the widget: below 20 µg good, up to 50 fair, above that poor. For comparison, the WHO recommends a daily average of at most 15 µg.
Common causes of poor readings: cooking and frying, toasting, the oven, candles, incense, a fireplace or wood stove, smoking and vaping, vacuuming (especially without a good filter), dusting and making beds, cleaning and hair sprays, 3D printers and laser printers. Dust can also come from outside: traffic, wood fires in the neighborhood, New Year''s fireworks, pollen or Saharan dust.
Note: optical sensors can sometimes read water vapor (showering, cooking) as dust. Short spikes are then not always real dust.
What helps: use the extractor hood and open a window when cooking, skip candles and incense, keep windows closed when the outdoor load is high (this is exactly what the widget advises), use a vacuum with a HEPA filter, and if needed an air purifier with a HEPA filter.')
    h21 = @('Temperatur', 'Temperature')
    b21 = @('Was es ist: die Lufttemperatur im Raum in °C. Sie bestimmt vor allem, wie wohl du dich fühlst, und sie beeinflusst die Luftfeuchte.
Im Widget: 17 bis 23 °C gut, 13 bis 25 °C mittel, kälter oder wärmer schlecht. Gut zu wissen: Zum Schlafen sind 16 bis 18 °C üblich, im Wohnzimmer 20 bis 22 °C. Das Widget bewertet alle Räume gleich.
Häufige Ursachen für zu warm: Sonne durch die Fenster (Südseite, Rollo offen), Computer und Elektrogeräte, viele Personen, Kochen, eine zu hoch gestellte Heizung, Dachgeschoss im Sommer.
Häufige Ursachen für zu kalt: Heizung aus oder zu niedrig, im Winter lange gekippte Fenster, schlecht gedämmte Wände und Fenster, Zugluft.
Hinweis: Steht der Sensor in der Sonne oder direkt neben einer Heizung oder einem Gerät, zeigt er zu viel an.
Was hilft: tagsüber Rollos schließen und im Sommer nachts lüften. Im Winter lieber kurz stoßlüften als lange kippen, dann kühlen Wände und Möbel weniger aus.', 'What it is: the air temperature in the room in °C. It mostly decides how comfortable you feel, and it affects humidity.
In the widget: 17 to 23 °C good, 13 to 25 °C fair, colder or warmer poor. Good to know: 16 to 18 °C is usual for sleeping, 20 to 22 °C for a living room. The widget rates all rooms the same.
Common causes of too warm: sun through the windows (south side, blinds open), computers and electronics, many people, cooking, heating set too high, an attic room in summer.
Common causes of too cold: heating off or too low, windows tilted for long in winter, poorly insulated walls and windows, drafts.
Note: if the sensor sits in the sun or right next to a heater or a device, it reads too high.
What helps: close blinds during the day and ventilate at night in summer. In winter, air out briefly in bursts instead of tilting for long, so walls and furniture cool down less.')
    h22 = @('Luftfeuchte', 'Humidity')
    b22 = @('Was es ist: die relative Luftfeuchte in %. Sie zeigt, wie viel Wasserdampf die Luft im Verhältnis zum Maximum bei der aktuellen Temperatur enthält.
Im Widget: 30 bis 60 % gut, 25 bis 70 % mittel, darüber oder darunter schlecht.
Zu trocken (unter etwa 30 %): trockene Schleimhäute, Reizhusten, gereizte Augen, statische Aufladung. Typische Ursachen: Heizen im Winter (kalte Außenluft wird beim Aufwärmen sehr trocken), Klimaanlage, langes Lüften bei Frost.
Zu feucht (dauerhaft über 60 %): Kondenswasser an Fenstern, Hausstaubmilben und Schimmel, vor allem an kalten Wänden und hinter Möbeln. Ab etwa 70 % über längere Zeit wächst die Schimmelgefahr deutlich. Typische Ursachen: Duschen und Baden, Kochen, Wäsche in der Wohnung trocknen, viele Zimmerpflanzen, viele Personen, zu seltenes Lüften, schwüles Wetter, Kellerräume.
Was hilft bei zu feucht: nach dem Duschen oder Kochen sofort stoßlüften (Tür zum Rest der Wohnung zu lassen), Möbel mit etwas Abstand zu kalten Außenwänden stellen, Wäsche wenn möglich anderswo trocknen. Bei zu trocken: regelmäßig stoßlüften, Zimmerpflanzen oder einen sauber gehaltenen Luftbefeuchter nutzen, Heizung nicht zu hoch stellen.', 'What it is: relative humidity in %. It shows how much water vapor the air holds compared to the maximum at the current temperature.
In the widget: 30 to 60 % good, 25 to 70 % fair, above or below that poor.
Too dry (below about 30 %): dry mucous membranes, irritating cough, irritated eyes, static electricity. Typical causes: heating in winter (cold outdoor air becomes very dry when warmed), air conditioning, ventilating for long in frost.
Too humid (lastingly above 60 %): condensation on windows, dust mites and mold, especially on cold walls and behind furniture. From about 70 % over a longer time the mold risk rises clearly. Typical causes: showering and bathing, cooking, drying laundry indoors, many houseplants, many people, ventilating too rarely, muggy weather, basement rooms.
What helps when too humid: air out in bursts right after showering or cooking (keep the door to the rest of the home closed), keep furniture a little away from cold outer walls, dry laundry elsewhere if possible. When too dry: air out regularly, use houseplants or a well-kept humidifier, do not set the heating too high.')
    help_expand = @('Alle aufklappen', 'Expand all')
    help_collapse = @('Alle zuklappen', 'Collapse all')
    help_now = @('jetzt {0} {1} ({2})', 'now {0} {1} ({2})')
    h5 = @('Die vier Messwerte', 'The four readings')
    b5 = @('CO₂ (ppm), Staub (Feinstaub PM2.5 in µg), Temperatur (°C) und Feuchte (%). Der Punkt vor jedem Wert zeigt seine Farbe. Was die Werte bedeuten und woher schlechte Werte kommen, steht in den vier Abschnitten direkt darunter.', 'CO₂ (ppm), dust (fine dust PM2.5 in µg), temperature (°C) and humidity (%). The dot in front of each value shows its color. What the values mean and where poor readings come from is explained in the four sections right below.')
    h6 = @('Räume wechseln', 'Switching rooms')
    b6 = @('Tippe oben auf den Raumnamen oder auf einen Raum in der Zeile darunter. Dann zeigt alles den gewählten Raum: Messwerte, Rat, Kurve und Geräte. Die Punkte in der Raumzeile zeigen auf einen Blick, wie es überall im Haus steht. Dein Raum wird beim Neustart wieder geladen.', 'Tap the room name at the top or a room in the row below. Everything then shows the chosen room: readings, advice, curve and devices. The dots in the room row show at a glance how every room in the house is doing. Your room is restored after a restart.')
    h7 = @('Wetter', 'Weather')
    b7 = @('Die blaue Zeile zeigt das Wetter draußen. Mit "Mehr" siehst du Wind, Feuchte, Wolken, Druck und einen Lüftungstipp, mit "Weniger" klappt es wieder zu.', 'The blue row shows the weather outside. "More" reveals wind, humidity, clouds, pressure and a ventilation tip; "Less" folds it back.')
    h8 = @('Geräte-Fläche', 'Device panel')
    b8 = @('Der Pfeil am rechten Rand öffnet die Geräte des Raums. Licht und schaltbare Steckdosen schaltest du per Tippen. Bei Steckdosen mit Messung wird nur der Verbrauch in Watt gezeigt. Heizung: mit − und + in 0,5-Grad-Schritten (16–24 °C). Rollo: ▲ auf, ■ stopp, ▼ zu. Welche Geräte erscheinen, legt dein Server fest (Freigabeliste).', 'The arrow on the right edge opens the devices of the room. Tap to switch lights and switchable plugs. Plugs with metering only show the power in watts. Heating: − and + in steps of 0.5 degrees (16–24 °C). Blinds: ▲ open, ■ stop, ▼ close. Which devices appear is decided by your server (allow-list).')
    h9 = @('Größen und Pille', 'Sizes and pill')
    b9 = @('S, M und L ändern die Größe, "kompakt" blendet die Details aus, und "Pille" schrumpft alles zu einem kleinen Farbpunkt mit Raum und CO₂-Wert. Doppelklick auf die Pille macht das Fenster wieder groß.', 'S, M and L change the size, "compact" hides the details, and "Pill" shrinks everything to a small color dot with room and CO₂ value. Double-click the pill to expand the window again.')
    h10 = @('Fenster und Rechtsklick', 'Window and right-click')
    b10 = @('Zum Verschieben das Fenster irgendwo anfassen und ziehen. Doppelklick aktualisiert sofort (sonst automatisch alle paar Sekunden). Rechtsklick öffnet das Menü: aktualisieren, immer im Vordergrund, Hinweiston, Fenster zurücksetzen, Protokoll, Hilfe und Beenden. Luftwächter startet mit Windows und stellt Position, Größe, Raum und Sprache wieder her. Das Fenster verhält sich wie jedes andere Fenster: Es kann hinter anderen Programmen verschwinden und ist in der Taskleiste. Wer es immer sichtbar haben will, schaltet im Menü "Immer im Vordergrund" ein. Wenn gelüftet werden soll, holt es sich kurz nach vorn (abschaltbar).', 'Grab the window anywhere and drag to move it. Double-click refreshes immediately (otherwise it refreshes automatically every few seconds). Right-click opens the menu: refresh, always on top, sound, reset window, log, help and quit. Luftwächter starts with Windows and restores position, size, room and language. The window behaves like any other window: it can go behind other programs and has a taskbar button. If you want it always visible, switch on "Always on top" in the menu. When ventilation is needed it briefly comes to the front (can be switched off).')
    h11 = @('Wenn etwas nicht klappt', 'If something does not work')
    b11 = @('Steht dort "Offline" oder "Keine Verbindung", erreicht dein PC den Server gerade nicht (Internet, VPN?). Es wird weiter versucht. Fehler werden im Protokoll gesammelt: Rechtsklick, dann "Protokoll öffnen". Die Version steht unten rechts. Die Sprache stellst du oben mit "DE | EN" um.', 'If it says "Offline" or "No connection", your PC cannot reach the server right now (internet, VPN?). It keeps trying. Errors are collected in the log: right-click, then "Open log". The version is shown at the bottom right. Change the language at the top with "DE | EN".')
}
function T([string]$k, $a = $null, $b = $null, $c = $null) {
    $idx = 0; if ($state.lang -eq 'en') { $idx = 1 }
    $s = $k; if ($script:Strings.ContainsKey($k)) { $s = [string]$script:Strings[$k][$idx] }
    if ($null -ne $a) { $s = $s.Replace('{0}', [string]$a) }
    if ($null -ne $b) { $s = $s.Replace('{1}', [string]$b) }
    if ($null -ne $c) { $s = $s.Replace('{2}', [string]$c) }
    return $s
}

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Luftwächter" SizeToContent="WidthAndHeight"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ResizeMode="NoResize" ShowInTaskbar="True" Topmost="False" FontFamily="Segoe UI Variable Text, Segoe UI"
        UseLayoutRounding="True" SnapsToDevicePixels="True" RenderOptions.ClearTypeHint="Enabled"
        TextOptions.TextFormattingMode="Display" TextOptions.TextRenderingMode="ClearType" TextOptions.TextHintingMode="Fixed">
<Grid x:Name="Scaler" Margin="16">
<StackPanel Orientation="Horizontal" VerticalAlignment="Top">
  <Border x:Name="Pill" Visibility="Collapsed" CornerRadius="22" Background="#FF1B222D" BorderThickness="2" BorderBrush="#FF7A8594" Padding="16,7" Cursor="Hand" ToolTip="Doppelklick: wieder groß">
    <StackPanel Orientation="Horizontal"><TextBlock x:Name="PillDot" Text="●" FontSize="20" Foreground="#FF7A8594" VerticalAlignment="Center"/><TextBlock x:Name="PillText" Text="…" Foreground="White" FontSize="18" FontWeight="Bold" Margin="8,0,0,0" VerticalAlignment="Center"/></StackPanel>
  </Border>
  <Border x:Name="Card" Width="427" CornerRadius="24" Background="#FF1B222D" BorderThickness="2" BorderBrush="#FF7A8594">
    <Border.Effect><DropShadowEffect x:Name="Glow" BlurRadius="24" ShadowDepth="0" Color="#FF7A8594" Opacity="0.5"/></Border.Effect>
    <StackPanel Margin="18,14,18,12">
      <StackPanel>
        <Border x:Name="TitleBox" HorizontalAlignment="Left" Background="Transparent" Padding="2,0,0,0">
          <StackPanel>
            <TextBlock x:Name="RoomName" Foreground="White" FontSize="30" FontWeight="Bold"/>
            <StackPanel Orientation="Horizontal" Margin="1,0,0,0"><TextBlock x:Name="RoomSub" Foreground="#FFFFFFFF" FontSize="15" FontWeight="SemiBold"/><TextBlock x:Name="TitleTag" Foreground="#FF9AA7B8" FontSize="12" VerticalAlignment="Bottom" Margin="8,0,0,1"/></StackPanel>
          </StackPanel>
        </Border>
        <DockPanel Margin="2,8,0,0">
          <StackPanel x:Name="SzBox" DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
            <Border x:Name="SzBS" CornerRadius="9" Padding="6,2" Cursor="Hand" Background="#00000000"><TextBlock x:Name="SzS" Text="S" Foreground="#FFA9B4C4" FontSize="12"/></Border>
            <Border x:Name="SzBM" CornerRadius="9" Padding="6,2" Cursor="Hand" Background="#00000000"><TextBlock x:Name="SzM" Text="M" Foreground="#FFA9B4C4" FontSize="12"/></Border>
            <Border x:Name="SzBL" CornerRadius="9" Padding="6,2" Cursor="Hand" Background="#00000000"><TextBlock x:Name="SzL" Text="L" Foreground="#FFA9B4C4" FontSize="12"/></Border>
            <Border x:Name="SzBC" CornerRadius="9" Padding="6,2" Cursor="Hand" Background="#00000000"><TextBlock x:Name="SzC" Text="kompakt" Foreground="#FFA9B4C4" FontSize="12"/></Border>
            <Border x:Name="SzBP" CornerRadius="9" Padding="6,2" Cursor="Hand" Background="#00000000"><TextBlock x:Name="SzP" Text="Pille" Foreground="#FFA9B4C4" FontSize="12"/></Border>
          </StackPanel>
          <Border x:Name="BtnHelp" DockPanel.Dock="Left" Width="22" Height="22" CornerRadius="11" Background="#FF585C64" Cursor="Hand"><TextBlock Text="?" Foreground="White" FontSize="14" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
          <Border x:Name="BtnLang" DockPanel.Dock="Left" Height="22" CornerRadius="11" Background="#FF494E57" Padding="8,0" Margin="6,0,0,0" Cursor="Hand">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center"><TextBlock x:Name="LangDe" Text="DE" FontSize="12" Foreground="#FFA9B4C4"/><TextBlock Text=" | " FontSize="12" Foreground="#FFA9B4C4"/><TextBlock x:Name="LangEn" Text="EN" FontSize="12" Foreground="#FFA9B4C4"/></StackPanel>
          </Border>
          <Border x:Name="BtnMode" DockPanel.Dock="Left" Height="22" CornerRadius="11" Background="#FF585C64" Padding="10,0" Margin="6,0,0,0" Cursor="Hand"><TextBlock x:Name="BtnModeT" Foreground="White" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center"/></Border>
          <TextBlock x:Name="Time" Foreground="#FFB4BFCE" FontSize="12" Margin="10,0,0,0" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
        </DockPanel>
      </StackPanel>
      <Border x:Name="Tour" Visibility="Collapsed" CornerRadius="14" Background="#FF494E57" Padding="14,10" Margin="0,10,0,0">
        <StackPanel>
          <TextBlock x:Name="TourH" Foreground="White" FontSize="16" FontWeight="Bold" TextWrapping="Wrap"/>
          <TextBlock x:Name="TourT" Foreground="#FFDFE5EE" FontSize="14" TextWrapping="Wrap" Margin="0,4,0,8"/>
          <Border x:Name="TourOk" HorizontalAlignment="Right" CornerRadius="12" Background="#FF2E9E5B" Padding="18,5" Cursor="Hand"><TextBlock x:Name="TourOkT" Foreground="White" FontSize="14" FontWeight="SemiBold"/></Border>
        </StackPanel>
      </Border>
      <Grid Margin="0,10,0,0">
        <Grid.ColumnDefinitions><ColumnDefinition Width="140"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
        <StackPanel Grid.Column="0" HorizontalAlignment="Center">
          <Grid Width="96" Height="96">
            <Ellipse Width="89" Height="89" Stroke="#FF2C3646" StrokeThickness="9"/>
            <Path x:Name="Arc" Stroke="#FF7A8594" StrokeThickness="9" StrokeStartLineCap="Round" StrokeEndLineCap="Round" Margin="6,6,0,0" HorizontalAlignment="Left" VerticalAlignment="Top"/>
            <TextBlock x:Name="Face" FontFamily="Segoe UI Emoji" FontSize="32" HorizontalAlignment="Center" VerticalAlignment="Center" Foreground="White"/>
          </Grid>
          <TextBlock x:Name="Level" FontSize="24" FontWeight="Bold" HorizontalAlignment="Center" Foreground="#FF7A8594"/>
          <TextBlock x:Name="Trend" FontSize="12" HorizontalAlignment="Center" TextAlignment="Center" TextWrapping="Wrap" MaxWidth="136" Foreground="#FFB4BFCE"/>
        </StackPanel>
        <Border x:Name="Panel" Grid.Column="1" CornerRadius="16" Background="#FF3C424C" Padding="12" Margin="4,0,0,0">
          <DockPanel VerticalAlignment="Center">
            <Grid Width="58" Height="58" DockPanel.Dock="Left" Margin="0,0,12,0" VerticalAlignment="Top">
              <Canvas x:Name="IcClosed" Width="58" Height="58">
                <Rectangle Canvas.Left="7" Canvas.Top="6" Width="44" Height="46" RadiusX="3" RadiusY="3" Stroke="#FF000000" StrokeThickness="4"/>
                <Path Data="M29,6 L29,52 M7,29 L51,29" Stroke="#FF000000" StrokeThickness="3"/>
                <Ellipse Canvas.Left="32.4" Canvas.Top="26.4" Width="5.2" Height="5.2" Fill="#FF000000"/>
              </Canvas>
              <Canvas x:Name="IcOpen" Width="58" Height="58" Visibility="Collapsed">
                <Rectangle Canvas.Left="7" Canvas.Top="6" Width="44" Height="46" RadiusX="3" RadiusY="3" Stroke="#FF000000" StrokeThickness="4"/>
                <Path Data="M7,6 L26,12 L26,46 L7,52 Z" Fill="#FF000000" Opacity="0.85"/>
                <Rectangle Canvas.Left="30" Canvas.Top="14" Width="17" Height="30" Fill="#FF000000" Opacity="0.25"/>
                <Path Data="M36,22 L44,22 M36,28 L44,28" Stroke="#FF000000" StrokeThickness="3" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
              </Canvas>
            </Grid>
            <StackPanel VerticalAlignment="Center">
              <TextBlock x:Name="Headline" Foreground="White" FontSize="22" FontWeight="Bold" TextWrapping="Wrap"/>
              <TextBlock x:Name="Detail" Foreground="#FFDFE5EE" FontSize="13" TextWrapping="Wrap" Margin="0,3,0,0"/>
              <TextBlock x:Name="DayScore" Foreground="#FFFFFFFF" FontSize="14" FontWeight="SemiBold" TextWrapping="Wrap" Margin="0,6,0,0" Visibility="Collapsed"/>
              <Border x:Name="BarTrack" Height="7" CornerRadius="4" Background="#FF494E57" Margin="0,8,0,0" Visibility="Collapsed"><Border x:Name="BarFill" HorizontalAlignment="Left" CornerRadius="4" Background="#FF2E9E5B" Width="0"/></Border>
            </StackPanel>
          </DockPanel>
        </Border>
      </Grid>
      <StackPanel x:Name="Details">
        <Grid x:Name="GrpTiles" Margin="0,10,0,0">
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
          <Border x:Name="SparkBox" Grid.Column="0" CornerRadius="12" Background="#26000000" Padding="8,6" Margin="0,3,6,3" Cursor="Hand" ToolTip="Tippen: 3 Std / 24 Std">
            <StackPanel>
              <Canvas x:Name="Spark" Height="62" ClipToBounds="True"/>
              <DockPanel><TextBlock x:Name="SparkR" DockPanel.Dock="Right" Text="jetzt" Foreground="#FFA9B4C4" FontSize="11"/><TextBlock x:Name="SparkLabel" Text="3 Std · Linie = 1000 ppm" Foreground="#FFA9B4C4" FontSize="11"/></DockPanel>
            </StackPanel>
          </Border>
          <Grid Grid.Column="1" Width="206"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions><Grid.RowDefinitions><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
            $chipXaml
          </Grid>
        </Grid>
        <TextBlock x:Name="Peak" Foreground="#FFB4BFCE" FontSize="12" Margin="2,2,0,0"/>
        <WrapPanel x:Name="RoomStrip" Margin="0,8,0,0"/>
        <Border x:Name="WLine" CornerRadius="14" Background="#4D3A5F8A" BorderBrush="#556D8FB8" BorderThickness="1" Padding="12,8" Margin="0,10,0,0" Cursor="Hand">
          <DockPanel>
            <Border x:Name="WMore" DockPanel.Dock="Right" CornerRadius="10" Background="#FF494E57" Padding="10,4" Margin="8,0,0,0"><TextBlock x:Name="WMoreT" Text="▾ Mehr" Foreground="White" FontSize="12" FontWeight="SemiBold"/></Border>
            <TextBlock x:Name="WLineText" Foreground="#FFDFE5EE" FontSize="14" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
          </DockPanel>
        </Border>
        <Border x:Name="WFull" CornerRadius="16" Background="#4D3A5F8A" BorderBrush="#556D8FB8" BorderThickness="1" Padding="12,8" Margin="0,10,0,0" Visibility="Collapsed">
          <StackPanel>
            <DockPanel>
              <Border x:Name="WLess" DockPanel.Dock="Right" CornerRadius="10" Background="#FF494E57" Padding="10,3"><TextBlock x:Name="WLessT" Text="▴ Weniger" Foreground="White" FontSize="12" FontWeight="SemiBold"/></Border>
              <TextBlock x:Name="WTitleT" Text="DRAUSSEN" Foreground="#FFB4BFCE" FontSize="11"/>
            </DockPanel>
            <Grid Margin="0,6,0,0">
              <Grid.ColumnDefinitions><ColumnDefinition Width="150"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
              <StackPanel VerticalAlignment="Center">
                <StackPanel Orientation="Horizontal"><TextBlock x:Name="WIcon" FontFamily="Segoe UI Emoji" FontSize="40" Foreground="White" Margin="0,0,8,0"/><TextBlock x:Name="WTemp" Foreground="White" FontSize="34" FontWeight="Bold" VerticalAlignment="Center"/></StackPanel>
                <TextBlock x:Name="WCond" Foreground="#FFDFE5EE" FontSize="14"/>
              </StackPanel>
              <Grid Grid.Column="1"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions><Grid.RowDefinitions><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
                $tileXaml
              </Grid>
            </Grid>
            <Border x:Name="WOutB" CornerRadius="10" Background="#33000000" Padding="4,6" Margin="3,6,3,0" Visibility="Collapsed"><UniformGrid x:Name="WOut" Columns="6"/></Border>
            <Border CornerRadius="10" Background="#33000000" Padding="10,6" Margin="3,6,3,0"><TextBlock x:Name="WTip" Foreground="White" FontSize="13" TextWrapping="Wrap"/></Border>
          </StackPanel>
        </Border>
        <DockPanel x:Name="GrpFoot" Margin="2,8,0,0"><TextBlock x:Name="Ver" Cursor="Hand" DockPanel.Dock="Right" Foreground="#FFB4BFCE" FontSize="11" FontWeight="SemiBold" Margin="8,0,0,0"/><TextBlock x:Name="Footer" Foreground="#FFA9B4C4" FontSize="11" TextTrimming="CharacterEllipsis"/></DockPanel>
        <DockPanel x:Name="GrpUpd" Margin="2,5,0,0">
          <Border x:Name="BtnUpd" DockPanel.Dock="Right" CornerRadius="9" Background="#FF494E57" Padding="9,2" Margin="8,0,0,0" Cursor="Hand"><TextBlock x:Name="BtnUpdT" Text="⟳ Update" Foreground="White" FontSize="11" FontWeight="SemiBold"/></Border>
          <TextBlock x:Name="Copy" Foreground="#FFA9B4C4" FontSize="11" Cursor="Hand" TextTrimming="CharacterEllipsis" VerticalAlignment="Center"/>
        </DockPanel>
      </StackPanel>
    </StackPanel>
  </Border>
  <Border x:Name="Help" Visibility="Collapsed" Width="427" CornerRadius="24" Background="#FF1B222D" BorderThickness="2" BorderBrush="#FF7A8594">
    <StackPanel Margin="18,14,14,14">
      <DockPanel><Border x:Name="HelpClose" DockPanel.Dock="Right" Width="26" Height="26" CornerRadius="13" Background="#FF494E57" Cursor="Hand"><TextBlock Text="✕" Foreground="White" FontSize="13" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
        <TextBlock x:Name="HelpTitle" Foreground="White" FontSize="24" FontWeight="Bold"/></DockPanel>
      <ScrollViewer x:Name="HelpScroll" MaxHeight="470" VerticalScrollBarVisibility="Auto" Margin="0,8,0,0"><StackPanel x:Name="HelpBody" Margin="0,0,10,0"/></ScrollViewer>
      <TextBlock x:Name="HelpVer" Foreground="#FFA9B4C4" FontSize="11" Margin="0,8,0,0"/>
    </StackPanel>
  </Border>
  <Border x:Name="Tab" Width="28" Height="120" CornerRadius="0,16,16,0" Background="#FF2A3342" BorderThickness="0,2,2,2" BorderBrush="#FF7A8594" Margin="-2,0,0,0" VerticalAlignment="Center" Cursor="Hand">
    <Grid><TextBlock x:Name="TabArr" Text="›" Foreground="White" FontSize="24" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/><TextBlock x:Name="TabLbl" Foreground="White" FontSize="13" FontWeight="SemiBold" HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed"><TextBlock.LayoutTransform><RotateTransform Angle="90"/></TextBlock.LayoutTransform></TextBlock></Grid>
  </Border>
  <Border x:Name="Drawer" Width="340" CornerRadius="0,24,24,0" Background="#FF1B222D" BorderThickness="0,2,2,2" BorderBrush="#FF7A8594" Margin="-2,0,0,0" Visibility="Collapsed">
    <StackPanel Margin="16,14,16,12">
      <DockPanel><Border x:Name="DrawerClose" DockPanel.Dock="Right" CornerRadius="10" Background="#FF494E57" Padding="10,0" Cursor="Hand"><TextBlock Text="‹" Foreground="White" FontSize="22" FontWeight="Bold"/></Border>
        <TextBlock x:Name="DrawerTitle" Foreground="White" FontSize="19" FontWeight="Bold" TextTrimming="CharacterEllipsis"/></DockPanel>
      <StackPanel x:Name="DevPanel" Margin="0,6,0,0"/>
    </StackPanel>
  </Border>
</StackPanel>
</Grid>
</Window>
"@

$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$xaml)))
$conv = New-Object Windows.Media.BrushConverter
function Brush([string]$hex) { return $conv.ConvertFromString($hex) }
$names = @('SzBS', 'SzBM', 'SzBL', 'SzBC', 'SzBP', 'DayScore', 'Tour', 'TourH', 'TourT', 'TourOk', 'TourOkT', 'GrpTiles', 'GrpFoot', 'GrpUpd', 'SzBox', 'BtnMode', 'BtnModeT', 'TabArr', 'TabLbl', 'Scaler', 'Card', 'Ver', 'RoomStrip', 'SparkBox', 'SparkLabel', 'Glow', 'WOut', 'WOutB', 'TitleBox', 'RoomName', 'RoomSub', 'TitleTag', 'Time', 'SzS', 'SzM', 'SzL', 'SzC', 'SzP', 'BtnHelp', 'BtnLang', 'LangDe', 'LangEn', 'WMoreT', 'WLessT', 'WTitleT', 'Help', 'HelpClose', 'HelpTitle', 'HelpScroll', 'HelpBody', 'HelpVer', 'BtnUpd', 'BtnUpdT', 'Copy', 'Pill', 'PillDot', 'PillText', 'Arc', 'Face', 'Level', 'Trend', 'Panel', 'IcClosed', 'IcOpen', 'Headline', 'Detail', 'BarTrack', 'BarFill', 'Details', 'Spark', 'SparkR', 'Peak', 'WLine', 'WMore', 'WLineText', 'WFull', 'WLess', 'WIcon', 'WTemp', 'WCond', 'WTip', 'Footer', 'Tab', 'Drawer', 'DrawerClose', 'DrawerTitle', 'DevPanel')
for ($i = 1; $i -le 4; $i++) { $names += @("C$i", "D$i", "V$i", "K$i", "WK$i", "WV$i") }
$ui = @{}
foreach ($n in $names) { $ui[$n] = $win.FindName($n) }

$grey = '#FF7A8594'
$script:fails = 0
$script:last = $null
$script:rooms = @()
$script:openSince = $null
$script:openRoom = $null
$script:devSig = ''
$script:pulseOn = $false
$script:prevOpen = $null
$script:curCo2 = $null
$script:ventStartCo2 = $null
$script:sumText = ''
$script:sumUntil = (Get-Date).AddMinutes(-1)
$script:ventEnd = $null
$script:ventLen = 10
$script:ventDone = $false
$script:ventDoneAt = $null
$script:lastAction = $null
$script:lastChime = (Get-Date).AddHours(-2)
$script:lastPop = (Get-Date).AddHours(-2)
$popTimer = New-Object System.Windows.Threading.DispatcherTimer
$popTimer.Interval = [TimeSpan]::FromSeconds(12)
$popTimer.Add_Tick({ $popTimer.Stop(); $win.Topmost = [bool]$state.topmost })
$script:tray = $null
$script:trayIcons = @{}
$script:lastBalloon = (Get-Date).AddHours(-2)
function Exit-App {
    try { Save-State } catch {}
    Close-Tray
    try { $mutex.ReleaseMutex() } catch {}
    [Environment]::Exit(0)
}
function Show-Window {
    try {
        $win.Show()
        if ($win.WindowState -eq 'Minimized') { $win.WindowState = 'Normal' }
        $win.Topmost = $true; $win.Activate() | Out-Null; Fade-In $win 200
        $popTimer.Stop(); $popTimer.Start()
    } catch { Write-Log ('Show-Window: ' + $_.Exception.Message) }
}
function Get-TrayIcon([string]$hex) {
    if ($script:trayIcons.ContainsKey($hex)) { return $script:trayIcons[$hex] }
    $bmp = New-Object System.Drawing.Bitmap(32, 32)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([System.Drawing.Color]::Transparent)
    $col = [System.Drawing.ColorTranslator]::FromHtml($hex)
    $br = New-Object System.Drawing.SolidBrush($col)
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 3)
    $g.FillEllipse($br, 3, 3, 25, 25); $g.DrawEllipse($pen, 3, 3, 25, 25)
    $g.Dispose(); $br.Dispose(); $pen.Dispose()
    $h = $bmp.GetHicon()
    $ic = [System.Drawing.Icon]::FromHandle($h)
    $script:trayIcons[$hex] = @{ icon = $ic; handle = $h }
    $bmp.Dispose()
    return $script:trayIcons[$hex]
}
function Init-Tray {
    try {
        $script:tray = New-Object System.Windows.Forms.NotifyIcon
        $cm = New-Object System.Windows.Forms.ContextMenuStrip
        $script:trayMiOpen = $cm.Items.Add('Luftwächter')
        $script:trayMiRefresh = $cm.Items.Add('Refresh now')
        $script:trayMiHa = $cm.Items.Add('Open Home Assistant')
        $script:trayMiHa.Visible = [bool]$script:haMode
        $script:trayMiHa.Add_Click({ try { if ($script:haUrl) { Start-Process $script:haUrl } } catch {} })
        $script:trayMiQuiet = $cm.Items.Add('Quiet for 1 hour')
        $script:trayMiRefresh.Add_Click({ Update-Widget })
        $script:trayMiQuiet.Add_Click({ Toggle-Snooze })
        $script:trayMiQuietM = $cm.Items.Add('Quiet until tomorrow morning')
        $script:trayMiQuietM.Add_Click({ Set-Snooze 'morning' })
        $script:trayMiExit = $cm.Items.Add('Exit')
        $script:trayMiOpen.Add_Click({ Show-Window })
        $script:trayMiExit.Add_Click({ Exit-App })
        $script:tray.ContextMenuStrip = $cm
        $script:tray.Add_MouseClick({ param($s, $e) if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Show-Window } })
        $script:tray.Icon = (Get-TrayIcon '#9AA5B1').icon
        $script:tray.Text = 'Luftwächter'
        $script:tray.Visible = [bool]$state.tray
    } catch { Write-Log ('Tray: ' + $_.Exception.Message); $script:tray = $null }
}
function Get-WorstRoom($d) {
    $rank = @{ gut = 0; mittel = 1; schlecht = 2 }
    $wk = $rank[[string]$d.level]; if ($null -eq $wk) { $wk = 0 }
    $wr = $null
    foreach ($r in @($d.rooms)) { $rk = $rank[[string]$r.level]; if ($null -ne $rk -and $rk -gt $wk) { $wk = $rk; $wr = $r } }
    return $wr
}
function Update-Tray($d, [string]$act) {
    if (-not $script:tray) { return }
    try {
        $script:tray.Visible = [bool]$state.tray
        if (-not $state.tray) { return }
        $hex = [string]$d.color
        if ($hex -notmatch '^#[0-9A-Fa-f]{6}$') { $hex = '#9AA5B1' }
        $script:tray.Icon = (Get-TrayIcon $hex).icon
        $co2 = ''
        foreach ($v in @($d.values)) { if ([string]$v.key -like 'CO*') { $co2 = ' · ' + [string]$v.value + ' ' + [string]$v.unit; break } }
        $tip = [string]$d.room.name + $co2 + ' · ' + [string]$d.headline
        $wr = Get-WorstRoom $d
        $l2 = ''
        if ($wr) { $l2 = (T 'tray_worst' ([string]$wr.name)); if ($l2.Length -gt 30) { $l2 = $l2.Substring(0, 29) + '…' } }
        $max1 = 63 - $(if ($l2) { $l2.Length + 1 } else { 0 })
        if ($tip.Length -gt $max1) { $tip = $tip.Substring(0, [Math]::Max($max1 - 1, 1)) + '…' }
        if ($l2) { $tip += "`n" + $l2 }
        if ($tip.Length -gt 63) { $tip = $tip.Substring(0, 62) + '…' }
        $script:tray.Text = $tip
        $h = (Get-Date).Hour
        if ($null -ne $script:lastAction -and $act -ne $script:lastAction -and ($act -eq 'oeffnen' -or $act -eq 'schliessen') -and -not (Test-Snooze) -and $h -ge 7 -and $h -lt 22 -and (((Get-Date) - $script:lastBalloon).TotalMinutes -gt 30)) {
            $script:lastBalloon = Get-Date
            $script:tray.ShowBalloonTip(8000, [string]$d.headline, [string]$d.detail, [System.Windows.Forms.ToolTipIcon]::Info)
        }
    } catch { Write-Log ('Update-Tray: ' + $_.Exception.Message) }
}
function Close-Tray {
    try {
        if ($script:tray) { $script:tray.Visible = $false; $script:tray.Dispose() }
        foreach ($k in @($script:trayIcons.Keys)) { try { [LW.Native]::DestroyIcon([IntPtr]$script:trayIcons[$k].handle) | Out-Null } catch {} }
    } catch {}
}
$script:compact = ($state.size -eq 'C')
$script:helpOpen = $false

function Save-State {
    try {
        $o = @{ left = $win.Left; top = $win.Top; topmost = $state.topmost; topmostSet = $state.topmostSet; popup = $state.popup; tray = $state.tray; room = $state.room; size = $state.size; weatherOpen = $state.weatherOpen; drawerOpen = $state.drawerOpen; sound = $state.sound; sparkHours = $state.sparkHours; metric = $state.metric; hidden = @($state.hidden); lang = $state.lang; hist = $state.hist; hist7 = $state.hist7; sensors = $state.sensors; simple = $state.simple; tourDone = $state.tourDone; demo = $state.demo; theme = $state.theme; seenVer = $state.seenVer; snooze = [string]$state.snooze; opacity = $state.opacity; locked = $state.locked; taskbar = $state.taskbar; hoverFull = $state.hoverFull }
        ($o | ConvertTo-Json -Depth 4) | Set-Content -Path $stateFile -Encoding UTF8
    } catch { Write-Log ('Speichern: ' + $_.Exception.Message) }
}

function Blend([string]$hex, [string]$base, [double]$t) {
    $a = [Convert]::ToInt32($hex.Substring($hex.Length - 6, 2), 16), [Convert]::ToInt32($hex.Substring($hex.Length - 4, 2), 16), [Convert]::ToInt32($hex.Substring($hex.Length - 2, 2), 16)
    $b = [Convert]::ToInt32($base.Substring($base.Length - 6, 2), 16), [Convert]::ToInt32($base.Substring($base.Length - 4, 2), 16), [Convert]::ToInt32($base.Substring($base.Length - 2, 2), 16)
    $r = for ($i = 0; $i -lt 3; $i++) { [int]($b[$i] + ($a[$i] - $b[$i]) * $t) }
    return ('#FF{0:X2}{1:X2}{2:X2}' -f $r[0], $r[1], $r[2])
}

function Get-Json([string]$u) {
    $req = [System.Net.HttpWebRequest]::Create($u)
    $req.Timeout = 15000
    $req.ReadWriteTimeout = 15000
    $req.UserAgent = 'Luftwaechter/3.0'
    $req.Headers.Add('Cache-Control', 'no-cache')
    $resp = $req.GetResponse()
    try {
        $sr = New-Object System.IO.StreamReader($resp.GetResponseStream(), [System.Text.Encoding]::UTF8)
        $txt = $sr.ReadToEnd(); $sr.Close()
    } finally { $resp.Close() }
    return ($txt | ConvertFrom-Json)
}

function Send-Command($body) {
    if (-not $script:canSwitch) { return }
    try {
        if ($script:haMode) {
            Send-HaCommand $body
        } else {
            $json = $body | ConvertTo-Json -Compress
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
            $req = [System.Net.HttpWebRequest]::Create($switchUrl)
            $req.Method = 'POST'; $req.ContentType = 'application/json; charset=utf-8'
            $req.Timeout = 8000; $req.ReadWriteTimeout = 8000
            $req.ContentLength = $bytes.Length
            $st = $req.GetRequestStream(); $st.Write($bytes, 0, $bytes.Length); $st.Close()
            $resp = $req.GetResponse(); $resp.Close()
        }
    } catch { Write-Log ('Schalten: ' + $_.Exception.Message) }
    $script:devSig = ''
    Update-Widget
}

function Set-IconColor($canvas, $brush) {
    foreach ($ch in $canvas.Children) {
        if ($ch.Stroke) { $ch.Stroke = $brush }
        if ($ch.Fill) { $ch.Fill = $brush }
    }
}

function Set-Ring([double]$pct, $brush) {
    $r = 40.0
    if ($pct -lt 0.06) { $pct = 0.06 }
    if ($pct -gt 0.999) { $pct = 0.999 }
    $ang = 2 * [Math]::PI * $pct
    $x = 40 + $r * [Math]::Sin($ang)
    $y = 40 - $r * [Math]::Cos($ang)
    $large = 0; if ($pct -gt 0.5) { $large = 1 }
    $path = 'M 40,0 A 40,40 0 ' + $large + ' 1 ' + $x.ToString('0.##', $inv) + ',' + $y.ToString('0.##', $inv)
    $ui.Arc.Data = [Windows.Media.Geometry]::Parse($path)
    $ui.Arc.Stroke = $brush
}

# ---------- CO2-Verlauf (3 Stunden, pro Raum gespeichert) ----------
function Add-Hist([string]$room, $co2, $extra) {
    if ($null -eq $co2) { return }
    $now = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $arr = @()
    if ($state.hist.ContainsKey($room)) { $arr = @($state.hist[$room]) }
    $lastTs = 0
    if ($arr.Count -gt 0) { $lastTs = [int]($arr[$arr.Count - 1].Split(':')[0]) }
    if (($now - $lastTs) -ge 60) {
        $arr += ('{0}:{1}:{2}:{3}:{4}' -f $now, [int]$co2, [string]$extra[0], [string]$extra[1], [string]$extra[2])
        $cut = $now - 24 * 3600
        $arr = @($arr | Where-Object { [int]($_.Split(':')[0]) -ge $cut })
        $state.hist[$room] = $arr
        # Wochenverlauf: alle 10 Minuten ein Punkt, 7 Tage lang
        $a7 = @()
        if ($state.hist7.ContainsKey($room)) { $a7 = @($state.hist7[$room]) }
        $l7 = 0
        if ($a7.Count -gt 0) { $l7 = [int]($a7[$a7.Count - 1].Split(':')[0]) }
        if (($now - $l7) -ge 600) {
            $a7 += $arr[$arr.Count - 1]
            $cut7 = $now - 7 * 24 * 3600
            $state.hist7[$room] = @($a7 | Where-Object { [int]($_.Split(':')[0]) -ge $cut7 })
        }
    }
}

function Show-Spark([string]$room, [string]$col) {
    $ui.Spark.Children.Clear()
    $m = [int]$state.metric
    for ($k = 0; $k -lt 4; $k++) { $ui.('C' + ($k + 1)).Background = Brush $(if ($k -eq $m) { '#FF686C72' } else { '#FF3C424C' }) }
    $lblKey = @('spark_co2', 'spark_dust', 'spark_temp', 'spark_hum')[$m]
    $unit = @('ppm', 'µg', '°C', '%')[$m]
    $lbl = (T $lblKey $state.sparkHours)
    if ([int]$state.sparkHours -eq 168) { $lbl = $lbl.Replace('168 Std', (Lx '7 Tage' '7 days')).Replace('168 h', (Lx '7 Tage' '7 days')) }
    $ui.SparkLabel.Text = $lbl
    $lineCol = @($col, '#C792EA', '#FF8A65', '#4FC3F7')[$m]
    $arr = @()
    if ($state.hist.ContainsKey($room)) { $arr = @($state.hist[$room]) }
    if ([int]$state.sparkHours -eq 168 -and $state.hist7.ContainsKey($room)) { $arr = @($state.hist7[$room]) }
    $w = 205.0; $h = 62.0
    $now = [double]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
    $pts = @()
    $field = $m + 1
    foreach ($e in $arr) {
        $p = $e.Split(':')
        if ($p.Count -le $field -or [string]$p[$field] -eq '') { continue }
        $v = 0.0
        if ([double]::TryParse([string]$p[$field], [Globalization.NumberStyles]::Float, $inv, [ref]$v)) { $pts += , @([double]$p[0], $v) }
    }
    $dmin = 0.0; $dmax = 0.0
    if ($pts.Count -gt 0) { $dmin = ($pts | ForEach-Object { $_[1] } | Measure-Object -Minimum).Minimum; $dmax = ($pts | ForEach-Object { $_[1] } | Measure-Object -Maximum).Maximum }
    switch ($m) {
        0 { $minv = 400.0; $maxv = [Math]::Max(1600.0, $dmax); $refs = @(1000.0) }
        1 { $minv = 0.0; $maxv = [Math]::Max(25.0, $dmax * 1.1); $refs = @(20.0) }
        2 { $minv = [Math]::Floor($dmin) - 1; $maxv = [Math]::Ceiling($dmax) + 1; $refs = @(); if ($pts.Count -eq 0) { $minv = 18.0; $maxv = 26.0 } }
        3 { $minv = [Math]::Min(20.0, $dmin - 2); $maxv = [Math]::Max(80.0, $dmax + 2); $refs = @(30.0, 60.0) }
    }
    if ($maxv - $minv -lt 6) { $c0 = ($maxv + $minv) / 2; $minv = $c0 - 3; $maxv = $c0 + 3 }
    $yOf = { param($v) $h - 4 - (($v - $minv) / ($maxv - $minv)) * ($h - 8) }
    foreach ($rv in $refs) {
        $ln = New-Object Windows.Shapes.Line
        $y1 = & $yOf $rv
        $ln.X1 = 0; $ln.X2 = $w; $ln.Y1 = $y1; $ln.Y2 = $y1
        $ln.Stroke = Brush '#FF686C72'; $ln.StrokeThickness = 1; $dc = New-Object Windows.Media.DoubleCollection; $dc.Add(3.0); $dc.Add(4.0); $ln.StrokeDashArray = $dc
        [void]$ui.Spark.Children.Add($ln)
    }
    $winSec = [double]$state.sparkHours * 3600.0
    if ($pts.Count -ge 2) {
        $span = $now - [double]$pts[0][0]
        if ($span -lt $winSec) { $winSec = [Math]::Max(900.0, $span * 1.05) }
    }
    $script:sp = @{ pts = $pts; now = $now; win = $winSec; w = $w; unit = $unit }
    if ($pts.Count -ge 2) {
        $poly = New-Object Windows.Shapes.Polygon
        $pc = New-Object Windows.Media.PointCollection
        foreach ($p in $pts) {
            $x = $w - (($now - $p[0]) / $winSec) * $w
            if ($x -lt 0) { continue }
            $pc.Add((New-Object Windows.Point($x, (& $yOf $p[1]))))
        }
        if ($pc.Count -ge 2) {
            $lastX = $pc[$pc.Count - 1].X; $firstX = $pc[0].X
            $line = New-Object Windows.Shapes.Polyline
            $line.Points = $pc; $line.Stroke = Brush $lineCol; $line.StrokeThickness = 2.2; $line.StrokeLineJoin = 'Round'
            $fillPc = New-Object Windows.Media.PointCollection
            $fillPc.Add((New-Object Windows.Point($firstX, $h)))
            foreach ($q in $pc) { $fillPc.Add($q) }
            $fillPc.Add((New-Object Windows.Point($lastX, $h)))
            $poly.Points = $fillPc; $poly.Fill = Brush ('#40' + $lineCol.Substring($lineCol.Length - 6))
            [void]$ui.Spark.Children.Add($poly); [void]$ui.Spark.Children.Add($line)
        }
    } elseif ($m -gt 0) {
        $tb = New-Text (T 'spark_wait') 11 '#FFA9B4C4' $false
        [Windows.Controls.Canvas]::SetLeft($tb, 4); [Windows.Controls.Canvas]::SetTop($tb, 20)
        [void]$ui.Spark.Children.Add($tb)
    }
    if ($m -gt 0) {
        $today = (Get-Date).Date; $tv = @()
        foreach ($q in $pts) { $lt = [DateTimeOffset]::FromUnixTimeSeconds([long]$q[0]).LocalDateTime; if ($lt -ge $today) { $tv += , @([double]$q[1], $lt) } }
        if ($tv.Count -ge 2) {
            $mnI = $tv[0]; $mxI = $tv[0]
            foreach ($q in $tv) { if ($q[0] -lt $mnI[0]) { $mnI = $q }; if ($q[0] -gt $mxI[0]) { $mxI = $q } }
            $ui.Peak.Text = (T 'mm2' ($mnI[0].ToString('0.#', $inv)) ($mxI[0].ToString('0.#', $inv)) $unit).Replace('{3}', $mnI[1].ToString('HH:mm')).Replace('{4}', $mxI[1].ToString('HH:mm'))
        } else { $ui.Peak.Text = '' }
    }
}

function Get-SparkPoint([double]$x) {
    $sp = $script:sp
    if (-not $sp -or @($sp.pts).Count -lt 2) { return $null }
    $ts = $sp.now - (($sp.w - $x) / $sp.w) * $sp.win
    $best = $null; $bd = [double]::MaxValue
    foreach ($q in $sp.pts) { $dd = [Math]::Abs($q[0] - $ts); if ($dd -lt $bd) { $bd = $dd; $best = $q } }
    if ($null -eq $best) { return $null }
    $lt = [DateTimeOffset]::FromUnixTimeSeconds([long]$best[0]).LocalDateTime
    $fmt = $(if ([int]$state.sparkHours -eq 168) { 'dd.MM. HH:mm' } else { 'HH:mm' })
    return @{ text = ($lt.ToString($fmt) + ' · ' + ([double]$best[1]).ToString('0.#', $inv) + ' ' + $sp.unit); px = ($sp.w - (($sp.now - $best[0]) / $sp.win) * $sp.w) }
}
function Clear-SparkMark {
    for ($i = $ui.Spark.Children.Count - 1; $i -ge 0; $i--) { if ([string]$ui.Spark.Children[$i].Tag -eq 'mark') { $ui.Spark.Children.RemoveAt($i) } }
}

function Get-Trend([string]$room) {
    $arr = @()
    if ($state.hist.ContainsKey($room)) { $arr = @($state.hist[$room]) }
    if ($arr.Count -lt 5) { return '' }
    $now = [int]($arr[$arr.Count - 1].Split(':')[0]); $cur = [int]($arr[$arr.Count - 1].Split(':')[1])
    $ref = $arr[0]
    foreach ($e in $arr) { if ([int]($e.Split(':')[0]) -ge ($now - 1800)) { $ref = $e; break } }
    $d = $cur - [int]($ref.Split(':')[1])
    $mins = [int](($now - [int]($ref.Split(':')[0])) / 60)
    if ($mins -lt 5) { return '' }
    if ($d -gt 50) { return ([string][char]0x2197) + ' ' + (T 'tr_up' $mins) }
    if ($d -lt -50) { return ([string][char]0x2198) + ' ' + (T 'tr_dn' $mins) }
    return ([string][char]0x2192) + ' ' + (T 'tr_flat')
}

function Get-Forecast([string]$room, $co2) {
    if ($null -eq $co2) { return '' }
    $arr = @()
    if ($state.hist.ContainsKey($room)) { $arr = @($state.hist[$room]) }
    if ($arr.Count -lt 4) { return '' }
    $last = $arr[$arr.Count - 1].Split(':')
    $nowT = [double]$last[0]; $nowV = [double]$last[1]
    $ref = $null
    foreach ($e in $arr) { $p = $e.Split(':'); if ([double]$p[0] -ge ($nowT - 900)) { $ref = $p; break } }
    if ($null -eq $ref) { return '' }
    $mins = ($nowT - [double]$ref[0]) / 60.0
    if ($mins -lt 4) { return '' }
    $slope = ($nowV - [double]$ref[1]) / $mins
    if ($slope -le -4 -and $co2 -gt 700) {
        $m = [int][Math]::Ceiling(($co2 - 700) / (-$slope))
        if ($m -lt 1) { $m = 1 }
        if ($m -le 90) { return (T 'fc_good' $m) }
    }
    if ($slope -ge 3 -and $co2 -lt 1000) {
        $m = [int][Math]::Ceiling((1000 - $co2) / $slope)
        if ($m -lt 1) { $m = 1 }
        if ($m -le 120) { return (T 'fc_over' $m) }
    }
    return ''
}

function Get-Peak([string]$room) {
    $arr = @()
    if ($state.hist.ContainsKey($room)) { $arr = @($state.hist[$room]) }
    if ($arr.Count -eq 0) { return '' }
    $today = (Get-Date).Date
    $best = $null; $bt = $null; $n = 0; $sum = 0; $good = 0
    foreach ($e in $arr) {
        $p = $e.Split(':'); $t = [DateTimeOffset]::FromUnixTimeSeconds([long]$p[0]).LocalDateTime
        if ($t -ge $today) {
            $v = [int]$p[1]; $n++; $sum += $v; if ($v -lt 1000) { $good++ }
            if (($null -eq $best) -or ($v -gt $best)) { $best = $v; $bt = $t }
        }
    }
    if ($null -eq $best) { return '' }
    $r = (T 'peak' $best ([string]$bt.ToString('HH:mm')))
    if ($n -ge 10) { $r += ("`n" + (T 'avg' ([int][Math]::Round($sum / $n)) ([int][Math]::Round(100.0 * $good / $n)))) }
    return $r
}

# ---------- Geräte-Fläche ----------
function New-Text([string]$t, [double]$size, [string]$fg, [bool]$bold) {
    $tb = New-Object Windows.Controls.TextBlock
    $tb.Text = $t; $tb.FontSize = $size; $tb.Foreground = Brush $fg
    if ($bold) { $tb.FontWeight = 'Bold' }
    return $tb
}
function New-Btn([string]$t, $tag) {
    $b = New-Object Windows.Controls.Border
    $b.Background = Brush '#FF494E57'; $b.CornerRadius = New-Object Windows.CornerRadius(9)
    $b.Padding = New-Object Windows.Thickness(10, 4, 10, 4); $b.Margin = New-Object Windows.Thickness(3, 0, 0, 0); $b.Cursor = 'Hand'
    $b.Child = (New-Text $t 14 '#FFFFFFFF' $true)
    $b.Tag = $tag
    $b.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; $c = @{ room = $state.room; entity = $s.Tag.e; action = $s.Tag.a }; if ($null -ne $s.Tag.v) { $c.value = $s.Tag.v }; Send-Command $c })
    return $b
}

function Build-Devices($devs) {
    $ui.DevPanel.Children.Clear()
    $hid = @($state.hidden)
    $nRx = '(?i)internetzugang|internet access|child lock|kindersicherung|reversal|calibrat|kalibrier|bluetooth proxy|nicht stören|do not disturb|benachrichtigung|notification|schlafmodus|sleep mode|display|backlight|auto.?update|firmware|identify|restart|neustart|pairing|permit join'
    $devs = @($devs | Where-Object { ($hid -notcontains [string]$_.entity) -and -not ($script:haMode -and -not [bool]$cfg.showAllDevices -and ([string]$_.type -eq 'switch') -and (([string]$_.name) -match $nRx)) })
    $groups = @('Licht', 'Strom', 'Heizung', 'Rollo')
    $gIcon = @{ Licht = ([char]::ConvertFromUtf32(0x1F4A1)); Strom = ([char]::ConvertFromUtf32(0x1F50C)); Heizung = ([char]::ConvertFromUtf32(0x1F321)); Rollo = ([string][char]0x25A5) }
    $any = $false
    foreach ($g in $groups) {
        $items = @($devs | Where-Object { $_.group -eq $g })
        if ($items.Count -eq 0) { continue }
        $any = $true
        $hd = New-Text ($gIcon[$g] + '  ' + (T ('grp_' + $g)).ToUpper()) 11 '#FFB3BECD' $false
        $hd.Margin = New-Object Windows.Thickness(2, 10, 0, 3)
        [void]$ui.DevPanel.Children.Add($hd)
        foreach ($dv in $items) {
            $row = New-Object Windows.Controls.Border
            $row.Background = Brush '#FF373C46'; $row.CornerRadius = New-Object Windows.CornerRadius(14)
            $row.Padding = New-Object Windows.Thickness(10, 6, 10, 6); $row.Margin = New-Object Windows.Thickness(0, 2, 0, 2)
            $dp = New-Object Windows.Controls.DockPanel
            $row.Child = $dp
            $entity = [string]$dv.entity
            $row.Tag = $entity
            $row.Add_MouseRightButtonUp({ param($s, $e)
                $e.Handled = $true
                $m = New-Object Windows.Controls.ContextMenu
                $mi = New-Object Windows.Controls.MenuItem; $mi.Header = (T 'dev_hide'); $mi.Tag = [string]$s.Tag
                $mi.Add_Click({ param($s2, $e2) $state.hidden = @(@($state.hidden) + [string]$s2.Tag); Save-State; $script:devSig = ''; if ($script:last) { Show-Data $script:last } })
                [void]$m.Items.Add($mi); $m.PlacementTarget = $s; $m.IsOpen = $true
            })
            $ctl = $null
            switch ([string]$dv.type) {
                'switch' {
                    $sw = New-Object Windows.Controls.Border
                    $sw.Width = 44; $sw.Height = 24; $sw.CornerRadius = New-Object Windows.CornerRadius(12); $sw.Cursor = 'Hand'
                    $knob = New-Object Windows.Shapes.Ellipse
                    $knob.Width = 18; $knob.Height = 18; $knob.Fill = Brush '#FFFFFFFF'; $knob.VerticalAlignment = 'Center'
                    $isOn = ([string]$dv.state -eq 'on')
                    if ($isOn) { $sw.Background = Brush '#FF2E9E5B'; $knob.HorizontalAlignment = 'Right'; $knob.Margin = New-Object Windows.Thickness(0, 0, 3, 0) }
                    else { $sw.Background = Brush '#FF4A5568'; $knob.HorizontalAlignment = 'Left'; $knob.Margin = New-Object Windows.Thickness(3, 0, 0, 0) }
                    $sw.Child = $knob
                    $sw.Tag = $entity
                    $sw.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; $s.Opacity = 0.5; Send-Command @{ room = $state.room; entity = [string]$s.Tag; action = 'toggle' } })
                    $ctl = $sw
                }
                'climate' {
                    $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'
                    $cur = [double]$dv.target
                    $minus = New-Btn ([string][char]0x2212) @{ e = $entity; a = 'temp'; v = ($cur - 0.5) }
                    $val = New-Text ($(if ($state.lang -eq 'en') { $cur.ToString('0.0', $inv) } else { ($cur.ToString('0.0', $inv)).Replace('.', ',') }) + '°') 17 '#FFFFFFFF' $true
                    $val.VerticalAlignment = 'Center'; $val.Margin = New-Object Windows.Thickness(6, 0, 3, 0)
                    $plus = New-Btn '+' @{ e = $entity; a = 'temp'; v = ($cur + 0.5) }
                    [void]$sp.Children.Add($minus); [void]$sp.Children.Add($val); [void]$sp.Children.Add($plus)
                    $ctl = $sp
                }
                'cover' {
                    $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'
                    [void]$sp.Children.Add((New-Btn ([string][char]0x25B2) @{ e = $entity; a = 'open' }))
                    [void]$sp.Children.Add((New-Btn ([string][char]0x25A0) @{ e = $entity; a = 'stop' }))
                    [void]$sp.Children.Add((New-Btn ([string][char]0x25BC) @{ e = $entity; a = 'close' }))
                    $ctl = $sp
                }
                'meter' {
                    $ctl = (New-Text ([string]$dv.value) 16 '#FFFFFFFF' $true)
                }
                'button' {
                    $ctl = New-Btn 'Start' @{ e = $entity; a = 'press' }
                }
            }
            if ($ctl) { [Windows.Controls.DockPanel]::SetDock($ctl, 'Right'); $ctl.VerticalAlignment = 'Center'; if ((-not $script:canSwitch) -and ([string]$dv.type -ne 'meter')) { $ctl.Opacity = 0.35; $ctl.IsEnabled = $false } ; [void]$dp.Children.Add($ctl) }
            $sp2 = New-Object Windows.Controls.StackPanel; $sp2.VerticalAlignment = 'Center'
            [void]$sp2.Children.Add((New-Text ([string]$dv.name) 14 '#FFFFFFFF' $false))
            if ($dv.detail) { [void]$sp2.Children.Add((New-Text ([string]$dv.detail) 11 '#FFB3BECD' $false)) }
            [void]$dp.Children.Add($sp2)
            [void]$ui.DevPanel.Children.Add($row)
        }
    }
    if ($hid.Count -gt 0) {
        $uh = New-Text (T 'dev_unhide' $hid.Count) 11 '#FF7CB7FF' $false
        $uh.Margin = New-Object Windows.Thickness(2, 10, 0, 0); $uh.Cursor = 'Hand'
        $uh.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; $state.hidden = @(); Save-State; $script:devSig = ''; if ($script:last) { Show-Data $script:last } })
        [void]$ui.DevPanel.Children.Add($uh)
    }
    if (-not $any) {
        $t = New-Text (T 'no_dev') 13 '#FFB3BECD' $false
        $t.TextWrapping = 'Wrap'; $t.Margin = New-Object Windows.Thickness(0, 12, 0, 0)
        [void]$ui.DevPanel.Children.Add($t)
    }
    if (-not $script:canSwitch) {
        $t = New-Text (T 'no_switch') 11 '#FFB3BECD' $false
        $t.Margin = New-Object Windows.Thickness(2, 10, 0, 0)
        [void]$ui.DevPanel.Children.Add($t)
    }
}

function Set-Summary($start, $now) {
    if ($null -eq $start -or $null -eq $now) { return }
    $script:sumText = ([string][char]0x2714) + ' ' + (T 'aired' ([int]$start) ([int]$now))
    $script:sumUntil = (Get-Date).AddMinutes(5)
}

# ---------- Haus-Überblick: alle Räume auf einen Blick ----------
function Build-Strip {
    $ui.RoomStrip.Children.Clear()
    $short = @{}
    try {
        $src = $cfg.roomShort
        if ($state.lang -eq 'en' -and $cfg.roomShortEn) { $src = $cfg.roomShortEn }
        if ($src) { foreach ($pp in $src.PSObject.Properties) { $short[[string]$pp.Name] = [string]$pp.Value } }
    } catch {}
    foreach ($r in $script:rooms) {
        $key = [string]$r.key
        $pill = New-Object Windows.Controls.Border
        $pill.CornerRadius = New-Object Windows.CornerRadius(10)
        $pill.Padding = New-Object Windows.Thickness(8, 3, 9, 3)
        $pill.Margin = New-Object Windows.Thickness(0, 0, 5, 4)
        $pill.Cursor = 'Hand'
        $pill.BorderThickness = New-Object Windows.Thickness(1.5)
        if ($key -eq [string]$state.room) { $pill.Background = Brush '#FF686C72'; $pill.BorderBrush = Brush '#FFFFFFFF' }
        else { $pill.Background = Brush '#FF3C424C'; $pill.BorderBrush = Brush '#00FFFFFF' }
        $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'
        $dot = New-Object Windows.Shapes.Ellipse; $dot.Width = 9; $dot.Height = 9; $dot.Margin = New-Object Windows.Thickness(0, 0, 6, 0); $dot.VerticalAlignment = 'Center'
        $c = '#FF7A8594'; if ($r.color) { $c = [string]$r.color }
        $dot.Fill = Brush $c
        $lbl = [string]$r.name; if ($short.ContainsKey($key)) { $lbl = $short[$key] }
        $tb = New-Object Windows.Controls.TextBlock; $tb.Text = $lbl; $tb.FontSize = 12; $tb.Foreground = Brush '#FFFFFFFF'
        if ($key -eq [string]$state.room) { $tb.FontWeight = 'Bold' }
        [void]$sp.Children.Add($dot); [void]$sp.Children.Add($tb)
        $pill.Child = $sp
        $pill.Tag = $key
        $chipTip = [string]$r.name; if ($r.co2) { $chipTip += ' · CO₂ ' + [string]$r.co2 + ' ppm' }; $lt0 = Get-LevelText ([string]$r.level); if ($lt0) { $chipTip += ' · ' + $lt0 }
        $pill.ToolTip = $chipTip
        [System.Windows.Automation.AutomationProperties]::SetName($pill, $chipTip)
        $pill.Add_MouseLeftButtonDown({ param($s2, $e2) $e2.Handled = $true; $state.room = [string]$s2.Tag; $script:ventEnd = $null; $script:prevOpen = $null; $script:sumText = ''; $script:lastAction = $null; $script:devSig = ''; $script:openSince = $null; Save-State; Update-Widget })
        Add-Hover $pill
        [void]$ui.RoomStrip.Children.Add($pill)
    }
}

# ---------- Ansicht ----------
function Toggle-Mode { $state.simple = -not [bool]$state.simple; Apply-View; Save-State; Apply-Lang }
function Apply-Simple {
    $sm = [bool]$state.simple
    $ui.BtnModeT.Text = $(if ($sm) { T 'mode_more' } else { T 'mode_simple' })
    $ui.BtnMode.ToolTip = (T 'mode_tip')
    $ui.TabLbl.Text = (T 'tab_lbl')
    $ui.TourOkT.Text = (T 'tour_ok')
    $script:tourMode = ''
    if ($sm -and -not $state.tourDone -and -not $script:compact) {
        $script:tourMode = 'tour'; $ui.TourH.Text = (T 'tour_h'); $ui.TourT.Text = (T 'tour_t')
    } elseif ($state.tourDone -and [string]$state.seenVer -ne $appVersion -and -not $script:compact) {
        if ($null -eq $script:newsText) {
            $script:newsText = ''
            try {
                $ent = @(Read-Changelog) | Where-Object { $_.ver -eq $appVersion } | Select-Object -First 1
                if ($ent) { $script:newsText = (@($ent.lines) -join "`n") }
            } catch {}
            if ($script:newsText.Length -gt 320) { $script:newsText = $script:newsText.Substring(0, 317) + '…' }
        }
        if ($script:newsText) { $script:tourMode = 'news'; $ui.TourH.Text = (T 'news_h' $appVersion); $ui.TourT.Text = $script:newsText }
        else { $state.seenVer = $appVersion }
    }
    if ($script:tourMode) { $ui.Tour.Visibility = 'Visible' } else { $ui.Tour.Visibility = 'Collapsed' }
    if ($script:compact) { return }
    $hide = $(if ($sm) { 'Collapsed' } else { 'Visible' })
    foreach ($n in 'GrpTiles', 'Peak', 'GrpFoot', 'SzBox', 'Time') { $ui.$n.Visibility = $hide }
    if ($sm) { $ui.WLine.Visibility = 'Collapsed'; $ui.WFull.Visibility = 'Collapsed' }
    elseif ($state.weatherOpen) { $ui.WLine.Visibility = 'Collapsed'; $ui.WFull.Visibility = 'Visible' } else { $ui.WLine.Visibility = 'Visible'; $ui.WFull.Visibility = 'Collapsed' }
    if ($sm) {
        $ui.Copy.Visibility = 'Collapsed'
        $ui.GrpUpd.Visibility = 'Visible'
        $ui.Headline.FontSize = 26; $ui.Detail.FontSize = 16; $ui.Level.FontSize = 28; $ui.Trend.FontSize = 14
        $ui.TabArr.Visibility = 'Collapsed'; $ui.TabLbl.Visibility = 'Visible'; $ui.Tab.Height = 170; $ui.Tab.Width = 34
    } else {
        $ui.Copy.Visibility = 'Visible'; $ui.GrpUpd.Visibility = 'Visible'
        $ui.Headline.FontSize = 22; $ui.Detail.FontSize = 13; $ui.Level.FontSize = 24; $ui.Trend.FontSize = 12
        $ui.TabArr.Visibility = 'Visible'; $ui.TabLbl.Visibility = 'Collapsed'; $ui.Tab.Height = 120; $ui.Tab.Width = 28
    }
}
function Apply-View {
    $scale = 1.0
    switch ($state.size) { 'S' { $scale = 0.82 } 'L' { $scale = 1.2 } 'XL' { $scale = 1.45 } default { $scale = 1.0 } }
    $ui.Scaler.LayoutTransform = New-Object Windows.Media.ScaleTransform($scale, $scale)
    $ui.Ver.Text = $version
    if ($state.drawerOpen -and -not ($state.size -eq 'C')) { $ui.Card.CornerRadius = New-Object Windows.CornerRadius(24, 0, 0, 24) } else { $ui.Card.CornerRadius = New-Object Windows.CornerRadius(24) }
    foreach ($k in 'S', 'M', 'L', 'C', 'P') { $ui.('Sz' + $k).Foreground = Brush '#FFA9B4C4'; $ui.('Sz' + $k).FontWeight = 'Normal'; $ui.('SzB' + $k).Background = Brush '#00000000' }
    if ($state.size -ne 'XL') { $ui.('Sz' + $state.size).Foreground = Brush '#FFFFFFFF'; $ui.('Sz' + $state.size).FontWeight = 'Bold'; $ui.('SzB' + $state.size).Background = Brush '#FF585C64' }
    $script:compact = ($state.size -eq 'C' -or $state.size -eq 'P')
    if ($state.size -eq 'P') { $ui.Card.Visibility = 'Collapsed'; $ui.Pill.Visibility = 'Visible' } else { $ui.Card.Visibility = 'Visible'; $ui.Pill.Visibility = 'Collapsed' }
    if ($script:compact) { $ui.Details.Visibility = 'Collapsed'; $ui.Detail.Visibility = 'Collapsed'; $ui.Drawer.Visibility = 'Collapsed'; $ui.Tab.Visibility = 'Collapsed' }
    else {
        $ui.Details.Visibility = 'Visible'; $ui.Detail.Visibility = 'Visible'
        if ($state.weatherOpen) { $ui.WLine.Visibility = 'Collapsed'; $ui.WFull.Visibility = 'Visible' } else { $ui.WLine.Visibility = 'Visible'; $ui.WFull.Visibility = 'Collapsed' }
        if ($state.drawerOpen) { $ui.Drawer.Visibility = 'Visible'; $ui.Tab.Visibility = 'Collapsed' } else { $ui.Drawer.Visibility = 'Collapsed'; $ui.Tab.Visibility = 'Visible' }
    }
    Apply-Simple
    if ($script:helpOpen) { $ui.Help.Visibility = 'Visible'; $ui.Card.Visibility = 'Collapsed'; $ui.Pill.Visibility = 'Collapsed'; $ui.Drawer.Visibility = 'Collapsed'; $ui.Tab.Visibility = 'Collapsed' } else { $ui.Help.Visibility = 'Collapsed' }
    if ($scale -eq 1.0) { [System.Windows.Media.TextOptions]::SetTextFormattingMode($win, [System.Windows.Media.TextFormattingMode]::Display) } else { [System.Windows.Media.TextOptions]::SetTextFormattingMode($win, [System.Windows.Media.TextFormattingMode]::Ideal) }
    $win.UpdateLayout()
    # Bildschirmgrenzen über alle Monitore (nicht nur den Hauptmonitor)
    $vl = [System.Windows.SystemParameters]::VirtualScreenLeft; $vt = [System.Windows.SystemParameters]::VirtualScreenTop
    $vr = $vl + [System.Windows.SystemParameters]::VirtualScreenWidth; $vb = $vt + [System.Windows.SystemParameters]::VirtualScreenHeight
    if ($win.Left + $win.ActualWidth -gt $vr) { $win.Left = [Math]::Max($vl, $vr - $win.ActualWidth - 6) }
    if ($win.Top + $win.ActualHeight -gt $vb) { $win.Top = [Math]::Max($vt, $vb - $win.ActualHeight - 6) }
}

function Get-DayScore([string]$room) {
    if (-not $state.hist.ContainsKey($room)) { return $null }
    $mid = [int][DateTimeOffset]::new((Get-Date).Date).ToUnixTimeSeconds()
    $n = 0; $good = 0
    foreach ($e in @($state.hist[$room])) {
        $f = ([string]$e).Split(':')
        if ($f.Count -lt 2 -or [int]$f[0] -lt $mid) { continue }
        $n++; if ([int]$f[1] -lt 1000) { $good++ }
    }
    if ($n -lt 20) { return $null }
    return [int][Math]::Round(100.0 * $good / $n)
}
function Get-WeekScore([string]$room) {
    if (-not $state.hist7.ContainsKey($room)) { return $null }
    $n = 0; $good = 0
    foreach ($e in @($state.hist7[$room])) {
        $f = ([string]$e).Split(':')
        if ($f.Count -lt 2) { continue }
        $n++; if ([int]$f[1] -lt 1000) { $good++ }
    }
    if ($n -lt 72) { return $null }
    return [int][Math]::Round(100.0 * $good / $n)
}
function Get-LevelText([string]$lv) {
    switch ($lv) { 'gut' { return (T 'lv_good') } 'mittel' { return (T 'lv_mid') } 'schlecht' { return (T 'lv_bad') } default { return '' } }
}
function Get-HouseText($rooms) {
    $rr = @($rooms); $n = $rr.Count
    if ($n -eq 0) { return '' }
    $b = @($rr | Where-Object { [string]$_.level -eq 'schlecht' }).Count
    $m = @($rr | Where-Object { [string]$_.level -eq 'mittel' }).Count
    if ($b -gt 0) { return (T 'house_bad' $b $n) }
    if ($m -gt 0) { return (T 'house_mid' $m $n) }
    return (T 'house_ok' 0 $n)
}
function Update-HouseTitle($d) {
    try {
        $h = Get-HouseText $d.rooms
        $win.Title = $(if ($h) { 'Luftwächter · ' + $h } else { 'Luftwächter' })
        [System.Windows.Automation.AutomationProperties]::SetName($ui.Card, (T 'sr_card' ([string]$d.room.name) (Get-LevelText ([string]$d.level)) ([string]$d.headline)))
    } catch { Write-Log ('Titel: ' + $_.Exception.Message) }
}
function Apply-Window {
    try {
        $win.Opacity = (Get-TargetOpacity $win.IsMouseOver)
        $win.ShowInTaskbar = ([bool]$state.taskbar -or -not [bool]$state.tray)
    } catch { Write-Log ('Fenster: ' + $_.Exception.Message) }
}
function Get-TargetOpacity([bool]$hover) {
    if ($hover -and [bool]$state.hoverFull) { return 1.0 }
    return [double]$state.opacity
}
$script:settingKeys = @('theme', 'lang', 'sound', 'popup', 'tray', 'simple', 'topmost', 'opacity', 'locked', 'taskbar', 'hoverFull')
function Export-Settings([string]$path) {
    try {
        $o = [ordered]@{ app = $appName; version = $appVersion }
        foreach ($k in $script:settingKeys) { $o[$k] = $state[$k] }
        ($o | ConvertTo-Json -Depth 3) | Set-Content -Path $path -Encoding UTF8
        return $true
    } catch { Write-Log ('Sicherung: ' + $_.Exception.Message); return $false }
}
function Import-Settings([string]$path) {
    try {
        $s = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$s.app -ne $appName) { return $false }
        if (@('auto', 'day', 'night') -contains [string]$s.theme) { $state.theme = [string]$s.theme }
        if (@('de', 'en') -contains [string]$s.lang) { $state.lang = [string]$s.lang }
        foreach ($k in 'sound', 'popup', 'tray', 'simple', 'topmost', 'locked', 'taskbar', 'hoverFull') { if ($null -ne $s.$k) { $state[$k] = [bool]$s.$k } }
        if ($null -ne $s.opacity -and [double]$s.opacity -ge 0.5 -and [double]$s.opacity -le 1.0) { $state.opacity = [double]$s.opacity }
        return $true
    } catch { Write-Log ('Wiederherstellen: ' + $_.Exception.Message); return $false }
}
function Step-Opacity {
    $state.opacity = $(if ([double]$state.opacity -gt 0.9) { 0.85 } elseif ([double]$state.opacity -gt 0.75) { 0.7 } else { 1.0 })
    Apply-Window; Save-State; Apply-Lang
}
function Test-Autostart { return [bool](Test-Path $startupLnk) }
function Set-Autostart([bool]$on) {
    try {
        if ($on) {
            $vbs = Join-Path $dir 'Start.vbs'
            if (-not (Test-Path $vbs)) { return $false }
            $sh = New-Object -ComObject WScript.Shell
            $lnk = $sh.CreateShortcut($startupLnk)
            $lnk.TargetPath = 'wscript.exe'
            $lnk.Arguments = '"' + $vbs + '"'
            $lnk.WorkingDirectory = $dir
            $lnk.Save()
        } else { Remove-Item -Force $startupLnk -ErrorAction SilentlyContinue }
        return $true
    } catch { Write-Log ('Autostart: ' + $_.Exception.Message); return $false }
}
function Get-WidgetBitmap {
    $el = $ui.Scaler
    $old = $el.LayoutTransform
    try {
        # The widget is scaled with a layout transform; measure and draw it at its natural size, then draw at (scale x 2) for a sharp picture.
        $s = 1.0; try { $s = [double]$old.Value.M11 } catch {}
        if ($s -lt 0.5 -or $s -gt 4) { $s = 1.0 }
        $el.LayoutTransform = [System.Windows.Media.Transform]::Identity
        $el.UpdateLayout()
        $w = [double]$el.ActualWidth; $h = [double]$el.ActualHeight
        if ($w -lt 10 -or $h -lt 10) {
            $el.Measure((New-Object System.Windows.Size 700, 2000)); $w = [double]$el.DesiredSize.Width; $h = [double]$el.DesiredSize.Height
            $el.Arrange((New-Object System.Windows.Rect 0, 0, $w, $h)); $el.UpdateLayout()
        }
        if ($w -lt 10 -or $h -lt 10) { return $null }
        $k = 2.0 * $s
        $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap ([int][Math]::Ceiling($w * $k)), ([int][Math]::Ceiling($h * $k)), 96, 96, ([System.Windows.Media.PixelFormats]::Pbgra32)
        $dv = New-Object System.Windows.Media.DrawingVisual
        $dc = $dv.RenderOpen()
        $dc.PushTransform((New-Object System.Windows.Media.ScaleTransform $k, $k))
        $dc.DrawRectangle((New-Object System.Windows.Media.VisualBrush $el), $null, (New-Object System.Windows.Rect 0, 0, $w, $h))
        $dc.Pop(); $dc.Close()
        $rtb.Render($dv)
        return $rtb
    } catch { Write-Log ('Bild: ' + $_.Exception.Message); return $null }
    finally { $el.LayoutTransform = $old; try { $el.UpdateLayout() } catch {} }
}
function Save-WidgetPicture([string]$folder) {
    $bmp = Get-WidgetBitmap
    if (-not $bmp) { return $null }
    try {
        if (-not $folder) { $folder = [Environment]::GetFolderPath('MyPictures') }
        if (-not (Test-Path $folder)) { New-Item -ItemType Directory -Force -Path $folder | Out-Null }
        $path = Join-Path $folder ('Luftwaechter-' + (Get-Date).ToString('yyyyMMdd-HHmmss') + '.png')
        $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
        $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bmp))
        $fs = [System.IO.File]::Create($path)
        try { $enc.Save($fs) } finally { $fs.Dispose() }
        return $path
    } catch { Write-Log ('Bild speichern: ' + $_.Exception.Message); return $null }
}
function Copy-WidgetPicture {
    $bmp = Get-WidgetBitmap
    if ($bmp) { try { [System.Windows.Clipboard]::SetImage($bmp); return $true } catch { Write-Log ('Bild kopieren: ' + $_.Exception.Message) } }
    return $false
}
function Get-AboutText { return ((T 'about_t' $appVersion) -replace '\\n', [Environment]::NewLine) }
function Get-ConfigWarnings {
    $w = @()
    try {
        if ($cfg.refreshSeconds -and (([int]$cfg.refreshSeconds -lt 2) -or ([int]$cfg.refreshSeconds -gt 10))) { $w += 'refreshSeconds is outside 2-10 and is limited' }
        if ($cfg.updateCheckMinutes -and (([int]$cfg.updateCheckMinutes -lt 15) -or ([int]$cfg.updateCheckMinutes -gt 1440))) { $w += 'updateCheckMinutes is outside 15-1440 and is limited' }
        if ($cfg.haUrl -and ([string]$cfg.haUrl -notmatch '^https?://')) { $w += 'haUrl does not start with http:// or https://' }
        if ($cfg.url -and ([string]$cfg.url -notmatch '^https?://')) { $w += 'url does not start with http:// or https://' }
    } catch { $w += 'config.json has a value of the wrong type' }
    return $w
}
function Get-Diagnostics {
    $mode = $(if ($state.demo) { 'demo' } elseif ($script:haMode) { 'home-assistant' } else { 'url' })
    $lines = @(
        ('Luftwächter ' + $appVersion),
        ('PowerShell ' + $PSVersionTable.PSVersion.ToString() + ' · ' + [Environment]::OSVersion.VersionString),
        ('Mode: ' + $mode + ' · language: ' + [string]$state.lang + ' · size: ' + [string]$state.size),
        ('Rooms: ' + @($script:rooms).Count + ' · failed updates in a row: ' + [string]$script:fails),
        ('Time: ' + (Get-Date).ToString('yyyy-MM-dd HH:mm') + ' · time zone: ' + [TimeZoneInfo]::Local.Id),
        ('Autostart: ' + (Test-Path $startupLnk) + ' · Home Assistant set up: ' + [bool]$script:haMode + ' · tray: ' + [string]$state.tray + ' · quiet: ' + (Test-Snooze)),
        ('Window: opacity ' + [string]$state.opacity + ' · locked: ' + [string]$state.locked + ' · taskbar: ' + [string]$state.taskbar + ' · opaque on hover: ' + [string]$state.hoverFull),
        ('Config warnings: ' + $(if (@(Get-ConfigWarnings).Count) { (@(Get-ConfigWarnings) -join '; ') } else { 'none' })),
        ('Last error: ' + $(if ($script:lastErr) { ([string]$script:lastErr -replace 'https?://\S+', '<address>') } else { 'none' })),
        '--- log (last 20 lines) ---'
    )
    try { if (Test-Path $logFile) { $lines += @(Get-Content $logFile -Tail 20 -Encoding UTF8) } } catch {}
    return ($lines -join [Environment]::NewLine)
}
function Copy-Diagnostics {
    try { $script:lastDiag = Get-Diagnostics; [System.Windows.Clipboard]::SetText($script:lastDiag) } catch { Write-Log ('Diagnose: ' + $_.Exception.Message) }
}
function Copy-AllRooms {
    try {
        if (-not $script:rooms -or @($script:rooms).Count -eq 0) { return }
        $parts = @('Luftwächter · ' + (Get-Date).ToString('dd.MM.yyyy HH:mm') + ' · ' + (Get-HouseText $script:rooms))
        foreach ($r in @($script:rooms)) {
            $co = ''; if ($r.co2) { $co = ' · ' + [string]$r.co2 + ' ppm' }
            $parts += ([string]$r.name + $co + ' · ' + (Get-LevelText ([string]$r.level)))
        }
        $script:lastCopyAll = ($parts -join [Environment]::NewLine)
        [System.Windows.Clipboard]::SetText($script:lastCopyAll)
    } catch { Write-Log ('Alle kopieren: ' + $_.Exception.Message) }
}
function Select-RoomIndex([int]$i) {
    $keys = @($script:rooms | ForEach-Object { [string]$_.key })
    if ($i -lt 0 -or $i -ge $keys.Count -or $keys[$i] -eq [string]$state.room) { return }
    $state.room = $keys[$i]
    $script:ventEnd = $null; $script:prevOpen = $null; $script:sumText = ''; $script:lastAction = $null; $script:devSig = ''; $script:openSince = $null
    Save-State; Update-Widget
}
function Copy-Readings {
    try {
        $d = $script:last; if (-not $d) { return }
        $parts = @('Luftwächter · ' + [string]$d.room.name + ' · ' + (Get-Date).ToString('dd.MM.yyyy HH:mm'))
        foreach ($v in @($d.values)) { $parts += ([string]$v.key + ': ' + [string]$v.value + ' ' + [string]$v.unit) }
        $parts += [string]$d.headline
        [System.Windows.Clipboard]::SetText(($parts -join [Environment]::NewLine))
        $script:lastCopy = ($parts -join [Environment]::NewLine)
    } catch { Write-Log ('Kopieren: ' + $_.Exception.Message) }
}
function Export-History {
    try {
        $rn = @{}
        foreach ($r in @($script:rooms)) { $rn[[string]$r.key] = [string]$r.name }
        $de = ($state.lang -ne 'en')
        $hdr = $(if ($de) { 'Zeit;Raum;CO2 ppm;Feinstaub ug/m3;Temperatur C;Luftfeuchte %' } else { 'Time;Room;CO2 ppm;Fine dust ug/m3;Temperature C;Humidity %' })
        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add($hdr)
        foreach ($k in @($state.hist7.Keys)) {
            $nm = $(if ($rn.ContainsKey($k)) { $rn[$k] } else { $k })
            foreach ($e in @($state.hist7[$k])) {
                $f = ([string]$e).Split(':')
                if ($f.Count -lt 2) { continue }
                $t = [DateTimeOffset]::FromUnixTimeSeconds([int64]$f[0]).LocalDateTime.ToString('yyyy-MM-dd HH:mm')
                $row = @($t, $nm, $f[1], $(if ($f.Count -gt 2) { $f[2] } else { '' }), $(if ($f.Count -gt 3) { $f[3] } else { '' }), $(if ($f.Count -gt 4) { $f[4] } else { '' }))
                if ($de) { for ($i = 2; $i -lt 6; $i++) { $row[$i] = ([string]$row[$i]).Replace('.', ',') } }
                $lines.Add(($row -join ';'))
            }
        }
        $docs = [Environment]::GetFolderPath('MyDocuments')
        $file = Join-Path $docs ('Luftwaechter-Verlauf-' + (Get-Date).ToString('yyyyMMdd-HHmm') + '.csv')
        [System.IO.File]::WriteAllLines($file, $lines, (New-Object System.Text.UTF8Encoding($true)))
        $script:lastExport = $file
        if (-not $SmokeTest) { Start-Process 'explorer.exe' -ArgumentList ('/select,"' + $file + '"') }
    } catch { Write-Log ('Export: ' + $_.Exception.Message) }
}
$script:snoozeUntil = $null
try { if ($state.snooze) { $sn0 = [datetime]::Parse([string]$state.snooze, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind); if ($sn0 -gt (Get-Date)) { $script:snoozeUntil = $sn0 } } } catch {}
function Set-Snooze([string]$mode) {
    if ($mode -eq 'off') { $script:snoozeUntil = $null }
    elseif ($mode -eq 'morning') { $t0 = (Get-Date).Date.AddHours(7); if ($t0 -le (Get-Date).AddMinutes(30)) { $t0 = $t0.AddDays(1) }; $script:snoozeUntil = $t0 }
    else { $script:snoozeUntil = (Get-Date).AddHours(1) }
    $state.snooze = $(if ($script:snoozeUntil) { $script:snoozeUntil.ToString('o') } else { '' })
    Save-State; Apply-Lang; if ($script:last) { Show-Data $script:last }
}
function Toggle-Snooze { if (Test-Snooze) { Set-Snooze 'off' } else { Set-Snooze 'hour' } }
function Clamp-ToScreen {
    $vl = [System.Windows.SystemParameters]::VirtualScreenLeft; $vt = [System.Windows.SystemParameters]::VirtualScreenTop
    $vr = $vl + [System.Windows.SystemParameters]::VirtualScreenWidth; $vb = $vt + [System.Windows.SystemParameters]::VirtualScreenHeight
    $w1 = [Math]::Max($win.ActualWidth, 120); $h1 = [Math]::Max($win.ActualHeight, 60)
    $moved = $false
    if ($win.Left + $w1 -lt $vl + 60 -or $win.Left -gt $vr - 60 -or $win.Top + $h1 -lt $vt + 40 -or $win.Top -gt $vb - 40) {
        $w0 = [System.Windows.SystemParameters]::WorkArea
        $win.Left = [Math]::Max($w0.Left, $w0.Right - $w1 - 20); $win.Top = $w0.Top + 20; $moved = $true
    }
    return $moved
}
function Test-Snooze { return ($null -ne $script:snoozeUntil -and (Get-Date) -lt $script:snoozeUntil) }
function Show-Data($d) {
    $ui.TitleTag.Text = $(if (Test-Snooze) { T 'quiet_tag' ($script:snoozeUntil.ToString('HH:mm')) } else { T 'tagline' })
    $script:rooms = @($d.rooms)
    if ([string]$script:lastShownRoom -ne [string]$d.room.key) { if ($script:lastShownRoom) { Fade-In $ui.Panel; Fade-In $ui.Arc }; $script:lastShownRoom = [string]$d.room.key }
    Build-Strip
    Update-HouseTitle $d
    if (-not $state.room -and $d.room.key) { $state.room = [string]$d.room.key }
    $col = [string]$d.color
    $b = Brush $col
    $ui.Card.BorderBrush = $b
    $ui.Tab.BorderBrush = $b; $ui.Drawer.BorderBrush = $b
    $ui.Glow.Color = ([Windows.Media.ColorConverter]::ConvertFromString($col))
    if (-not $script:themeBg) { $script:themeBg = '#FF1B222D' }
    $ui.Card.Background = Brush $script:themeBg; $ui.Drawer.Background = Brush $script:themeBg
    $ui.Panel.Background = Brush (Blend-Hex $col 0.2)
    $ui.Level.Foreground = $b
    $ui.RoomSub.Text = [string]$d.room.name
    $ui.DrawerTitle.Text = (T 'dev_title') + [string]$d.room.name
    $lvl = (T 'no_vals'); $face = [char]::ConvertFromUtf32(0x1F914)
    switch ([string]$d.level) {
        'gut'      { $lvl = (T 'lv_good');      $face = [char]::ConvertFromUtf32(0x1F60A) }
        'mittel'   { $lvl = (T 'lv_mid');   $face = [char]::ConvertFromUtf32(0x1F610) }
        'schlecht' { $lvl = (T 'lv_bad'); $face = [char]::ConvertFromUtf32(0x1F61F) }
    }
    $ui.Level.Text = $lvl; $ui.Face.Text = $face
    $ui.Pill.BorderBrush = $b; $ui.PillDot.Foreground = $b
    $ui.PillText.Text = [string]$d.room.name + ' · ' + $(if ($d.values -and $d.values[0].value) { [string]$d.values[0].value + ' ppm' } else { (T 'pill_no') })

    $co2 = $null
    $tmp = 0.0
    if ([double]::TryParse((([string]$d.values[0].value) -replace ',', '.'), [Globalization.NumberStyles]::Float, $inv, [ref]$tmp)) { $co2 = $tmp }
    if ($null -ne $co2) { Set-Ring ((2000.0 - $co2) / 1600.0) $b } else { Set-Ring 0.06 (Brush $grey) }
    $ex = @('', '', '')
    $vals = @($d.values)
    for ($j = 1; $j -le 3; $j++) {
        if ($vals.Count -gt $j) { $t2 = 0.0; if ([double]::TryParse((([string]$vals[$j].value) -replace ',', '.'), [Globalization.NumberStyles]::Float, $inv, [ref]$t2)) { $ex[$j - 1] = $t2.ToString('0.##', $inv) } }
    }
    Add-Hist ([string]$d.room.key) $co2 $ex
    $trTxt = Get-Trend ([string]$d.room.key)
    $fc = Get-Forecast ([string]$d.room.key) $co2
    if ($fc) { $trTxt = ($trTxt + "`n" + $fc).Trim() }
    $ui.Trend.Text = $trTxt
    $ui.Peak.Text = Get-Peak ([string]$d.room.key)
    Show-Spark ([string]$d.room.key) $col

    $isOpen = ([string]$d.window -eq 'offen')
    if ($isOpen) { $ui.IcOpen.Visibility = 'Visible'; $ui.IcClosed.Visibility = 'Collapsed'; Set-IconColor $ui.IcOpen $b }
    else { $ui.IcOpen.Visibility = 'Collapsed'; $ui.IcClosed.Visibility = 'Visible'; Set-IconColor $ui.IcClosed $b }

    $script:curCo2 = $co2
    if ($null -ne $script:prevOpen) {
        if ($isOpen -and -not $script:prevOpen) { $script:ventStartCo2 = $co2 }
        if ((-not $isOpen) -and $script:prevOpen) { Set-Summary $script:ventStartCo2 $co2; $script:ventStartCo2 = $null }
    }
    $script:prevOpen = $isOpen
    if ($isOpen) { if ((-not $script:openSince) -or ($script:openRoom -ne $d.room.key)) { $script:openSince = Get-Date; $script:openRoom = [string]$d.room.key } } else { $script:openSince = $null }
    $detail = [string]$d.detail
    $ui.BarTrack.Visibility = 'Collapsed'
    if ($isOpen -and $script:openSince -and ([string]$d.action -eq 'offen_lassen') -and $d.ventMin) {
        $el = ((Get-Date) - $script:openSince).TotalMinutes
        $rem = [Math]::Ceiling([double]$d.ventMin - $el)
        if ($rem -gt 0) { $detail = (T 'rem' ([int]$rem)) } else { $detail = (T 'vent_ok') }
        $ui.BarTrack.Visibility = 'Visible'
        $frac = [Math]::Min(1.0, [Math]::Max(0.03, $el / [double]$d.ventMin))
        $ui.BarFill.Width = [Math]::Max(4, $frac * 190)
        $ui.BarFill.Background = $b
    }
    $ui.Headline.Text = [string]$d.headline
    $ui.Detail.Text = $detail
    $ds = $null
    if ($state.simple -and -not $script:compact) { $ds = Get-DayScore ([string]$d.room.key) }
    if ($null -ne $ds) {
        $k = $(if ($ds -ge 90) { 'day_good' } elseif ($ds -ge 70) { 'day_ok' } else { 'day_low' })
        $wk = Get-WeekScore ([string]$d.room.key)
        $ui.DayScore.Text = (T $k $ds) + $(if ($null -ne $wk) { T 'week_tag' $wk } else { '' }); $ui.DayScore.Visibility = 'Visible'
    } else { $ui.DayScore.Visibility = 'Collapsed' }
    # Lüftungs-Timer (per Tippen auf die Rat-Fläche), vor allem für Räume ohne Fensterkontakt
    $actNow = [string]$d.action
    if ($script:ventEnd -and -not $isOpen) {
        $remMin = ($script:ventEnd - (Get-Date)).TotalMinutes
        $ui.BarTrack.Visibility = 'Visible'
        $ui.BarFill.Background = $b
        if ($remMin -gt 0) {
            $ui.Headline.Text = (T 'vent_run')
            $ui.Detail.Text = (T 'vent_left' ([int][Math]::Ceiling($remMin)))
            $ui.BarFill.Width = [Math]::Max(4, [Math]::Min(1.0, 1.0 - $remMin / [double]$script:ventLen) * 190)
        } else {
            if (-not $script:ventDone) {
                $script:ventDone = $true; $script:ventDoneAt = Get-Date
                Set-Summary $script:ventStartCo2 $co2; $script:ventStartCo2 = $null
                if ($state.sound -and -not (Test-Snooze)) { try { [System.Media.SystemSounds]::Exclamation.Play() } catch {} }
            }
            $ui.Headline.Text = (T 'vent_close')
            $ui.Detail.Text = (T 'vent_over')
            $ui.BarFill.Width = 190
            if (((Get-Date) - $script:ventDoneAt).TotalMinutes -gt 3) { $script:ventEnd = $null; $script:ventDone = $false }
        }
    } elseif ($actNow -eq 'oeffnen' -and -not $isOpen) {
        $ui.Detail.Text = $detail + (T 'tap_timer')
    }

    $short = @('CO₂', (T 'k_pm'), (T 'k_t'), (T 'k_h'))
    for ($i = 0; $i -lt 4; $i++) {
        $v = $d.values[$i]; $n = $i + 1
        $ui.('V' + $n).Text = [string]$v.value
        $ui.('K' + $n).Text = $short[$i] + ' ' + [string]$v.unit
        if ($null -ne $v.level) { $ui.('D' + $n).Fill = Brush ([string]$d.colors[[int]$v.level]) } else { $ui.('D' + $n).Fill = Brush $grey }
    }

    if ((Get-Date) -lt $script:sumUntil -and $script:sumText) { $ui.Peak.Text = $script:sumText }

    # Wetter
    $o = $d.outside
    if ($o -and $o.temp) {
        $ui.WLineText.Text = ([string]$o.icon) + '  ' + [string]$o.temp + ' °C  ' + [string]$o.cond + '  ·  ' + [string]$o.wind + ' km/h  ·  ' + [string]$o.hum + ' %'
        $ui.WIcon.Text = [string]$o.icon; $ui.WTemp.Text = [string]$o.temp + ' °C'; $ui.WCond.Text = [string]$o.cond
        $lab = @('Wind', (T 'w_hum'), (T 'w_cl'), (T 'w_pr'))
        $val = @(([string]$o.wind + ' km/h ' + [string]$o.windDir), ([string]$o.hum + ' %'), ([string]$o.cloud + ' %'), ([string]$o.press + ' hPa'))
        for ($i = 0; $i -lt 4; $i++) { $ui.('WK' + ($i + 1)).Text = $lab[$i]; $ui.('WV' + ($i + 1)).Text = $val[$i] }
        $ui.WTip.Text = [string]$o.tip
        $ui.WOut.Children.Clear()
        foreach ($q in @($o.out)) {
            $sp = New-Object Windows.Controls.StackPanel; $sp.HorizontalAlignment = 'Center'
            $t1 = New-Object Windows.Controls.TextBlock; $t1.Text = ([string]$q.h + ' h'); $t1.FontSize = 11; $t1.Foreground = Brush '#FFB4BFCE'; $t1.HorizontalAlignment = 'Center'
            $t2 = New-Object Windows.Controls.TextBlock; $t2.Text = [string]$q.ic; $t2.FontSize = 17; $t2.Foreground = Brush '#FFFFFFFF'; $t2.HorizontalAlignment = 'Center'; $t2.FontFamily = New-Object Windows.Media.FontFamily('Segoe UI Emoji')
            $t3 = New-Object Windows.Controls.TextBlock; $t3.Text = ([string]$q.tp + '°'); $t3.FontSize = 13; $t3.FontWeight = 'SemiBold'; $t3.Foreground = Brush '#FFFFFFFF'; $t3.HorizontalAlignment = 'Center'
            [void]$sp.Children.Add($t1); [void]$sp.Children.Add($t2); [void]$sp.Children.Add($t3)
            [void]$ui.WOut.Children.Add($sp)
        }
        if (@($o.out).Count -gt 0) { $ui.WOutB.Visibility = 'Visible' } else { $ui.WOutB.Visibility = 'Collapsed' }
    } else { $ui.WLineText.Text = (T 'w_na'); $ui.WTip.Text = ''; $ui.WOutB.Visibility = 'Collapsed' }

    $ui.Time.Text = [string]$d.updated
    if ($d.warn) { $ui.Footer.Text = [string]$d.warn; $ui.Footer.Foreground = Brush '#FFFFC857'; $ui.Footer.Cursor = 'Hand'; $ui.Footer.ToolTip = (Lx 'Ein Sensor liefert keine aktuellen Werte. Klick: Sensoren für diesen Raum wählen.' 'A sensor is not delivering current values. Click: choose sensors for this room.') }
    elseif ($null -ne $d.nsrc) { $ui.Footer.Text = (Lx ('Messwerte: ' + $d.nsrc + ' Sensoren · Home Assistant') ('Readings: ' + $d.nsrc + ' sensors · Home Assistant')); $ui.Footer.Foreground = Brush '#FFA9B4C4'; $ui.Footer.Cursor = 'Arrow'; $ui.Footer.ToolTip = $null }
    else { $ui.Footer.Text = (Get-FooterText); $ui.Footer.Foreground = Brush '#FFA9B4C4'; $ui.Footer.Cursor = 'Arrow' }

    # Geräte nur neu bauen, wenn sich etwas geändert hat
    $sig = (@($d.devices) | ForEach-Object { [string]$_.entity + ':' + [string]$_.state + ':' + [string]$_.target + ':' + [string]$_.detail }) -join '|'
    $sig = [string]$d.room.key + '#' + $sig
    if ($sig -ne $script:devSig) { $script:devSig = $sig; Build-Devices @($d.devices) }

    $script:pulse = ([string]$d.action -eq 'oeffnen')
    # sanfter Hinweiston, wenn sich der Rat ändert (nicht nachts, höchstens alle 30 Min)
    $act = [string]$d.action
    $h = (Get-Date).Hour
    if ($state.sound -and -not (Test-Snooze) -and $null -ne $script:lastAction -and $act -ne $script:lastAction -and ($act -eq 'oeffnen' -or $act -eq 'schliessen') -and $h -ge 7 -and $h -lt 22 -and (((Get-Date) - $script:lastChime).TotalMinutes -gt 30)) {
        try { [System.Media.SystemSounds]::Asterisk.Play() } catch {}
        $script:lastChime = Get-Date
    }
    if ($state.popup -and -not (Test-Snooze) -and -not $state.topmost -and $null -ne $script:lastAction -and $act -ne $script:lastAction -and ($act -eq 'oeffnen' -or $act -eq 'schliessen') -and $h -ge 7 -and $h -lt 22 -and (((Get-Date) - $script:lastPop).TotalMinutes -gt 30)) {
        $script:lastPop = Get-Date
        $win.Topmost = $true
        $popTimer.Stop(); $popTimer.Start()
    }
    Update-Tray $d $act
    $script:lastAction = $act
    Apply-View
}

function Show-Setup {
    $g = Brush $grey
    $ui.Card.BorderBrush = $g; $ui.Level.Text = '–'; $ui.Level.Foreground = $g; $ui.Face.Text = [char]::ConvertFromUtf32(0x1F527)
    $ui.PillText.Text = (T 'setup'); $ui.PillDot.Foreground = $g; Set-Ring 0.06 $g
    $ui.Panel.Background = Brush '#FF494E57'; if ($script:haMode) { $ui.Headline.Text = (T 'ha_norooms'); $ui.Detail.Text = (T 'ha_norooms_d') } else { $ui.Headline.Text = (T 'setup'); $ui.Detail.Text = (T 'setup_d') }
    $ui.RoomSub.Text = ''; $ui.Time.Text = ''; $script:pulse = $false
}

# ---------- Home Assistant direkt: Räume, Messwerte und Geräte automatisch finden ----------
$script:HaTpl = @'
{%- set rooms = namespace(l=[]) -%}
{%- set lab = label_entities('airguard') -%}
{%- for a in areas() -%}
{%- set es = namespace(l=[]) -%}
{%- for e in area_entities(a) -%}
{%- set dom = e.split('.')[0] -%}
{%- if states[e] is not none -%}
{%- set dc = state_attr(e, 'device_class') -%}
{%- if (dom == 'sensor' and dc in ['carbon_dioxide', 'pm25', 'temperature', 'humidity']) or (dom == 'binary_sensor' and dc == 'window') or dom in ['light', 'switch', 'climate', 'cover', 'button'] -%}
{%- set es.l = es.l + [{'i': e, 'd': dom, 'c': dc, 's': states(e), 'n': (state_attr(e, 'friendly_name') or e), 't': state_attr(e, 'temperature'), 'cu': state_attr(e, 'current_temperature'), 'ha': state_attr(e, 'hvac_action'), 'p': state_attr(e, 'current_position'), 'lr': as_timestamp(states[e].last_reported or states[e].last_updated, 0)}] -%}
{%- endif -%}
{%- endif -%}
{%- endfor -%}
{%- if es.l | length > 0 -%}
{%- set rooms.l = rooms.l + [{'a': a, 'n': area_name(a), 'e': es.l}] -%}
{%- endif -%}
{%- endfor -%}
{%- set wl = states.weather | list -%}
__WIDLINE__
{{ {'r': rooms.l, 'L': lab, 'w': ({'id': wid, 't': state_attr(wid, 'temperature'), 'c': states(wid), 'h': state_attr(wid, 'humidity'), 'ws': state_attr(wid, 'wind_speed'), 'wu': state_attr(wid, 'wind_speed_unit'), 'wb': state_attr(wid, 'wind_bearing'), 'cl': state_attr(wid, 'cloud_coverage'), 'p': state_attr(wid, 'pressure')} if wid else none)} | tojson }}
'@

function Lx([string]$de, [string]$en) { if ($state.lang -eq 'en') { return $en } else { return $de } }
function Num($v) {
    $o = 0.0
    if ($null -ne $v -and [double]::TryParse((([string]$v) -replace ',', '.'), [Globalization.NumberStyles]::Float, $inv, [ref]$o)) { return $o }
    return $null
}
function Fmt($v, [int]$dg) {
    if ($null -eq $v) { return [string][char]0x2013 }
    $s = ([double]$v).ToString('F' + $dg, $inv)
    if ($state.lang -ne 'en') { $s = $s.Replace('.', ',') }
    return $s
}
function LvAbove($v, $g, $f) { if ($null -eq $v) { return $null }; if ($v -lt $g) { return 0 }; if ($v -lt $f) { return 1 }; return 2 }
function LvRange($v, $g1, $g2, $f1, $f2) { if ($null -eq $v) { return $null }; if (($v -ge $g1) -and ($v -le $g2)) { return 0 }; if (($v -ge $f1) -and ($v -le $f2)) { return 1 }; return 2 }
function Test-Cand($e, [string]$dc) {
    $v = Num $e.s
    if ($null -eq $v) { return $false }
    $t = (([string]$e.i) + ' ' + ([string]$e.n)).ToLower()
    if ($dc -eq 'temperature') { if ($t -match 'taupunkt|dew|device_temp|ger[aä]tetemp|chip|cpu|prozessor|battery|batterie') { return $false }; return ($v -gt -30 -and $v -lt 60) }
    if ($dc -eq 'humidity') { if ($t -match 'absolut') { return $false }; return ($v -ge 0 -and $v -le 100) }
    if ($dc -eq 'carbon_dioxide') { return ($v -ge 250 -and $v -le 10000) }
    return ($v -ge 0 -and $v -le 2000)
}
function Get-Cands($ents, [string]$dc) {
    return @($ents | Where-Object { $_.d -eq 'sensor' -and $_.c -eq $dc -and (Test-Cand $_ $dc) })
}
# liefert den Wert eines Raums: gewählter Sensor, sonst Mittelwert der Sensoren (Label "airguard" bevorzugt, veraltete ausgenommen)
function Short-Name([string]$n, [string]$room) {
    if ($room -and $n.StartsWith($room, [StringComparison]::OrdinalIgnoreCase)) { $n = $n.Substring($room.Length).TrimStart(' ', '-', ':', '·').Trim() }
    if ($n.Length -gt 34) { $n = $n.Substring(0, 33) + '…' }
    return $n
}
function Pick-Val($ents, [string]$dc, $lab, [string]$selId, [string]$room) {
    $c = @(Get-Cands $ents $dc)
    if ($c.Count -eq 0) { return $null }
    $nowE = [double][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if ($selId) { $one = @($c | Where-Object { [string]$_.i -eq $selId }); if ($one.Count -gt 0) { $ag = 0; if ([double]$one[0].lr -gt 0) { $ag = [int][Math]::Max(0, ($nowE - [double]$one[0].lr) / 60) }; return [pscustomobject]@{ v = (Num $one[0].s); n = 1; age = $ag; skipped = @(); name = (Short-Name ([string]$one[0].n) $room); dc = $dc } } }
    $lb = @($c | Where-Object { @($lab) -contains [string]$_.i })
    if ($lb.Count -gt 0) { $c = $lb }
    $mx = ($c | ForEach-Object { [double]$_.lr } | Measure-Object -Maximum).Maximum
    $skipped = @()
    # Luftqualitäts-Monitore melden alle paar Sekunden (30 min = veraltet); Temperatur-/Feuchte-Sensoren auf Batterie melden nur bei Änderung (6 h)
    $lim = 1800; if ($dc -eq 'temperature' -or $dc -eq 'humidity') { $lim = 21600 }
    if ($mx -gt 0) { $fresh = @($c | Where-Object { [double]$_.lr -ge ($mx - $lim) }); if ($fresh.Count -gt 0) { $skipped = @($c | Where-Object { [double]$_.lr -lt ($mx - $lim) } | ForEach-Object { Short-Name ([string]$_.n) $room }); $c = $fresh } }
    $sum = 0.0; foreach ($e in $c) { $sum += (Num $e.s) }
    $ag = 0; if ($mx -gt 0) { $ag = [int][Math]::Max(0, ($nowE - $mx) / 60) }
    return [pscustomobject]@{ v = ($sum / $c.Count); n = $c.Count; age = $ag; skipped = $skipped; name = (Short-Name ([string]$c[0].n) $room); dc = $dc }
}
function Eval-HaRoom($r, $lab, $sel) {
    $ents = @($r.e)
    $vCo2 = Pick-Val $ents 'carbon_dioxide' $lab ([string]$sel.co2) ([string]$r.n)
    $vPm = Pick-Val $ents 'pm25' $lab ([string]$sel.pm) ([string]$r.n)
    $vT = Pick-Val $ents 'temperature' $lab ([string]$sel.t) ([string]$r.n)
    $vH = Pick-Val $ents 'humidity' $lab ([string]$sel.h) ([string]$r.n)
    $co2 = $null; if ($vCo2) { $co2 = $vCo2.v }
    $pm = $null; if ($vPm) { $pm = $vPm.v }
    $tt = $null; if ($vT) { $tt = $vT.v }
    $hh = $null; if ($vH) { $hh = $vH.v }
    $warn = ''
    foreach ($pv in @($vCo2, $vPm, $vT, $vH)) {
        if (-not $pv -or $warn) { continue }
        $lim = 20; if ($pv.dc -eq 'temperature' -or $pv.dc -eq 'humidity') { $lim = 360 }
        if ($pv.age -ge $lim) { $warn = (Lx ('⚠ ' + $pv.name + ' meldet seit ' + $pv.age + ' min nichts') ('⚠ ' + $pv.name + ' silent for ' + $pv.age + ' min')) }
        elseif (@($pv.skipped).Count -gt 0) { $warn = (Lx ('⚠ ignoriert (veraltet): ' + [string]@($pv.skipped)[0]) ('⚠ ignored (stale): ' + [string]@($pv.skipped)[0])) }
    }
    $nsrc = 0; foreach ($pv in @($vCo2, $vPm, $vT, $vH)) { if ($pv) { $nsrc += $pv.n } }
    $hasAir = (@($ents | Where-Object { $_.d -eq 'sensor' -and ($_.c -eq 'carbon_dioxide' -or $_.c -eq 'pm25') }).Count -gt 0)
    $lvl = @((LvAbove $co2 1000 1500), (LvAbove $pm 20 50), (LvRange $tt 17 23 13 25), (LvRange $hh 30 60 25 70))
    $known = @($lvl | Where-Object { $null -ne $_ })
    $worst = $null; if ($known.Count -gt 0) { $worst = ($known | Measure-Object -Maximum).Maximum }
    return [pscustomobject]@{ co2 = $co2; pm = $pm; t = $tt; h = $hh; lv = $lvl; worst = $worst; air = $hasAir; warn = $warn; nsrc = $nsrc }
}
$script:fcCache = $null
$script:fcAt = [DateTime]::MinValue
function Get-HaRain([string]$wid) {
    # liefert die erste Stunde (lokale Uhrzeit, Text) in den nächsten 6 h mit Regen/Schnee/Gewitter, sonst ''
    if (-not $wid) { return '' }
    try {
        if (((Get-Date) - $script:fcAt).TotalMinutes -gt 15) {
            $script:fcAt = Get-Date
            $body = (@{ entity_id = $wid; type = 'hourly' } | ConvertTo-Json -Compress)
            $txt = Invoke-Ha $script:haUrl $script:haTok 'POST' '/api/services/weather/get_forecasts?return_response' $body
            $js = $txt | ConvertFrom-Json
            $resp = $js.service_response
            $first = @($resp.PSObject.Properties)[0]
            $script:fcCache = @($first.Value.forecast)
        }
        $now = [DateTimeOffset]::UtcNow
        foreach ($f in @($script:fcCache)) {
            $t = [DateTimeOffset]::Parse([string]$f.datetime, $inv)
            if ($t -le $now) { continue }
            if (($t - $now).TotalHours -gt 6) { break }
            $c = [string]$f.condition; $pr = Num $f.precipitation
            if (@('rainy', 'pouring', 'lightning-rainy', 'lightning', 'snowy', 'snowy-rainy', 'hail') -contains $c -or ($null -ne $pr -and $pr -ge 0.3)) { return $t.ToLocalTime().ToString('HH:mm') }
        }
    } catch { Write-Log ('Vorhersage: ' + $_.Exception.Message) }
    return ''
}
function Build-HaData($data, [string]$wantRoom) {
    $script:haData = $data
    $en = ($state.lang -eq 'en')
    $colors = @('#2e9e5b', '#e8a317', '#d9472b')
    $lnames = @('gut', 'mittel', 'schlecht')
    $list = @()
    foreach ($r in @($data.r)) {
        $ev = Eval-HaRoom $r @($data.L) $state.sensors[[string]$r.a]
        if ($ev.air) { $list += [pscustomobject]@{ key = [string]$r.a; name = [string]$r.n; raw = $r; ev = $ev } }
    }
    if ($list.Count -eq 0) { return $null }
    $list = @($list | Sort-Object { $_.name })
    $chosen = $list[0]
    foreach ($x in $list) { if ($x.key -eq $wantRoom -or $x.name -ieq $wantRoom) { $chosen = $x; break } }
    $state.room = $chosen.key

    # Wetter
    $wx = $data.w
    $ot = $null; $cond = ''
    if ($wx) { $ot = Num $wx.t; $cond = [string]$wx.c }
    $condDe = @{ 'clear-night' = 'klar'; cloudy = 'bewölkt'; partlycloudy = 'teils bewölkt'; sunny = 'sonnig'; rainy = 'Regen'; pouring = 'Starkregen'; snowy = 'Schnee'; 'snowy-rainy' = 'Schneeregen'; fog = 'Nebel'; windy = 'windig'; 'windy-variant' = 'windig'; hail = 'Hagel'; lightning = 'Gewitter'; 'lightning-rainy' = 'Gewitter mit Regen'; exceptional = 'Unwetter' }
    $condEn = @{ 'clear-night' = 'clear'; cloudy = 'cloudy'; partlycloudy = 'partly cloudy'; sunny = 'sunny'; rainy = 'rain'; pouring = 'heavy rain'; snowy = 'snow'; 'snowy-rainy' = 'sleet'; fog = 'fog'; windy = 'windy'; 'windy-variant' = 'windy'; hail = 'hail'; lightning = 'thunderstorm'; 'lightning-rainy' = 'thunderstorm with rain'; exceptional = 'severe weather' }
    $iconCp = @{ 'clear-night' = 0x1F319; cloudy = 0x2601; partlycloudy = 0x26C5; sunny = 0x2600; rainy = 0x1F327; pouring = 0x1F327; snowy = 0x1F328; 'snowy-rainy' = 0x1F328; fog = 0x1F32B; windy = 0x1F4A8; 'windy-variant' = 0x1F4A8; hail = 0x1F328; lightning = 0x26C8; 'lightning-rainy' = 0x26C8; exceptional = 0x26A0 }
    $rainAt = ''
    if ($wx) { $rainAt = Get-HaRain ([string]$wx.id) }
    if ($cond -eq 'rainy' -or $cond -eq 'pouring') { $rainAt = '' }
    $outlook = @()
    if ($wx -and $script:fcCache) {
        $nowO = [DateTimeOffset]::UtcNow; $nO = 0
        foreach ($f in @($script:fcCache)) {
            try { $t = [DateTimeOffset]::Parse([string]$f.datetime, $inv) } catch { continue }
            if ($t -le $nowO) { continue }
            $nO++
            if ($nO % 2 -ne 0) { continue }
            $fi = ''; if ($iconCp.ContainsKey([string]$f.condition)) { $fi = [char]::ConvertFromUtf32([int]$iconCp[[string]$f.condition]) }
            $outlook += [pscustomobject]@{ h = $t.ToLocalTime().ToString('HH'); ic = $fi; tp = (Fmt (Num $f.temperature) 0) }
            if ($outlook.Count -ge 6) { break }
        }
    }
    $badOut = (@('pouring', 'lightning', 'lightning-rainy', 'hail', 'snowy-rainy', 'exceptional') -contains $cond)

    $rooms = @()
    foreach ($x in $list) {
        $ew = $x.ev.worst
        $nm = 'unbekannt'; $cl = '#7a8594'
        if ($null -ne $ew) { $nm = $lnames[$ew]; $cl = $colors[$ew] }
        $c2 = ''; if ($null -ne $x.ev.co2) { $c2 = [string][int][Math]::Round($x.ev.co2) }
        $rooms += [pscustomobject]@{ key = $x.key; name = $x.name; level = $nm; color = $cl; co2 = $c2 }
    }

    $ev = $chosen.ev
    $co2 = $ev.co2; $pm = $ev.pm; $tt = $ev.t; $hh = $ev.h; $worst = $ev.worst
    $wins = @($chosen.raw.e | Where-Object { $_.d -eq 'binary_sensor' -and $_.c -eq 'window' })
    $hasWindow = ($wins.Count -gt 0)
    $wst = 'unbekannt'
    if ($hasWindow) {
        if (@($wins | Where-Object { $_.s -eq 'on' }).Count -gt 0) { $wst = 'offen' }
        elseif (@($wins | Where-Object { $_.s -eq 'off' }).Count -eq $wins.Count) { $wst = 'zu' }
    }
    $needVent = (($null -ne $co2) -and ($co2 -ge 1000)) -or (($null -ne $hh) -and ($hh -gt 60)) -or (($null -ne $tt) -and ($tt -ge 25) -and ($null -ne $ot) -and ($ot -lt ($tt - 2)))
    if ($null -ne $ot -and $ot -lt 5) { $howT = (Lx 'Ganz öffnen, 5 Minuten lüften.' 'Open fully, ventilate for 5 minutes.'); $howM = 5 }
    elseif ($null -ne $ot -and $ot -lt 15) { $howT = (Lx 'Ganz öffnen, 10 Minuten lüften.' 'Open fully, ventilate for 10 minutes.'); $howM = 10 }
    else { $howT = (Lx 'Fenster öffnen, ca. 15 Minuten lüften.' 'Open the window, ventilate for about 15 minutes.'); $howM = 15 }
    $action = ''; $headline = ''; $detail = ''; $ventMin = 0
    if (($null -eq $co2) -and ($null -eq $pm)) {
        $action = 'unbekannt'; $headline = (Lx 'Keine Messwerte' 'No data'); $detail = (Lx 'Der Sensor meldet gerade nichts. Bitte später nochmal schauen.' 'The sensor is not reporting right now. Please check again later.')
    } elseif ($wst -eq 'offen') {
        if (($null -ne $co2) -and ($co2 -lt 700) -and -not (($null -ne $tt) -and ($tt -ge 25)) -and -not (($null -ne $hh) -and ($hh -gt 60))) {
            $action = 'schliessen'; $headline = (Lx 'Bitte Fenster schließen' 'Please close the window'); $detail = (Lx 'Die Luft ist wieder frisch.' 'The air is fresh again.')
            if ($null -ne $ot -and $ot -lt 15) { $detail += (Lx ' Sonst wird es kalt im Zimmer.' ' Otherwise the room gets cold.') }
        } else {
            $action = 'offen_lassen'; $headline = (Lx 'Fenster offen lassen' 'Keep the window open'); $detail = (Lx 'Die Luft wird gerade besser.' 'The air is getting better.'); $ventMin = $howM
        }
    } elseif ($needVent) {
        if ($badOut) {
            $cd = $condDe[$cond]; if (-not $cd) { $cd = 'Unwetter' }
            $ce = $condEn[$cond]; if (-not $ce) { $ce = 'severe weather' }
            $action = 'warten'; $headline = (Lx 'Jetzt noch nicht lüften' 'Do not ventilate yet'); $detail = (Lx ('Draußen ist ' + $cd + '. Später lüften.') ('Outside: ' + $ce + '. Ventilate later.'))
        } else {
            $action = 'oeffnen'
            if ($hasWindow) { $headline = (Lx 'Bitte Fenster öffnen' 'Please open the window') } else { $headline = (Lx 'Bitte lüften' 'Please ventilate') }
            $detail = $howT
            if ($rainAt) { $detail += (Lx (' Bald lüften: ab ' + $rainAt + ' Uhr kommt Regen.') (' Ventilate soon: rain from ' + $rainAt + '.')) }
            if (($null -ne $co2) -and ($co2 -ge 1500)) { $detail += (Lx ' Die Luft ist verbraucht.' ' The air is stale.') }
        }
    } elseif (($null -ne $pm) -and ($pm -ge 35)) {
        $action = 'zu_lassen'
        if ($hasWindow) { $headline = (Lx 'Fenster zu lassen' 'Keep the window closed') } else { $headline = (Lx 'Nicht dauerhaft lüften' 'Do not ventilate continuously') }
        $detail = (Lx 'Viel Feinstaub im Raum. Nicht dauerhaft lüften.' 'High fine dust in the room. Do not ventilate continuously.')
    } else {
        $action = 'zu_lassen'; $headline = (Lx 'Alles in Ordnung' 'All good')
        if ($hasWindow) { $detail = (Lx 'Das Fenster kann zu bleiben.' 'The window can stay closed.') } else { $detail = (Lx 'Die Luft ist in Ordnung.' 'The air is fine.') }
    }
    $values = @(
        [pscustomobject]@{ key = 'CO₂'; value = (Fmt $co2 0); unit = 'ppm'; level = $ev.lv[0] },
        [pscustomobject]@{ key = 'Feinstaub'; value = (Fmt $pm 0); unit = 'µg'; level = $ev.lv[1] },
        [pscustomobject]@{ key = 'Temperatur'; value = (Fmt $tt 1); unit = '°C'; level = $ev.lv[2] },
        [pscustomobject]@{ key = 'Luftfeuchte'; value = (Fmt $hh 0); unit = '%'; level = $ev.lv[3] }
    )

    # Wetter-Anzeige
    $outside = $null
    if ($null -ne $ot) {
        $ws = Num $wx.ws
        $wu = [string]$wx.wu
        if ($null -ne $ws) { if ($wu -eq 'm/s') { $ws = $ws * 3.6 } elseif ($wu -eq 'mph') { $ws = $ws * 1.609344 } elseif ($wu -eq 'kn') { $ws = $ws * 1.852 } }
        $dirs = $(if ($en) { @('N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW') } else { @('N', 'NO', 'O', 'SO', 'S', 'SW', 'W', 'NW') })
        $wbN = Num $wx.wb
        $windDir = ''
        if ($null -ne $wbN) { $windDir = $dirs[[int]([Math]::Round($wbN / 45.0)) % 8] } elseif ($wx.wb) { $windDir = [string]$wx.wb }
        $oh = Num $wx.h
        $tip = (Lx 'Gute Zeit zum Lüften.' 'Good time to ventilate.')
        if ($cond -eq 'rainy' -or $cond -eq 'pouring') { $tip = (Lx 'Es regnet: Fenster nur kurz öffnen (Stoßlüften 3 Min) oder in einer Regenpause lüften.' 'It is raining: open the window only briefly (3 min burst) or wait for a break in the rain.') }
        elseif ($rainAt) { $tip = (Lx ('Gute Zeit zum Lüften, ab ' + $rainAt + ' Uhr kommt Regen.') ('Good time to ventilate, rain from ' + $rainAt + '.')) }
        elseif ($ot -lt 5) { $tip = (Lx 'Es ist kalt: lieber kurz und ganz öffnen (Stoßlüften 5 Min), das spart Heizenergie.' 'It is cold: better open fully for a short time (5 min burst), it saves heating energy.') }
        elseif ($ot -ge 25) { $tip = (Lx 'Es ist warm draußen: morgens oder abends lüften, tagsüber Fenster zu lassen.' 'It is warm outside: ventilate in the morning or evening, keep windows closed during the day.') }
        elseif (($null -ne $oh) -and ($oh -gt 90)) { $tip = (Lx 'Draußen ist es feucht: kurz lüften, nicht dauerhaft kippen.' 'It is humid outside: ventilate briefly, do not leave the window tilted.') }
        $cn = $(if ($en) { $condEn[$cond] } else { $condDe[$cond] }); if (-not $cn) { $cn = $cond }
        $ic = ''; if ($iconCp.ContainsKey($cond)) { $ic = [char]::ConvertFromUtf32([int]$iconCp[$cond]) }
        $outside = [pscustomobject]@{ temp = (Fmt $ot 0); cond = [string]$cn; icon = $ic; wind = (Fmt $ws 0); windDir = $windDir; hum = (Fmt $oh 0); cloud = (Fmt (Num $wx.cl) 0); press = (Fmt (Num $wx.p) 0); tip = $tip; out = $outlook }
    }

    # Geräte des Raums
    $script:haDevs = @{}
    $lab = @($data.L)
    $useLab = ($lab.Count -gt 0)
    $devices = @()
    $grp = @{ light = @('Licht', 'switch'); switch = @('Strom', 'switch'); climate = @('Heizung', 'climate'); cover = @('Rollo', 'cover'); button = @('Strom', 'button') }
    foreach ($x in @($chosen.raw.e)) {
        $dom = [string]$x.d
        if (-not $grp.ContainsKey($dom)) { continue }
        if ($dom -eq 'button' -and -not $useLab) { continue }
        if ($useLab -and ($lab -notcontains [string]$x.i)) { continue }
        if ($x.s -eq 'unavailable' -or $x.s -eq 'unknown') { continue }
        $nm = [string]$x.n
        if ($nm.StartsWith($chosen.name + ' ', [StringComparison]::OrdinalIgnoreCase) -and $nm.Length -gt ($chosen.name.Length + 1)) { $nm = $nm.Substring($chosen.name.Length + 1) }
        $nm = ($nm -replace '\s+-\s+(Schalter|Switch)$', '')
        $wds = @($nm -split '\s+')
        if ($wds.Count -ge 3) { $pre = (($wds[0..($wds.Count - 2)] -join '').ToLower()); if ($pre.EndsWith($wds[$wds.Count - 1].ToLower())) { $nm = ($wds[0..($wds.Count - 2)] -join ' ') } }
        if ($dom -eq 'climate' -and ($nm -ieq $chosen.name)) { $nm = (Lx 'Heizung' 'Heating') }
        $o = [pscustomobject]@{ group = $grp[$dom][0]; entity = [string]$x.i; name = $nm; type = $grp[$dom][1]; state = [string]$x.s; detail = ''; target = $null; value = '' }
        if ($dom -eq 'climate') {
            $tg = Num $x.t; $cu = Num $x.cu
            if ($null -eq $tg) { $tg = 21 }
            $o.target = $tg
            $d1 = ''; if ($null -ne $cu) { $d1 = (Lx 'Ist ' 'Now ') + (Fmt $cu 1) + ' °C' }
            if ($x.ha -eq 'heating') { $d1 += (Lx ' · heizt' ' · heating') } elseif ($x.ha -eq 'idle') { $d1 += (Lx ' · aus' ' · off') }
            $o.detail = $d1
        }
        if ($dom -eq 'cover') {
            $pp = Num $x.p
            if ($x.s -eq 'open') { $o.detail = (Lx 'offen' 'open') } elseif ($x.s -eq 'closed') { $o.detail = (Lx 'zu' 'closed') } elseif ($x.s -eq 'opening') { $o.detail = (Lx 'öffnet' 'opening') } elseif ($x.s -eq 'closing') { $o.detail = (Lx 'schließt' 'closing') } elseif ($null -ne $pp) { $o.detail = [string][int][Math]::Round($pp) + ' %' } else { $o.detail = [string]$x.s }
        }
        $script:haDevs[[string]$x.i] = $true
        $devices += $o
    }

    $wk = 'unbekannt'; $wc = '#7a8594'
    if ($null -ne $worst) { $wk = $lnames[$worst]; $wc = $colors[$worst] }
    return [pscustomobject]@{
        room = [pscustomobject]@{ key = $chosen.key; name = $chosen.name }; rooms = $rooms
        level = $wk; color = $wc; headline = $headline; detail = $detail; action = $action
        window = $wst; hasWindow = $hasWindow; ventMin = $ventMin; values = $values; colors = $colors
        mold = $false; warn = $ev.warn; nsrc = $ev.nsrc; outside = $outside; devices = $devices; updated = (Get-Date).ToString('HH:mm:ss')
    }
}
function Get-HaData([string]$wantRoom) {
    $wid = [string]$cfg.weatherEntity
    if ($wid -match '^weather\.[a-z0-9_]+$') { $wl = "{%- set wid = '" + $wid + "' -%}" }
    else { $wl = "{%- set wid = (wl | first) if (wl | length) > 0 else none -%}`n{%- set wid = wid.entity_id if wid else none -%}" }
    $tpl = $script:HaTpl.Replace('__WIDLINE__', $wl)
    $body = (@{ template = $tpl } | ConvertTo-Json -Compress)
    try { $txt = Invoke-Ha $script:haUrl $script:haTok 'POST' '/api/template' $body }
    catch {
        $body = (@{ template = $tpl.Replace("label_entities('airguard')", '[]') } | ConvertTo-Json -Compress)
        $txt = Invoke-Ha $script:haUrl $script:haTok 'POST' '/api/template' $body
    }
    $data = $txt | ConvertFrom-Json
    return (Build-HaData $data $wantRoom)
}
function Send-HaCommand($body) {
    $ent = [string]$body.entity; $act = [string]$body.action
    if (-not $script:haDevs.ContainsKey($ent)) { Write-Log ('Schalten abgelehnt (nicht in der Liste): ' + $ent); return }
    $dom = $ent.Split('.')[0]
    $svc = ''; $payload = @{ entity_id = $ent }
    switch ($act) {
        'toggle' { if ($dom -eq 'light' -or $dom -eq 'switch') { $svc = $dom + '/toggle' } }
        'temp' { if ($dom -eq 'climate') { $tv = Num $body.value; if ($null -ne $tv) { $payload.temperature = [Math]::Max(5.0, [Math]::Min(30.0, $tv)); $svc = 'climate/set_temperature' } } }
        'open' { if ($dom -eq 'cover') { $svc = 'cover/open_cover' } }
        'close' { if ($dom -eq 'cover') { $svc = 'cover/close_cover' } }
        'stop' { if ($dom -eq 'cover') { $svc = 'cover/stop_cover' } }
        'press' { if ($dom -eq 'button') { $svc = 'button/press' } }
    }
    if (-not $svc) { Write-Log ('Schalten: unbekannte Aktion ' + $act + ' für ' + $ent); return }
    [void](Invoke-Ha $script:haUrl $script:haTok 'POST' ('/api/services/' + $svc) ($payload | ConvertTo-Json -Compress))
}

function Show-SensorDialog {
    if (-not $script:haData) { return }
    $room = @($script:haData.r | Where-Object { [string]$_.a -eq [string]$state.room })[0]
    if (-not $room) { return }
    $x = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Luftwächter" Width="520" SizeToContent="Height" WindowStartupLocation="CenterScreen" Topmost="True" ResizeMode="NoResize" Background="#FF1B222D" FontFamily="Segoe UI">
  <StackPanel Margin="22">
    <TextBlock x:Name="STitle" Foreground="White" FontSize="21" FontWeight="Bold" TextWrapping="Wrap"/>
    <TextBlock x:Name="SIntro" Foreground="#FFB3BECD" FontSize="13" TextWrapping="Wrap" Margin="0,6,0,14"/>
    <TextBlock x:Name="SL0" Foreground="White" FontSize="13" FontWeight="SemiBold"/><ComboBox x:Name="SC0" Margin="0,4,0,10" Padding="6,4" FontSize="13"/>
    <TextBlock x:Name="SL1" Foreground="White" FontSize="13" FontWeight="SemiBold"/><ComboBox x:Name="SC1" Margin="0,4,0,10" Padding="6,4" FontSize="13"/>
    <TextBlock x:Name="SL2" Foreground="White" FontSize="13" FontWeight="SemiBold"/><ComboBox x:Name="SC2" Margin="0,4,0,10" Padding="6,4" FontSize="13"/>
    <TextBlock x:Name="SL3" Foreground="White" FontSize="13" FontWeight="SemiBold"/><ComboBox x:Name="SC3" Margin="0,4,0,14" Padding="6,4" FontSize="13"/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right"><Button x:Name="SNo" Padding="16,6" Margin="0,0,8,0"/><Button x:Name="SYes" Padding="16,6" IsDefault="True"/></StackPanel>
  </StackPanel>
</Window>
"@
    $d = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$x)))
    $script:sdDlg = $d
    $d.FindName('STitle').Text = (T 'sens_title' ([string]$room.n)); $d.FindName('SIntro').Text = (T 'sens_intro')
    $d.FindName('SNo').Content = (T 'ha_cancel'); $d.FindName('SYes').Content = (T 'sens_save')
    $defs = @(@('co2', 'carbon_dioxide', 'sens_co2', 0), @('pm', 'pm25', 'sens_pm', 0), @('t', 'temperature', 'sens_t', 1), @('h', 'humidity', 'sens_h', 0))
    $cur = $state.sensors[[string]$state.room]
    $nowE = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $script:sdBoxes = @()
    for ($k = 0; $k -lt 4; $k++) {
        $df = $defs[$k]
        $d.FindName('SL' + $k).Text = (T $df[2])
        $cb = $d.FindName('SC' + $k)
        $cands = @(Get-Cands @($room.e) $df[1])
        $a = New-Object System.Windows.Controls.ComboBoxItem
        $a.Tag = ''
        if ($cands.Count -eq 0) { $a.Content = (T 'sens_none') } elseif ($cands.Count -eq 1) { $a.Content = (Lx 'Automatisch' 'Automatic') } else { $a.Content = (Lx ('Automatisch (Mittelwert aus ' + $cands.Count + ')') ('Automatic (average of ' + $cands.Count + ')')) }
        [void]$cb.Items.Add($a)
        $cb.SelectedItem = $a
        foreach ($c in $cands) {
            $age = ''
            if ([double]$c.lr -gt 0) { $m = [int][Math]::Max(0, ($nowE - [double]$c.lr) / 60); if ($m -ge 5) { $age = ' · ' + (Lx ('vor ' + $m + ' min') ($m.ToString() + ' min ago')) } }
            $it = New-Object System.Windows.Controls.ComboBoxItem
            $it.Content = ([string]$c.n + ' · ' + (Fmt (Num $c.s) $df[3]) + $age); $it.Tag = [string]$c.i
            [void]$cb.Items.Add($it)
            if ($cur -and [string]$cur[$df[0]] -eq [string]$c.i) { $cb.SelectedItem = $it }
        }
        $cb.Tag = $df[0]
        $script:sdBoxes += $cb
    }
    $d.FindName('SNo').Add_Click({ $script:sdDlg.DialogResult = $false })
    $d.FindName('SYes').Add_Click({
        $h = @{}
        foreach ($b in $script:sdBoxes) { $sel = $b.SelectedItem; if ($sel -and [string]$sel.Tag) { $h[[string]$b.Tag] = [string]$sel.Tag } }
        if ($h.Count -gt 0) { $state.sensors[[string]$state.room] = $h } else { $state.sensors.Remove([string]$state.room) }
        Save-State
        $script:sdDlg.DialogResult = $true
    })
    $res = $d.ShowDialog()
    if ($res) { $script:devSig = ''; Update-Widget }
}
function Show-HaDialog {
    $x = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Luftwächter" Width="480" SizeToContent="Height" WindowStartupLocation="CenterScreen" Topmost="True" ResizeMode="NoResize" Background="#FF1B222D" FontFamily="Segoe UI">
  <StackPanel Margin="22">
    <TextBlock x:Name="HTitle" Foreground="White" FontSize="21" FontWeight="Bold" TextWrapping="Wrap"/>
    <TextBlock x:Name="HIntro" Foreground="#FFB3BECD" FontSize="13" TextWrapping="Wrap" Margin="0,6,0,14"/>
    <TextBlock x:Name="HUrlL" Foreground="White" FontSize="13" FontWeight="SemiBold"/>
    <DockPanel Margin="0,4,0,12"><Button x:Name="HFind" DockPanel.Dock="Right" Padding="12,4" Margin="8,0,0,0"/><TextBox x:Name="HUrl" Padding="6,4" FontSize="13"/></DockPanel>
    <TextBlock x:Name="HTokL" Foreground="White" FontSize="13" FontWeight="SemiBold"/>
    <PasswordBox x:Name="HTok" Padding="6,4" FontSize="13" Margin="0,4,0,6"/>
    <TextBlock x:Name="HOpen" Foreground="#FF7CB7FF" FontSize="12" Cursor="Hand" Margin="0,0,0,10"/>
    <TextBlock x:Name="HMsg" Foreground="#FFFFD27A" FontSize="12.5" TextWrapping="Wrap" Margin="0,0,0,10"/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right"><Button x:Name="HNo" Padding="16,6" Margin="0,0,8,0"/><Button x:Name="HYes" Padding="16,6" IsDefault="True"/></StackPanel>
  </StackPanel>
</Window>
"@
    $d = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$x)))
    $script:hdDlg = $d
    $script:hdUrl = $d.FindName('HUrl'); $script:hdTok = $d.FindName('HTok'); $script:hdMsg = $d.FindName('HMsg')
    $d.FindName('HTitle').Text = (T 'ha_title'); $d.FindName('HIntro').Text = (T 'ha_intro')
    $d.FindName('HUrlL').Text = (T 'ha_url'); $d.FindName('HTokL').Text = (T 'ha_tok')
    $d.FindName('HOpen').Text = (T 'ha_open'); $d.FindName('HFind').Content = (T 'ha_find')
    $d.FindName('HNo').Content = (T 'ha_cancel'); $d.FindName('HYes').Content = (T 'ha_go')
    $script:hdUrl.Text = $(if ($script:haUrl) { $script:haUrl } else { 'http://homeassistant.local:8123' })
    $d.FindName('HOpen').Add_MouseLeftButtonDown({ try { $u0 = Normalize-HaUrl $script:hdUrl.Text; if ($u0) { Start-Process ($u0 + '/profile/security') } } catch {} })
    $d.FindName('HFind').Add_Click({
        $script:hdMsg.Text = (T 'ha_searching'); $script:hdDlg.Dispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::Render)
        $f = @(Find-Ha)
        if ($f.Count -gt 0) { $script:hdUrl.Text = $f[0]; $script:hdMsg.Text = (T 'ha_found' $f[0]) } else { $script:hdMsg.Text = (T 'ha_nofind') }
    })
    $d.FindName('HNo').Add_Click({ $script:hdDlg.DialogResult = $false })
    $d.FindName('HYes').Add_Click({
        $u1 = Normalize-HaUrl $script:hdUrl.Text; $t1 = ([string]$script:hdTok.Password).Trim()
        if (-not $u1 -or -not $t1) { $script:hdMsg.Text = (T 'ha_empty'); return }
        $script:hdMsg.Text = (T 'ha_testing'); $script:hdDlg.Dispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::Render)
        $r1 = Test-Ha $u1 $t1
        if ($r1 -eq 'ok') {
            Save-HaUrl $cfgFile $u1; Save-HaToken $t1
            $script:haUrl = $u1; $script:haTok = $t1; $script:haMode = $true; $script:canSwitch = $true
            $script:devSig = ''; $script:last = $null; $script:fails = 0
            $script:hdDlg.DialogResult = $true
        } elseif ($r1 -eq 'auth') { $script:hdMsg.Text = (T 'ha_auth') } else { $script:hdMsg.Text = (T 'ha_net') }
    })
    $f0 = @(); $r = $d.ShowDialog()
    if ($r -eq $true) { Update-Widget }
}

function Get-DemoData([string]$wantRoom) {
    # Simulierte Räume für Ausprobieren ohne Home Assistant: CO2 steigt, Fenster auf, fällt wieder (Zyklus 14 Minuten)
    $dn = @(@('living', (Lx 'Wohnzimmer' 'Living room'), 0), @('office', (Lx 'Büro' 'Office'), 4), @('bed', (Lx 'Schlafzimmer' 'Bedroom'), 8))
    $mins = ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() / 60.0)
    $green = '#2e9e5b'; $amber = '#e8a317'; $red = '#d9472b'
    $rooms = @(); $cur = $null
    foreach ($r in $dn) {
        $ph = (($mins + $r[2]) % 14.0)
        if ($ph -lt 9) { $co2 = 620 + 95 * $ph } else { $co2 = 1475 - 150 * ($ph - 9) }
        $co2 = [int][Math]::Round($co2)
        $lv = $(if ($co2 -lt 1000) { 'gut' } elseif ($co2 -lt 1400) { 'mittel' } else { 'schlecht' })
        $col = $(if ($lv -eq 'gut') { $green } elseif ($lv -eq 'mittel') { $amber } else { $red })
        $rooms += @{ key = $r[0]; name = $r[1]; level = $lv; color = $col; co2 = [string]$co2; ph = $ph }
    }
    foreach ($r in $rooms) { if ($r.key -eq $wantRoom) { $cur = $r } }
    if ($null -eq $cur) { $cur = $rooms[0] }
    $co2 = [int]$cur.co2; $ph = [double]$cur.ph
    if ($ph -ge 9) { $act = 'offen_lassen'; $win = 'offen'; $hl = (Lx 'Fenster offen lassen' 'Keep the window open'); $dt = (Lx 'Frische Luft kommt herein.' 'Fresh air is coming in.') }
    elseif ($co2 -ge 1000) { $act = 'oeffnen'; $win = 'zu'; $hl = (Lx 'Bitte Fenster öffnen' 'Please open the window'); $dt = (Lx 'Weit öffnen, etwa 5 Minuten lüften.' 'Open fully and ventilate for about 5 minutes.') }
    else { $act = 'zu_lassen'; $win = 'zu'; $hl = (Lx 'Die Luft ist gut' 'The air is good'); $dt = (Lx 'Gerade ist nichts zu tun.' 'Nothing to do right now.') }
    $lvl = [string]$cur.level
    $rr = @(); foreach ($r in $rooms) { $rr += @{ key = $r.key; name = $r.name; level = $r.level; color = $r.color; co2 = $r.co2 } }
    $cl = $(if ($co2 -lt 1000) { 0 } elseif ($co2 -lt 1400) { 1 } else { 2 })
    $t = 21.0 + 0.4 * [Math]::Sin($mins / 5.0)
    return [pscustomobject]@{
        room = [pscustomobject]@{ key = $cur.key; name = ($cur.name + ' · ' + (T 'demo_tag')) }
        rooms = @($rr | ForEach-Object { [pscustomobject]$_ })
        level = $lvl; color = [string]$cur.color; headline = $hl; detail = $dt; action = $act; window = $win; hasWindow = $false; ventMin = 5
        values = @(
            [pscustomobject]@{ key = 'CO₂'; value = [string]$co2; unit = 'ppm'; level = $cl },
            [pscustomobject]@{ key = (Lx 'Feinstaub' 'Fine dust'); value = '7'; unit = 'µg'; level = 0 },
            [pscustomobject]@{ key = (Lx 'Temperatur' 'Temperature'); value = (Fmt $t 1); unit = '°C'; level = 0 },
            [pscustomobject]@{ key = (Lx 'Luftfeuchte' 'Humidity'); value = '46'; unit = '%'; level = 0 })
        colors = @($green, $amber, $red); mold = $false
        outside = [pscustomobject]@{ temp = '7'; cond = 'cloudy'; icon = [string][char]0x2601; wind = '12'; windDir = 'SW'; hum = '80'; cloud = '90'; press = '1012'; tip = (Lx 'Guter Zeitpunkt zum Lüften.' 'Good time to ventilate.') }
        devices = @()
        updated = (Get-Date).ToString('HH:mm:ss')
    }
}
function Blend-Hex([string]$hex, [double]$a) {
    $h = $hex.Substring($hex.Length - 6)
    $base = @(27, 34, 45)
    $o = '#FF'
    for ($i = 0; $i -lt 3; $i++) {
        $c = [Convert]::ToInt32($h.Substring($i * 2, 2), 16)
        $o += ([int][Math]::Round($base[$i] + $a * ($c - $base[$i]))).ToString('X2')
    }
    return $o
}
function Apply-Theme {
    $night = $false
    $hh = (Get-Date).Hour
    switch ([string]$state.theme) { 'night' { $night = $true } 'day' { $night = $false } default { $night = ($hh -ge 22 -or $hh -lt 7) } }
    $bg = $(if ($night) { '#FF0E1218' } else { '#FF1B222D' })
    $script:themeBg = $bg
    foreach ($b in @($ui.Card, $ui.Drawer, $ui.Pill)) { if ($b) { $b.Background = Brush $bg } }
    $script:nightOn = $night
}
function Update-Widget {
    if (Clamp-ToScreen) { Write-Log 'Fenster zurück auf den Bildschirm geholt'; Save-State }
    if ($state.demo) { try { $d = Get-DemoData ([string]$state.room); $script:fails = 0; $script:last = $d; Show-Data $d } catch { Write-Log ('Demo: ' + $_.Exception.Message) }; return }
    if (-not $script:haMode -and $url -notmatch '^https?://') { Show-Setup; return }
    try {
        if ($script:haMode) {
            $d = Get-HaData ([string]$state.room)
            if ($null -eq $d) { Show-Setup; return }
        } else {
            $u = $url
            if ($u.Contains('?')) { $u += '&' } else { $u += '?' }
            $u += 'room=' + [Uri]::EscapeDataString([string]$state.room) + '&lang=' + [string]$state.lang
            $d = Get-Json $u
        }
        $script:fails = 0
        $script:last = $d
        $script:lastOkAt = Get-Date
        Show-Data $d
    } catch {
        Write-Log ('Aktualisieren: ' + $_.Exception.Message + ' @' + $_.InvocationInfo.ScriptLineNumber)
        $script:lastErr = [string]$_.Exception.Message
        $script:fails++
        if ($script:fails -ge 3) {
            $g = Brush $grey
            $ui.Card.BorderBrush = $g
            $ui.Level.Text = (T 'offline'); $ui.PillText.Text = (T 'offline'); $ui.PillDot.Foreground = $g; $ui.Level.Foreground = $g
            $ui.Face.Text = [char]::ConvertFromUtf32(0x1F50C)
            Set-Ring 0.06 $g
            $ui.Panel.Background = Brush '#FF494E57'
            $ui.Headline.Text = (T 'no_conn'); $ui.Headline.ToolTip = (T 'offline_hint'); $ui.Detail.ToolTip = (T 'offline_hint')
            $script:pulse = $false
            if ($script:tray -and $state.tray) { try { $script:tray.Icon = (Get-TrayIcon '#7A8594').icon; $script:tray.Text = (T 'offline_tip') } catch {} }
            if ($script:last) {
                if ($script:lastOkAt) { $ui.Detail.Text = (T 'stale2' $script:lastOkAt.ToString('HH:mm') ([int][Math]::Floor(((Get-Date) - $script:lastOkAt).TotalMinutes))) } else { $ui.Detail.Text = (T 'stale') }
                $ui.Time.Text = (T 'asof') + [string]$script:last.updated
            }
            else { $ui.Detail.Text = (T 'no_air') }
        }
    }
}

# ---------- Fenster-Position ----------
$wa = [System.Windows.SystemParameters]::WorkArea
$win.WindowStartupLocation = 'Manual'
$vl0 = [System.Windows.SystemParameters]::VirtualScreenLeft; $vt0 = [System.Windows.SystemParameters]::VirtualScreenTop
$vr0 = $vl0 + [System.Windows.SystemParameters]::VirtualScreenWidth; $vb0 = $vt0 + [System.Windows.SystemParameters]::VirtualScreenHeight
if ($null -ne $state.left -and $null -ne $state.top -and $state.left -ge ($vl0 - 50) -and $state.left -le ($vr0 - 120) -and $state.top -ge ($vt0 - 10) -and $state.top -le ($vb0 - 120)) {
    $win.Left = [double]$state.left; $win.Top = [double]$state.top
} else { $win.Left = $wa.Right - 480; $win.Top = $wa.Top + 20 }
$win.Topmost = [bool]$state.topmost

# ---------- Bedienung ----------
$ui.Pill.Add_MouseLeftButtonDown({ param($s, $e)
    if ($e.ClickCount -eq 2) {
        $e.Handled = $true
        $back = 'M'; if ($script:prevSize -and $script:prevSize -ne 'P') { $back = $script:prevSize }
        $state.size = $back; Apply-View; Save-State
    }
})
$win.Add_MouseLeftButtonDown({ param($s, $e) if ($e.ClickCount -eq 2) { Update-Widget } else { if (-not $state.locked) { try { $win.DragMove(); Snap-Edges; Save-State } catch {} } } })
function Snap-Edges {
    # rastet an den Rändern des Bildschirms ein, auf dem das Widget steht (Abstand unter 18 px)
    $wa0 = [System.Windows.SystemParameters]::WorkArea
    try {
        $src = [System.Windows.PresentationSource]::FromVisual($win)
        $sx = 1.0; $sy = 1.0
        if ($src -and $src.CompositionTarget) { $sx = $src.CompositionTarget.TransformToDevice.M11; $sy = $src.CompositionTarget.TransformToDevice.M22 }
        $cx = [int](($win.Left + $win.ActualWidth / 2) * $sx); $cy = [int](($win.Top + 20) * $sy)
        $wa = [System.Windows.Forms.Screen]::FromPoint((New-Object System.Drawing.Point($cx, $cy))).WorkingArea
        $wa0 = New-Object System.Windows.Rect(($wa.Left / $sx), ($wa.Top / $sy), ($wa.Width / $sx), ($wa.Height / $sy))
    } catch {}
    $w = $win.ActualWidth; $h = $win.ActualHeight; $m = 18
    if ($win.Left -gt ($wa0.Right + 5) -or ($win.Left + $w) -lt ($wa0.Left - 5) -or $win.Top -gt ($wa0.Bottom + 5)) { return }
    if ([Math]::Abs($win.Left - $wa0.Left) -lt $m) { $win.Left = $wa0.Left }
    elseif ([Math]::Abs(($win.Left + $w) - $wa0.Right) -lt $m) { $win.Left = $wa0.Right - $w }
    if ([Math]::Abs($win.Top - $wa0.Top) -lt $m) { $win.Top = $wa0.Top }
    elseif ([Math]::Abs(($win.Top + $h) - $wa0.Bottom) -lt $m) { $win.Top = $wa0.Bottom - $h }
}
$ui.RoomStrip.Add_MouseWheel({ param($s, $e) if (-not ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) { $e.Handled = $true; if ($e.Delta -gt 0) { Switch-Room -1 } else { Switch-Room 1 } } })
function Set-Glow($el, [bool]$on) {
    if ($null -eq $el) { return }
    if ($on) {
        $fx = New-Object Windows.Media.Effects.DropShadowEffect
        $fx.Color = [Windows.Media.Colors]::White; $fx.BlurRadius = 10; $fx.ShadowDepth = 0; $fx.Opacity = 0.45
        $el.Effect = $fx
    } else { $el.Effect = $null }
}
function Add-Hover($el) {
    if ($null -eq $el) { return }
    $el.Add_MouseEnter({ param($s1, $e1) Set-Glow $s1 $true })
    $el.Add_MouseLeave({ param($s1, $e1) Set-Glow $s1 $false })
}
function Fade-In($el, [int]$ms = 170) {
    try {
        $an = New-Object Windows.Media.Animation.DoubleAnimation(0.5, $(if ($el -eq $win) { [double]$state.opacity } else { 1.0 }), [TimeSpan]::FromMilliseconds($ms))
        $an.FillBehavior = [Windows.Media.Animation.FillBehavior]::Stop
        $el.BeginAnimation([Windows.UIElement]::OpacityProperty, $an)
    } catch { Write-Log ('Fade: ' + $_.Exception.Message) }
}
foreach ($hn in 'BtnHelp', 'BtnLang', 'BtnMode', 'BtnUpd', 'TourOk', 'WMore', 'WLess', 'C1', 'C2', 'C3', 'C4', 'SzBS', 'SzBM', 'SzBL', 'SzBC', 'SzBP', 'DrawerClose', 'HelpClose', 'Tab') { Add-Hover $ui.$hn }
function Switch-Room([int]$dir) {
    $keys = @($script:rooms | ForEach-Object { [string]$_.key })
    if ($keys.Count -lt 2) { return }
    $i = [Array]::IndexOf($keys, [string]$state.room); if ($i -lt 0) { $i = 0 }
    $state.room = $keys[(($i + $dir) % $keys.Count + $keys.Count) % $keys.Count]
    $script:ventEnd = $null; $script:prevOpen = $null; $script:sumText = ''; $script:lastAction = $null; $script:devSig = ''; $script:openSince = $null
    Save-State; Update-Widget
}
$win.Add_KeyDown({ param($s, $e)
    switch ($e.Key) {
        'Left' { Switch-Room -1; $e.Handled = $true }
        'Right' { Switch-Room 1; $e.Handled = $true }
        'D' { $mods = [System.Windows.Input.Keyboard]::Modifiers; if (($mods -band [System.Windows.Input.ModifierKeys]::Control) -and ($mods -band [System.Windows.Input.ModifierKeys]::Shift)) { Copy-Diagnostics } else { Toggle-Mode }; $e.Handled = $true }
        'S' { $mods = [System.Windows.Input.Keyboard]::Modifiers; if (($mods -band [System.Windows.Input.ModifierKeys]::Control) -and ($mods -band [System.Windows.Input.ModifierKeys]::Shift)) { [void](Save-WidgetPicture ''); $e.Handled = $true } }
        'O' { Step-Opacity; $e.Handled = $true }
        'P' { $state.topmost = -not [bool]$state.topmost; $state.topmostSet = $true; $win.Topmost = [bool]$state.topmost; $miTop.IsChecked = [bool]$state.topmost; Save-State; $e.Handled = $true }
        'L' { $state.lang = $(if ($state.lang -eq 'de') { 'en' } else { 'de' }); Apply-Lang; Save-State; Update-Widget; $e.Handled = $true }
        'U' { Invoke-UpdateFlow $true; $e.Handled = $true }
        'Home' { Select-RoomIndex 0; $e.Handled = $true }
        'End' { $nr = @($script:rooms).Count; if ($nr -gt 0) { Select-RoomIndex ($nr - 1) }; $e.Handled = $true }
        'G' { if ($script:haMode -and $script:haUrl) { try { Start-Process $script:haUrl } catch {} ; $e.Handled = $true } }
        'F5' { Update-Widget; $e.Handled = $true }
        'F1' { $script:helpOpen = -not $script:helpOpen; if ($script:helpOpen) { Build-Help }; Apply-View; $e.Handled = $true }
        'Q' { Toggle-Snooze; $e.Handled = $true }
        'T' { $state.theme = $(switch ([string]$state.theme) { 'auto' { 'day' } 'day' { 'night' } default { 'auto' } }); Apply-Theme; Save-State; Apply-Lang; $e.Handled = $true }
        'C' { $mods = [System.Windows.Input.Keyboard]::Modifiers; if ($mods -band [System.Windows.Input.ModifierKeys]::Control) { if ($mods -band [System.Windows.Input.ModifierKeys]::Shift) { Copy-AllRooms } else { Copy-Readings }; $e.Handled = $true } }
        { $_ -match '^(D|NumPad)[1-9]$' } { Select-RoomIndex ([int]([string]$_)[-1].ToString() - 1); $e.Handled = $true }
        'Escape' { $script:helpOpen = $false; $state.drawerOpen = $false; Apply-View; $e.Handled = $true }
        { $_ -eq 'OemPlus' -or $_ -eq 'Add' } { Step-Size 1; $e.Handled = $true }
        { $_ -eq 'OemMinus' -or $_ -eq 'Subtract' } { Step-Size -1; $e.Handled = $true }
    }
})

$ui.Spark.Background = [Windows.Media.Brushes]::Transparent
$ui.Spark.Add_MouseMove({ param($s, $e)
    $aw = [Math]::Max($s.ActualWidth, 1.0); $w2 = 205.0
    $r = Get-SparkPoint ($e.GetPosition($s).X * ($w2 / $aw))
    if (-not $r) { return }
    $ui.SparkR.Text = [string]$r.text
    Clear-SparkMark
    $ln = New-Object Windows.Shapes.Line
    $ln.X1 = $r.px; $ln.X2 = $r.px; $ln.Y1 = 0; $ln.Y2 = 62; $ln.Stroke = Brush '#FFE6EBF2'; $ln.StrokeThickness = 1; $ln.Tag = 'mark'; $ln.IsHitTestVisible = $false
    [void]$ui.Spark.Children.Add($ln)
})
$ui.Spark.Add_MouseLeave({ Clear-SparkMark; $ui.SparkR.Text = (T 'now') })

foreach ($k in 'S', 'M', 'L', 'C', 'P') {
    $ui.('SzB' + $k).Tag = $k
    $ui.('SzB' + $k).Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; if ([string]$s.Tag -eq 'P' -and $state.size -ne 'P') { $script:prevSize = $state.size }; $state.size = [string]$s.Tag; Apply-View; Save-State })
}
$ui.WLine.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; $state.weatherOpen = $true; Apply-View; Save-State })
$ui.WLess.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; $state.weatherOpen = $false; Apply-View; Save-State })
$ui.Panel.Add_MouseLeftButtonDown({
    param($s, $e)
    $e.Handled = $true
    if ($script:ventEnd) { $script:ventEnd = $null; $script:ventDone = $false }
    elseif ($script:last -and ([string]$script:last.action -eq 'oeffnen')) {
        $len = 10
        if ($script:last.ventMin -and [int]$script:last.ventMin -gt 0) { $len = [int]$script:last.ventMin }
        $script:ventLen = $len; $script:ventEnd = (Get-Date).AddMinutes($len); $script:ventDone = $false; $script:ventStartCo2 = $script:curCo2
    }
    if ($script:last) { Show-Data $script:last }
})
for ($k = 0; $k -lt 4; $k++) {
    $cb = $ui.('C' + ($k + 1)); $cb.Tag = $k
    $cb.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; $state.metric = [int]$s.Tag; if ($script:last) { Show-Data $script:last }; Save-State })
    $cb.Add_MouseRightButtonUp({ param($s, $e) $e.Handled = $true; Show-HelpSection (19 + [int]$s.Tag) })
}
$ui.SparkBox.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; if ($state.sparkHours -eq 3) { $state.sparkHours = 24 } elseif ($state.sparkHours -eq 24) { $state.sparkHours = 168 } else { $state.sparkHours = 3 }; if ($script:last) { Show-Data $script:last }; Save-State })
$ui.TourOk.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; $state.tourDone = $true; $state.seenVer = $appVersion; $ui.Tour.Visibility = 'Collapsed'; Save-State; Apply-View })
$ui.BtnMode.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; Toggle-Mode })
$ui.Tab.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; $state.drawerOpen = $true; Apply-View; Save-State })
$ui.DrawerClose.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; $state.drawerOpen = $false; Apply-View; Save-State })

$ui.Footer.Add_MouseLeftButtonDown({ param($s, $e) if ($script:last -and $script:last.warn) { $e.Handled = $true; Show-SensorDialog } })

$menu = New-Object System.Windows.Controls.ContextMenu
$miRefresh = New-Object System.Windows.Controls.MenuItem; $miRefresh.Header = 'Jetzt aktualisieren'
$miPop = New-Object System.Windows.Controls.MenuItem; $miPop.IsCheckable = $true; $miPop.IsChecked = [bool]$state.popup
$miTop = New-Object System.Windows.Controls.MenuItem; $miTop.Header = 'Immer im Vordergrund'; $miTop.IsCheckable = $true; $miTop.IsChecked = [bool]$state.topmost
$miLog = New-Object System.Windows.Controls.MenuItem; $miLog.Header = 'Protokoll öffnen (bei Problemen)'
$miReset = New-Object System.Windows.Controls.MenuItem; $miReset.Header = 'Fenster zurücksetzen (oben rechts)'
$miSound = New-Object System.Windows.Controls.MenuItem; $miSound.Header = 'Hinweiston beim Lüften'; $miSound.IsCheckable = $true; $miSound.IsChecked = [bool]$state.sound
$miTray = New-Object System.Windows.Controls.MenuItem; $miTray.IsCheckable = $true; $miTray.IsChecked = [bool]$state.tray
$miHa = New-Object System.Windows.Controls.MenuItem
$miMode = New-Object System.Windows.Controls.MenuItem
$miBig = New-Object System.Windows.Controls.MenuItem
$miSmall = New-Object System.Windows.Controls.MenuItem
$miCopy = New-Object System.Windows.Controls.MenuItem
$miCopyAll = New-Object System.Windows.Controls.MenuItem
$miExport = New-Object System.Windows.Controls.MenuItem
$miSnooze = New-Object System.Windows.Controls.MenuItem
$miTheme = New-Object System.Windows.Controls.MenuItem
$miDemo = New-Object System.Windows.Controls.MenuItem
$miHaSup = New-Object System.Windows.Controls.MenuItem
$miSens = New-Object System.Windows.Controls.MenuItem
$miHelp = New-Object System.Windows.Controls.MenuItem
$miUpd = New-Object System.Windows.Controls.MenuItem
$miCfg = New-Object System.Windows.Controls.MenuItem
$miHaOpen = New-Object System.Windows.Controls.MenuItem
$miHaPanel = New-Object System.Windows.Controls.MenuItem
$miDiag = New-Object System.Windows.Controls.MenuItem
$miPicSave = New-Object System.Windows.Controls.MenuItem
$miLock = New-Object System.Windows.Controls.MenuItem; $miLock.IsCheckable = $true; $miLock.IsChecked = [bool]$state.locked
$miOpacity = New-Object System.Windows.Controls.MenuItem
$miTaskbar = New-Object System.Windows.Controls.MenuItem; $miTaskbar.IsCheckable = $true; $miTaskbar.IsChecked = [bool]$state.taskbar
$miAuto = New-Object System.Windows.Controls.MenuItem; $miAuto.IsCheckable = $true
$miHover = New-Object System.Windows.Controls.MenuItem; $miHover.IsCheckable = $true; $miHover.IsChecked = [bool]$state.hoverFull
$miExport = New-Object System.Windows.Controls.MenuItem
$miImport = New-Object System.Windows.Controls.MenuItem
$miPicCopy = New-Object System.Windows.Controls.MenuItem
$miAbout = New-Object System.Windows.Controls.MenuItem
$miNews = New-Object System.Windows.Controls.MenuItem
$miBug = New-Object System.Windows.Controls.MenuItem
$miData = New-Object System.Windows.Controls.MenuItem
$miExit = New-Object System.Windows.Controls.MenuItem
$miRefresh.Add_Click({ Update-Widget })
$miTop.Add_Click({ $state.topmost = [bool]$miTop.IsChecked; $state.topmostSet = $true; $win.Topmost = $state.topmost; Save-State })
$miTray.Add_Click({ $state.tray = [bool]$miTray.IsChecked; if ($script:tray) { $script:tray.Visible = $state.tray }; Save-State })
$miPop.Add_Click({ $state.popup = [bool]$miPop.IsChecked; Save-State })
$miLog.Add_Click({ try { if (-not (Test-Path $logFile)) { Set-Content -Path $logFile -Value (T 'no_errors') -Encoding UTF8 }; Start-Process notepad.exe -ArgumentList ('"' + $logFile + '"') } catch {} })
$miReset.Add_Click({ $w0 = [System.Windows.SystemParameters]::WorkArea; $win.Left = [Math]::Max($w0.Left, $w0.Right - $win.ActualWidth - 20); $win.Top = $w0.Top + 20; Save-State })
$miSound.Add_Click({ $state.sound = $miSound.IsChecked; Save-State })
$miExit.Add_Click({ Exit-App })
$miHa.Add_Click({ Show-HaDialog })
$miHaOpen.Add_Click({ try { if ($script:haUrl) { Start-Process $script:haUrl } } catch { Write-Log ('HA öffnen: ' + $_.Exception.Message) } })
$miHaPanel.Add_Click({ try { if ($script:haUrl) { Start-Process ($script:haUrl.TrimEnd('/') + '/luftwaechter') } } catch { Write-Log ('HA-Ansicht: ' + $_.Exception.Message) } })
$miDiag.Add_Click({ Copy-Diagnostics })
$miPicSave.Add_Click({ $pp = Save-WidgetPicture ''; if ($pp) { try { Start-Process explorer.exe -ArgumentList ('/select,"' + $pp + '"') } catch {} } })
$miPicCopy.Add_Click({ [void](Copy-WidgetPicture) })
$miLock.Add_Click({ $state.locked = [bool]$miLock.IsChecked; Save-State })
$miOpacity.Add_Click({ Step-Opacity })
$miHover.Add_Click({ $state.hoverFull = [bool]$miHover.IsChecked; Save-State })
$miExport.Add_Click({
    try {
        $f = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Luftwaechter-Einstellungen.json'
        if (Export-Settings $f) { Start-Process explorer.exe -ArgumentList ('/select,"' + $f + '"') }
    } catch { Write-Log ('Sicherung: ' + $_.Exception.Message) }
})
$miImport.Add_Click({
    try {
        $d = New-Object System.Windows.Forms.OpenFileDialog
        $d.Filter = 'Luftwächter (*.json)|*.json'; $d.InitialDirectory = [Environment]::GetFolderPath('MyDocuments')
        if ($d.ShowDialog() -eq 'OK' -and (Import-Settings $d.FileName)) {
            $miPop.IsChecked = [bool]$state.popup; $miTray.IsChecked = [bool]$state.tray; $miSound.IsChecked = [bool]$state.sound; $miTop.IsChecked = [bool]$state.topmost
            $miLock.IsChecked = [bool]$state.locked; $miTaskbar.IsChecked = [bool]$state.taskbar; $miHover.IsChecked = [bool]$state.hoverFull
            $win.Topmost = [bool]$state.topmost; Apply-Window; Apply-Theme; Apply-Lang; Save-State; Update-Widget
        }
    } catch { Write-Log ('Wiederherstellen: ' + $_.Exception.Message) }
})
$win.Add_MouseEnter({ if ($state.hoverFull) { $win.Opacity = 1.0 } })
$win.Add_MouseLeave({ $win.Opacity = [double]$state.opacity })
$miTaskbar.Add_Click({ $state.taskbar = [bool]$miTaskbar.IsChecked; Apply-Window; Save-State })
$miAuto.Add_Click({ if (-not (Set-Autostart ([bool]$miAuto.IsChecked))) { $miAuto.IsChecked = (Test-Autostart) } })
$miAbout.Add_Click({ try { [void][System.Windows.MessageBox]::Show((Get-AboutText), (T 'm_about'), 'OK', 'Information') } catch { Write-Log ('Über: ' + $_.Exception.Message) } })
$miNews.Add_Click({ try { Start-Process ('https://github.com/DanStasiak/airguard-widget/releases/tag/v' + $appVersion) } catch { Write-Log ('Versionshinweise: ' + $_.Exception.Message) } })
$miBug.Add_Click({ try { Start-Process 'https://github.com/DanStasiak/airguard-widget/issues/new/choose' } catch { Write-Log ('Problem melden: ' + $_.Exception.Message) } })
$miData.Add_Click({ try { if (Test-Path $stateDir) { Start-Process explorer.exe -ArgumentList ('"' + $stateDir + '"') } } catch { Write-Log ('Datenordner: ' + $_.Exception.Message) } })
$miMode.Add_Click({ Toggle-Mode })
$miCopy.Add_Click({ Copy-Readings })
$miCopyAll.Add_Click({ Copy-AllRooms })
$miExport.Add_Click({ Export-History })
$miSnooze.Add_Click({ Toggle-Snooze })
$miSnoozeM = New-Object System.Windows.Controls.MenuItem
$miSnoozeM.Add_Click({ Set-Snooze 'morning' })
$miTheme.Add_Click({ $state.theme = $(switch ([string]$state.theme) { 'auto' { 'day' } 'day' { 'night' } default { 'auto' } }); Apply-Theme; Save-State; Apply-Lang })
$miDemo.Add_Click({ $state.demo = -not [bool]$state.demo; $state.room = ''; Save-State; Apply-Lang; Update-Widget })
$miHaSup.Add_Click({ try { Start-Process 'https://www.home-assistant.io/' } catch {} })
function Step-Size([int]$dir) {
    $ord = @('S', 'M', 'L', 'XL')
    $i = [Array]::IndexOf($ord, [string]$state.size)
    if ($i -lt 0) { $i = 1 }
    $n = [Math]::Max(0, [Math]::Min($ord.Count - 1, $i + $dir))
    $state.size = $ord[$n]; Apply-View; Save-State
}
$miBig.Add_Click({ Step-Size 1 })
$miSmall.Add_Click({ Step-Size -1 })
$win.Add_PreviewMouseWheel({ param($s, $e) if ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control) { $e.Handled = $true; if ($e.Delta -gt 0) { Step-Size 1 } else { Step-Size -1 } } })
$miSens.Add_Click({ Show-SensorDialog })
$miHelp.Add_Click({ $script:helpOpen = $true; Apply-View })
$miCfg.Add_Click({ try { if (-not (Test-Path $cfgFile)) { Copy-Item (Join-Path $dir 'config.example.json') $cfgFile }; Start-Process notepad.exe -ArgumentList ('"' + $cfgFile + '"') } catch { Write-Log ('Konfig: ' + $_.Exception.Message) } })
$miUpd.Add_Click({ Invoke-UpdateFlow $true })
$miAdv = New-Object System.Windows.Controls.MenuItem
foreach ($mx in @($miHaOpen, $miHaPanel, $miHa, $miSens, $miCfg, $miAuto, $miExport, $miImport, $miData, $miDiag, $miLog, $miDemo)) { [void]$miAdv.Items.Add($mx) }
function Update-HaMenu { $miAuto.IsChecked = (Test-Autostart); if ($script:trayMiHa) { $script:trayMiHa.Visible = [bool]$script:haMode }; $vis = $(if ($script:haMode) { 'Visible' } else { 'Collapsed' }); $miHaOpen.Visibility = $vis; $miHaPanel.Visibility = $vis }
$menu.Add_Opened({ Update-HaMenu })
$menuGroups = @(
    @($miMode, $miTheme, $miBig, $miSmall),
    @($miSnooze, $miSnoozeM, $miPop, $miTray, $miSound, $miTop),
    @($miRefresh, $miCopy, $miCopyAll, $miExport),
    @($miReset, $miLock, $miOpacity, $miHover, $miTaskbar, $miPicSave, $miPicCopy, $miAdv),
    @($miHelp, $miNews, $miBug, $miAbout, $miHaSup, $miUpd),
    @($miExit)
)
for ($gi = 0; $gi -lt $menuGroups.Count; $gi++) {
    if ($gi -gt 0) { [void]$menu.Items.Add((New-Object System.Windows.Controls.Separator)) }
    foreach ($mx in $menuGroups[$gi]) { [void]$menu.Items.Add($mx) }
}
$win.ContextMenu = $menu


# ---------- Sprache / Hilfe ----------
function Get-FooterText { if ($footerCfg) { return $footerCfg }; return (T 'footer') }
$script:helpOrder = @(1, 2, 3, 4, 5, 19, 20, 21, 22, 6, 7, 8, 9, 10, 18, 11, 15, 16, 13, 14, 17, 12)
$script:helpOpenSec = @{ 1 = $true }
$script:helpBodies = @{}; $script:helpHeads = @{}; $script:helpTitles = @{}
function Get-HelpLive([int]$id) {
    if ($id -lt 19 -or $id -gt 22 -or -not $script:last) { return '' }
    try {
        $v = @($script:last.values)[$id - 19]
        if ($null -eq $v -or [string]$v.value -eq '') { return '' }
        $lv = @('gut', 'mittel', 'schlecht')[[int]$v.level]
        return ' · ' + (T 'help_now' ([string]$v.value) ([string]$v.unit) (Get-LevelText $lv))
    } catch { return '' }
}
function Set-HelpHead([int]$id) {
    $open = [bool]$script:helpOpenSec[$id]
    $script:helpHeads[$id].Text = $(if ($open) { '▾ ' } else { '▸ ' }) + $script:helpTitles[$id]
    $script:helpBodies[$id].Visibility = $(if ($open) { 'Visible' } else { 'Collapsed' })
}
function Toggle-HelpSection([int]$id, $force = $null) {
    $open = -not [bool]$script:helpOpenSec[$id]
    if ($null -ne $force) { $open = [bool]$force }
    $script:helpOpenSec[$id] = $open
    Set-HelpHead $id
}
function Set-HelpAll([bool]$open) { foreach ($id in $script:helpOrder) { $script:helpOpenSec[$id] = $open; Set-HelpHead $id } }
function Show-HelpSection([int]$id) {
    $script:helpOpen = $true
    Build-Help
    Toggle-HelpSection $id $true
    Apply-View
    try { $ui.HelpBody.UpdateLayout(); $script:helpHeads[$id].BringIntoView() } catch {}
}
function Build-Help {
    $ui.HelpBody.Children.Clear()
    $script:helpBodies = @{}; $script:helpHeads = @{}; $script:helpTitles = @{}
    $bar = New-Object Windows.Controls.StackPanel; $bar.Orientation = 'Horizontal'; $bar.Margin = New-Object Windows.Thickness(0, 4, 0, 2)
    $ex = New-Text (T 'help_expand') 12 '#FF9CC9FF' $false; $ex.Cursor = 'Hand'
    $sep = New-Text '   ·   ' 12 '#FFA9B4C4' $false
    $co = New-Text (T 'help_collapse') 12 '#FF9CC9FF' $false; $co.Cursor = 'Hand'
    $ex.Add_MouseLeftButtonDown({ param($s1, $e1) $e1.Handled = $true; Set-HelpAll $true })
    $co.Add_MouseLeftButtonDown({ param($s1, $e1) $e1.Handled = $true; Set-HelpAll $false })
    [void]$bar.Children.Add($ex); [void]$bar.Children.Add($sep); [void]$bar.Children.Add($co)
    [void]$ui.HelpBody.Children.Add($bar)
    foreach ($i in $script:helpOrder) {
        $script:helpTitles[$i] = (T ('h' + $i)) + (Get-HelpLive $i)
        $h = New-Text '' 15 '#FFFFFFFF' $true
        $h.Margin = New-Object Windows.Thickness(0, 10, 0, 2); $h.Cursor = 'Hand'; $h.Tag = $i; $h.TextWrapping = 'Wrap'
        $h.Add_MouseLeftButtonDown({ param($s1, $e1) $e1.Handled = $true; Toggle-HelpSection ([int]$s1.Tag) })
        $bk = 'b' + $i; $bt = $(if ($i -eq 12) { T $bk $repoUrl } else { T $bk }); $b = New-Text $bt 13 '#FFDFE5EE' $false
        $b.TextWrapping = 'Wrap'; $b.Margin = New-Object Windows.Thickness(16, 0, 0, 4)
        $script:helpHeads[$i] = $h; $script:helpBodies[$i] = $b
        Set-HelpHead $i
        [void]$ui.HelpBody.Children.Add($h); [void]$ui.HelpBody.Children.Add($b)
    }
    $ui.HelpTitle.Text = (T 'help_title') + ' · Luftwächter'
    $ui.HelpVer.Text = $version + '  ·  ' + $copyright
}
function Apply-Lang {
    $ui.SzC.Text = (T 'sz_c'); $ui.SzP.Text = (T 'sz_p')
    $ui.WMoreT.Text = (T 'more'); $ui.WLessT.Text = (T 'less'); $ui.WTitleT.Text = (T 'outside') + $(if ($place) { ' · ' + $place.ToUpper() } else { '' })
    $ui.SparkR.Text = (T 'now'); $ui.SparkBox.ToolTip = (T 'spark_tip'); for ($k = 1; $k -le 4; $k++) { $ui.('C' + $k).ToolTip = (T ('chip_tip_' + $k)) }; $ui.Pill.ToolTip = (T 'pill_tip')
    $ui.BtnHelp.ToolTip = (T 'help_tip'); $ui.BtnLang.ToolTip = (T 'lang_tip')
    $ui.SzBS.ToolTip = (T 'sz_tip_s'); $ui.SzBM.ToolTip = (T 'sz_tip_m'); $ui.SzBL.ToolTip = (T 'sz_tip_l'); $ui.SzBC.ToolTip = (T 'sz_tip_c'); $ui.SzBP.ToolTip = (T 'sz_tip_p')
    $ui.Time.ToolTip = (T 'time_tip'); $ui.DrawerClose.ToolTip = (T 'drawer_close_tip'); $ui.Tab.ToolTip = (T 'tab_tip'); $ui.HelpClose.ToolTip = (T 'help_close_tip'); $miAdv.Header = (T 'm_adv')
    foreach ($k in 'De', 'En') { $ui.('Lang' + $k).Foreground = Brush '#FFA9B4C4'; $ui.('Lang' + $k).FontWeight = 'Normal' }
    if ($state.lang -eq 'en') { $ui.LangEn.Foreground = Brush '#FFFFFFFF'; $ui.LangEn.FontWeight = 'Bold' } else { $ui.LangDe.Foreground = Brush '#FFFFFFFF'; $ui.LangDe.FontWeight = 'Bold' }
    $miCopy.Header = (T 'm_copy'); $miCopyAll.Header = (T 'm_copy_all'); $miExport.Header = (T 'm_export');
    if ($script:trayMiExit) { $script:trayMiExit.Text = (T 'm_exit'); $script:trayMiRefresh.Text = (T 'm_refresh'); $script:trayMiQuietM.Text = (T 'm_snooze_m'); $script:trayMiQuiet.Text = $(if (Test-Snooze) { T 'm_snooze_off' ($script:snoozeUntil.ToString('HH:mm')) } else { T 'm_snooze' }) }
 $miSnoozeM.Header = (T 'm_snooze_m'); $miSnooze.Header = $(if (Test-Snooze) { T 'm_snooze_off' ($script:snoozeUntil.ToString('HH:mm')) } else { T 'm_snooze' }); $miTheme.Header = $(switch ([string]$state.theme) { 'day' { T 'm_theme_day' } 'night' { T 'm_theme_night' } default { T 'm_theme_auto' } }); $miDemo.Header = $(if ($state.demo) { T 'm_demo_off' } else { T 'm_demo' }); $miHaSup.Header = (T 'm_ha_support'); $miBig.Header = (T 'm_bigger'); $miSmall.Header = (T 'm_smaller'); $miRefresh.Header = (T 'm_refresh'); $miTop.Header = (T 'm_top'); $miPop.Header = (T 'm_pop'); $miTray.Header = (T 'm_tray'); if ($script:trayMiOpen) { $script:trayMiOpen.Text = (T 'tray_open'); $script:trayMiExit.Text = (T 'm_exit') }; $miSound.Header = (T 'm_sound'); $miReset.Header = (T 'm_reset'); $miLog.Header = (T 'm_log'); $miHelp.Header = (T 'm_help'); $miHa.Header = (T 'm_ha'); $miHaOpen.Header = (T 'm_ha_open'); $miHaPanel.Header = (T 'm_ha_panel'); $miDiag.Header = (T 'm_diag'); $miNews.Header = (T 'm_news'); $miBug.Header = (T 'm_bug'); $miData.Header = (T 'm_data'); $miPicSave.Header = (T 'm_pic_save'); $miLock.Header = (T 'm_lock'); $miOpacity.Header = (T 'm_opacity' ([int][Math]::Round([double]$state.opacity * 100))); $miTaskbar.Header = (T 'm_taskbar'); $miAuto.Header = (T 'm_auto'); $miHover.Header = (T 'm_hover'); $miExport.Header = (T 'm_export'); $miImport.Header = (T 'm_import'); $miPicCopy.Header = (T 'm_pic_copy'); $miAbout.Header = (T 'm_about'); if ($script:trayMiHa) { $script:trayMiHa.Text = (T 'tray_ha') }; $miMode.Header = $(if ($state.simple) { T 'm_mode_full' } else { T 'm_mode_simple' }); $miSens.Header = (T 'm_sens'); $miCfg.Header = (T 'm_cfg'); $miUpd.Header = (T 'm_upd'); $miExit.Header = (T 'm_exit')
    $ui.RoomName.Text = 'Luftwächter'; $ui.TitleTag.Text = (T 'tagline')
    $ui.Footer.Text = (Get-FooterText)
    $ui.Copy.Text = $copyright + ' · GitHub'; $ui.Copy.ToolTip = (T 'copy_tip'); $ui.Ver.ToolTip = (T 'ver_tip')
    Set-UpdateButton
    Build-Help
    $script:devSig = ''
    if ($script:last) { Show-Data $script:last }
}

$ui.BtnHelp.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; $script:helpOpen = $true; Build-Help; Apply-View })
$ui.HelpClose.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; $script:helpOpen = $false; Apply-View })
$ui.LangDe.Tag = 'de'; $ui.LangEn.Tag = 'en'
foreach ($k in 'De', 'En') {
    $ui.('Lang' + $k).Cursor = 'Hand'
    $ui.('Lang' + $k).Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; if ($state.lang -ne [string]$s.Tag) { $state.lang = [string]$s.Tag; Apply-Lang; Save-State; Update-Widget } })
}


# ---------- Updates über GitHub ----------
$script:newVer = $null
function Set-UpdateButton {
    if ($script:newVer) { $ui.BtnUpdT.Text = (T 'upd_new' ('v' + $script:newVer)); $ui.BtnUpd.Background = Brush '#FF2E9E5B' }
    else { $ui.BtnUpdT.Text = (T 'upd_btn'); $ui.BtnUpd.Background = Brush '#FF494E57' }
    if ($script:newVer) { $ui.BtnUpd.ToolTip = (T 'upd_tip_new' ('v' + $script:newVer)) }
    elseif ($script:lastUpdCheck) { $ui.BtnUpd.ToolTip = (T 'upd_tip' $script:lastUpdCheck.ToString('HH:mm') $updMinutes) }
    else { $ui.BtnUpd.ToolTip = (T 'upd_tip_never') }
    Apply-Simple
}
function Get-LatestRelease {
    $api = 'https://api.github.com/repos/' + $repoOwner + '/' + $repoName + '/releases/latest'
    return (Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'Luftwaechter-Updater'; 'Accept' = 'application/vnd.github+json' } -TimeoutSec 10)
}
function Test-Newer([string]$remote, [string]$local) {
    try { return ([version]$remote.TrimStart('v')) -gt ([version]$local) } catch { return $false }
}
function Read-Changelog {
    $list = @()
    try {
        $f = Join-Path $dir 'CHANGELOG.md'
        if (-not (Test-Path $f)) { return @() }
        $cur = $null
        foreach ($ln in (Get-Content -Path $f -Encoding UTF8)) {
            if ($ln -match '^##\s+\[(.+?)\]\s*-?\s*(.*)$') {
                $v = $Matches[1]; $mj = ($v -split '[\. ]')[0]
                $cur = [pscustomobject]@{ ver = $v; date = [string]$Matches[2]; major = $mj; lines = @(); de = @() }
                $list += $cur
            } elseif ($cur -and $ln.Trim() -ne '') {
                $t = ($ln.Trim() -replace '^-\s+', '')
                if ($t -match '^DE:\s*(.*)$') { $cur.de += $Matches[1] } else { $cur.lines += $t }
            }
        }
    } catch { Write-Log ('Changelog: ' + $_.Exception.Message) }
    if ($state.lang -ne 'en') { foreach ($e in $list) { if (@($e.de).Count -gt 0) { $e.lines = @($e.de) } } }
    return $list
}
function Show-UpdateDialog($rel, [string]$remote, [bool]$isNew) {
    $x = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Luftwächter" Width="560" SizeToContent="Height" MaxHeight="720" WindowStartupLocation="CenterScreen" Topmost="True" ResizeMode="NoResize" Background="#FF1B222D" FontFamily="Segoe UI">
  <StackPanel Margin="22">
    <TextBlock x:Name="UTitle" Foreground="White" FontSize="21" FontWeight="Bold" TextWrapping="Wrap"/>
    <TextBlock x:Name="USub" Foreground="#FFB3BECD" FontSize="13" Margin="0,4,0,10"/>
    <Border Background="#33000000" CornerRadius="8" Margin="0,0,0,16" Padding="12"><ScrollViewer MaxHeight="470" VerticalScrollBarVisibility="Auto"><StackPanel x:Name="UBody"/></ScrollViewer></Border>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right"><Button x:Name="UNo" Padding="16,6" Margin="0,0,8,0"/><Button x:Name="UYes" Padding="16,6" IsDefault="True"/></StackPanel>
  </StackPanel>
</Window>
"@
    $d = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$x)))
    if ($isNew) {
        $d.FindName('UTitle').Text = (T 'upd_title')
        $d.FindName('USub').Text = (T 'upd_sub' ('v' + $appVersion) ('v' + $remote))
    } else {
        $d.FindName('UTitle').Text = (T 'upd_hist')
        $d.FindName('USub').Text = (T 'upd_none' ('v' + $appVersion))
    }
    $body = $d.FindName('UBody')
    $add = { param($txt, $sz, $fg, $bold, $top) $tb = New-Text $txt $sz $fg $bold; $tb.TextWrapping = 'Wrap'; $tb.Margin = New-Object Windows.Thickness(0, $top, 0, 0); [void]$body.Children.Add($tb) }
    if ($isNew) {
        & $add (T 'upd_what') 14 '#FF7CE0A0' $true 0
        $nb = ([string]$rel.body).Trim(); if (-not $nb) { $nb = (T 'upd_nonotes') }
        & $add $nb 12.5 '#FFFFFFFF' $false 3
    }
    $log = @(Read-Changelog)
    if ($log.Count -gt 0) {
        $curMajor = ($appVersion -split '\.')[0]
        $top = 0; if ($isNew) { $top = 16 }
        & $add (T 'upd_cur' $curMajor) 14 '#FF9CC4FF' $true $top
        foreach ($e in @($log | Where-Object { $_.major -eq $curMajor })) {
            & $add ('v' + $e.ver + '  ·  ' + $e.date) 12.5 '#FFFFFFFF' $true 9
            foreach ($l in @($e.lines)) { & $add ('•  ' + $l) 12 '#FFDFE5EE' $false 2 }
        }
        $others = @($log | Where-Object { $_.major -ne $curMajor })
        if ($others.Count -gt 0) {
            & $add (T 'upd_prev') 14 '#FF9CC4FF' $true 18
            $sums = @{ '3' = @('Vom Ein-Raum-Widget zur vollständigen App: mehrere Räume, ausfahrbares Geräte-Fenster (Licht, Steckdosen, Heizung, Jalousien), Wetterzeile, CO₂-Kurve mit Trend und Prognose, Lüftungs-Timer, Raumleiste, Autostart, Nachtmodus, Fehlerprotokoll, Pill-Modus, Tagesbilanz, Hilfe und DE/EN-Umschalter. Mit 3.13 kam die erste öffentliche Version (MIT-Lizenz) mit Update-Button, Konfiguration und n8n-Referenz-Backend; 3.14 brachte Tray-Symbol, Lüftungs-Benachrichtigungen und Startmenü-Eintrag, 3.15 die klickbaren Werte-Kacheln mit eigener Kurve je Messwert.', 'From a single-room widget to a complete app: multiple rooms, slide-out device panel (lights, plugs, heating, blinds), weather row, CO₂ curve with trend and forecast, ventilation timer, room strip, autostart, night dimming, error log, pill mode, daily summary, help and DE/EN toggle. 3.13 was the first public release (MIT License) with the update button, configuration and an n8n reference backend; 3.14 added the tray icon, ventilation notifications and a Start menu entry, 3.15 the clickable value tiles with their own curve per reading.') }
            foreach ($mj in @($others | ForEach-Object { $_.major } | Select-Object -Unique)) {
                $grp = @($others | Where-Object { $_.major -eq $mj })
                $a = ([string]$grp[$grp.Count - 1].ver -split ' ')[0]; $b = ([string]$grp[0].ver -split ' ')[0]
                $range = $a; if ($a -ne $b) { $range = $a + ' – ' + $b }
                & $add ((Lx 'Version ' 'Version ') + $mj + '  (' + $range + ')') 12.5 '#FFFFFFFF' $true 9
                if ($sums.ContainsKey($mj)) { $para = (Lx $sums[$mj][0] $sums[$mj][1]) }
                else { $para = ((@($grp | ForEach-Object { $_.lines }) | ForEach-Object { $_ -replace '^(New|Fix|Improved):\s*', '' }) -join ' ') }
                & $add $para 12 '#FFDFE5EE' $false 2
            }
        }
    }
    $d.FindName('UNo').Content = $(if ($isNew) { T 'upd_no' } else { T 'upd_close' }); $d.FindName('UYes').Content = (T 'upd_yes')
    if (-not $isNew) { $d.FindName('UYes').Visibility = 'Collapsed'; $d.FindName('UNo').IsDefault = $true }
    $script:dlg = $d
    $d.FindName('UNo').Add_Click({ $script:dlg.DialogResult = $false })
    $d.FindName('UYes').Add_Click({ $script:dlg.DialogResult = $true })
    $r = $d.ShowDialog()
    return ($r -eq $true)
}
function Start-Update($rel) {
    $fail = $false
    try {
        if ($dir -ne $installDir) { [void][System.Windows.MessageBox]::Show((T 'upd_notinst'), 'Luftwächter', 'OK', 'Information'); return }
        $asset = @($rel.assets | Where-Object { [string]$_.name -like '*.zip' }) | Select-Object -First 1
        if (-not $asset) { throw 'Kein ZIP im Release' }
        $u = [string]$asset.browser_download_url
        if (-not $u.StartsWith('https://github.com/' + $repoOwner + '/' + $repoName + '/releases/download/')) { throw ('Unerwartete Download-Adresse: ' + $u) }
        $tmp = Join-Path $env:TEMP ('luft-update-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        $zip = Join-Path $tmp 'update.zip'
        $hdr = @{ 'User-Agent' = 'Luftwaechter-Updater' }
        Invoke-WebRequest -Uri $u -OutFile $zip -UseBasicParsing -TimeoutSec 120 -Headers $hdr
        # Prüfsumme, wenn das Release eine SHA256SUMS.txt mitbringt
        $sumAsset = @($rel.assets | Where-Object { [string]$_.name -eq 'SHA256SUMS.txt' }) | Select-Object -First 1
        if ($sumAsset) {
            $su = [string]$sumAsset.browser_download_url
            if (-not $su.StartsWith('https://github.com/' + $repoOwner + '/' + $repoName + '/releases/download/')) { throw 'Unerwartete Prüfsummen-Adresse' }
            $sums = (Invoke-WebRequest -Uri $su -UseBasicParsing -TimeoutSec 30 -Headers $hdr).Content
            if ($sums -is [byte[]]) { $sums = [System.Text.Encoding]::UTF8.GetString($sums) }
            $want = $null
            foreach ($ln in ([string]$sums -split "`n")) { if ($ln -match '^([0-9a-fA-F]{64})\s+\*?(.+?)\s*$' -and $matches[2] -eq [string]$asset.name) { $want = $matches[1] } }
            if (-not $want) { throw 'Keine Prüfsumme für das ZIP gefunden' }
            $have = (Get-FileHash -Algorithm SHA256 -Path $zip).Hash
            if ($have -ne $want.ToUpper()) { throw 'Prüfsumme stimmt nicht' }
        }
        $ex = Join-Path $tmp 'x'
        Expand-Archive -Path $zip -DestinationPath $ex -Force
        $ps1 = Get-ChildItem -Path $ex -Recurse -Filter 'Luftwaechter.ps1' | Select-Object -First 1
        if (-not $ps1) { throw 'Luftwaechter.ps1 fehlt im ZIP' }
        $perr = $null; $null = [System.Management.Automation.Language.Parser]::ParseFile($ps1.FullName, [ref]$null, [ref]$perr)
        if ($perr -and $perr.Count -gt 0) { throw ('Skript fehlerhaft: ' + $perr[0].Message) }
        $root = $ps1.DirectoryName
        $helper = Join-Path $tmp 'apply-update.ps1'
        $code = @'
param([int]$ProcId, [string]$Src, [string]$Dst)
try { Wait-Process -Id $ProcId -Timeout 30 -ErrorAction SilentlyContinue } catch {}
Start-Sleep -Milliseconds 700
$bak = Join-Path $Dst ('backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force -Path $bak | Out-Null
$files = 'Luftwaechter.ps1', 'Start.vbs', 'Installieren.bat', 'Deinstallieren.bat', 'config.example.json', 'LICENSE', 'README.md', 'CHANGELOG.md', 'VERSION'
try {
    foreach ($f in $files) {
        $s = Join-Path $Src $f; $d = Join-Path $Dst $f
        if (Test-Path $s) { if (Test-Path $d) { Copy-Item -Force $d $bak }; Copy-Item -Force $s $d }
    }
} catch {
    foreach ($f in Get-ChildItem $bak -File) { Copy-Item -Force $f.FullName (Join-Path $Dst $f.Name) }
}
Get-ChildItem $Dst -Directory -Filter 'backup-*' | Sort-Object Name -Descending | Select-Object -Skip 2 | ForEach-Object { Remove-Item -Recurse -Force $_.FullName }
Start-Process 'wscript.exe' -ArgumentList ('"' + (Join-Path $Dst 'Start.vbs') + '"')
'@
        Set-Content -Path $helper -Value $code -Encoding UTF8
        Write-Log ('Update gestartet: ' + $appVersion + ' -> ' + [string]$rel.tag_name)
        Start-Process 'powershell.exe' -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ('"' + $helper + '"'), '-ProcId', [string]$PID, '-Src', ('"' + $root + '"'), '-Dst', ('"' + $dir + '"'))
        $win.Close()
    } catch {
        Write-Log ('Update: ' + $_.Exception.Message)
        [void][System.Windows.MessageBox]::Show((T 'upd_dlfail'), 'Luftwächter', 'OK', 'Warning')
    }
}
function Invoke-UpdateFlow([bool]$manual) {
    try {
        $rel = Get-LatestRelease
        $script:lastUpdCheck = Get-Date
        $remote = ([string]$rel.tag_name).TrimStart('v')
        if (Test-Newer $remote $appVersion) {
            $script:newVer = $remote; Set-UpdateButton
            if (-not $manual -and $script:notifiedVer -ne $remote) {
                $script:notifiedVer = $remote
                try { if ($script:tray -and $state.tray) { $script:tray.ShowBalloonTip(8000, 'Luftwächter', (T 'upd_balloon' ('v' + $remote)), [System.Windows.Forms.ToolTipIcon]::Info) } } catch {}
            }
            if ($manual) { if (Show-UpdateDialog $rel $remote $true) { Start-Update $rel } }
        } else {
            $script:newVer = $null; Set-UpdateButton
            if ($manual) { [void](Show-UpdateDialog $null '' $false) }
        }
    } catch {
        Write-Log ('Update-Suche: ' + $_.Exception.Message)
        if ($manual) { [void][System.Windows.MessageBox]::Show((T 'upd_fail'), 'Luftwächter', 'OK', 'Warning') }
    }
}
$ui.BtnUpd.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; Invoke-UpdateFlow $true })
$ui.TitleBox.Add_MouseLeftButtonDown({ param($s, $e) if ($e.ClickCount -ge 2) { $e.Handled = $true; Toggle-Mode } })
$ui.Copy.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; try { Start-Process $repoUrl } catch {} })
$ui.Ver.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; try { Start-Process ($repoUrl + '/releases') } catch {} })

# ---------- Takt: Aktualisieren, Pulsieren, Nachtmodus, Speichern ----------
$script:pulse = $false
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds($interval)
$script:tickN = 0
function Test-Hidden { return ($win.WindowState -eq 'Minimized' -or -not $win.IsVisible) }
function Step-Poll {
    $script:tickN++
    if ((Test-Hidden) -and ($script:tickN % 3) -ne 0) { return $false }
    Update-Widget; return $true
}
$timer.Add_Tick({ [void](Step-Poll) })
$win.Add_StateChanged({ if ($win.WindowState -ne 'Minimized') { Update-Widget } })

$pulseTimer = New-Object System.Windows.Threading.DispatcherTimer
$pulseTimer.Interval = [TimeSpan]::FromMilliseconds(1000)
$pulseTimer.Add_Tick({
    $h = (Get-Date).Hour
    # Tag-/Nachtdesign: Die Durchsichtigkeit stellt der Nutzer ein (Taste O), die Farbe wechselt
    $win.Opacity = (Get-TargetOpacity $win.IsMouseOver)
    $nt = $false
    switch ([string]$state.theme) { 'night' { $nt = $true } 'day' { $nt = $false } default { $nt = ($h -ge 22 -or $h -lt 7) } }
    if ($nt -ne $script:nightOn) { Apply-Theme }
    if ($script:newVer -and $ui.BtnUpd) { $script:updOn = -not $script:updOn; if ($script:updOn) { $ui.BtnUpd.Background = Brush '#FF2E9E5B' } else { $ui.BtnUpd.Background = Brush '#FF237A47' } }
    if ($script:pulse) { $script:pulseOn = -not $script:pulseOn; if ($script:pulseOn) { $ui.Glow.Opacity = 0.95 } else { $ui.Glow.Opacity = 0.25 } }
    else { $ui.Glow.Opacity = 0.5 }
})

$saveTimer = New-Object System.Windows.Threading.DispatcherTimer
$saveTimer.Interval = [TimeSpan]::FromMinutes(5)
$saveTimer.Add_Tick({ Save-State })

$firstCheck = New-Object System.Windows.Threading.DispatcherTimer
$firstCheck.Interval = [TimeSpan]::FromSeconds(12)
$firstCheck.Add_Tick({ $firstCheck.Stop(); Invoke-UpdateFlow $false })
$checkTimer = New-Object System.Windows.Threading.DispatcherTimer
$checkTimer.Interval = [TimeSpan]::FromMinutes($updMinutes)
$checkTimer.Add_Tick({ Invoke-UpdateFlow $false })

$win.Add_Closing({ Save-State; $timer.Stop(); $pulseTimer.Stop(); $saveTimer.Stop(); $firstCheck.Stop(); $checkTimer.Stop(); Close-Tray })
if ($dir -eq $installDir -and -not (Test-Path $startMenuLnk)) { New-StartMenuShortcut }
$script:firstRun = $true
$win.Add_ContentRendered({ if ($script:firstRun) { $script:firstRun = $false; if (-not $script:haMode -and $url -notmatch '^https?://') { Show-HaDialog } } })
Init-Tray
Apply-Lang
Apply-View
Write-Log ('Start ' + $version)
Update-Widget
if ($SmokeTest) {
    # Selbsttest ohne Home Assistant: Fenster zeigen, alle Ansichten mit Demo-Daten durchspielen, Fehler melden (für GitHub Actions)
    $script:smokeFail = New-Object System.Collections.ArrayList
    $l0 = 0; if (Test-Path $logFile) { $l0 = @(Get-Content -Path $logFile -Encoding UTF8).Count }
    function Smoke([string]$n, [scriptblock]$b) {
        try { $r = & $b; if ($r -eq $false) { throw 'check returned false' }; Write-Host ('ok    ' + $n) }
        catch { [void]$script:smokeFail.Add($n); Write-Host ('FAIL  ' + $n + ': ' + $_.Exception.Message + ' @line ' + $_.InvocationInfo.ScriptLineNumber) }
    }
    $script:firstRun = $false
    $script:snoozeUntil = (Get-Date).AddDays(1)
    Smoke 'window shows' { $win.Show(); $win.UpdateLayout(); $true }
    Smoke 'demo data, all rooms' { $state.demo = $true; foreach ($k in 'living', 'office', 'bed') { $state.room = $k; Update-Widget }; ($ui.Headline.Text.Length -gt 0) }
    Smoke 'simple view' { $state.simple = $true; Apply-View; Apply-Lang; $win.UpdateLayout(); $true }
    Smoke 'details view' { $state.simple = $false; Apply-View; Apply-Lang; Update-Widget; $win.UpdateLayout(); $true }
    Smoke 'English' { $state.lang = 'en'; Apply-Lang; Update-Widget; $state.lang = 'de'; Apply-Lang; $true }
    Smoke 'themes day/night/auto' { foreach ($t in 'day', 'night', 'auto') { $state.theme = $t; Apply-Theme }; ($null -ne $script:themeBg) }
    Smoke 'sizes S M L XL compact pill' { foreach ($z in 'S', 'M', 'L', 'XL', 'C', 'P', 'M') { $state.size = $z; Apply-View; $win.UpdateLayout() }; $true }
    Smoke 'bigger/smaller' { Step-Size 1; Step-Size -1; $true }
    Smoke 'daily score' {
        $now = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $state.hist['smoke'] = @(for ($i = 0; $i -lt 30; $i++) { '{0}:{1}:5:21.0:45' -f ($now - $i * 60), (700 + $i * 20) })
        $v = Get-DayScore 'smoke'; ($null -eq $v -or ($v -ge 0 -and $v -le 100))
    }
    Smoke 'help' { $script:helpOpen = $true; Apply-View; Build-Help; $script:helpOpen = $false; Apply-View; $true }
    Smoke 'update button states' { $script:newVer = '99.0.0'; Set-UpdateButton; $script:newVer = $null; Set-UpdateButton; $true }
    Smoke 'quiet time' { Apply-Lang; (Test-Snooze) }
    Smoke 'what is new card' { $state.simple = $true; $state.tourDone = $true; $state.seenVer = ''; $script:newsText = $null; Apply-View; $true }
    Smoke 'keyboard room switch' { $state.demo = $true; $state.room = 'living'; Update-Widget; Switch-Room 1; ([string]$state.room -eq 'office') }
    Smoke 'snap to edges' { $wa1 = [System.Windows.SystemParameters]::WorkArea; $state.size = 'M'; Apply-View; $win.UpdateLayout(); $win.Left = $wa1.Left + 7; $win.Top = $wa1.Top + 9; Snap-Edges; ($win.Left -eq $wa1.Left -and $win.Top -eq $wa1.Top) }
    Smoke 'quiet tag' { Show-Data $script:last; ($ui.TitleTag.Text -match '🔕') }
    Smoke 'German changelog' { $state.lang = 'de'; $e1 = @(Read-Changelog) | Select-Object -First 1; $state.lang = 'en'; $e2 = @(Read-Changelog) | Select-Object -First 1; $state.lang = 'de'; ($e1 -and $e2 -and ((@($e1.lines) -join ' ') -ne (@($e2.lines) -join ' '))) }
    Smoke 'offline message' { $script:lastOkAt = (Get-Date).AddMinutes(-6); $t = (T 'stale2' $script:lastOkAt.ToString('HH:mm') 6); ($t -match '6') }
    Smoke 'week score' { $now2 = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); $state.hist7['wk'] = @(for ($i = 0; $i -lt 100; $i++) { '{0}:{1}:5:21.0:45' -f ($now2 - $i * 600), (600 + $i * 10) }); $w = Get-WeekScore 'wk'; ($w -ge 0 -and $w -le 100) }
    Smoke 'copy readings' { Update-Widget; Copy-Readings; ($script:lastCopy -match 'CO') }
    Smoke 'snap multi-monitor' { $win.Left = [System.Windows.SystemParameters]::WorkArea.Left + 6; Snap-Edges; ([Math]::Abs($win.Left - [System.Windows.SystemParameters]::WorkArea.Left) -lt 1) }
    Smoke 'tray menu texts' { Apply-Lang; ((-not $script:tray) -or ($script:trayMiExit.Text -eq (T 'm_exit'))) }
    Smoke 'CSV export' { $state.hist7['smoke'] = $state.hist['smoke']; Export-History; ($script:lastExport -and (Test-Path $script:lastExport)) }
    Smoke 'quiet until morning' { Set-Snooze 'morning'; $ok1 = ($script:snoozeUntil -gt (Get-Date).AddMinutes(25) -and $script:snoozeUntil.Hour -eq 7 -and [string]$state.snooze -ne ''); Set-Snooze 'off'; ($ok1 -and -not (Test-Snooze) -and [string]$state.snooze -eq '') }
    Smoke 'quiet saved' { Set-Snooze 'hour'; $f1 = Get-Content $stateFile -Raw | ConvertFrom-Json; $ok2 = ([string]$f1.snooze -ne ''); Set-Snooze 'off'; $script:snoozeUntil = (Get-Date).AddDays(1); $ok2 }
    Smoke 'window rescue' { $win.Left = 99999; $win.Top = -99999; $r1 = Clamp-ToScreen; $vr1 = [System.Windows.SystemParameters]::VirtualScreenLeft + [System.Windows.SystemParameters]::VirtualScreenWidth; ($r1 -and $win.Left -lt $vr1 -and $win.Top -ge [System.Windows.SystemParameters]::VirtualScreenTop) }
    Smoke 'keyboard shortcuts' { $kw = Build-Help; $state.theme = 'auto'; $script:helpOpen = $true; Apply-View; $script:helpOpen = $false; Apply-View; $true }
    Smoke 'offline tray icon' { $script:fails = 2; $u0 = $url; $state.demo = $false; $script:haMode = $false; $url = 'http://127.0.0.1:9/x'; Update-Widget; $ok3 = ($ui.Level.Text -eq (T 'offline')); $state.demo = $true; $url = $u0; $script:fails = 0; Remove-Item $logFile -Force -ErrorAction SilentlyContinue; $ok3 }
    Smoke 'chart hover' { $state.demo = $true; $nw = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); $state.hist['living'] = @(for ($i = 60; $i -ge 0; $i--) { '{0}:{1}:9:21.5:44' -f ($nw - $i * 120), (700 + $i * 5) }); $state.metric = 0; $state.sparkHours = 3; Show-Spark 'living' '#4CAF50'; $r2 = Get-SparkPoint 100.0; ($r2 -and $r2.text -match 'ppm' -and $r2.px -ge 0 -and $r2.px -le 205) }
    Smoke 'min/max with times' { $state.metric = 1; Show-Spark 'living' '#4CAF50'; $ok4 = ($ui.Peak.Text -match '\d\d:\d\d.*\d\d:\d\d'); $state.metric = 0; Show-Spark 'living' '#4CAF50'; $ok4 }
    Smoke 'tile tooltips' { Apply-Lang; ([string]$ui.C1.ToolTip -match '1000' -and [string]$ui.C4.ToolTip -match '30') }
    Smoke 'worst room in tray' { $w5 = Get-WorstRoom ([pscustomobject]@{ level = 'gut'; rooms = @([pscustomobject]@{ name = 'A'; level = 'gut' }, [pscustomobject]@{ name = 'B'; level = 'schlecht' }) }); $n5 = Get-WorstRoom ([pscustomobject]@{ level = 'schlecht'; rooms = @([pscustomobject]@{ name = 'A'; level = 'mittel' }) }); ($w5.name -eq 'B' -and $null -eq $n5) }
    Smoke 'slow polling when minimized' { $win.WindowState = 'Minimized'; $script:tickN = 0; $r6 = @((Step-Poll), (Step-Poll), (Step-Poll)); $win.WindowState = 'Normal'; ($r6[0] -eq $false -and $r6[1] -eq $false -and $r6[2] -eq $true) }
    Smoke 'room chip tooltips' { $state.demo = $true; $state.room = 'living'; Update-Widget; $tt = @($ui.RoomStrip.Children | ForEach-Object { [string]$_.ToolTip }); ($tt.Count -ge 1 -and ($tt -join ' ') -match 'CO') }
    Smoke 'house title' { Update-Widget; ($win.Title -match 'Luftwächter' -and (Get-HouseText @([pscustomobject]@{ level = 'gut' }, [pscustomobject]@{ level = 'schlecht' })) -match '1') }
    Smoke 'screen reader name' { Update-Widget; ([System.Windows.Automation.AutomationProperties]::GetName($ui.Card) -match 'Luftwächter') }
    Smoke 'copy all rooms' { Update-Widget; Copy-AllRooms; ($script:lastCopyAll -match 'Luftwächter' -and @($script:lastCopyAll -split "`n").Count -ge 2) }
    Smoke 'number key room' { $state.room = 'living'; Update-Widget; $k0 = @($script:rooms).Count; Select-RoomIndex 1; $ok7 = ($k0 -lt 2 -or [string]$state.room -ne 'living'); Select-RoomIndex 0; $ok7 }
    Smoke 'tray tooltip length' { $dd1 = [pscustomobject]@{ color = '#FFD9432E'; level = 'gut'; headline = 'Fenster offen lassen bitte jetzt'; room = [pscustomobject]@{ name = 'Büro Demo mit sehr langem Namen' }; values = @([pscustomobject]@{ key = 'CO₂'; value = '918'; unit = 'ppm' }); rooms = @([pscustomobject]@{ name = 'Wohnzimmer mit sehr langem Namen'; level = 'schlecht' }) }; Update-Tray $dd1 ''; ((-not $script:tray) -or $script:tray.Text.Length -le 63) }
    Smoke 'hover glow' { Set-Glow $ui.BtnHelp $true; $g1 = ($null -ne $ui.BtnHelp.Effect); Set-Glow $ui.BtnHelp $false; ($g1 -and $null -eq $ui.BtnHelp.Effect) }
    Smoke 'size picker highlight' { $state.size = 'L'; Apply-View; $okL = ($ui.SzBL.Background.Color.A -gt 0 -and $ui.SzBM.Background.Color.A -eq 0); $state.size = 'M'; Apply-View; ($okL -and $ui.SzBM.Background.Color.A -gt 0 -and $ui.SzBL.Background.Color.A -eq 0) }
    Smoke 'fade on room change' { $state.demo = $true; $script:lastShownRoom = 'zzz'; Update-Widget; Fade-In $ui.Panel; Fade-In $win 50; ($ui.Panel.Opacity -le 1.0) }
    Smoke 'grouped menu' { $nsep = @($menu.Items | Where-Object { $_ -is [System.Windows.Controls.Separator] }).Count; ($nsep -ge 4 -and $miAdv.Items.Count -eq 12 -and $menu.Items.Count -ge 20) }
    Smoke 'diagnostics copy' { Copy-Diagnostics; ($script:lastDiag -match 'Luftwächter 5\.25\.0' -and $script:lastDiag -match 'opacity' -and $script:lastDiag -match 'PowerShell' -and $script:lastDiag -notmatch 'Bearer|token') }
    Smoke 'support menu items' { Apply-Lang; $okS = ([string]$miNews.Header -ne '' -and [string]$miBug.Header -ne '' -and [string]$miData.Header -ne ''); $state.lang = 'en'; Apply-Lang; $okE = ([string]$miBug.Header -match 'GitHub'); $state.lang = 'de'; Apply-Lang; ($okS -and $okE -and (Get-Diagnostics) -match 'Autostart') }
    Smoke 'opacity steps' { $state.opacity = 1.0; Step-Opacity; $a1 = [double]$state.opacity; Step-Opacity; $a2 = [double]$state.opacity; Step-Opacity; $a3 = [double]$state.opacity; ($a1 -eq 0.85 -and $a2 -eq 0.7 -and $a3 -eq 1.0 -and [Math]::Abs($win.Opacity - 1.0) -lt 0.01 -and ([string]$miOpacity.Header -match '100')) }
    Smoke 'taskbar and lock' { $state.taskbar = $false; $state.tray = $true; Apply-Window; $a = (-not $win.ShowInTaskbar); $state.tray = $false; Apply-Window; $b = $win.ShowInTaskbar; $state.tray = $true; $state.taskbar = $true; Apply-Window; $state.locked = $true; Save-State; $c = ((Get-Content $stateFile -Raw) -match '"locked":\s*true'); $state.locked = $false; Save-State; ($a -and $b -and $c) }
    Smoke 'settings backup' { $f = Join-Path $stateDir 'backup.json'; $state.theme = 'night'; $state.opacity = 0.85; $state.locked = $true; $ok1 = (Export-Settings $f); $state.theme = 'day'; $state.opacity = 1.0; $state.locked = $false; $ok2 = (Import-Settings $f); $r = ($ok1 -and $ok2 -and $state.theme -eq 'night' -and $state.opacity -eq 0.85 -and $state.locked); Set-Content -Path $f -Value '{"app":"other","opacity":0.6}' -Encoding UTF8; $bad = (Import-Settings $f); Set-Content -Path $f -Value '{"app":"Luftwaechter","opacity":5,"theme":"pink"}' -Encoding UTF8; [void](Import-Settings $f); $state.theme = 'auto'; $state.opacity = 1.0; $state.locked = $false; ($r -and -not $bad) }
    Smoke 'opaque on hover' { $state.opacity = 0.7; $state.hoverFull = $true; $a = (Get-TargetOpacity $true); $b = (Get-TargetOpacity $false); $state.hoverFull = $false; $c = (Get-TargetOpacity $true); $state.hoverFull = $true; $state.opacity = 1.0; ($a -eq 1.0 -and $b -eq 0.7 -and $c -eq 0.7) }
    Smoke 'autostart toggle' { $startupLnk = Join-Path $stateDir 'autostart-test.lnk'; $o1 = (Set-Autostart $true); $y = (Test-Autostart); [void](Set-Autostart $false); $n = (Test-Autostart); (($o1 -and $y -and -not $n) -or (-not $o1 -and -not $n)) }
    Smoke 'config warnings' { $c0 = $cfg; $cfg = [pscustomobject]@{ refreshSeconds = 99; updateCheckMinutes = 5; haUrl = 'ftp://x'; url = '' }; $ww = @(Get-ConfigWarnings); $cfg = $c0; ($ww.Count -ge 3 -and (Get-Diagnostics) -match 'Config warnings') }
    Smoke 'last error is scrubbed' { $script:lastErr = 'The remote name could not be resolved: http://192.168.1.50:8123/api/states'; $dg = Get-Diagnostics; $script:lastErr = $null; ($dg -match '<address>' -and $dg -notmatch '192\.168') }
    Smoke 'offline hint text' { $state.lang = 'de'; $h1 = (T 'offline_hint'); $state.lang = 'en'; $h2 = (T 'offline_hint'); $state.lang = 'de'; ($h1 -match 'Diagnose' -and $h2 -match 'diagnostics') }
    Smoke 'about text' { $state.lang = 'de'; $a1 = Get-AboutText; $state.lang = 'en'; $a2 = Get-AboutText; $state.lang = 'de'; ($a1 -match '5\.25\.0' -and $a1 -match 'Datenschutz' -and $a2 -match 'Privacy' -and $a2 -match 'github\.com/DanStasiak') }
    Smoke 'picture export' { Update-Widget; $pp = Save-WidgetPicture $stateDir; $okP = ($pp -and (Test-Path $pp) -and ((Get-Item $pp).Length -gt 2000)); if ($okP) { $bb = [System.IO.File]::ReadAllBytes($pp); $okP = ($bb[0] -eq 0x89 -and $bb[1] -eq 0x50 -and $bb[2] -eq 0x4E -and $bb[3] -eq 0x47) }; $okP }
    Smoke 'picture to clipboard' { Update-Widget; (Copy-WidgetPicture) }
    Smoke 'ha menu items' { $script:haMode = $true; Update-HaMenu; $a = ($miHaOpen.Visibility -eq 'Visible'); $script:haMode = $false; Update-HaMenu; $b = ($miHaOpen.Visibility -eq 'Collapsed'); $script:haMode = [bool]($script:haUrl -and $script:haTok); ($a -and $b) }
    Smoke 'header tooltips' { Apply-Lang; ([string]$ui.SzBC.ToolTip -ne '' -and [string]$ui.Time.ToolTip -ne '' -and [string]$miAdv.Header -ne '') }
    Smoke 'help explains readings' { $okh = $true; foreach ($q in 19, 20, 21, 22) { $state.lang = 'de'; if ((T ('b' + $q)) -notmatch 'Ursachen' -or (T ('b' + $q)).Length -lt 400) { $okh = $false }; $state.lang = 'en'; if ((T ('b' + $q)) -notmatch 'causes' -or (T ('b' + $q)).Length -lt 400) { $okh = $false } }; $state.lang = 'de'; $okh }
    Smoke 'help sections fold' { $state.demo = $true; Update-Widget; Build-Help; $okf = ($script:helpHeads.Count -eq 22); Set-HelpAll $false; $c1 = ($script:helpBodies[19].Visibility -eq 'Collapsed'); Toggle-HelpSection 19 $true; $o1 = ($script:helpBodies[19].Visibility -eq 'Visible'); Set-HelpAll $true; Set-HelpAll $false; ($okf -and $c1 -and $o1) }
    Smoke 'help live reading' { $state.demo = $true; Update-Widget; Build-Help; ([string]$script:helpTitles[19] -match 'ppm') }
    Smoke 'help jump from tile' { Show-HelpSection 20; $okj = ($script:helpOpen -and $script:helpBodies[20].Visibility -eq 'Visible'); $script:helpOpen = $false; Apply-View; $okj }
    Smoke 'real limits shown' { $state.lang = 'de'; ((T 'chip_tip_1') -match '1500' -and (T 'chip_tip_2') -match '20 ' -and (T 'chip_tip_3') -match '17' -and (T 'chip_tip_4') -match '30' -and (T 'spark_dust' 3) -match '20' -and (T 'spark_hum' 3) -match '30') }
    Smoke 'no errors logged' {
        $new = @(); if (Test-Path $logFile) { $new = @(Get-Content -Path $logFile -Encoding UTF8 | Select-Object -Skip $l0 | Where-Object { $_ -notmatch 'Start v' }) }
        foreach ($x in $new) { Write-Host ('      log: ' + $x) }
        ($new.Count -eq 0)
    }
    try { if ($script:lastExport) { Remove-Item $script:lastExport -Force } } catch {}
    try { $win.Close() } catch {}
    try { Close-Tray } catch {}
    try { $mutex.ReleaseMutex() } catch {}
    if ($script:smokeFail.Count -gt 0) { Write-Host ($script:smokeFail.Count.ToString() + ' smoke step(s) failed'); [Environment]::Exit(1) }
    Write-Host 'Smoke test passed'; [Environment]::Exit(0)
}
$timer.Start(); $pulseTimer.Start(); $saveTimer.Start(); $firstCheck.Start(); $checkTimer.Start()
Apply-Window
[void]$win.ShowDialog()
Exit-App

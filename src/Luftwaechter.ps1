# Luftwächter / Airguard – indoor air quality, ventilation advice, weather and room devices (Windows widget)
# Copyright (c) 2026 Dan Stasiak. Licensed under the MIT License (see LICENSE). SPDX-License-Identifier: MIT
# Source: https://github.com/DanStasiak/airguard-widget
param([switch]$Install, [switch]$Uninstall)

$appName = 'Luftwaechter'
$appVersion = '3.14.2'
$appDate = '22.11.2026'
$version = 'v' + $appVersion + ' · ' + $appDate
$repoOwner = 'DanStasiak'
$repoName = 'airguard-widget'
$repoUrl = 'https://github.com/' + $repoOwner + '/' + $repoName
$copyright = '© 2026 Dan Stasiak · MIT'
$installDir = Join-Path $env:LOCALAPPDATA $appName
$stateDir = Join-Path $env:APPDATA $appName
$startupLnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'Luftwaechter.lnk'

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
    if (Test-Path $sc) { Copy-Item -Force $sc $dc } elseif (-not (Test-Path $dc)) { Copy-Item -Force (Join-Path $src 'config.example.json') $dc }
    $sh = New-Object -ComObject WScript.Shell
    $lnk = $sh.CreateShortcut($startupLnk)
    $lnk.TargetPath = 'wscript.exe'
    $lnk.Arguments = '"' + (Join-Path $installDir 'Start.vbs') + '"'
    $lnk.WorkingDirectory = $installDir
    $lnk.Save()
    New-StartMenuShortcut
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
$mutex = New-Object System.Threading.Mutex($true, 'Local\LuftwaechterWidget', [ref]$created)
if (-not $created) { exit 0 }

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
$interval = 10
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
$state = @{ left = $null; top = $null; topmost = $false; topmostSet = $false; popup = $true; tray = $true; room = [string]$cfg.defaultRoom; size = 'M'; weatherOpen = $false; drawerOpen = $false; sound = $true; sparkHours = 3; lang = 'de'; hist = @{} }
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
        if ($s.sparkHours -eq 24) { $state.sparkHours = 24 }
        if ($s.lang -eq 'en' -or $s.lang -eq 'de') { $state.lang = [string]$s.lang }
        if ($s.hist) { foreach ($p in $s.hist.PSObject.Properties) { $state.hist[$p.Name] = @($p.Value) } }
    } catch {}
}

# ---------- Oberfläche ----------
$chipXaml = ''
for ($i = 1; $i -le 4; $i++) {
    $r = [Math]::Floor(($i - 1) / 2); $c = ($i - 1) % 2
    $chipXaml += @"
<Border Grid.Row="$r" Grid.Column="$c" CornerRadius="12" Background="#26FFFFFF" Margin="3" Padding="9,5">
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
    spark_tip = @('Tippen: 3 Std / 24 Std', 'Tap: 3 h / 24 h')
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
    setup_d = @('Rechtsklick, dann "Konfiguration öffnen", und den Server-Link (url) eintragen. Siehe Hilfe.', 'Right-click, then "Open configuration", and enter your server link (url). See Help.')
    m_cfg = @('Konfiguration öffnen', 'Open configuration')
    m_upd = @('Nach Updates suchen', 'Check for updates')
    upd_btn = @('⟳ Update', '⟳ Update')
    upd_new = @('⬆ {0} verfügbar', '⬆ {0} available')
    upd_title = @('Neue Version verfügbar', 'New version available')
    upd_sub = @('Installiert: {0}   ·   Neu: {1}', 'Installed: {0}   ·   New: {1}')
    upd_what = @('Das ist neu:', 'What is new:')
    upd_nonotes = @('(Keine Änderungsnotizen angegeben.)', '(No release notes provided.)')
    upd_yes = @('Jetzt aktualisieren', 'Update now')
    upd_no = @('Später', 'Later')
    upd_none = @('Du hast die neueste Version ({0}).', 'You are on the latest version ({0}).')
    upd_fail = @('Die Update-Suche hat nicht geklappt. Bitte später erneut versuchen.', 'The update check failed. Please try again later.')
    upd_dlfail = @('Das Update konnte nicht geladen oder geprüft werden. Es wurde nichts geändert.', 'The update could not be downloaded or verified. Nothing was changed.')
    upd_notinst = @('Updates funktionieren nur in der installierten Version. Bitte zuerst Installieren.bat ausführen.', 'Updates only work in the installed copy. Please run Installieren.bat first.')
    ver_tip = @('Version · Klick: alle Versionen auf GitHub', 'Version · click: all versions on GitHub')
    copy_tip = @('Freie Software (MIT) · Quellcode auf GitHub', 'Free software (MIT) · source code on GitHub')
    h12 = @('Über Luftwächter · freie Software', 'About Luftwächter · free software')
    b12 = @('Luftwächter ist freie Software unter der MIT-Lizenz: Du darfst es kostenlos nutzen, ändern und weitergeben. Der Hinweis auf den Urheber (Dan Stasiak) muss dabei erhalten bleiben. Quellcode, Änderungsliste (Changelog), Fehlermeldungen und Verbesserungsvorschläge: {0}', 'Luftwächter is free software under the MIT License: you may use, modify and share it free of charge. The notice crediting the author (Dan Stasiak) must be kept. Source code, changelog, bug reports and ideas: {0}')
    h13 = @('Updates', 'Updates')
    b13 = @('Der Knopf "⟳ Update" unten rechts fragt GitHub, ob es eine neuere Version gibt. Du siehst die Änderungen und entscheidest, ob aktualisiert wird. Danach tauscht sich das Programm selbst aus und startet neu. Deine Einstellungen und dein Zustand bleiben erhalten; die alte Version liegt als Sicherung im Programmordner. Alle paar Stunden wird still im Hintergrund geprüft, der Knopf wird dann grün.', 'The "⟳ Update" button at the bottom right asks GitHub whether a newer version exists. You see the changes and decide whether to update. The program then replaces itself and restarts. Your settings and state are kept; the old version is stored as a backup in the program folder. A silent check runs every few hours; the button then turns green.')
    h14 = @('Einrichtung (config.json)', 'Setup (config.json)')
    b14 = @('Rechtsklick, dann "Konfiguration öffnen". url = Server-Link zum Lesen der Daten, switchUrl = Server-Link zum Schalten (optional), defaultRoom = Startraum, place = Ort für die Wetterzeile, footer = Quellenhinweis, roomShort = Kurznamen der Räume. Nach dem Speichern das Programm per Rechtsklick beenden und neu starten.', 'Right-click, then "Open configuration". url = server link for reading data, switchUrl = server link for switching (optional), defaultRoom = start room, place = location for the weather row, footer = source note, roomShort = short room names. After saving, quit via right-click and start the program again.')
    help_title = @('Hilfe', 'Help')
    h1 = @('Wofür ist das?', 'What is this?')
    b1 = @('Luftwächter zeigt dir, wie gut die Luft in einem Raum ist, und sagt dir in einfachen Worten, ob du lüften sollst. Dazu kommen das Wetter draußen und die Geräte im Raum. Es zeigt alle Räume, die dein Server liefert.', 'Luftwächter shows how good the air in a room is and tells you in plain words whether you should ventilate. It also shows the weather outside and the devices in the room. It shows all rooms your server provides.')
    h2 = @('Farben und Ring', 'Colors and ring')
    b2 = @('Grün = gut, gelb = mittel, rot = schlecht. Die Farbe richtet sich nach dem schlechtesten der vier Messwerte. Der Ring zeigt den CO₂-Wert: je voller, desto besser. Grenzen: CO₂ unter 1000 ppm ist gut, bis 1500 mittel, darüber schlecht. Feinstaub unter 20 µg ist gut, bis 50 mittel. Temperatur 17–23 °C und Luftfeuchte 30–60 % sind gut. In allen Räumen gelten dieselben Grenzen.', 'Green = good, yellow = fair, red = poor. The color follows the worst of the four readings. The ring shows the CO₂ value: the fuller, the better. Limits: CO₂ below 1000 ppm is good, up to 1500 fair, above that poor. Fine dust below 20 µg is good, up to 50 fair. Temperature 17–23 °C and humidity 30–60 % are good. The same limits apply in every room.')
    h3 = @('Der Rat: lüften oder nicht', 'The advice: ventilate or not')
    b3 = @('Das große Feld sagt, was zu tun ist: Fenster öffnen, offen lassen, schließen oder noch warten (z. B. bei Unwetter). Ist das Fenster offen, zeigt ein Balken, wie lange noch gelüftet werden soll. In Räumen ohne Fensterkontakt tippst du auf das Feld: Dann startet ein Lüftungs-Timer, und am Ende kommt ein Ton. Nach dem Lüften steht kurz da, wie sich der CO₂-Wert verbessert hat. Nachts (22–7 Uhr) ist das Fenster abgedunkelt, und es gibt keinen Hinweiston.', 'The large panel tells you what to do: open the window, keep it open, close it, or wait a bit (for example during a storm). When the window is open, a bar shows how much longer to ventilate. In rooms without a window contact, tap the panel: a ventilation timer starts and a sound plays at the end. After ventilating, the panel briefly shows how the CO₂ value improved. At night (22:00–07:00) the window is dimmed and there is no alert sound.')
    h4 = @('Kurve, Trend und Tagesbilanz', 'Curve, trend and daily summary')
    b4 = @('Die Kurve zeigt den CO₂-Verlauf der letzten 3 Stunden; die Linie markiert 1000 ppm. Ein Tipp auf die Kurve wechselt zu 24 Stunden. Links daneben steht der Trend (steigt, sinkt, stabil) und, wenn möglich, eine Prognose, z. B. wann die Luft wieder gut ist. Die Tagesbilanz nennt Höchstwert, Durchschnitt und den Anteil der Zeit unter 1000 ppm. Die Werte werden auf deinem PC gesammelt und bleiben beim Neustart erhalten.', 'The curve shows the CO₂ history of the last 3 hours; the line marks 1000 ppm. Tap the curve to switch to 24 hours. The trend (rising, falling, steady) and, when possible, a forecast such as when the air will be good again, appear under the ring. The daily summary gives the peak, the average and the share of time below 1000 ppm. The data is collected on your PC and kept across restarts.')
    h5 = @('Die vier Messwerte', 'The four readings')
    b5 = @('CO₂ (ppm), Staub (Feinstaub PM2.5 in µg), Temperatur (°C) und Feuchte (%). Der Punkt vor jedem Wert zeigt seine Farbe.', 'CO₂ (ppm), dust (fine dust PM2.5 in µg), temperature (°C) and humidity (%). The dot in front of each value shows its color.')
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
function T([string]$k, $a = $null, $b = $null) {
    $idx = 0; if ($state.lang -eq 'en') { $idx = 1 }
    $s = $k; if ($script:Strings.ContainsKey($k)) { $s = [string]$script:Strings[$k][$idx] }
    if ($null -ne $a) { $s = $s.Replace('{0}', [string]$a) }
    if ($null -ne $b) { $s = $s.Replace('{1}', [string]$b) }
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
        <Border x:Name="TitleBox" HorizontalAlignment="Left" CornerRadius="14" Background="#33FFFFFF" Padding="14,4" Cursor="Hand">
          <StackPanel Orientation="Horizontal"><TextBlock x:Name="RoomName" Foreground="White" FontSize="30" FontWeight="Bold"/><TextBlock Text="  ▾" Foreground="#FFDFE5EE" FontSize="18" VerticalAlignment="Center"/></StackPanel>
        </Border>
        <DockPanel Margin="2,8,0,0">
          <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
            <TextBlock x:Name="SzS" Text="S" Foreground="#FFA9B4C4" FontSize="12" Cursor="Hand"/><TextBlock Text=" · " Foreground="#FFA9B4C4" FontSize="12"/>
            <TextBlock x:Name="SzM" Text="M" Foreground="#FFA9B4C4" FontSize="12" Cursor="Hand"/><TextBlock Text=" · " Foreground="#FFA9B4C4" FontSize="12"/>
            <TextBlock x:Name="SzL" Text="L" Foreground="#FFA9B4C4" FontSize="12" Cursor="Hand"/><TextBlock Text=" · " Foreground="#FFA9B4C4" FontSize="12"/>
            <TextBlock x:Name="SzC" Text="kompakt" Foreground="#FFA9B4C4" FontSize="12" Cursor="Hand"/><TextBlock Text=" · " Foreground="#FFA9B4C4" FontSize="12"/>
            <TextBlock x:Name="SzP" Text="Pille" Foreground="#FFA9B4C4" FontSize="12" Cursor="Hand"/>
          </StackPanel>
          <Border x:Name="BtnHelp" DockPanel.Dock="Left" Width="22" Height="22" CornerRadius="11" Background="#44FFFFFF" Cursor="Hand"><TextBlock Text="?" Foreground="White" FontSize="14" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
          <Border x:Name="BtnLang" DockPanel.Dock="Left" Height="22" CornerRadius="11" Background="#33FFFFFF" Padding="8,0" Margin="6,0,0,0" Cursor="Hand">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center"><TextBlock x:Name="LangDe" Text="DE" FontSize="12" Foreground="#FFA9B4C4"/><TextBlock Text=" | " FontSize="12" Foreground="#FFA9B4C4"/><TextBlock x:Name="LangEn" Text="EN" FontSize="12" Foreground="#FFA9B4C4"/></StackPanel>
          </Border>
          <TextBlock x:Name="Time" Foreground="#FFB4BFCE" FontSize="12" Margin="10,0,0,0" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
        </DockPanel>
      </StackPanel>
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
        <Border x:Name="Panel" Grid.Column="1" CornerRadius="16" Background="#26FFFFFF" Padding="12" Margin="4,0,0,0">
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
              <Border x:Name="BarTrack" Height="7" CornerRadius="4" Background="#33FFFFFF" Margin="0,8,0,0" Visibility="Collapsed"><Border x:Name="BarFill" HorizontalAlignment="Left" CornerRadius="4" Background="#FF2E9E5B" Width="0"/></Border>
            </StackPanel>
          </DockPanel>
        </Border>
      </Grid>
      <StackPanel x:Name="Details">
        <Grid Margin="0,10,0,0">
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
            <Border x:Name="WMore" DockPanel.Dock="Right" CornerRadius="10" Background="#33FFFFFF" Padding="10,4" Margin="8,0,0,0"><TextBlock x:Name="WMoreT" Text="▾ Mehr" Foreground="White" FontSize="12" FontWeight="SemiBold"/></Border>
            <TextBlock x:Name="WLineText" Foreground="#FFDFE5EE" FontSize="14" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
          </DockPanel>
        </Border>
        <Border x:Name="WFull" CornerRadius="16" Background="#4D3A5F8A" BorderBrush="#556D8FB8" BorderThickness="1" Padding="12,8" Margin="0,10,0,0" Visibility="Collapsed">
          <StackPanel>
            <DockPanel>
              <Border x:Name="WLess" DockPanel.Dock="Right" CornerRadius="10" Background="#33FFFFFF" Padding="10,3"><TextBlock x:Name="WLessT" Text="▴ Weniger" Foreground="White" FontSize="12" FontWeight="SemiBold"/></Border>
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
            <Border CornerRadius="10" Background="#33000000" Padding="10,6" Margin="3,6,3,0"><TextBlock x:Name="WTip" Foreground="White" FontSize="13" TextWrapping="Wrap"/></Border>
          </StackPanel>
        </Border>
        <DockPanel Margin="2,8,0,0"><TextBlock x:Name="Ver" Cursor="Hand" DockPanel.Dock="Right" Foreground="#FFB4BFCE" FontSize="11" FontWeight="SemiBold" Margin="8,0,0,0"/><TextBlock x:Name="Footer" Foreground="#FFA9B4C4" FontSize="11" TextTrimming="CharacterEllipsis"/></DockPanel>
        <DockPanel Margin="2,5,0,0">
          <Border x:Name="BtnUpd" DockPanel.Dock="Right" CornerRadius="9" Background="#33FFFFFF" Padding="9,2" Margin="8,0,0,0" Cursor="Hand"><TextBlock x:Name="BtnUpdT" Text="⟳ Update" Foreground="White" FontSize="11" FontWeight="SemiBold"/></Border>
          <TextBlock x:Name="Copy" Foreground="#FFA9B4C4" FontSize="11" Cursor="Hand" TextTrimming="CharacterEllipsis" VerticalAlignment="Center"/>
        </DockPanel>
      </StackPanel>
    </StackPanel>
  </Border>
  <Border x:Name="Help" Visibility="Collapsed" Width="427" CornerRadius="24" Background="#FF1B222D" BorderThickness="2" BorderBrush="#FF7A8594">
    <StackPanel Margin="18,14,14,14">
      <DockPanel><Border x:Name="HelpClose" DockPanel.Dock="Right" Width="26" Height="26" CornerRadius="13" Background="#33FFFFFF" Cursor="Hand"><TextBlock Text="✕" Foreground="White" FontSize="13" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
        <TextBlock x:Name="HelpTitle" Foreground="White" FontSize="24" FontWeight="Bold"/></DockPanel>
      <ScrollViewer x:Name="HelpScroll" MaxHeight="470" VerticalScrollBarVisibility="Auto" Margin="0,8,0,0"><StackPanel x:Name="HelpBody" Margin="0,0,10,0"/></ScrollViewer>
      <TextBlock x:Name="HelpVer" Foreground="#FFA9B4C4" FontSize="11" Margin="0,8,0,0"/>
    </StackPanel>
  </Border>
  <Border x:Name="Tab" Width="28" Height="120" CornerRadius="0,16,16,0" Background="#FF2A3342" BorderThickness="0,2,2,2" BorderBrush="#FF7A8594" Margin="-2,0,0,0" VerticalAlignment="Center" Cursor="Hand">
    <TextBlock Text="›" Foreground="White" FontSize="24" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/>
  </Border>
  <Border x:Name="Drawer" Width="340" CornerRadius="0,24,24,0" Background="#FF1B222D" BorderThickness="0,2,2,2" BorderBrush="#FF7A8594" Margin="-2,0,0,0" Visibility="Collapsed">
    <StackPanel Margin="16,14,16,12">
      <DockPanel><Border x:Name="DrawerClose" DockPanel.Dock="Right" CornerRadius="10" Background="#33FFFFFF" Padding="10,0" Cursor="Hand"><TextBlock Text="‹" Foreground="White" FontSize="22" FontWeight="Bold"/></Border>
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
$names = @('Scaler', 'Card', 'Ver', 'RoomStrip', 'SparkBox', 'SparkLabel', 'Glow', 'TitleBox', 'RoomName', 'Time', 'SzS', 'SzM', 'SzL', 'SzC', 'SzP', 'BtnHelp', 'BtnLang', 'LangDe', 'LangEn', 'WMoreT', 'WLessT', 'WTitleT', 'Help', 'HelpClose', 'HelpTitle', 'HelpScroll', 'HelpBody', 'HelpVer', 'BtnUpd', 'BtnUpdT', 'Copy', 'Pill', 'PillDot', 'PillText', 'Arc', 'Face', 'Level', 'Trend', 'Panel', 'IcClosed', 'IcOpen', 'Headline', 'Detail', 'BarTrack', 'BarFill', 'Details', 'Spark', 'SparkR', 'Peak', 'WLine', 'WMore', 'WLineText', 'WFull', 'WLess', 'WIcon', 'WTemp', 'WCond', 'WTip', 'Footer', 'Tab', 'Drawer', 'DrawerClose', 'DrawerTitle', 'DevPanel')
for ($i = 1; $i -le 4; $i++) { $names += @("D$i", "V$i", "K$i", "WK$i", "WV$i") }
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
        $win.Topmost = $true; $win.Activate() | Out-Null
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
        if ($tip.Length -gt 62) { $tip = $tip.Substring(0, 61) + '…' }
        $script:tray.Text = $tip
        $h = (Get-Date).Hour
        if ($null -ne $script:lastAction -and $act -ne $script:lastAction -and ($act -eq 'oeffnen' -or $act -eq 'schliessen') -and $h -ge 7 -and $h -lt 22 -and (((Get-Date) - $script:lastBalloon).TotalMinutes -gt 30)) {
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
        $o = @{ left = $win.Left; top = $win.Top; topmost = $state.topmost; topmostSet = $state.topmostSet; popup = $state.popup; tray = $state.tray; room = $state.room; size = $state.size; weatherOpen = $state.weatherOpen; drawerOpen = $state.drawerOpen; sound = $state.sound; sparkHours = $state.sparkHours; lang = $state.lang; hist = $state.hist }
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
    if (-not $switchUrl) { return }
    try {
        $json = $body | ConvertTo-Json -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $req = [System.Net.HttpWebRequest]::Create($switchUrl)
        $req.Method = 'POST'; $req.ContentType = 'application/json; charset=utf-8'
        $req.Timeout = 8000; $req.ReadWriteTimeout = 8000
        $req.ContentLength = $bytes.Length
        $st = $req.GetRequestStream(); $st.Write($bytes, 0, $bytes.Length); $st.Close()
        $resp = $req.GetResponse(); $resp.Close()
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
function Add-Hist([string]$room, $co2) {
    if ($null -eq $co2) { return }
    $now = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $arr = @()
    if ($state.hist.ContainsKey($room)) { $arr = @($state.hist[$room]) }
    $lastTs = 0
    if ($arr.Count -gt 0) { $lastTs = [int]($arr[$arr.Count - 1].Split(':')[0]) }
    if (($now - $lastTs) -ge 60) {
        $arr += ('{0}:{1}' -f $now, [int]$co2)
        $cut = $now - 24 * 3600
        $arr = @($arr | Where-Object { [int]($_.Split(':')[0]) -ge $cut })
        $state.hist[$room] = $arr
    }
}

function Show-Spark([string]$room, [string]$col) {
    $ui.Spark.Children.Clear()
    $ui.SparkLabel.Text = (T 'spark' $state.sparkHours)
    $arr = @()
    if ($state.hist.ContainsKey($room)) { $arr = @($state.hist[$room]) }
    $w = 205.0; $h = 62.0
    $now = [double]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
    $pts = @(); $maxv = 1600.0; $minv = 400.0
    foreach ($e in $arr) { $p = $e.Split(':'); $pts += , @([double]$p[0], [double]$p[1]); if ([double]$p[1] -gt $maxv) { $maxv = [double]$p[1] } }
    $yOf = { param($v) $h - 4 - (($v - $minv) / ($maxv - $minv)) * ($h - 8) }
    $ln = New-Object Windows.Shapes.Line
    $y1 = & $yOf 1000
    $ln.X1 = 0; $ln.X2 = $w; $ln.Y1 = $y1; $ln.Y2 = $y1
    $ln.Stroke = Brush '#55FFFFFF'; $ln.StrokeThickness = 1; $dc = New-Object Windows.Media.DoubleCollection; $dc.Add(3.0); $dc.Add(4.0); $ln.StrokeDashArray = $dc
    [void]$ui.Spark.Children.Add($ln)
    if ($pts.Count -ge 2) {
        $poly = New-Object Windows.Shapes.Polygon
        $pc = New-Object Windows.Media.PointCollection
        $x0 = 0
        foreach ($p in $pts) {
            $x = $w - (($now - $p[0]) / ([double]$state.sparkHours * 3600.0)) * $w
            if ($x -lt 0) { continue }
            $pc.Add((New-Object Windows.Point($x, (& $yOf $p[1]))))
        }
        $lastX = $pc[$pc.Count - 1].X; $firstX = $pc[0].X
        $line = New-Object Windows.Shapes.Polyline
        $line.Points = $pc; $line.Stroke = Brush $col; $line.StrokeThickness = 2.2; $line.StrokeLineJoin = 'Round'
        $fillPc = New-Object Windows.Media.PointCollection
        $fillPc.Add((New-Object Windows.Point($firstX, $h)))
        foreach ($q in $pc) { $fillPc.Add($q) }
        $fillPc.Add((New-Object Windows.Point($lastX, $h)))
        $poly.Points = $fillPc; $poly.Fill = Brush ('#40' + $col.Substring($col.Length - 6))
        [void]$ui.Spark.Children.Add($poly); [void]$ui.Spark.Children.Add($line)
    }
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
    $b.Background = Brush '#33FFFFFF'; $b.CornerRadius = New-Object Windows.CornerRadius(9)
    $b.Padding = New-Object Windows.Thickness(10, 4, 10, 4); $b.Margin = New-Object Windows.Thickness(3, 0, 0, 0); $b.Cursor = 'Hand'
    $b.Child = (New-Text $t 14 '#FFFFFFFF' $true)
    $b.Tag = $tag
    $b.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; $c = @{ room = $state.room; entity = $s.Tag.e; action = $s.Tag.a }; if ($null -ne $s.Tag.v) { $c.value = $s.Tag.v }; Send-Command $c })
    return $b
}

function Build-Devices($devs) {
    $ui.DevPanel.Children.Clear()
    $groups = @('Licht', 'Strom', 'Heizung', 'Rollo')
    $gIcon = @{ Licht = ([char]::ConvertFromUtf32(0x1F4A1)); Strom = ([char]::ConvertFromUtf32(0x1F50C)); Heizung = ([char]::ConvertFromUtf32(0x1F321)); Rollo = ([char]::ConvertFromUtf32(0x1FA9F)) }
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
            $row.Background = Brush '#1FFFFFFF'; $row.CornerRadius = New-Object Windows.CornerRadius(14)
            $row.Padding = New-Object Windows.Thickness(10, 6, 10, 6); $row.Margin = New-Object Windows.Thickness(0, 2, 0, 2)
            $dp = New-Object Windows.Controls.DockPanel
            $row.Child = $dp
            $entity = [string]$dv.entity
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
            if ($ctl) { [Windows.Controls.DockPanel]::SetDock($ctl, 'Right'); $ctl.VerticalAlignment = 'Center'; if ((-not $switchUrl) -and ([string]$dv.type -ne 'meter')) { $ctl.Opacity = 0.35; $ctl.IsEnabled = $false } ; [void]$dp.Children.Add($ctl) }
            $sp2 = New-Object Windows.Controls.StackPanel; $sp2.VerticalAlignment = 'Center'
            [void]$sp2.Children.Add((New-Text ([string]$dv.name) 14 '#FFFFFFFF' $false))
            if ($dv.detail) { [void]$sp2.Children.Add((New-Text ([string]$dv.detail) 11 '#FFB3BECD' $false)) }
            [void]$dp.Children.Add($sp2)
            [void]$ui.DevPanel.Children.Add($row)
        }
    }
    if (-not $any) {
        $t = New-Text (T 'no_dev') 13 '#FFB3BECD' $false
        $t.TextWrapping = 'Wrap'; $t.Margin = New-Object Windows.Thickness(0, 12, 0, 0)
        [void]$ui.DevPanel.Children.Add($t)
    }
    if (-not $switchUrl) {
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
        if ($key -eq [string]$state.room) { $pill.Background = Brush '#55FFFFFF'; $pill.BorderBrush = Brush '#FFFFFFFF' }
        else { $pill.Background = Brush '#26FFFFFF'; $pill.BorderBrush = Brush '#00FFFFFF' }
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
        $pill.Add_MouseLeftButtonDown({ param($s2, $e2) $e2.Handled = $true; $state.room = [string]$s2.Tag; $script:ventEnd = $null; $script:prevOpen = $null; $script:sumText = ''; $script:lastAction = $null; $script:devSig = ''; $script:openSince = $null; Save-State; Update-Widget })
        [void]$ui.RoomStrip.Children.Add($pill)
    }
}

# ---------- Ansicht ----------
function Apply-View {
    $scale = 1.0
    switch ($state.size) { 'S' { $scale = 0.82 } 'L' { $scale = 1.2 } default { $scale = 1.0 } }
    $ui.Scaler.LayoutTransform = New-Object Windows.Media.ScaleTransform($scale, $scale)
    $ui.Ver.Text = $version
    if ($state.drawerOpen -and -not ($state.size -eq 'C')) { $ui.Card.CornerRadius = New-Object Windows.CornerRadius(24, 0, 0, 24) } else { $ui.Card.CornerRadius = New-Object Windows.CornerRadius(24) }
    foreach ($k in 'S', 'M', 'L', 'C', 'P') { $ui.('Sz' + $k).Foreground = Brush '#FFA9B4C4'; $ui.('Sz' + $k).FontWeight = 'Normal' }
    $ui.('Sz' + $state.size).Foreground = Brush '#FFFFFFFF'; $ui.('Sz' + $state.size).FontWeight = 'Bold'
    $script:compact = ($state.size -eq 'C' -or $state.size -eq 'P')
    if ($state.size -eq 'P') { $ui.Card.Visibility = 'Collapsed'; $ui.Pill.Visibility = 'Visible' } else { $ui.Card.Visibility = 'Visible'; $ui.Pill.Visibility = 'Collapsed' }
    if ($script:compact) { $ui.Details.Visibility = 'Collapsed'; $ui.Detail.Visibility = 'Collapsed'; $ui.Drawer.Visibility = 'Collapsed'; $ui.Tab.Visibility = 'Collapsed' }
    else {
        $ui.Details.Visibility = 'Visible'; $ui.Detail.Visibility = 'Visible'
        if ($state.weatherOpen) { $ui.WLine.Visibility = 'Collapsed'; $ui.WFull.Visibility = 'Visible' } else { $ui.WLine.Visibility = 'Visible'; $ui.WFull.Visibility = 'Collapsed' }
        if ($state.drawerOpen) { $ui.Drawer.Visibility = 'Visible'; $ui.Tab.Visibility = 'Collapsed' } else { $ui.Drawer.Visibility = 'Collapsed'; $ui.Tab.Visibility = 'Visible' }
    }
    if ($script:helpOpen) { $ui.Help.Visibility = 'Visible'; $ui.Card.Visibility = 'Collapsed'; $ui.Pill.Visibility = 'Collapsed'; $ui.Drawer.Visibility = 'Collapsed'; $ui.Tab.Visibility = 'Collapsed' } else { $ui.Help.Visibility = 'Collapsed' }
    if ($scale -eq 1.0) { [System.Windows.Media.TextOptions]::SetTextFormattingMode($win, [System.Windows.Media.TextFormattingMode]::Display) } else { [System.Windows.Media.TextOptions]::SetTextFormattingMode($win, [System.Windows.Media.TextFormattingMode]::Ideal) }
    $win.UpdateLayout()
    # Bildschirmgrenzen über alle Monitore (nicht nur den Hauptmonitor)
    $vl = [System.Windows.SystemParameters]::VirtualScreenLeft; $vt = [System.Windows.SystemParameters]::VirtualScreenTop
    $vr = $vl + [System.Windows.SystemParameters]::VirtualScreenWidth; $vb = $vt + [System.Windows.SystemParameters]::VirtualScreenHeight
    if ($win.Left + $win.ActualWidth -gt $vr) { $win.Left = [Math]::Max($vl, $vr - $win.ActualWidth - 6) }
    if ($win.Top + $win.ActualHeight -gt $vb) { $win.Top = [Math]::Max($vt, $vb - $win.ActualHeight - 6) }
}

function Show-Data($d) {
    $script:rooms = @($d.rooms)
    Build-Strip
    if (-not $state.room -and $d.room.key) { $state.room = [string]$d.room.key }
    $col = [string]$d.color
    $b = Brush $col
    $ui.Card.BorderBrush = $b
    $ui.Tab.BorderBrush = $b; $ui.Drawer.BorderBrush = $b
    $ui.Glow.Color = ([Windows.Media.ColorConverter]::ConvertFromString($col))
    $ui.Card.Background = New-Object Windows.Media.LinearGradientBrush ((([Windows.Media.ColorConverter]::ConvertFromString((Blend $col '#1B222D' 0.22)))), ([Windows.Media.ColorConverter]::ConvertFromString('#FF1B222D')), 90)
    $ui.Drawer.Background = Brush '#FF1B222D'
    $ui.Panel.Background = Brush ('#33' + $col.Substring($col.Length - 6))
    $ui.Level.Foreground = $b
    $ui.RoomName.Text = [string]$d.room.name
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
    Add-Hist ([string]$d.room.key) $co2
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
                if ($state.sound) { try { [System.Media.SystemSounds]::Exclamation.Play() } catch {} }
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
    } else { $ui.WLineText.Text = (T 'w_na'); $ui.WTip.Text = '' }

    $ui.Time.Text = [string]$d.updated
    $ui.Footer.Text = (Get-FooterText)

    # Geräte nur neu bauen, wenn sich etwas geändert hat
    $sig = (@($d.devices) | ForEach-Object { [string]$_.entity + ':' + [string]$_.state + ':' + [string]$_.target + ':' + [string]$_.detail }) -join '|'
    $sig = [string]$d.room.key + '#' + $sig
    if ($sig -ne $script:devSig) { $script:devSig = $sig; Build-Devices @($d.devices) }

    $script:pulse = ([string]$d.action -eq 'oeffnen')
    # sanfter Hinweiston, wenn sich der Rat ändert (nicht nachts, höchstens alle 30 Min)
    $act = [string]$d.action
    $h = (Get-Date).Hour
    if ($state.sound -and $null -ne $script:lastAction -and $act -ne $script:lastAction -and ($act -eq 'oeffnen' -or $act -eq 'schliessen') -and $h -ge 7 -and $h -lt 22 -and (((Get-Date) - $script:lastChime).TotalMinutes -gt 30)) {
        try { [System.Media.SystemSounds]::Asterisk.Play() } catch {}
        $script:lastChime = Get-Date
    }
    if ($state.popup -and -not $state.topmost -and $null -ne $script:lastAction -and $act -ne $script:lastAction -and ($act -eq 'oeffnen' -or $act -eq 'schliessen') -and $h -ge 7 -and $h -lt 22 -and (((Get-Date) - $script:lastPop).TotalMinutes -gt 30)) {
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
    $ui.Panel.Background = Brush '#33FFFFFF'; $ui.Headline.Text = (T 'setup'); $ui.Detail.Text = (T 'setup_d')
    $ui.RoomName.Text = 'Luftwächter'; $ui.Time.Text = ''; $script:pulse = $false
}

function Update-Widget {
    if ($url -notmatch '^https?://') { Show-Setup; return }
    try {
        $u = $url
        if ($u.Contains('?')) { $u += '&' } else { $u += '?' }
        $u += 'room=' + [Uri]::EscapeDataString([string]$state.room) + '&lang=' + [string]$state.lang
        $d = Get-Json $u
        $script:fails = 0
        $script:last = $d
        Show-Data $d
    } catch {
        Write-Log ('Aktualisieren: ' + $_.Exception.Message + ' @' + $_.InvocationInfo.ScriptLineNumber)
        $script:fails++
        if ($script:fails -ge 3) {
            $g = Brush $grey
            $ui.Card.BorderBrush = $g
            $ui.Level.Text = (T 'offline'); $ui.PillText.Text = (T 'offline'); $ui.PillDot.Foreground = $g; $ui.Level.Foreground = $g
            $ui.Face.Text = [char]::ConvertFromUtf32(0x1F50C)
            Set-Ring 0.06 $g
            $ui.Panel.Background = Brush '#33FFFFFF'
            $ui.Headline.Text = (T 'no_conn')
            $script:pulse = $false
            if ($script:last) { $ui.Detail.Text = (T 'stale'); $ui.Time.Text = (T 'asof') + [string]$script:last.updated }
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
$win.Add_MouseLeftButtonDown({ param($s, $e) if ($e.ClickCount -eq 2) { Update-Widget } else { try { $win.DragMove(); Save-State } catch {} } })

foreach ($k in 'S', 'M', 'L', 'C', 'P') {
    $ui.('Sz' + $k).Tag = $k
    $ui.('Sz' + $k).Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; if ([string]$s.Tag -eq 'P' -and $state.size -ne 'P') { $script:prevSize = $state.size }; $state.size = [string]$s.Tag; Apply-View; Save-State })
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
$ui.SparkBox.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; if ($state.sparkHours -eq 3) { $state.sparkHours = 24 } else { $state.sparkHours = 3 }; if ($script:last) { Show-Data $script:last }; Save-State })
$ui.Tab.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; $state.drawerOpen = $true; Apply-View; Save-State })
$ui.DrawerClose.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; $state.drawerOpen = $false; Apply-View; Save-State })

$ui.TitleBox.Add_MouseLeftButtonDown({
    param($s, $e)
    $e.Handled = $true
    $m = New-Object Windows.Controls.ContextMenu
    foreach ($r in $script:rooms) {
        $mi = New-Object Windows.Controls.MenuItem
        $dot = New-Object Windows.Shapes.Ellipse; $dot.Width = 11; $dot.Height = 11
        $c = '#FF7A8594'; if ($r.color) { $c = [string]$r.color }
        $dot.Fill = Brush $c
        $mi.Icon = $dot
        $txt = [string]$r.name
        if ($r.co2) { $txt += '    CO₂ ' + [string]$r.co2 }
        $mi.Header = $txt
        $mi.FontSize = 15
        if ([string]$r.key -eq [string]$state.room) { $mi.FontWeight = 'Bold' }
        $mi.Tag = [string]$r.key
        $mi.Add_Click({ param($s2, $e2) $state.room = [string]$s2.Tag; $script:ventEnd = $null; $script:prevOpen = $null; $script:sumText = ''; $script:lastAction = $null; $script:devSig = ''; $script:openSince = $null; Save-State; Update-Widget })
        [void]$m.Items.Add($mi)
    }
    if ($m.Items.Count -eq 0) { $mi = New-Object Windows.Controls.MenuItem; $mi.Header = (T 'rooms_loading'); $mi.IsEnabled = $false; [void]$m.Items.Add($mi) }
    $m.PlacementTarget = $ui.TitleBox; $m.Placement = 'Bottom'; $m.IsOpen = $true
})

$menu = New-Object System.Windows.Controls.ContextMenu
$miRefresh = New-Object System.Windows.Controls.MenuItem; $miRefresh.Header = 'Jetzt aktualisieren'
$miPop = New-Object System.Windows.Controls.MenuItem; $miPop.IsCheckable = $true; $miPop.IsChecked = [bool]$state.popup
$miTop = New-Object System.Windows.Controls.MenuItem; $miTop.Header = 'Immer im Vordergrund'; $miTop.IsCheckable = $true; $miTop.IsChecked = [bool]$state.topmost
$miLog = New-Object System.Windows.Controls.MenuItem; $miLog.Header = 'Protokoll öffnen (bei Problemen)'
$miReset = New-Object System.Windows.Controls.MenuItem; $miReset.Header = 'Fenster zurücksetzen (oben rechts)'
$miSound = New-Object System.Windows.Controls.MenuItem; $miSound.Header = 'Hinweiston beim Lüften'; $miSound.IsCheckable = $true; $miSound.IsChecked = [bool]$state.sound
$miTray = New-Object System.Windows.Controls.MenuItem; $miTray.IsCheckable = $true; $miTray.IsChecked = [bool]$state.tray
$miHelp = New-Object System.Windows.Controls.MenuItem
$miUpd = New-Object System.Windows.Controls.MenuItem
$miCfg = New-Object System.Windows.Controls.MenuItem
$miExit = New-Object System.Windows.Controls.MenuItem
$miRefresh.Add_Click({ Update-Widget })
$miTop.Add_Click({ $state.topmost = [bool]$miTop.IsChecked; $state.topmostSet = $true; $win.Topmost = $state.topmost; Save-State })
$miTray.Add_Click({ $state.tray = [bool]$miTray.IsChecked; if ($script:tray) { $script:tray.Visible = $state.tray }; Save-State })
$miPop.Add_Click({ $state.popup = [bool]$miPop.IsChecked; Save-State })
$miLog.Add_Click({ try { if (-not (Test-Path $logFile)) { Set-Content -Path $logFile -Value (T 'no_errors') -Encoding UTF8 }; Start-Process notepad.exe -ArgumentList ('"' + $logFile + '"') } catch {} })
$miReset.Add_Click({ $w0 = [System.Windows.SystemParameters]::WorkArea; $win.Left = [Math]::Max($w0.Left, $w0.Right - $win.ActualWidth - 20); $win.Top = $w0.Top + 20; Save-State })
$miSound.Add_Click({ $state.sound = $miSound.IsChecked; Save-State })
$miExit.Add_Click({ Exit-App })
$miHelp.Add_Click({ $script:helpOpen = $true; Apply-View })
$miCfg.Add_Click({ try { if (-not (Test-Path $cfgFile)) { Copy-Item (Join-Path $dir 'config.example.json') $cfgFile }; Start-Process notepad.exe -ArgumentList ('"' + $cfgFile + '"') } catch { Write-Log ('Konfig: ' + $_.Exception.Message) } })
$miUpd.Add_Click({ Invoke-UpdateFlow $true })
[void]$menu.Items.Add($miRefresh); [void]$menu.Items.Add($miTop); [void]$menu.Items.Add($miPop); [void]$menu.Items.Add($miTray); [void]$menu.Items.Add($miSound); [void]$menu.Items.Add($miReset); [void]$menu.Items.Add($miLog); [void]$menu.Items.Add($miHelp); [void]$menu.Items.Add($miCfg); [void]$menu.Items.Add($miUpd); [void]$menu.Items.Add((New-Object System.Windows.Controls.Separator)); [void]$menu.Items.Add($miExit)
$win.ContextMenu = $menu


# ---------- Sprache / Hilfe ----------
function Get-FooterText { if ($footerCfg) { return $footerCfg }; return (T 'footer') }
function Build-Help {
    $ui.HelpBody.Children.Clear()
    for ($i = 1; $i -le 15; $i++) {
        $h = New-Text (T ('h' + $i)) 15 '#FFFFFFFF' $true
        $h.Margin = New-Object Windows.Thickness(0, 10, 0, 2)
        $bk = 'b' + $i; $bt = $(if ($i -eq 12) { T $bk $repoUrl } else { T $bk }); $b = New-Text $bt 13 '#FFDFE5EE' $false
        $b.TextWrapping = 'Wrap'
        [void]$ui.HelpBody.Children.Add($h); [void]$ui.HelpBody.Children.Add($b)
    }
    $ui.HelpTitle.Text = (T 'help_title') + ' · Luftwächter'
    $ui.HelpVer.Text = $version + '  ·  ' + $copyright
}
function Apply-Lang {
    $ui.SzC.Text = (T 'sz_c'); $ui.SzP.Text = (T 'sz_p')
    $ui.WMoreT.Text = (T 'more'); $ui.WLessT.Text = (T 'less'); $ui.WTitleT.Text = (T 'outside') + $(if ($place) { ' · ' + $place.ToUpper() } else { '' })
    $ui.SparkR.Text = (T 'now'); $ui.SparkBox.ToolTip = (T 'spark_tip'); $ui.Pill.ToolTip = (T 'pill_tip')
    $ui.BtnHelp.ToolTip = (T 'help_tip'); $ui.BtnLang.ToolTip = (T 'lang_tip')
    foreach ($k in 'De', 'En') { $ui.('Lang' + $k).Foreground = Brush '#FFA9B4C4'; $ui.('Lang' + $k).FontWeight = 'Normal' }
    if ($state.lang -eq 'en') { $ui.LangEn.Foreground = Brush '#FFFFFFFF'; $ui.LangEn.FontWeight = 'Bold' } else { $ui.LangDe.Foreground = Brush '#FFFFFFFF'; $ui.LangDe.FontWeight = 'Bold' }
    $miRefresh.Header = (T 'm_refresh'); $miTop.Header = (T 'm_top'); $miPop.Header = (T 'm_pop'); $miTray.Header = (T 'm_tray'); if ($script:trayMiOpen) { $script:trayMiOpen.Text = (T 'tray_open'); $script:trayMiExit.Text = (T 'm_exit') }; $miSound.Header = (T 'm_sound'); $miReset.Header = (T 'm_reset'); $miLog.Header = (T 'm_log'); $miHelp.Header = (T 'm_help'); $miCfg.Header = (T 'm_cfg'); $miUpd.Header = (T 'm_upd'); $miExit.Header = (T 'm_exit')
    $ui.Footer.Text = (Get-FooterText)
    $ui.Copy.Text = $copyright + ' · GitHub'; $ui.Copy.ToolTip = (T 'copy_tip'); $ui.Ver.ToolTip = (T 'ver_tip')
    Set-UpdateButton
    Build-Help
    $script:devSig = ''
    if ($script:last) { Show-Data $script:last }
}

$ui.BtnHelp.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; $script:helpOpen = $true; Apply-View })
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
    else { $ui.BtnUpdT.Text = (T 'upd_btn'); $ui.BtnUpd.Background = Brush '#33FFFFFF' }
}
function Get-LatestRelease {
    $api = 'https://api.github.com/repos/' + $repoOwner + '/' + $repoName + '/releases/latest'
    return (Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'Luftwaechter-Updater'; 'Accept' = 'application/vnd.github+json' } -TimeoutSec 10)
}
function Test-Newer([string]$remote, [string]$local) {
    try { return ([version]$remote.TrimStart('v')) -gt ([version]$local) } catch { return $false }
}
function Show-UpdateDialog($rel, [string]$remote) {
    $x = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Luftwächter" Width="470" SizeToContent="Height" MaxHeight="640" WindowStartupLocation="CenterScreen" Topmost="True" ResizeMode="NoResize" Background="#FF1B222D" FontFamily="Segoe UI">
  <StackPanel Margin="22">
    <TextBlock x:Name="UTitle" Foreground="White" FontSize="21" FontWeight="Bold" TextWrapping="Wrap"/>
    <TextBlock x:Name="USub" Foreground="#FFB3BECD" FontSize="13" Margin="0,4,0,12"/>
    <TextBlock x:Name="UWhat" Foreground="White" FontSize="13" FontWeight="SemiBold"/>
    <Border Background="#33000000" CornerRadius="8" Margin="0,4,0,16" Padding="10"><ScrollViewer MaxHeight="280" VerticalScrollBarVisibility="Auto"><TextBlock x:Name="UBody" Foreground="#FFDFE5EE" FontSize="12.5" TextWrapping="Wrap"/></ScrollViewer></Border>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right"><Button x:Name="UNo" Padding="16,6" Margin="0,0,8,0"/><Button x:Name="UYes" Padding="16,6" IsDefault="True"/></StackPanel>
  </StackPanel>
</Window>
"@
    $d = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$x)))
    $d.FindName('UTitle').Text = (T 'upd_title')
    $d.FindName('USub').Text = (T 'upd_sub' ('v' + $appVersion) ('v' + $remote))
    $d.FindName('UWhat').Text = (T 'upd_what')
    $body = ([string]$rel.body).Trim(); if (-not $body) { $body = (T 'upd_nonotes') }
    $d.FindName('UBody').Text = $body
    $d.FindName('UNo').Content = (T 'upd_no'); $d.FindName('UYes').Content = (T 'upd_yes')
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
        $remote = ([string]$rel.tag_name).TrimStart('v')
        if (Test-Newer $remote $appVersion) {
            $script:newVer = $remote; Set-UpdateButton
            if ($manual) { if (Show-UpdateDialog $rel $remote) { Start-Update $rel } }
        } else {
            $script:newVer = $null; Set-UpdateButton
            if ($manual) { [void][System.Windows.MessageBox]::Show((T 'upd_none' ('v' + $appVersion)), 'Luftwächter', 'OK', 'Information') }
        }
    } catch {
        Write-Log ('Update-Suche: ' + $_.Exception.Message)
        if ($manual) { [void][System.Windows.MessageBox]::Show((T 'upd_fail'), 'Luftwächter', 'OK', 'Warning') }
    }
}
$ui.BtnUpd.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; Invoke-UpdateFlow $true })
$ui.Copy.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; try { Start-Process $repoUrl } catch {} })
$ui.Ver.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; try { Start-Process ($repoUrl + '/releases') } catch {} })

# ---------- Takt: Aktualisieren, Pulsieren, Nachtmodus, Speichern ----------
$script:pulse = $false
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds($interval)
$timer.Add_Tick({ Update-Widget })

$pulseTimer = New-Object System.Windows.Threading.DispatcherTimer
$pulseTimer.Interval = [TimeSpan]::FromMilliseconds(1000)
$pulseTimer.Add_Tick({
    $h = (Get-Date).Hour
    if ($h -ge 22 -or $h -lt 7) { $win.Opacity = 0.62 } else { $win.Opacity = 1.0 }
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
$checkTimer.Interval = [TimeSpan]::FromHours(6)
$checkTimer.Add_Tick({ Invoke-UpdateFlow $false })

$win.Add_Closing({ Save-State; $timer.Stop(); $pulseTimer.Stop(); $saveTimer.Stop(); $firstCheck.Stop(); $checkTimer.Stop(); Close-Tray })
if ($dir -eq $installDir -and -not (Test-Path $startMenuLnk)) { New-StartMenuShortcut }
Init-Tray
Apply-Lang
Apply-View
Write-Log ('Start ' + $version)
Update-Widget
$timer.Start(); $pulseTimer.Start(); $saveTimer.Start(); $firstCheck.Start(); $checkTimer.Start()
[void]$win.ShowDialog()
Exit-App

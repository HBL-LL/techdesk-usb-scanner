# Relève la fiche technique complète de ce laptop Windows, l'ajoute au journal de la clé (journal-des-scans.csv)
# et l'envoie à TechDesk (POST /api/v1/products/specs), qui l'affiche sur le produit ayant ce numéro de série.
# N'ajoute rien au stock : c'est SCAN-WINDOWS.cmd qui le fait, avant ou après. Sans internet, la fiche part au
# prochain envoi fait avec internet. Compatible Windows PowerShell 5.1 (aussi à l'écran d'installation de
# Windows, via Maj+F10).
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$dir = Split-Path -Parent $PSScriptRoot
$log = Join-Path $dir 'journal-des-scans.csv'

# Chaque lecture est facultative : si une info manque, la fiche est quand même enregistrée
function Safe([scriptblock]$block) { try { & $block } catch { $null } }
function First($items) { @($items) | Select-Object -First 1 }
function Size([double]$bytes) {
    $gb = [math]::Round($bytes / 1e9)
    if ($gb -ge 1000) { return ('{0} To' -f ([math]::Round($gb / 1000, 1))).Replace('.', ',') }
    return "$gb Go"
}

# ---- Nom ----
$cs = First (Safe { Get-CimInstance Win32_ComputerSystem })
$csp = First (Safe { Get-CimInstance Win32_ComputerSystemProduct })
$bios = First (Safe { Get-CimInstance Win32_BIOS })
$maker = "$($cs.Manufacturer)".Trim()
$model = "$($cs.Model)".Trim()
$version = "$($csp.Version)".Trim()
switch -regex ($maker) {
    '^LENOVO' { $maker = 'Lenovo' }
    '^ASUS' { $maker = 'ASUS' }
    '^Dell' { $maker = 'Dell' }
    '^(HP|Hewlett)' { $maker = 'HP' }
    '^Micro-Star' { $maker = 'MSI' }
    '^Acer' { $maker = 'Acer' }
    '^Microsoft' { $maker = 'Microsoft' }
}
if ($maker -eq 'Lenovo' -and $version) {
    # Chez Lenovo, Model est la référence (21KC0011FR) et Version le nom (ThinkPad X1 Carbon Gen 12)
    $name = "Lenovo $version"
    $ref = $model
} else {
    $name = ("$maker " + ($model -replace "^$([regex]::Escape($maker))\s*", '')).Trim()
    $ref = "$($cs.SystemSKUNumber)".Trim()
}
$serial = "$($bios.SerialNumber)".Trim()

# ---- Couleur du boîtier ----
$color = ''
$rawChassis = "$($cs.Model) $($csp.Version) $($cs.SystemSKUNumber)"
switch -regex ($rawChassis) {
    '(?i)\b(space\s*black|noir\s*sid[eé]ral)\b' { $color = 'Noir sidéral'; break }
    '(?i)\b(space\s*gr[ae]y|gris\s*sid[eé]ral)\b' { $color = 'Gris sidéral'; break }
    '(?i)\b(midnight|minuit)\b' { $color = 'Minuit'; break }
    '(?i)\b(starlight|lumi[eè]re\s*stellaire)\b' { $color = 'Lumière stellaire'; break }
    '(?i)\b(eclipse\s*black|graphite\s*black|villi\s*black|black|noir)\b' { $color = 'Noir'; break }
    '(?i)\b(storm\s*gr[ae]y|luna\s*gr[ae]y|arctic\s*gr[ae]y|cloud\s*gr[ae]y|slate\s*gr[ae]y|iron\s*gr[ae]y|gr[ae]y|gris)\b' { $color = 'Gris'; break }
    '(?i)\b(platinum\s*silver|natural\s*silver|silver|argent)\b' { $color = 'Argent'; break }
    '(?i)\b(gold|champagne|or)\b' { $color = 'Or'; break }
    '(?i)\b(rose\s*gold|or\s*rose)\b' { $color = 'Or rose'; break }
    '(?i)\b(blue|bleu)\b' { $color = 'Bleu'; break }
    '(?i)\b(white|blanc)\b' { $color = 'Blanc'; break }
}

# ---- Écran intégré (lu dans son EDID) ----
$screen = ''; $res = ''; $hz = 0; $panel = 'LCD'; $panelId = ''
$monitors = @(Safe { Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorConnectionParams })
# 6 = LVDS, 11 = DisplayPort intégré (eDP), 13 = UDI intégré, 0x80000000 = écran interne
$internal = First ($monitors | Where-Object { @(6, 11, 13, 2147483648) -contains $_.VideoOutputTechnology })
if (-not $internal) { $internal = First $monitors }
$edid = $null
if ($internal) {
    $instance = $internal.InstanceName -replace '_\d+$', ''
    $edid = Safe { [byte[]](Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Enum\$instance\Device Parameters" -Name EDID).EDID }
}
if ($edid -and $edid.Length -ge 128) {
    $e = $edid
    # Taille en mm et résolution native : 1er bloc de description détaillée (octets 54-71)
    $wmm = $e[66] + (($e[68] -shr 4) -shl 8)
    $hmm = $e[67] + (($e[68] -band 0x0F) -shl 8)
    if (-not $wmm -or -not $hmm) { $wmm = $e[21] * 10; $hmm = $e[22] * 10 }
    $hres = $e[56] + (($e[58] -shr 4) -shl 8)
    $vres = $e[59] + (($e[61] -shr 4) -shl 8)
    if ($hres -and $vres) { $res = "${hres}x${vres}" }
    # Fabricant de la dalle (3 lettres, ex. BOE, SDC, AUO) et textes de l'EDID (souvent la référence de la dalle)
    $code = ([char](64 + (($e[8] -shr 2) -band 0x1F))).ToString() +
        [char](64 + ((($e[8] -band 3) -shl 3) -bor ($e[9] -shr 5))) + [char](64 + ($e[9] -band 0x1F))
    $texts = @()
    foreach ($d in 54, 72, 90, 108) {
        if ($e[$d] -eq 0 -and $e[$d + 1] -eq 0) {
            if ($e[$d + 3] -eq 0xFC -or $e[$d + 3] -eq 0xFE) {
                $t = ([Text.Encoding]::ASCII.GetString($e, $d + 5, 13) -split "`n")[0].Trim()
                if ($t) { $texts += $t }
            }
        } else {
            # Bloc de timing : le plus haut rafraîchissement à la résolution native
            $clock = ($e[$d] + ($e[$d + 1] -shl 8)) * 10000
            $h = $e[$d + 2] + (($e[$d + 4] -shr 4) -shl 8); $hTotal = $h + $e[$d + 3] + (($e[$d + 4] -band 0x0F) -shl 8)
            $v = $e[$d + 5] + (($e[$d + 7] -shr 4) -shl 8); $vTotal = $v + $e[$d + 6] + (($e[$d + 7] -band 0x0F) -shl 8)
            if ($h -eq $hres -and $v -eq $vres -and $hTotal -and $vTotal) {
                $hz = [math]::Max([double]$hz, [math]::Round($clock / ($hTotal * $vTotal)))
            }
        }
    }
    $panelId = ("$code " + ($texts -join ' ')).Trim()
    if ($panelId -match 'OLED|ATNA') { $panel = 'OLED' }   # ATNA = dalles AMOLED Samsung
    # Sinon : luminosité minimale annoncée pour le HDR (extension CTA-861). Presque 0 = noir parfait = OLED
    for ($b = 128; $panel -eq 'LCD' -and $b + 127 -lt $e.Length; $b += 128) {
        if ($e[$b] -ne 0x02) { continue }
        $i = $b + 4
        while ($i -lt $b + $e[$b + 2]) {
            $len = $e[$i] -band 0x1F
            if (($e[$i] -shr 5) -eq 7 -and $len -ge 6 -and $e[$i + 1] -eq 6 -and $e[$i + 6] -gt 0) {
                $max = 50 * [math]::Pow(2, $e[$i + 4] / 32)
                if ($max * [math]::Pow($e[$i + 6] / 255, 2) / 100 -lt 0.005) { $panel = 'OLED (probable)' }
            }
            $i += $len + 1
        }
    }
} else {
    $wmm = 0; $hmm = 0
    $size = First (Safe { Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBasicDisplayParams })
    if ($size) { $wmm = $size.MaxHorizontalImageSize * 10; $hmm = $size.MaxVerticalImageSize * 10 }
}
if ($wmm -and $hmm) {
    # Diagonale arrondie à la taille vendue la plus proche
    $inches = [math]::Sqrt($wmm * $wmm + $hmm * $hmm) / 25.4
    $best = [math]::Round($inches, 1)
    foreach ($s in 10.1, 11.6, 12, 12.3, 12.4, 12.5, 13, 13.3, 13.4, 13.5, 13.6, 13.8, 14, 14.5, 15, 15.3, 15.6, 16, 16.1, 17, 17.3, 18) {
        if ([math]::Abs($inches - $s) -lt [math]::Abs($inches - $best) -and [math]::Abs($inches - $s) -le 0.15) { $best = $s }
    }
    $screen = ("$best" -replace '\.', ',') + '"'
}
$video = @(Safe { Get-CimInstance Win32_VideoController })
if (-not $res) {
    $v = First ($video | Where-Object { $_.CurrentHorizontalResolution })
    if ($v) { $res = "$($v.CurrentHorizontalResolution)x$($v.CurrentVerticalResolution)" }
}
foreach ($v in $video) { if ($v.CurrentRefreshRate -gt $hz -and $v.CurrentRefreshRate -lt 1000) { $hz = [int]$v.CurrentRefreshRate } }
if ($res -and $hz) { $res = "$res @ $hz Hz" }

# ---- Processeur, carte graphique ----
$p = First (Safe { Get-CimInstance Win32_Processor })
$cpu = ("$($p.Name)" -replace '\((R|TM)\)', '' -replace '\s+', ' ').Trim()
if ($p.NumberOfCores) { $cpu += " ($($p.NumberOfCores) cœurs / $($p.NumberOfLogicalProcessors) threads)" }
$gpu = (@($video | ForEach-Object { "$($_.Name)".Trim() } | Where-Object { $_ }) -join ' + ')

# ---- RAM ----
$sticks = @(Safe { Get-CimInstance Win32_PhysicalMemory })
$ramBytes = Safe { ($sticks | Measure-Object -Property Capacity -Sum).Sum }
if (-not $ramBytes) { $ramBytes = $cs.TotalPhysicalMemory }
$ram = "$([math]::Round($ramBytes / 1GB)) Go"
$types = @{ 20 = 'DDR'; 21 = 'DDR2'; 24 = 'DDR3'; 26 = 'DDR4'; 27 = 'LPDDR'; 28 = 'LPDDR2'; 29 = 'LPDDR3'; 30 = 'LPDDR4'; 34 = 'DDR5'; 35 = 'LPDDR5' }
$stick = First $sticks
if ($stick -and $types.ContainsKey([int]$stick.SMBIOSMemoryType)) { $ram += " $($types[[int]$stick.SMBIOSMemoryType])" }
$speed = 0
if ($stick) { $speed = [int]$stick.ConfiguredClockSpeed; if (-not $speed) { $speed = [int]$stick.Speed } }
if ($speed) { $ram += " $speed MT/s" }

# ---- Stockage (disques internes, la clé USB est exclue) ----
$disks = @(Safe { Get-CimInstance -Namespace root\Microsoft\Windows\Storage -ClassName MSFT_PhysicalDisk } |
    Where-Object { $_.BusType -ne 7 -and $_.Size } | Sort-Object -Property Size -Descending)
if ($disks.Count) {
    $storage = (@($disks | ForEach-Object {
        $kind = switch ([int]$_.MediaType) { 3 { 'HDD' } 4 { 'SSD' } default { '' } }
        if ([int]$_.BusType -eq 17) { $kind = "$kind NVMe".Trim() }
        ("$(Size $_.Size) $kind").Trim()
    }) -join ' + ')
} else {
    $storage = (@(Safe { Get-CimInstance Win32_DiskDrive } |
        Where-Object { $_.InterfaceType -ne 'USB' -and "$($_.MediaType)" -notmatch 'Removable|External' -and $_.Size } |
        Sort-Object -Property Size -Descending | ForEach-Object { Size $_.Size }) -join ' + ')
}

# ---- Batterie ----
$design = 0; $full = 0; $cycles = ''
$report = Join-Path $env:TEMP 'fiche-batterie.xml'
Safe { powercfg /batteryreport /xml /output "$report" | Out-Null }
$xml = Safe { [xml](Get-Content -Raw -Encoding UTF8 $report) }
foreach ($bat in @(Safe { $xml.BatteryReport.Batteries.Battery })) {
    if (-not $bat) { continue }
    $design += [double]$bat.DesignCapacity; $full += [double]$bat.FullChargeCapacity
    if ("$($bat.CycleCount)" -match '^\d+$') { $cycles = [int]$cycles + [int]$bat.CycleCount }
}
Safe { Remove-Item -Force $report }
if (-not $design) {
    $design = Safe { (Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData | Measure-Object -Property DesignedCapacity -Sum).Sum }
    $full = Safe { (Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity | Measure-Object -Property FullChargedCapacity -Sum).Sum }
    $c = First (Safe { Get-CimInstance -Namespace root\wmi -ClassName BatteryCycleCount })
    if ($c -and $c.CycleCount) { $cycles = [int]$c.CycleCount }
}
$battery = ''
if ($design -and $full) { $battery = "$([math]::Round($full * 100 / $design)) %" }

# ---- Affichage ----
$shownScreen = (@($screen, $res, $panel) | Where-Object { $_ }) -join '  -  '
$shownBattery = 'pas de batterie détectée'
if ($battery) { $shownBattery = $battery }
if ("$cycles" -ne '') { $shownBattery += "  -  $cycles cycles" }
Write-Host ''
Write-Host '  Fiche technique :' -ForegroundColor Cyan
Write-Host "    Nom          : $name"
Write-Host "    Référence    : $ref"
Write-Host "    N° de série  : $serial"
if ($color) { Write-Host "    Couleur      : $color" }
Write-Host "    Écran        : $shownScreen"
if ($panelId) { Write-Host "    Dalle        : $panelId" }
Write-Host "    Processeur   : $cpu"
Write-Host "    Graphique    : $gpu"
Write-Host "    RAM          : $ram"
Write-Host "    Stockage     : $storage"
Write-Host "    Batterie     : $shownBattery"

# ---- Journal (une ligne par scan, s'ouvre dans Excel) ----
$failed = 0
function Csv($values) { (@($values | ForEach-Object { '"' + ("$_" -replace '"', '""') + '"' }) -join ';') + "`r`n" }
try {
    if (-not (Test-Path $log)) {
        $header = Csv @('Date', 'Système', 'Nom', 'Référence', 'N° de série', 'Couleur', 'Écran', 'Résolution', "Type d'écran", 'Dalle',
            'Processeur', 'Carte graphique', 'RAM', 'Stockage', 'Batterie (santé)', 'Cycles batterie')
        [IO.File]::WriteAllText($log, $header, (New-Object Text.UTF8Encoding $true))
    }
    $line = Csv @((Get-Date -Format 'yyyy-MM-dd HH:mm'), 'Windows', $name, $ref, $serial, $color, $screen, $res, $panel, $panelId,
        $cpu, $gpu, $ram, $storage, $battery, $cycles)
    [IO.File]::AppendAllText($log, $line, (New-Object Text.UTF8Encoding $false))
    Write-Host ''
    Write-Host '  ENREGISTRÉ dans fiche-technique\journal-des-scans.csv' -ForegroundColor Green
} catch {
    Write-Host ''
    Write-Host "  Impossible d'écrire le journal sur la clé (clé pleine ou protégée ?)." -ForegroundColor Red
    $failed++
}

# ---- Envoi à TechDesk (cette fiche + celles restées en attente) ----
$usb = Split-Path -Parent $dir
$pending = Join-Path $usb 'scans\fiches-en-attente'
$sent = Join-Path $usb 'scans\fiches-envoyees'
New-Item -ItemType Directory -Force -Path $pending, $sent | Out-Null
$cfg = @{}
Get-Content -Encoding UTF8 (Join-Path $usb 'settings.txt') | ForEach-Object {
    if ($_ -match '^\s*([A-Z_]+)\s*=\s*(.+?)\s*$') { $cfg[$matches[1]] = $matches[2] }
}
$url = "$($cfg['TECHDESK_URL'])".TrimEnd('/')
$key = "$($cfg['API_KEY'])"

if (-not $serial) {
    Write-Host ''
    Write-Host "  Pas de numéro de série : la fiche n'est pas envoyée à TechDesk (elle est seulement dans le journal)." -ForegroundColor Yellow
} else {
    $fiche = [ordered]@{
        os = 'windows'; serialNumber = $serial; name = $name; reference = $ref; color = $color
        screen = $screen; resolution = $res; screenType = $panel; panel = $panelId
        cpu = $cpu; gpu = $gpu; ram = $ram; storage = $storage; battery = $battery; batteryCycles = "$cycles"
    }
    $file = Join-Path $pending ("{0}-{1}-{2}.json" -f ($serial -replace '[^A-Za-z0-9_-]', ''), (Get-Date -Format 'yyyyMMdd-HHmmss'), $PID)
    [IO.File]::WriteAllText($file, ($fiche | ConvertTo-Json), (New-Object Text.UTF8Encoding $false))
}

if (-not $url -or $url -match 'example\.com' -or $key -notmatch '^smk_' -or $key -match 'COLLEZ') {
    Write-Host ''
    Write-Host '  Réglages incomplets : ouvrez settings.txt sur la clé et mettez TECHDESK_URL et API_KEY.' -ForegroundColor Yellow
    Write-Host '  La fiche est gardée sur la clé et partira au prochain envoi.' -ForegroundColor Yellow
    exit 1
}

foreach ($item in Get-ChildItem -Path $pending -Filter '*.json' | Sort-Object Name) {
    $body = [IO.File]::ReadAllBytes($item.FullName)
    try {
        $reply = Invoke-RestMethod -Method Post -Uri "$url/api/v1/products/specs" -TimeoutSec 20 `
            -Headers @{ 'X-API-Key' = $key } -ContentType 'application/json; charset=utf-8' -Body $body
        Write-Host ''
        if ($reply.product) {
            Write-Host "  FICHE AJOUTÉE dans TechDesk : $($reply.product.brand) $($reply.product.name)  (Bar ID $($reply.product.barId))" -ForegroundColor Green
        } else {
            Write-Host "  FICHE ENREGISTRÉE dans TechDesk (N° de série $($reply.serialNumber))." -ForegroundColor Green
            Write-Host "    Ce laptop n'est pas encore en stock : lancez SCAN-WINDOWS.cmd, la fiche s'affichera sur le produit." -ForegroundColor Cyan
        }
        Move-Item -Force -Path $item.FullName -Destination (Join-Path $sent $item.Name)
    } catch {
        $status = $null
        try { $status = [int]$_.Exception.Response.StatusCode } catch {}
        Write-Host ''
        if ($status -eq 400) {
            Write-Host "  TechDesk refuse la fiche $($item.Name) : elle reste seulement dans le journal." -ForegroundColor Yellow
            Move-Item -Force -Path $item.FullName -Destination (Join-Path $sent $item.Name)
        } elseif ($status -eq 401 -or $status -eq 403) {
            $failed++
            Write-Host '  TechDesk refuse la clé : vérifiez API_KEY dans settings.txt (clé "Scanner USB").' -ForegroundColor Red
        } elseif ($status) {
            $failed++
            Write-Host "  TechDesk a répondu une erreur ($status) pour $($item.Name)." -ForegroundColor Red
        } else {
            $failed++
            Write-Host '  Pas de connexion à TechDesk : la fiche reste sur la clé et partira au prochain envoi avec internet.' -ForegroundColor Yellow
        }
    }
}
if ($failed) { exit 1 }

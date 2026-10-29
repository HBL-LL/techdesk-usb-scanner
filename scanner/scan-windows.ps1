# Lit les caractéristiques de ce laptop Windows et l'ajoute au stock TechDesk (POST /api/v1/products/scan).
# Chaque scan est d'abord enregistré sur la clé (scans\en-attente). Sans internet, il part au prochain scan
# fait avec internet, sur n'importe quel laptop. Compatible Windows PowerShell 5.1 (aussi à l'écran
# d'installation de Windows, via Maj+F10).
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$usb = Split-Path -Parent $PSScriptRoot
$pending = Join-Path $usb 'scans\en-attente'
$sent = Join-Path $usb 'scans\envoyes'
New-Item -ItemType Directory -Force -Path $pending, $sent | Out-Null

# ---- Réglages ----
$cfg = @{}
Get-Content -Encoding UTF8 (Join-Path $usb 'settings.txt') | ForEach-Object {
    if ($_ -match '^\s*([A-Z_]+)\s*=\s*(.+?)\s*$') { $cfg[$matches[1]] = $matches[2] }
}
$url = "$($cfg['TECHDESK_URL'])".TrimEnd('/')
$key = "$($cfg['API_KEY'])"

# ---- Lecture du laptop ----
function First($items) { @($items) | Select-Object -First 1 }
$cs = First (Get-CimInstance Win32_ComputerSystem)
$csp = First (Get-CimInstance Win32_ComputerSystemProduct)
$bios = First (Get-CimInstance Win32_BIOS)
$cpu = First (Get-CimInstance Win32_Processor)
$ram = (Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum
if (-not $ram) { $ram = $cs.TotalPhysicalMemory }
# Le disque interne : le plus grand qui n'est pas en USB (la clé elle-même est en USB)
$disk = Get-CimInstance Win32_DiskDrive |
    Where-Object { $_.InterfaceType -ne 'USB' -and "$($_.MediaType)" -notmatch 'Removable|External' } |
    Sort-Object -Property Size -Descending | Select-Object -First 1
$gpus = @(Get-CimInstance Win32_VideoController | ForEach-Object { "$($_.Name)" })

$scan = [ordered]@{
    os             = 'windows'
    manufacturer   = "$($cs.Manufacturer)".Trim()
    model          = "$($cs.Model)".Trim()
    productVersion = "$($csp.Version)".Trim()
    cpu            = "$($cpu.Name)".Trim()
    ramBytes       = [double]$ram
    diskBytes      = [double]$(if ($disk) { $disk.Size } else { 0 })
    gpus           = $gpus
    serialNumber   = "$($bios.SerialNumber)".Trim()
}

Write-Host ''
Write-Host '  Laptop lu :' -ForegroundColor Cyan
Write-Host "    $($scan.manufacturer) $($scan.model) $($scan.productVersion)"
Write-Host "    $($scan.cpu)"
Write-Host ("    RAM {0:N0} Go  -  Disque {1:N0} Go (taille brute)" -f ($scan.ramBytes / 1GB), ($scan.diskBytes / 1e9))
Write-Host "    $($gpus -join ' / ')"
Write-Host "    N° de série : $($scan.serialNumber)"

$name = ($scan.serialNumber -replace '[^A-Za-z0-9_-]', '')
if (-not $name) { $name = 'laptop' }
$file = Join-Path $pending ("{0}-{1}.json" -f $name, (Get-Date -Format 'yyyyMMdd-HHmmss'))
[IO.File]::WriteAllText($file, ($scan | ConvertTo-Json -Depth 3), (New-Object Text.UTF8Encoding $false))

# ---- Envoi (ce laptop + ceux restés en attente) ----
if (-not $url -or $url -match 'example\.com' -or $key -notmatch '^smk_' -or $key -match 'COLLEZ') {
    Write-Host ''
    Write-Host '  Réglages incomplets : ouvrez settings.txt sur la clé et mettez TECHDESK_URL et API_KEY.' -ForegroundColor Yellow
    Write-Host '  Le scan est gardé sur la clé et partira au prochain scan.' -ForegroundColor Yellow
    exit 1
}

$failed = 0
foreach ($item in Get-ChildItem -Path $pending -Filter '*.json' | Sort-Object Name) {
    $body = [IO.File]::ReadAllBytes($item.FullName)
    try {
        $res = Invoke-RestMethod -Method Post -Uri "$url/api/v1/products/scan" -TimeoutSec 20 `
            -Headers @{ 'X-API-Key' = $key } -ContentType 'application/json; charset=utf-8' -Body $body
        $p = $res.product
        Write-Host ''
        if ($res.created) {
            Write-Host "  AJOUTÉ AU STOCK : $($p.brand) $($p.name)" -ForegroundColor Green
        } else {
            Write-Host "  DÉJÀ EN STOCK (pas ajouté deux fois) : $($p.brand) $($p.name)" -ForegroundColor Yellow
        }
        Write-Host "    $($p.configuration)"
        Write-Host "    Bar ID : $($p.barId)   -   Prix et état à compléter dans TechDesk" -ForegroundColor Cyan
        Move-Item -Force -Path $item.FullName -Destination (Join-Path $sent $item.Name)
    } catch {
        $failed++
        $status = $null
        try { $status = [int]$_.Exception.Response.StatusCode } catch {}
        Write-Host ''
        if ($status -eq 401 -or $status -eq 403) {
            Write-Host '  TechDesk refuse la clé : vérifiez API_KEY dans settings.txt (clé "Scanner USB").' -ForegroundColor Red
        } elseif ($status) {
            Write-Host "  TechDesk a répondu une erreur ($status) pour $($item.Name)." -ForegroundColor Red
        } else {
            Write-Host '  Pas de connexion à TechDesk : le scan reste sur la clé et partira au prochain scan avec internet.' -ForegroundColor Yellow
        }
    }
}
if ($failed) { exit 1 }

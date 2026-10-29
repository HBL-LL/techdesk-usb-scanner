# LaptopLand USB scanner

A USB stick that adds a newly arrived laptop to the TechDesk ERP stock. Plug it into a Windows laptop or a
MacBook, double-click one file, and the laptop appears in TechDesk with its name, configuration and serial
number in the shop's format. Prices, condition and supplier are left for you to fill in; TechDesk flags these
laptops **Prix manquant** until the prices are set.

Instructions for the shop (in French) are in [LISEZ-MOI.txt](LISEZ-MOI.txt), which is copied onto the stick.

## How it works

| File | Role |
|---|---|
| `SCAN-WINDOWS.cmd` → `scanner/scan-windows.ps1` | Reads the laptop with Windows PowerShell 5.1 (CIM): maker, model, CPU, RAM, internal disk, GPUs, BIOS serial number. Runs after Windows setup, or on the setup screen via Shift+F10. |
| `SCAN-MAC.command` → `scanner/scan-mac.sh` | Reads the Mac with built-in tools only (`system_profiler`, `sysctl`, `diskutil`, `plutil`, `curl`): model, chip, RAM, disk, native screen resolution, serial number. |
| `settings.txt` | `TECHDESK_URL` and `API_KEY` (a TechDesk **USB scanner** key, `smk_…`). |
| `scans/en-attente/`, `scans/envoyes/` | Each scan is written to `en-attente` first, then moved to `envoyes` once TechDesk accepts it. Scans made without internet are sent by the next scan that has a connection, from either OS. |

The scripts send raw facts to `POST /api/v1/products/scan` in TechDesk ERP. **TechDesk** turns them into the
shop's name and configuration (`server/laptopScan.ts` there), so naming rules change without touching the stick:

- Windows: `ThinkPad X1 Carbon Gen 12` / `Ultra 7 1re | RTX 4060 | 32Go | 1To`
- MacBook: `MacBook Pro 14"` / `M4 Pro - 24 Go RAM - 512 Go`

The endpoint creates the product with quantity 1, prices 0, no condition and supplier `À définir`, and does not add
the same serial number twice. See `PRODUCT_API.md` in the TechDesk-ERP repo.

## Requirements

- TechDesk ERP with the `/api/v1/products/scan` endpoint (the USB scanner key type in Settings > API).
- A USB stick formatted **exFAT** (readable on Windows and macOS).

## Notes for editing

- Keep `scan-windows.ps1` compatible with **Windows PowerShell 5.1** (no `??`, no ternary) and saved as
  **UTF-8 with BOM + CRLF**, or accented messages break. `.gitattributes` keeps the line endings.
- Keep `scan-mac.sh` compatible with macOS's **bash 3.2** and free of Python or Homebrew tools.
- The USB scanner key can only add laptops: it cannot read stock, prices or suppliers, or sell. If a stick is lost,
  revoke its key in TechDesk > Settings > API.

# TechDesk USB scanner

A USB stick that adds a newly arrived laptop to the TechDesk ERP stock. Plug it into a Windows laptop or a
MacBook, double-click one file, and the laptop appears in TechDesk with its name, configuration and serial
number in the shop's format. Prices, condition and supplier are left for you to fill in; TechDesk flags these
laptops **Prix manquant** until the prices are set.

Instructions for the shop (in French) are in [LISEZ-MOI.txt](LISEZ-MOI.txt), which is copied onto the stick.

## How to use

### 1. Prepare the stick (once)

1. Format a USB stick as **exFAT**, so it works on both Windows and Mac.
   - Mac: Disk Utility → select the stick → **Erase** → Format **ExFAT**.
   - Windows: right-click the stick in Explorer → **Format** → File system **exFAT**.
2. Copy everything in this folder onto the stick (`SCAN-WINDOWS.cmd`, `SCAN-MAC.command`, `settings.txt`,
   `LISEZ-MOI.txt` and the `scanner` folder). You don't need `README.md` or the `.git*` files.
3. In TechDesk: **Settings → API**.
   - Tick **USB scanner (adds laptops only)**.
   - Name the key, e.g. `Clé USB`, and click **Create key**.
   - Copy the key (`smk_…`): it is shown only once.
4. On the stick, open `settings.txt` and fill in:
   ```
   TECHDESK_URL=https://your-techdesk-address     (as in your browser, no "/" at the end)
   API_KEY=smk_...                                (the key you just copied)
   ```
   Save the file. Keep the key private: don't send it by message, and never commit it. In this repo,
   `settings.txt` holds placeholders only.

### 2. Scan a Windows laptop

- **Brand new laptop, still on the Windows setup screen** (country, Wi-Fi...):
  1. Plug in the stick.
  2. Press **Shift + F10**. On some laptops it's **Shift + Fn + F10**. A black window opens.
  3. Type `D:\SCAN-WINDOWS.cmd` and press Enter. If it says "not found", try `E:\SCAN-WINDOWS.cmd`, then `F:\…`.
  4. Read the result, press a key, close the window. The laptop stays factory-fresh.

  Tip: connect to Wi-Fi on the setup screen first. Otherwise the scan waits on the stick (see below).
- **Windows already set up:** open the stick in Explorer and double-click `SCAN-WINDOWS.cmd`.

### 3. Scan a Mac

The Mac must have finished its setup (you can't run anything from the "Hello" setup screens).

1. Plug in the stick and open it in Finder.
2. Double-click `SCAN-MAC.command`.

If macOS says it can't open it: **right-click → Open → Open**.

### 4. Read the result

| Message | Meaning |
|---|---|
| `AJOUTÉ AU STOCK` | Added. The Bar ID, name and configuration are shown. |
| `DÉJÀ EN STOCK` | A laptop with this serial number is already in stock; it was not added twice. |
| `Pas de connexion à TechDesk` | No internet. The scan is kept in `scans/en-attente` on the stick and is sent automatically by the next scan made with internet, on any laptop. |
| `TechDesk refuse la clé` | Check `API_KEY` in `settings.txt` (it must be a **USB scanner** key). |
| `Réglages incomplets` | `settings.txt` still has the example address or key. |

### 5. Finish in TechDesk

Open **Products** and click the **Missing price** filter. For each scanned laptop:
- set the purchase price, selling price and condition;
- replace the supplier `À définir` with the real one.

The red badge disappears once both prices are set.

### If the stick is lost

TechDesk → **Settings → API** → **Revoke** on the stick's key. The key stops working immediately. It could only
add laptops: it can't read your stock, prices or suppliers, and it can't sell.

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

#Requires -Version 5.1
<#
.SYNOPSIS
    Invoice Parser - Windows Dependency Installer
.DESCRIPTION
    Installs Python (latest) and Tesseract OCR if not already present,
    ensures both are on PATH, then installs Python requirements.
.USAGE
    irm "https://your-raw-url/install.ps1" | iex
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Helpers ──────────────────────────────────────────────────────────────────

function Write-Header {
    param([string]$Text)
    Write-Host ""
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ("  " + ("─" * ($Text.Length))) -ForegroundColor DarkCyan
}

function Write-OK   { param([string]$m) Write-Host "  [OK]  $m" -ForegroundColor Green  }
function Write-Info { param([string]$m) Write-Host "  [>>]  $m" -ForegroundColor Yellow }
function Write-Fail { param([string]$m) Write-Host "  [!!]  $m" -ForegroundColor Red    }

function Refresh-Path {
    # Reload PATH from registry without restarting the shell
    $machine = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = ($machine, $user | Where-Object { $_ }) -join ';'
}

function Add-ToPath {
    param([string]$Dir)
    if (-not (Test-Path $Dir)) { return }

    $current = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    if ($current -split ';' | Where-Object { $_ -ieq $Dir }) {
        Write-Info "Already in PATH: $Dir"
        return
    }
    $new = ($current.TrimEnd(';'), $Dir) -join ';'
    [System.Environment]::SetEnvironmentVariable('Path', $new, 'User')
    Write-OK "Added to PATH: $Dir"
    Refresh-Path
}

function Get-LatestPythonVersion {
    Write-Info "Querying latest Python version from python.org..."
    $html = (Invoke-WebRequest 'https://www.python.org/downloads/windows/' -UseBasicParsing).Content
    # Match patterns like 3.13.2
    $matches = [regex]::Matches($html, 'Python (\d+\.\d+\.\d+)')
    $versions = $matches | ForEach-Object { [version]$_.Groups[1].Value } | Sort-Object -Descending
    return $versions[0].ToString()
}

function Get-LatestPopplerAsset {
    Write-Info "Querying latest Poppler release from GitHub..."
    $api = 'https://api.github.com/repos/oschwartz10612/poppler-windows/releases/latest'
    $headers = @{ 'User-Agent' = 'invoice-parser-installer' }
    $release = Invoke-RestMethod -Uri $api -Headers $headers
    # Assets are named like Release-24.08.0-0.zip
    $asset = $release.assets | Where-Object { $_.name -match '\.zip$' } | Select-Object -First 1
    return $asset
}

function Get-LatestTesseractAsset {
    Write-Info "Querying latest Tesseract release from GitHub..."
    $api = 'https://api.github.com/repos/UB-Mannheim/tesseract/releases/latest'
    $headers = @{ 'User-Agent' = 'invoice-parser-installer' }
    $release = Invoke-RestMethod -Uri $api -Headers $headers
    # Prefer the 64-bit installer exe
    $asset = $release.assets | Where-Object {
        $_.name -match 'tesseract.*w64.*setup\.exe$' -or
        $_.name -match 'tesseract-ocr-w64-setup.*\.exe$'
    } | Select-Object -First 1
    if (-not $asset) {
        # Fallback: any setup exe
        $asset = $release.assets | Where-Object { $_.name -match 'setup.*\.exe$' } | Select-Object -First 1
    }
    return $asset
}

# ── Python ───────────────────────────────────────────────────────────────────

Write-Header "Python"

$pythonExe = Get-Command python -ErrorAction SilentlyContinue

if ($pythonExe) {
    $ver = & python --version 2>&1
    Write-OK "Already installed: $ver"
} else {
    $pyVer = Get-LatestPythonVersion
    $arch  = if ([Environment]::Is64BitOperatingSystem) { 'amd64' } else { 'win32' }
    $url   = "https://www.python.org/ftp/python/$pyVer/python-$pyVer-$arch.exe"
    $dest  = "$env:TEMP\python-$pyVer-$arch.exe"

    Write-Info "Downloading Python $pyVer..."
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing

    Write-Info "Installing Python $pyVer (user install, no UAC required)..."
    $args = '/quiet', 'InstallAllUsers=0', 'PrependPath=1', 'Include_pip=1', 'Include_launcher=1'
    $proc = Start-Process -FilePath $dest -ArgumentList $args -Wait -PassThru
    Remove-Item $dest -Force

    if ($proc.ExitCode -ne 0) {
        Write-Fail "Python installer exited with code $($proc.ExitCode)"
        exit 1
    }

    Refresh-Path
    $pythonExe = Get-Command python -ErrorAction SilentlyContinue
    if ($pythonExe) {
        $ver = & python --version 2>&1
        Write-OK "Installed: $ver"
    } else {
        Write-Fail "Python not found after install. You may need to restart your terminal."
        exit 1
    }
}

# Ensure Scripts folder is on PATH (pip-installed tools land here)
$scriptsDir = & python -c "import sysconfig; print(sysconfig.get_path('scripts'))" 2>$null
if ($scriptsDir) { Add-ToPath $scriptsDir }

# ── Tesseract OCR ────────────────────────────────────────────────────────────

Write-Header "Tesseract OCR"

$tessExe = Get-Command tesseract -ErrorAction SilentlyContinue

if ($tessExe) {
    $tessVer = & tesseract --version 2>&1 | Select-Object -First 1
    Write-OK "Already installed: $tessVer"
} else {
    $asset = Get-LatestTesseractAsset
    if (-not $asset) {
        Write-Fail "Could not locate a Tesseract installer asset on GitHub."
        exit 1
    }

    $dest = "$env:TEMP\$($asset.name)"
    Write-Info "Downloading $($asset.name)..."
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $dest -UseBasicParsing

    Write-Info "Installing Tesseract (silent)..."
    $proc = Start-Process -FilePath $dest -ArgumentList '/S' -Wait -PassThru
    Remove-Item $dest -Force

    if ($proc.ExitCode -ne 0) {
        Write-Fail "Tesseract installer exited with code $($proc.ExitCode)"
        exit 1
    }

    # Add standard install locations to PATH
    $candidates = @(
        "$env:ProgramFiles\Tesseract-OCR",
        "${env:ProgramFiles(x86)}\Tesseract-OCR",
        "$env:LOCALAPPDATA\Programs\Tesseract-OCR"
    )
    foreach ($dir in $candidates) {
        if (Test-Path "$dir\tesseract.exe") {
            Add-ToPath $dir
            break
        }
    }

    Refresh-Path
    $tessExe = Get-Command tesseract -ErrorAction SilentlyContinue
    if ($tessExe) {
        $tessVer = & tesseract --version 2>&1 | Select-Object -First 1
        Write-OK "Installed: $tessVer"
    } else {
        Write-Fail "Tesseract not found after install. You may need to restart your terminal."
        exit 1
    }
}

# ── Poppler ───────────────────────────────────────────────────────────────────

Write-Header "Poppler (pdf2image)"

$popplerInstallDir = "$env:LOCALAPPDATA\Programs\poppler"
$popplerBin        = "$popplerInstallDir\bin"
$pdfInfoExe        = Get-Command pdftoppm -ErrorAction SilentlyContinue

if ($pdfInfoExe) {
    Write-OK "Already installed: $($pdfInfoExe.Source)"
} else {
    $asset = Get-LatestPopplerAsset
    if (-not $asset) {
        Write-Fail "Could not locate a Poppler zip asset on GitHub."
        exit 1
    }

    $dest = "$env:TEMP\$($asset.name)"
    Write-Info "Downloading $($asset.name)..."
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $dest -UseBasicParsing

    Write-Info "Extracting to $popplerInstallDir..."
    if (Test-Path $popplerInstallDir) { Remove-Item $popplerInstallDir -Recurse -Force }

    # Zip contains a top-level folder; extract to TEMP first, then move
    $extractTemp = "$env:TEMP\poppler-extract"
    if (Test-Path $extractTemp) { Remove-Item $extractTemp -Recurse -Force }
    Expand-Archive -Path $dest -DestinationPath $extractTemp -Force
    Remove-Item $dest -Force

    # Find the inner folder (e.g. poppler-24.08.0)
    $inner = Get-ChildItem $extractTemp -Directory | Select-Object -First 1
    Move-Item $inner.FullName $popplerInstallDir
    Remove-Item $extractTemp -Recurse -Force

    # The bin folder may be nested one level deeper (Library\bin on some builds)
    if (-not (Test-Path "$popplerInstallDir\bin\pdftoppm.exe")) {
        $altBin = Get-ChildItem $popplerInstallDir -Recurse -Filter 'pdftoppm.exe' |
                  Select-Object -First 1
        if ($altBin) {
            $popplerBin = $altBin.DirectoryName
        }
    }

    Add-ToPath $popplerBin

    Refresh-Path
    $pdfInfoExe = Get-Command pdftoppm -ErrorAction SilentlyContinue
    if ($pdfInfoExe) {
        Write-OK "Installed: $($pdfInfoExe.Source)"
    } else {
        Write-Fail "Poppler not found after install. You may need to restart your terminal."
        exit 1
    }
}

# ── Python packages ──────────────────────────────────────────────────────────

Write-Header "Python packages (requirements.txt)"

# Try to find a requirements.txt next to the script, or use the embedded list
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD.Path }
$reqFile = Join-Path $scriptDir 'requirements.txt'

if (Test-Path $reqFile) {
    Write-Info "Found requirements.txt — installing..."
    & python -m pip install --upgrade pip --quiet
    & python -m pip install -r $reqFile
    Write-OK "All packages installed."
} else {
    Write-Info "No requirements.txt found alongside the script — skipping pip install."
    Write-Info "Run manually:  pip install -r requirements.txt"
}

# ── Done ─────────────────────────────────────────────────────────────────────

Write-Header "Setup complete"
Write-OK "Python   : $(& python --version 2>&1)"
Write-OK "Tesseract: $(& tesseract --version 2>&1 | Select-Object -First 1)"
$pdftoppm = Get-Command pdftoppm -ErrorAction SilentlyContinue
Write-OK "Poppler  : $(if ($pdftoppm) { $pdftoppm.Source } else { 'not on PATH — restart terminal' })"
Write-Host ""
Write-Host "  You're ready to use invoice-parser." -ForegroundColor White
Write-Host ""


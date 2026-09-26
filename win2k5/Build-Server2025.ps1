#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Builds a Windows Server 2025 ISO with drivers injected into boot.wim
    and all indexes of install.wim.

.DESCRIPTION
    Expected layout:

      C:\Server2025\
        Server2025.iso
        Drivers\
          <driver folders containing .inf files>

    The ISO is extracted automatically, modified, and a new ISO is created.

    Requires:
      - Windows 10/11 or Windows Server with DISM
      - ADK deployment tools (oscdimg.exe) in PATH
        OR place oscdimg.exe next to this script.

    By default:
      - boot.wim index 2 receives all drivers
      - install.wim ALL indexes receive all drivers
      - the original WIM files are backed up as .bak
      - output is C:\Server2025\Server2025-custom.iso
#>

[CmdletBinding()]
param(
    [string]$WorkRoot = 'C:\Server2025',
    [string]$IsoPath = 'C:\Server2025\Server2025.iso',
    [string]$DriverPath = 'C:\Server2025\Drivers',
    [string]$OutputIso = 'C:\Server2025\Server2025-custom.iso',

    # boot.wim normally needs index 2 (Windows Setup).
    [int]$BootIndex = 2,

    # Set to $true to inject into all install.wim indexes.
    [bool]$AllInstallIndexes = $true
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$IsoRoot   = Join-Path $WorkRoot 'ISO'
$MountRoot = Join-Path $WorkRoot 'Mount'
$LogRoot   = Join-Path $WorkRoot 'Logs'

$BootWim    = Join-Path $IsoRoot 'sources\boot.wim'
$InstallWim = Join-Path $IsoRoot 'sources\install.wim'

function Write-Step {
    param([string]$Message)
    Write-Host "`n=== $Message ===" -ForegroundColor Cyan
}

function Invoke-Dism {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    Write-Host "DISM $($Arguments -join ' ')" -ForegroundColor DarkGray

    & dism.exe @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "DISM failed with exit code $LASTEXITCODE."
    }
}

function Remove-MountSafely {
    param([string]$MountPath)

    if (Test-Path $MountPath) {
        try {
            & dism.exe /English /Get-MountedWimInfo 2>$null | Out-Null

            & dism.exe /Unmount-Wim /MountDir:$MountPath /Discard 2>$null

            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Could not discard mount $MountPath automatically."
            }
        }
        catch {
            Write-Warning "Mount cleanup failed: $($_.Exception.Message)"
        }
    }
}

function Mount-Wim {
    param(
        [string]$WimFile,
        [int]$Index,
        [string]$MountPath
    )

    New-Item -ItemType Directory -Force -Path $MountPath | Out-Null

    Invoke-Dism @(
        '/English'
        '/Mount-Wim'
        "/WimFile:$WimFile"
        "/Index:$Index"
        "/MountDir:$MountPath"
    )
}

function Add-Drivers {
    param([string]$MountPath)

    Invoke-Dism @(
        '/English'
        "/Image:$MountPath"
        '/Add-Driver'
        "/Driver:$DriverPath"
        '/Recurse'
    )
}

function Commit-Wim {
    param([string]$MountPath)

    Invoke-Dism @(
        '/English'
        '/Unmount-Wim'
        "/MountDir:$MountPath"
        '/Commit'
    )
}

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

Write-Step 'Validating environment'

if (-not (Test-Path $IsoPath -PathType Leaf)) {
    throw "ISO not found: $IsoPath"
}

if (-not (Test-Path $DriverPath -PathType Container)) {
    throw "Driver directory not found: $DriverPath"
}

if (-not (Get-Command dism.exe -ErrorAction SilentlyContinue)) {
    throw 'DISM.exe was not found.'
}

$OsCdImg = $null

if (Get-Command oscdimg.exe -ErrorAction SilentlyContinue) {
    $OsCdImg = (Get-Command oscdimg.exe).Source
}
else {
    $LocalOsCdImg = Join-Path $PSScriptRoot 'oscdimg.exe'

    if (Test-Path $LocalOsCdImg) {
        $OsCdImg = $LocalOsCdImg
    }
}

if (-not $OsCdImg) {
    throw @"
oscdimg.exe was not found.

Install the Microsoft Windows ADK (Deployment Tools), or copy oscdimg.exe
next to this script.

After installing ADK, normally oscdimg.exe is under:
C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\
"@
}

$DriverCount = @(Get-ChildItem -Path $DriverPath -Filter '*.inf' -Recurse -File).Count

if ($DriverCount -eq 0) {
    throw "No .inf drivers were found below $DriverPath"
}

Write-Host "ISO:             $IsoPath"
Write-Host "Drivers:         $DriverPath"
Write-Host "INF files found: $DriverCount"
Write-Host "Output ISO:      $OutputIso"
Write-Host "oscdimg:         $OsCdImg"

# ---------------------------------------------------------------------------
# Prepare directories
# ---------------------------------------------------------------------------

Write-Step 'Preparing workspace'

New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null
New-Item -ItemType Directory -Force -Path $IsoRoot   | Out-Null
New-Item -ItemType Directory -Force -Path $MountRoot | Out-Null
New-Item -ItemType Directory -Force -Path $LogRoot   | Out-Null

# Prevent stale files from an earlier failed build.
$ExistingIsoFiles = Get-ChildItem -Path $IsoRoot -Force -ErrorAction SilentlyContinue
if ($ExistingIsoFiles) {
    Write-Host "Removing previous extracted ISO contents..."
    Remove-Item -Path (Join-Path $IsoRoot '*') -Recurse -Force
}

# ---------------------------------------------------------------------------
# Extract ISO
# ---------------------------------------------------------------------------

Write-Step 'Extracting Windows Server 2025 ISO'

$MountedIso = $null

try {
    $MountedIso = Mount-DiskImage -ImagePath $IsoPath -PassThru
    Start-Sleep -Seconds 2

    $Volume = $MountedIso | Get-Volume |
        Where-Object { $_.DriveLetter } |
        Select-Object -First 1

    if (-not $Volume) {
        throw "Could not determine the mounted ISO drive letter."
    }

    $IsoDrive = "$($Volume.DriveLetter):"

    Write-Host "Mounted ISO at $IsoDrive"

    Copy-Item -Path "$IsoDrive\*" -Destination $IsoRoot -Recurse -Force
}
finally {
    if ($MountedIso) {
        Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue
    }
}

if (-not (Test-Path $BootWim)) {
    throw "boot.wim was not found at $BootWim"
}

if (-not (Test-Path $InstallWim)) {
    throw "install.wim was not found at $InstallWim"
}

# ---------------------------------------------------------------------------
# Show WIM information
# ---------------------------------------------------------------------------

Write-Step 'Reading WIM information'

Write-Host "`n--- boot.wim ---"
Invoke-Dism @(
    '/English'
    '/Get-WimInfo'
    "/WimFile:$BootWim"
)

Write-Host "`n--- install.wim ---"
Invoke-Dism @(
    '/English'
    '/Get-WimInfo'
    "/WimFile:$InstallWim"
)

# ---------------------------------------------------------------------------
# Backup WIMs
# ---------------------------------------------------------------------------

Write-Step 'Backing up original WIM files'

Copy-Item $BootWim "$BootWim.bak" -Force
Copy-Item $InstallWim "$InstallWim.bak" -Force

# ---------------------------------------------------------------------------
# boot.wim
# ---------------------------------------------------------------------------

Write-Step "Injecting drivers into boot.wim index $BootIndex"

Remove-MountSafely $MountRoot

try {
    Mount-Wim -WimFile $BootWim -Index $BootIndex -MountPath $MountRoot
    Add-Drivers -MountPath $MountRoot

    Write-Host "`nDrivers currently installed in boot.wim:"
    Invoke-Dism @(
        '/English'
        "/Image:$MountRoot"
        '/Get-Drivers'
        '/Format:Table'
    )

    Commit-Wim -MountPath $MountRoot
}
catch {
    Remove-MountSafely $MountRoot
    throw
}

# ---------------------------------------------------------------------------
# install.wim indexes
# ---------------------------------------------------------------------------

Write-Step 'Reading install.wim indexes'

$WimInfoFile = Join-Path $LogRoot 'install-wim-info.txt'

& dism.exe /English /Get-WimInfo /WimFile:$InstallWim |
    Tee-Object -FilePath $WimInfoFile

if ($LASTEXITCODE -ne 0) {
    throw "Could not read install.wim information."
}

$Indexes = @(
    Select-String -Path $WimInfoFile -Pattern '^\s*Index\s*:\s*(\d+)' |
    ForEach-Object { [int]$_.Matches[0].Groups[1].Value }
)

if ($Indexes.Count -eq 0) {
    throw "No install.wim indexes could be detected."
}

if (-not $AllInstallIndexes) {
    $Indexes = @($Indexes | Select-Object -First 1)
}

Write-Host "Indexes to modify: $($Indexes -join ', ')"

foreach ($Index in $Indexes) {

    Write-Step "Injecting drivers into install.wim index $Index"

    Remove-MountSafely $MountRoot

    try {
        Mount-Wim -WimFile $InstallWim -Index $Index -MountPath $MountRoot
        Add-Drivers -MountPath $MountRoot

        Commit-Wim -MountPath $MountRoot
    }
    catch {
        Remove-MountSafely $MountRoot
        throw
    }
}

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------

Write-Step 'Verifying modified WIM files'

Invoke-Dism @(
    '/English'
    '/Get-WimInfo'
    "/WimFile:$BootWim"
)

Invoke-Dism @(
    '/English'
    '/Get-WimInfo'
    "/WimFile:$InstallWim"
)

# ---------------------------------------------------------------------------
# Create bootable ISO
# ---------------------------------------------------------------------------

Write-Step 'Creating bootable ISO'

if (Test-Path $OutputIso) {
    Remove-Item $OutputIso -Force
}

# Server installation media normally uses BIOS + UEFI boot files.
# The El Torito entries below preserve Microsoft's standard dual boot layout.
$BootData = '2#p0,e,b"{0}"#pEF,e,b"{1}"' -f `
    (Join-Path $IsoRoot 'boot\etfsboot.com'), `
    (Join-Path $IsoRoot 'efi\microsoft\boot\efisys.bin')

& $OsCdImg `
    '-m' `
    '-o' `
    '-u2' `
    '-udfver102' `
    "-bootdata:$BootData" `
    $IsoRoot `
    $OutputIso

if ($LASTEXITCODE -ne 0) {
    throw "oscdimg failed with exit code $LASTEXITCODE."
}

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

Remove-MountSafely $MountRoot

Write-Step 'BUILD COMPLETE'

$OutputFile = Get-Item $OutputIso

Write-Host ""
Write-Host "Created:"
Write-Host "  $($OutputFile.FullName)"
Write-Host ""
Write-Host ("Size: {0:N2} GB" -f ($OutputFile.Length / 1GB))
Write-Host ""
Write-Host "Original WIM backups:"
Write-Host "  $BootWim.bak"
Write-Host "  $InstallWim.bak"
Write-Host ""
Write-Host "Driver INF files injected: $DriverCount"
Write-Host "install.wim indexes modified: $($Indexes -join ', ')"
Write-Host ""
Write-Host "You can now write the custom ISO to USB or use it as VM installation media."

#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Install cccleaner for Windows PowerShell.

.DESCRIPTION
    Installs cccleaner.ps1 and a cccleaner.cmd launcher into $HOME\.local\bin
    without changing PowerShell, PATH, or profile settings by default.
#>

[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $HOME ".local\bin"),
    [switch]$AddToPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Repo = "Grassgod/cccleaner"
$Branch = "master"
$RawUrl = "https://raw.githubusercontent.com/$Repo/$Branch"
$ScriptName = "cccleaner.ps1"
$ShimName = "cccleaner.cmd"

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Yellow
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-ErrorMessage {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Add-UserPath {
    param([Parameter(Mandatory)][string]$Directory)

    $current = [Environment]::GetEnvironmentVariable("Path", "User")
    $parts = @()
    if (-not [string]::IsNullOrWhiteSpace($current)) {
        $parts = $current -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }

    if ($parts -contains $Directory) {
        return $false
    }

    $next = if ([string]::IsNullOrWhiteSpace($current)) {
        $Directory
    }
    else {
        "$current;$Directory"
    }

    [Environment]::SetEnvironmentVariable("Path", $next, "User")
    $env:Path = "$env:Path;$Directory"
    return $true
}

try {
    Write-Host "cccleaner Windows installation script"
    Write-Host "====================================="
    Write-Host ""

    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

    $localScript = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        Join-Path $PSScriptRoot $ScriptName
    }
    else {
        $null
    }
    $localShim = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        Join-Path $PSScriptRoot $ShimName
    }
    else {
        $null
    }
    $target = Join-Path $InstallDir $ScriptName
    $shimTarget = Join-Path $InstallDir $ShimName

    if ($localScript -and (Test-Path -LiteralPath $localScript -PathType Leaf)) {
        Write-Info "Local installation detected"
        Copy-Item -LiteralPath $localScript -Destination $target -Force
        if ($localShim -and (Test-Path -LiteralPath $localShim -PathType Leaf)) {
            Copy-Item -LiteralPath $localShim -Destination $shimTarget -Force
        }
        else {
            Invoke-WebRequest -Uri "$RawUrl/$ShimName" -OutFile $shimTarget
        }
    }
    else {
        Write-Info "Remote installation from GitHub"
        Invoke-WebRequest -Uri "$RawUrl/$ScriptName" -OutFile $target
        Invoke-WebRequest -Uri "$RawUrl/$ShimName" -OutFile $shimTarget
    }

    Write-Success "Installed $ScriptName to $target"
    Write-Success "Installed $ShimName to $shimTarget"

    if ($AddToPath) {
        if (Add-UserPath -Directory $InstallDir) {
            Write-Success "Added $InstallDir to the current user's PATH"
            Write-Host "Open a new terminal to use cccleaner by name."
        }
        else {
            Write-Info "$InstallDir is already in the current user's PATH"
        }
    }
    else {
        Write-Info "PATH was not changed. Use the full launcher path shown below."
    }

    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  & `"$shimTarget`" -Help"
    Write-Host "  & `"$shimTarget`" -List"
    Write-Host "  & `"$shimTarget`" -All"
    Write-Host ""
    Write-Host "Optional: rerun install.ps1 with -AddToPath if you want the short 'cccleaner' command."
}
catch {
    Write-ErrorMessage $_.Exception.Message
    throw
}

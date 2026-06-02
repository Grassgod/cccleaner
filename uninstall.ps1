#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Uninstall cccleaner for Windows PowerShell.
#>

[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $HOME ".local\bin"),
    [switch]$Yes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptName = "cccleaner.ps1"
$ShimName = "cccleaner.cmd"
$Target = Join-Path $InstallDir $ScriptName
$ShimTarget = Join-Path $InstallDir $ShimName

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

function Remove-UserPath {
    param([Parameter(Mandatory)][string]$Directory)

    $current = [Environment]::GetEnvironmentVariable("Path", "User")
    if ([string]::IsNullOrWhiteSpace($current)) {
        return $false
    }

    $parts = $current -split ";" | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_) -and $_ -ne $Directory
    }
    $next = $parts -join ";"

    if ($next -eq $current) {
        return $false
    }

    [Environment]::SetEnvironmentVariable("Path", $next, "User")
    return $true
}

try {
    Write-Host "cccleaner Windows uninstallation script"
    Write-Host "======================================="
    Write-Host ""

    if (-not $Yes) {
        Write-Host "This will remove:"
        Write-Host "  - $Target"
        Write-Host "  - $ShimTarget"
        Write-Host "  - $InstallDir from the current user's PATH when it was added by install.ps1"
        Write-Host ""
        $confirm = Read-Host "Are you sure you want to uninstall cccleaner? (y/N)"
        if ($confirm -notmatch "^[Yy]$") {
            Write-Info "Uninstallation cancelled."
            exit 0
        }
    }

    if (Test-Path -LiteralPath $Target -PathType Leaf) {
        Remove-Item -LiteralPath $Target -Force
        Write-Success "Removed $Target"
    }
    else {
        Write-Info "$Target not found, skipping"
    }

    if (Test-Path -LiteralPath $ShimTarget -PathType Leaf) {
        Remove-Item -LiteralPath $ShimTarget -Force
        Write-Success "Removed $ShimTarget"
    }
    else {
        Write-Info "$ShimTarget not found, skipping"
    }

    if (Remove-UserPath -Directory $InstallDir) {
        Write-Success "Removed $InstallDir from the current user's PATH"
    }

    Write-Host ""
    Write-Success "Uninstallation completed successfully!"
    Write-Host "Note: Your $HOME\.claude.json and $HOME\.claude_backups\ remain untouched."
}
catch {
    Write-ErrorMessage $_.Exception.Message
    exit 1
}

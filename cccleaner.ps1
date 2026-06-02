#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Claude Code Cleaner for Windows PowerShell.

.DESCRIPTION
    Cleans Claude Code history and local cache data from $HOME\.claude.json
    and $HOME\.claude\. This script is the native Windows counterpart to the
    Bash cccleaner script. It preserves authentication data and Windows
    Credential Manager entries.
#>

[CmdletBinding(DefaultParameterSetName = "Default")]
param(
    [Alias("a")]
    [switch]$All,

    [Alias("p")]
    [string]$Project,

    [Alias("l")]
    [switch]$List,

    [Alias("i")]
    [switch]$Interactive,

    [Alias("c")]
    [switch]$Cache,

    [Alias("g")]
    [switch]$GithubRepos,

    [Alias("f")]
    [switch]$Folders,

    [Alias("u")]
    [switch]$UserId,

    [switch]$NoBackup,

    [Alias("h")]
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ClaudeJson = Join-Path $HOME ".claude.json"
$ClaudeDir = Join-Path $HOME ".claude"
$BackupDir = Join-Path $HOME ".claude_backups"

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-WarningMessage {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-ErrorMessage {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Show-Usage {
    $scriptName = Split-Path -Leaf $PSCommandPath
    @"
Claude Code Cleaner for Windows - Clean history from $ClaudeJson

Usage:
    pwsh .\$scriptName [options]

Options:
    -All, -a              Clean everything (histories + projects + folders + cache + githubRepoPaths + history.jsonl + counters + identity IDs)
    -Project, -p PATH     Clear history for specific project path
    -List, -l             List all projects
    -Interactive, -i      Interactive mode to select projects
    -Cache, -c            Clear cached data
    -GithubRepos, -g      Clear GitHub repository paths
    -Folders, -f          Clear .claude folder contents
    -UserId, -u           Regenerate userID and anonymousId in .claude.json
    -NoBackup             Skip backup creation (not recommended)
    -Help, -h             Show this help message

Examples:
    pwsh .\$scriptName -List
    pwsh .\$scriptName -All
    pwsh .\$scriptName -Folders
    pwsh .\$scriptName -UserId
    pwsh .\$scriptName -Project "C:\Users\you\myproject"
"@
}

function Assert-ClaudeJsonExists {
    if (-not (Test-Path -LiteralPath $ClaudeJson -PathType Leaf)) {
        throw "Claude config not found: $ClaudeJson"
    }
}

function Read-ClaudeJson {
    Assert-ClaudeJsonExists
    $raw = Get-Content -LiteralPath $ClaudeJson -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "Claude config is empty: $ClaudeJson"
    }
    return $raw | ConvertFrom-Json
}

function Save-ClaudeJson {
    param([Parameter(Mandatory)]$Config)

    $parent = Split-Path -Parent $ClaudeJson
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $tempFile = [System.IO.Path]::GetTempFileName()
    try {
        $json = $Config | ConvertTo-Json -Depth 100
        Set-Content -LiteralPath $tempFile -Value $json -Encoding UTF8
        Get-Content -LiteralPath $tempFile -Raw | ConvertFrom-Json | Out-Null
        Move-Item -LiteralPath $tempFile -Destination $ClaudeJson -Force
    }
    catch {
        Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
        throw
    }
}

function New-Backup {
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

    if (Test-Path -LiteralPath $ClaudeJson -PathType Leaf) {
        $backupFile = Join-Path $BackupDir "claude_.claude.json_$timestamp"
        Copy-Item -LiteralPath $ClaudeJson -Destination $backupFile -Force
        Write-Success "Backup created: $backupFile"
    }

    if (Test-Path -LiteralPath $ClaudeDir -PathType Container) {
        $backupPath = Join-Path $BackupDir "claude_dir_$timestamp"
        Copy-Item -LiteralPath $ClaudeDir -Destination $backupPath -Recurse -Force
        Write-Success "Backup created: $backupPath"
    }
}

function Get-ProjectProperties {
    param([Parameter(Mandatory)]$Config)

    if (-not ($Config.PSObject.Properties.Name -contains "projects") -or $null -eq $Config.projects) {
        return @()
    }

    return @($Config.projects.PSObject.Properties)
}

function List-Projects {
    $config = Read-ClaudeJson
    Write-Info "Projects in ${ClaudeJson}:"
    Write-Host ""

    $projects = Get-ProjectProperties -Config $config
    if ($projects.Count -eq 0) {
        Write-WarningMessage "No projects found"
        return
    }

    foreach ($project in $projects) {
        Write-Host "  $($project.Name)"
    }
}

function Clear-AllHistories {
    $config = Read-ClaudeJson
    foreach ($project in (Get-ProjectProperties -Config $config)) {
        if ($project.Value.PSObject.Properties.Name -contains "history") {
            $project.Value.history = @()
        }
        else {
            Add-Member -InputObject $project.Value -MemberType NoteProperty -Name "history" -Value @()
        }
    }
    Save-ClaudeJson -Config $config
    Write-Success "Cleared all project histories"
}

function Clear-ProjectHistory {
    param([Parameter(Mandatory)][string]$ProjectPath)

    $config = Read-ClaudeJson
    $project = Get-ProjectProperties -Config $config | Where-Object { $_.Name -eq $ProjectPath } | Select-Object -First 1
    if (-not $project) {
        throw "Project not found: $ProjectPath"
    }

    if ($project.Value.PSObject.Properties.Name -contains "history") {
        $project.Value.history = @()
    }
    else {
        Add-Member -InputObject $project.Value -MemberType NoteProperty -Name "history" -Value @()
    }

    Save-ClaudeJson -Config $config
    Write-Success "Cleared history for: $ProjectPath"
}

function Remove-Project {
    param([Parameter(Mandatory)][string]$ProjectPath)

    $config = Read-ClaudeJson
    if (-not (Get-ProjectProperties -Config $config | Where-Object { $_.Name -eq $ProjectPath } | Select-Object -First 1)) {
        throw "Project not found: $ProjectPath"
    }

    $config.projects.PSObject.Properties.Remove($ProjectPath)
    Save-ClaudeJson -Config $config
    Write-Success "Deleted project: $ProjectPath"
}

function Clear-AllProjects {
    $config = Read-ClaudeJson
    if ($config.PSObject.Properties.Name -contains "projects") {
        $config.projects = [pscustomobject]@{}
    }
    else {
        Add-Member -InputObject $config -MemberType NoteProperty -Name "projects" -Value ([pscustomobject]@{})
    }
    Save-ClaudeJson -Config $config
    Write-Success "Cleared all projects"
}

function Remove-JsonPropertyIfPresent {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name
    )

    if ($Object.PSObject.Properties.Name -contains $Name) {
        $Object.PSObject.Properties.Remove($Name)
    }
}

function Set-JsonProperty {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value
    )

    if ($Object.PSObject.Properties.Name -contains $Name) {
        $Object.PSObject.Properties[$Name].Value = $Value
    }
    else {
        Add-Member -InputObject $Object -MemberType NoteProperty -Name $Name -Value $Value
    }
}

function Clear-CacheData {
    $config = Read-ClaudeJson

    @(
        "cachedChangelog",
        "cachedStatsigGates",
        "cachedDynamicConfigs",
        "cachedGrowthBookFeatures",
        "metricsStatusCache",
        "clientDataCache",
        "hasShownOpus45Notice"
    ) | ForEach-Object { Remove-JsonPropertyIfPresent -Object $config -Name $_ }

    if ($config.PSObject.Properties.Name -contains "groveConfigCache") {
        $config.groveConfigCache = [pscustomobject]@{}
    }
    if ($config.PSObject.Properties.Name -contains "passesEligibilityCache") {
        $config.passesEligibilityCache = [pscustomobject]@{}
    }
    if ($config.PSObject.Properties.Name -contains "s1mAccessCache") {
        $config.s1mAccessCache = [pscustomobject]@{}
    }
    if ($config.PSObject.Properties.Name -contains "lastPlanModeUse") {
        $config.lastPlanModeUse = 0
    }
    if ($config.PSObject.Properties.Name -contains "passesUpsellSeenCount") {
        $config.passesUpsellSeenCount = 0
    }

    Save-ClaudeJson -Config $config
    Write-Success "Cleared cached data"
}

function Clear-GithubRepoPaths {
    $config = Read-ClaudeJson
    Remove-JsonPropertyIfPresent -Object $config -Name "githubRepoPaths"
    Save-ClaudeJson -Config $config
    Write-Success "Cleared githubRepoPaths"
}

function New-UserId {
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    }
    finally {
        $rng.Dispose()
    }
    return -join ($bytes | ForEach-Object { $_.ToString("x2") })
}

function New-AnonymousId {
    return "claudecode.v1.$([System.Guid]::NewGuid().ToString().ToLowerInvariant())"
}

function Get-IdentityValue {
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string[]]$Names
    )

    foreach ($name in $Names) {
        if ($Config.PSObject.Properties.Name -contains $name) {
            return [string]$Config.PSObject.Properties[$name].Value
        }
    }

    return ""
}

function Format-MaskedIdentity {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return "<missing>"
    }

    if ($Value.Length -le 8) {
        return "***"
    }

    return "$($Value.Substring(0, 4))...$($Value.Substring($Value.Length - 4))"
}

function Reset-Counters {
    $config = Read-ClaudeJson
    $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.000Z")

    foreach ($name in @("numStartups", "btwUseCount", "promptQueueUseCount", "opus1mMergeNoticeSeenCount", "voiceNoticeSeenCount")) {
        if ($config.PSObject.Properties.Name -contains $name) {
            $config.$name = 0
        }
    }

    foreach ($name in @("firstStartTime", "claudeCodeFirstTokenDate")) {
        if ($config.PSObject.Properties.Name -contains $name) {
            $config.$name = $now
        }
    }

    foreach ($name in @("skillUsage", "toolUsage")) {
        if ($config.PSObject.Properties.Name -contains $name) {
            $config.$name = [pscustomobject]@{}
        }
    }

    if ($config.PSObject.Properties.Name -contains "tipsHistory" -and $null -ne $config.tipsHistory) {
        if ($config.tipsHistory -is [System.Array]) {
            $config.tipsHistory = @($config.tipsHistory | ForEach-Object { 0 })
        }
        elseif ($config.tipsHistory -is [System.Collections.IDictionary]) {
            foreach ($key in @($config.tipsHistory.Keys)) {
                $config.tipsHistory[$key] = 0
            }
        }
        elseif ($config.tipsHistory -is [pscustomobject]) {
            foreach ($tip in @($config.tipsHistory.PSObject.Properties)) {
                $config.tipsHistory.PSObject.Properties[$tip.Name].Value = 0
            }
        }
    }

    Save-ClaudeJson -Config $config
    Write-Success "Reset numStartups, btwUseCount, promptQueueUseCount, tipsHistory, opus1mMergeNoticeSeenCount, voiceNoticeSeenCount, firstStartTime, claudeCodeFirstTokenDate, skillUsage, and toolUsage"
}

function Reset-IdentityIds {
    $config = Read-ClaudeJson
    $oldUserId = Get-IdentityValue -Config $config -Names @("userID", "user_id", "userId")
    $oldAnonymousId = Get-IdentityValue -Config $config -Names @("anonymousId")
    $newUserId = New-UserId
    $newAnonymousId = New-AnonymousId

    if ($config.PSObject.Properties.Name -contains "userID") {
        $config.userID = $newUserId
    }
    elseif ($config.PSObject.Properties.Name -contains "user_id") {
        $config.user_id = $newUserId
    }
    elseif ($config.PSObject.Properties.Name -contains "userId") {
        $config.userId = $newUserId
    }
    else {
        Add-Member -InputObject $config -MemberType NoteProperty -Name "userID" -Value $newUserId
    }

    Set-JsonProperty -Object $config -Name "anonymousId" -Value $newAnonymousId
    Save-ClaudeJson -Config $config

    $writtenConfig = Read-ClaudeJson
    $writtenUserId = Get-IdentityValue -Config $writtenConfig -Names @("userID", "user_id", "userId")
    $writtenAnonymousId = Get-IdentityValue -Config $writtenConfig -Names @("anonymousId")

    if ($writtenUserId -ne $newUserId -or $writtenAnonymousId -ne $newAnonymousId) {
        throw "Failed to verify regenerated identity IDs after writing $ClaudeJson"
    }

    $parts = @()
    if ([string]::IsNullOrEmpty($oldUserId)) {
        $parts += "userID created: $(Format-MaskedIdentity $writtenUserId)"
    }
    elseif ($oldUserId -ne $writtenUserId) {
        $parts += "userID changed: $(Format-MaskedIdentity $oldUserId) -> $(Format-MaskedIdentity $writtenUserId)"
    }
    else {
        throw "userID did not change after regeneration"
    }

    if ([string]::IsNullOrEmpty($oldAnonymousId)) {
        $parts += "anonymousId created: $(Format-MaskedIdentity $writtenAnonymousId)"
    }
    elseif ($oldAnonymousId -ne $writtenAnonymousId) {
        $parts += "anonymousId changed: $(Format-MaskedIdentity $oldAnonymousId) -> $(Format-MaskedIdentity $writtenAnonymousId)"
    }
    else {
        throw "anonymousId did not change after regeneration"
    }

    Write-Success "Verified identity replacement ($($parts -join '; '))"
}

function Clear-DirectoryContents {
    param([Parameter(Mandatory)][string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Container) {
        Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
        return $true
    }

    return $false
}

function Clear-ClaudeFolders {
    $cleaned = $false
    $folders = @(
        "file-history",
        "projects",
        "todos",
        "shell-snapshots",
        "statsig",
        "debug",
        "session-env",
        "tasks",
        "plans",
        "paste-cache",
        "telemetry",
        "backups"
    )

    foreach ($folder in $folders) {
        $path = Join-Path $ClaudeDir $folder
        if (Clear-DirectoryContents -Path $path) {
            Write-Success "Cleared $folder"
            $cleaned = $true
        }
    }

    $statsCache = Join-Path $ClaudeDir "stats-cache.json"
    if (Test-Path -LiteralPath $statsCache -PathType Leaf) {
        Set-Content -LiteralPath $statsCache -Value "" -NoNewline
        Write-Success "Cleared stats-cache.json"
        $cleaned = $true
    }

    if (-not $cleaned) {
        Write-WarningMessage "No folders found to clean"
    }
}

function Clear-HistoryJsonl {
    $historyPath = Join-Path $ClaudeDir "history.jsonl"
    if (Test-Path -LiteralPath $historyPath -PathType Leaf) {
        Set-Content -LiteralPath $historyPath -Value "" -NoNewline
        Write-Success "Cleared history.jsonl"
    }
    else {
        Write-WarningMessage "history.jsonl not found"
    }
}

function Invoke-CleanAll {
    Write-Info "Performing deep clean..."
    Write-Host ""

    Clear-AllHistories
    Clear-AllProjects
    Clear-ClaudeFolders
    Clear-CacheData
    Clear-GithubRepoPaths
    Clear-HistoryJsonl
    Reset-Counters
    Reset-IdentityIds
    Write-Success "Deep clean completed!"
}

function Invoke-Interactive {
    $config = Read-ClaudeJson
    $projects = Get-ProjectProperties -Config $config

    Write-Info "Interactive Mode - Select projects to clean"
    Write-Host ""

    if ($projects.Count -eq 0) {
        Write-WarningMessage "No projects found"
        return
    }

    Write-Host "Projects:"
    for ($i = 0; $i -lt $projects.Count; $i++) {
        $project = $projects[$i]
        $historyCount = 0
        if ($project.Value.PSObject.Properties.Name -contains "history" -and $null -ne $project.Value.history) {
            $historyCount = @($project.Value.history).Count
        }
        Write-Host ("  [{0}] {1} ({2} history items)" -f ($i + 1), $project.Name, $historyCount)
    }

    Write-Host ""
    Write-Host "Options:"
    Write-Host "  [a] Clean everything"
    Write-Host "  [c] Clear cache"
    Write-Host "  [g] Clear GitHub repository paths"
    Write-Host "  [f] Clear folders"
    Write-Host "  [u] Regenerate userID and anonymousId"
    Write-Host "  [q] Quit"
    Write-Host ""

    $selection = Read-Host "Enter selection (number/a/c/g/f/u/q)"
    switch -Regex ($selection) {
        "^[aA]$" {
            if ((Read-Host "Clean everything? (y/N)") -match "^[Yy]$") { Invoke-CleanAll }
            break
        }
        "^[cC]$" {
            if ((Read-Host "Clear cached data? (y/N)") -match "^[Yy]$") { Clear-CacheData }
            break
        }
        "^[gG]$" {
            if ((Read-Host "Clear GitHub repository paths? (y/N)") -match "^[Yy]$") { Clear-GithubRepoPaths }
            break
        }
        "^[fF]$" {
            if ((Read-Host "Clear .claude folders and history.jsonl? (y/N)") -match "^[Yy]$") {
                Clear-ClaudeFolders
                Clear-HistoryJsonl
            }
            break
        }
        "^[uU]$" {
            if ((Read-Host "Regenerate userID and anonymousId? (y/N)") -match "^[Yy]$") { Reset-IdentityIds }
            break
        }
        "^[qQ]$" {
            Write-Info "Exiting"
            break
        }
        "^[0-9]+$" {
            $index = [int]$selection - 1
            if ($index -lt 0 -or $index -ge $projects.Count) {
                throw "Invalid selection"
            }

            $projectPath = $projects[$index].Name
            Write-Host ""
            Write-Host "What would you like to do with: $projectPath"
            Write-Host "  [1] Clear history only"
            Write-Host "  [2] Delete project entirely"
            Write-Host "  [q] Cancel"

            $action = Read-Host "Enter selection"
            switch ($action) {
                "1" { Clear-ProjectHistory -ProjectPath $projectPath }
                "2" {
                    if ((Read-Host "Delete project entirely? (y/N)") -match "^[Yy]$") {
                        Remove-Project -ProjectPath $projectPath
                    }
                }
                default { Write-Info "Cancelled" }
            }
            break
        }
        default {
            throw "Invalid selection"
        }
    }
}

function Get-RequestedActionCount {
    $count = 0
    foreach ($enabled in @($All, [bool]$Project, $List, $Interactive, $Cache, $GithubRepos, $Folders, $UserId)) {
        if ($enabled) { $count++ }
    }
    return $count
}

try {
    if ($Help -or (Get-RequestedActionCount) -eq 0) {
        Show-Usage
        exit 0
    }

    if ((Get-RequestedActionCount) -gt 1) {
        throw "Please specify only one action at a time."
    }

    if ($List) {
        List-Projects
        exit 0
    }

    if (-not $NoBackup) {
        New-Backup
        Write-Host ""
    }

    if ($All) {
        Invoke-CleanAll
    }
    elseif ($Project) {
        Clear-ProjectHistory -ProjectPath $Project
    }
    elseif ($Interactive) {
        Invoke-Interactive
    }
    elseif ($Cache) {
        Clear-CacheData
    }
    elseif ($GithubRepos) {
        Clear-GithubRepoPaths
    }
    elseif ($Folders) {
        Clear-ClaudeFolders
        Clear-HistoryJsonl
    }
    elseif ($UserId) {
        Reset-IdentityIds
    }

    if (-not $All) {
        Write-Success "Done!"
    }
}
catch {
    Write-ErrorMessage $_.Exception.Message
    exit 1
}

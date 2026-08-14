#Requires -Version 5.1
<#
.SYNOPSIS
    Copies selected Codex or Claude Code operation logs to the Box audit folder.

.DESCRIPTION
    Authentication and configuration files are deliberately not copied. This
    script uses a whitelist of transcript, history, and diagnostic-log paths;
    it never copies an agent's state directory as a whole.
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Codex", "ClaudeCode")]
    [string]$Tool,

    [Parameter(Mandatory = $true)]
    [string]$BoxTarget,

    [Parameter(Mandatory = $true)]
    [string]$SandboxUser
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$auditRoot = Join-Path $BoxTarget (Join-Path "Sandbox" (Join-Path $SandboxUser "AI-Agent-Audit"))
$destinationRoot = Join-Path $auditRoot $Tool
$excludedFileNames = @("auth.json", ".credentials.json", "config.toml")
$copiedFiles = 0
$copyErrors = [System.Collections.Generic.List[string]]::new()

function Copy-LogFile {
    param(
        [Parameter(Mandatory = $true)][string]$SourceFile,
        [Parameter(Mandatory = $true)][string]$DestinationFile
    )

    if ((Split-Path -Leaf $SourceFile) -in $excludedFileNames) { return }

    try {
        New-Item -ItemType Directory -Path (Split-Path -Parent $DestinationFile) -Force | Out-Null
        Copy-Item -LiteralPath $SourceFile -Destination $DestinationFile -Force
        $script:copiedFiles++
    } catch {
        $script:copyErrors.Add("$SourceFile : $($_.Exception.Message)")
    }
}

function Copy-LogDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$SourceDirectory,
        [Parameter(Mandatory = $true)][string]$DestinationDirectory
    )

    if (-not (Test-Path -LiteralPath $SourceDirectory -PathType Container)) { return }

    Get-ChildItem -LiteralPath $SourceDirectory -File -Recurse -Force | ForEach-Object {
        $relativePath = $_.FullName.Substring($SourceDirectory.Length).TrimStart("\\")
        Copy-LogFile -SourceFile $_.FullName -DestinationFile (Join-Path $DestinationDirectory $relativePath)
    }
}

try {
    New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null

    if ($Tool -eq "Codex") {
        $codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME ".codex" }
        $history = Join-Path $codexHome "history.jsonl"
        if (Test-Path -LiteralPath $history -PathType Leaf) {
            Copy-LogFile -SourceFile $history -DestinationFile (Join-Path $destinationRoot "history.jsonl")
        }
        Copy-LogDirectory -SourceDirectory (Join-Path $codexHome "sessions") -DestinationDirectory (Join-Path $destinationRoot "sessions")
        Copy-LogDirectory -SourceDirectory (Join-Path $codexHome "archived_sessions") -DestinationDirectory (Join-Path $destinationRoot "archived_sessions")
        Copy-LogDirectory -SourceDirectory (Join-Path $codexHome "logs") -DestinationDirectory (Join-Path $destinationRoot "logs")
    } else {
        $claudeConfig = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE ".claude" }
        $history = Join-Path $claudeConfig "history.jsonl"
        if (Test-Path -LiteralPath $history -PathType Leaf) {
            Copy-LogFile -SourceFile $history -DestinationFile (Join-Path $destinationRoot "history.jsonl")
        }
        Copy-LogDirectory -SourceDirectory (Join-Path $claudeConfig "projects") -DestinationDirectory (Join-Path $destinationRoot "projects")
        Copy-LogDirectory -SourceDirectory (Join-Path $claudeConfig "debug") -DestinationDirectory (Join-Path $destinationRoot "debug")
    }
} catch {
    $copyErrors.Add($_.Exception.Message)
}

if ($copyErrors.Count -gt 0) {
    Write-Error ("$Tool log synchronization completed with $($copyErrors.Count) error(s): " + ($copyErrors -join " | "))
    exit 1
}

Write-Host "$Tool audit logs synchronized: $copiedFiles file(s) -> $destinationRoot"
exit 0

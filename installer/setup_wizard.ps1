#Requires -Version 5.1
<#
.SYNOPSIS
  AI Agent Guardrail セットアップウィザード（GUI）
  SETUP.bat または PowerShell から直接実行できます。
#>
param()

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---- Paths ----------------------------------------------------------------
$repoRoot        = Split-Path -Parent $PSScriptRoot
$installerScript = Join-Path $PSScriptRoot "install_standard.ps1"
$workspaceShortcutScript = Join-Path $PSScriptRoot "register_workspace_shortcut.ps1"
$workspaceRuntimeScript = Join-Path $PSScriptRoot "install_workspace_runtime.ps1"

if (-not (Test-Path $installerScript)) {
    [System.Windows.Forms.MessageBox]::Show(
        "installer\install_standard.ps1 が見つかりません。`n`n" +
        "SETUP.bat をリポジトリのルートフォルダから実行してください。",
        "ファイルが見つかりません",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 1
}

# ---- Environment detection ------------------------------------------------
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Test-Command([string]$name) {
    $null -ne (Get-Command $name -ErrorAction SilentlyContinue)
}

# Persist the Python command path for applications launched after SETUP.bat
# finishes (not merely for this PowerShell process). Claude Code starts its
# hook through cmd.exe, so a process-only PATH update is insufficient.
function Add-PythonToUserPath {
    param([Parameter(Mandatory = $true)][string]$PythonExe)

    $pythonDir  = Split-Path -Parent $PythonExe
    $scriptsDir = Join-Path $pythonDir 'Scripts'
    $current    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries    = @($current -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $known      = @{}
    foreach ($entry in $entries) {
        $known[[Environment]::ExpandEnvironmentVariables($entry).TrimEnd('\').ToLowerInvariant()] = $true
    }
    foreach ($entry in @($pythonDir, $scriptsDir)) {
        $key = $entry.TrimEnd('\').ToLowerInvariant()
        if (-not $known.ContainsKey($key)) {
            $entries += $entry
            $known[$key] = $true
        }
    }

    $updated = $entries -join ';'
    [Environment]::SetEnvironmentVariable('Path', $updated, 'User')
    $env:Path = "$pythonDir;$scriptsDir;$env:Path"
}

$isAdmin       = Test-IsAdmin
$hasNode       = Test-Command "node"
$hasNpm        = Test-Command "npm"
$hasGit        = Test-Command "git"
$hasClaude     = Test-Command "claude"
$hasCodex      = Test-Command "codex"
$hasWinget     = Test-Command "winget"

# Python detection: check PATH first (python / python3), then common
# Miniforge / Mambaforge / Conda / Anaconda installation directories.
function Find-PythonExe {
    function Test-PythonExe([string]$Candidate) {
        if (-not $Candidate -or -not (Test-Path -LiteralPath $Candidate -PathType Leaf)) { return $false }
        try {
            $version = & $Candidate --version 2>$null
            return ($LASTEXITCODE -eq 0 -and "$version" -match '^Python\s+\d+\.\d+')
        } catch { return $false }
    }

    foreach ($name in @('python', 'python3')) {
        $c = Get-Command $name -ErrorAction SilentlyContinue
        if ($c -and $c.Source -and (Test-Path -LiteralPath $c.Source -PathType Leaf)) {
            # Windows の App Execution Alias は python.exe として見つかっても、
            # 実体の Python がアンインストール済みなら Microsoft Store を開くだけです。
            # 実行可能な CPython であることまで確認して、誤って「検出済み」にしない。
            if (Test-PythonExe $c.Source) { return $c.Source }
        }
    }
    $wingetPythonRoot = Join-Path $env:LOCALAPPDATA 'Programs\Python'
    if (Test-Path -LiteralPath $wingetPythonRoot -PathType Container) {
        $candidates = @()
        foreach ($directory in Get-ChildItem -LiteralPath $wingetPythonRoot -Directory -ErrorAction SilentlyContinue) {
            $candidate = Join-Path $directory.FullName 'python.exe'
            if ((Test-PythonExe $candidate) -and ($candidate -notmatch '(?i)[\\/](?:\.venv|venv)[\\/]')) { $candidates += $candidate }
        }
        if ($candidates.Count -gt 0) { return ($candidates | Sort-Object -Descending | Select-Object -First 1) }
    }
    $condaBases = @(
        "$env:USERPROFILE\miniforge3",
        "$env:USERPROFILE\mambaforge",
        "$env:USERPROFILE\miniconda3",
        "$env:USERPROFILE\Miniconda3",
        "$env:USERPROFILE\anaconda3",
        "$env:USERPROFILE\Anaconda3",
        "$env:LOCALAPPDATA\miniforge3",
        "$env:LOCALAPPDATA\mambaforge",
        "$env:ProgramData\miniforge3",
        "$env:ProgramData\mambaforge",
        "C:\miniforge3",
        "C:\mambaforge",
        "C:\miniconda3",
        "C:\anaconda3"
    )
    foreach ($base in $condaBases) {
        $py = Join-Path $base 'python.exe'
        if (Test-PythonExe $py) { return $py }
    }
    return $null
}

$pythonExePath = Find-PythonExe
$hasPython     = $null -ne $pythonExePath
# If Python was already installed but was not on PATH, persist both its main
# directory and Scripts directory. The former implementation updated only
# this setup process, so Claude Code launched later could not run the hook.
if ($hasPython) {
    Add-PythonToUserPath -PythonExe $pythonExePath
}

$nodeVer   = if ($hasNode)   { (node --version 2>$null) -replace '^v','' } else { $null }
$claudeVer = if ($hasClaude) {
    $v = (claude --version 2>$null); if ($v) { "$v" } else { "検出済み" }
} else { $null }
$codexVer  = if ($hasCodex)  { "検出済み" } else { $null }

$defaultInstallPath = Join-Path $env:USERPROFILE "AIAgent_Workspace"

# ---- Design tokens --------------------------------------------------------
$clrHeader    = [System.Drawing.Color]::FromArgb(0, 71, 171)
$clrHeaderFg  = [System.Drawing.Color]::White
$clrSubFg     = [System.Drawing.Color]::FromArgb(200, 220, 255)
$clrBg        = [System.Drawing.Color]::FromArgb(245, 246, 248)
$clrWhite     = [System.Drawing.Color]::White
$clrInstall   = [System.Drawing.Color]::FromArgb(0, 120, 215)
$clrInstallFg = [System.Drawing.Color]::White
$clrDone      = [System.Drawing.Color]::FromArgb(40, 167, 69)
$clrDoneFg    = [System.Drawing.Color]::White
$clrFail      = [System.Drawing.Color]::FromArgb(180, 40, 40)
$clrDisabled  = [System.Drawing.Color]::FromArgb(190, 190, 190)
$clrDisabledFg = [System.Drawing.Color]::FromArgb(120, 120, 120)
$clrWarn      = [System.Drawing.Color]::FromArgb(255, 248, 230)
$clrWarnBorder = [System.Drawing.Color]::FromArgb(255, 193, 7)

$fntTitle = New-Object System.Drawing.Font("Meiryo UI", 14, [System.Drawing.FontStyle]::Bold)
$fntSub   = New-Object System.Drawing.Font("Meiryo UI",  9)
$fntUI    = New-Object System.Drawing.Font("Meiryo UI",  9)
$fntSmall = New-Object System.Drawing.Font("Meiryo UI",  8)
$fntBtn   = New-Object System.Drawing.Font("Meiryo UI", 11, [System.Drawing.FontStyle]::Bold)
$fntLog   = New-Object System.Drawing.Font("Consolas",   9)

# ---- Form -----------------------------------------------------------------
$contentSize = New-Object System.Drawing.Size(600, 1218)

$form = New-Object System.Windows.Forms.Form
$form.Text            = "AI Agent Workspace セットアップ v0.2"
$form.StartPosition   = "CenterScreen"
$form.FormBorderStyle = "Sizable"
$form.MaximizeBox     = $true
$form.MinimumSize     = New-Object System.Drawing.Size(($contentSize.Width + 18), 300)
$form.BackColor       = $clrBg
$form.Font            = $fntUI
$form.AutoScroll         = $true
$form.AutoScrollMinSize  = $contentSize

# Fit on screen: use the full content height when it fits, otherwise clamp to
# the visible work area so the window (and its scrollbar) stay on-screen
# instead of the previous fixed 600x1130 running off the bottom of smaller
# displays with no way to reach the lower controls.
$workArea  = [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position).WorkingArea
$formWidth  = $contentSize.Width + 18
$formHeight = [Math]::Min($contentSize.Height + 40, $workArea.Height - 40)
$form.Size = New-Object System.Drawing.Size($formWidth, $formHeight)

# ---- Header ---------------------------------------------------------------
$pnlHeader = New-Object System.Windows.Forms.Panel
$pnlHeader.Location  = New-Object System.Drawing.Point(0, 0)
$pnlHeader.Size      = New-Object System.Drawing.Size(600, 82)
$pnlHeader.BackColor = $clrHeader
$form.Controls.Add($pnlHeader)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text      = "AI Agent Workspace"
$lblTitle.Font      = $fntTitle
$lblTitle.ForeColor = $clrHeaderFg
$lblTitle.Location  = New-Object System.Drawing.Point(16, 10)
$lblTitle.AutoSize  = $true
$pnlHeader.Controls.Add($lblTitle)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text      = "v0.2  |  Claude Code / Codex 向け標準ガードレール"
$lblSub.Font      = $fntSub
$lblSub.ForeColor = $clrSubFg
$lblSub.Location  = New-Object System.Drawing.Point(18, 50)
$lblSub.AutoSize  = $true
$pnlHeader.Controls.Add($lblSub)

# ---- Tool detection strip -------------------------------------------------
$pnlDetect = New-Object System.Windows.Forms.Panel
$pnlDetect.Location    = New-Object System.Drawing.Point(14, 96)
$pnlDetect.Size        = New-Object System.Drawing.Size(562, 68)
$pnlDetect.BackColor   = $clrWhite
$pnlDetect.BorderStyle = "FixedSingle"
$form.Controls.Add($pnlDetect)

function New-StatusLabel([string]$text, [System.Drawing.Color]$color, [int]$x, [int]$y) {
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text      = $text
    $lbl.ForeColor = $color
    $lbl.Font      = $fntSmall
    $lbl.Location  = New-Object System.Drawing.Point($x, $y)
    $lbl.AutoSize  = $true
    $lbl
}

# Row 1: Node.js / Claude Code / Codex
$nodeIcon  = if ($hasNode)   { "[OK]" } else { "[!]" }
$nodeColor = if ($hasNode)   { [System.Drawing.Color]::DarkGreen } else { [System.Drawing.Color]::Red }
$nodeText  = if ($hasNode)   { "Node.js v$nodeVer" } else { "Node.js 未検出" }

$claudeIcon  = if ($hasClaude) { "[OK]" } else { "[!]" }
$claudeColor = if ($hasClaude) { [System.Drawing.Color]::DarkGreen } else { [System.Drawing.Color]::DarkOrange }
$claudeText  = if ($hasClaude) { "Claude Code $claudeVer" } else { "Claude Code 未検出" }

$codexIcon  = if ($hasCodex) { "[OK]" } else { "[!]" }
$codexColor = if ($hasCodex) { [System.Drawing.Color]::DarkGreen } else { [System.Drawing.Color]::DarkOrange }
$codexText  = if ($hasCodex) { "Codex $codexVer" } else { "Codex 未検出" }

$pnlDetect.Controls.Add((New-StatusLabel "$nodeIcon  $nodeText"   $nodeColor   8 6))
$pnlDetect.Controls.Add((New-StatusLabel "$claudeIcon  $claudeText" $claudeColor 8 26))
$pnlDetect.Controls.Add((New-StatusLabel "$codexIcon  $codexText"   $codexColor  8 46))

# Row 1 right: admin / python
$adminIcon  = if ($isAdmin)   { "[OK]" } else { "[!]" }
$adminColor = if ($isAdmin)   { [System.Drawing.Color]::DarkGreen } else { [System.Drawing.Color]::DarkOrange }
$adminText  = if ($isAdmin)   { "管理者権限あり" } else { "管理者権限なし（制限あり）" }

$pyIcon  = if ($hasPython) { "[OK]" } else { "[!]" }
$pyColor = if ($hasPython) { [System.Drawing.Color]::DarkGreen } else { [System.Drawing.Color]::DarkOrange }
$pyText  = if (-not $hasPython) {
    "Python 未検出"
} elseif (Test-Command 'python') {
    "Python 検出済み"
} else {
    $pythonInstallName = Split-Path (Split-Path $pythonExePath -Parent) -Leaf
    "Python 検出済み（$pythonInstallName）"
}

$pnlDetect.Controls.Add((New-StatusLabel "$adminIcon  $adminText" $adminColor 320 6))
$pnlDetect.Controls.Add((New-StatusLabel "$pyIcon  $pyText"       $pyColor   320 26))

# Node.js warning
if (-not $hasNode) {
    $lblNodeWarn = New-Object System.Windows.Forms.Label
    $lblNodeWarn.Text      = "  Node.js が見つかりません。Claude Code / Codex のインストールには Node.js が必要です。"
    $lblNodeWarn.Font      = $fntSmall
    $lblNodeWarn.ForeColor = [System.Drawing.Color]::FromArgb(120, 80, 0)
    $lblNodeWarn.Location  = New-Object System.Drawing.Point(320, 46)
    $lblNodeWarn.AutoSize  = $true
    $pnlDetect.Controls.Add($lblNodeWarn)
}

# ---- Group: Runtime / AI tool installation --------------------------------
$gbTools = New-Object System.Windows.Forms.GroupBox
$gbTools.Text      = "  ランタイム / AI ツール  "
$gbTools.Location  = New-Object System.Drawing.Point(14, 174)
$gbTools.Size      = New-Object System.Drawing.Size(562, 172)
$gbTools.BackColor = $clrWhite
$form.Controls.Add($gbTools)

# Node.js checkbox (winget) — prerequisite for Claude Code / Codex npm install
$cbInstNode = New-Object System.Windows.Forms.CheckBox
if ($hasNode) {
    $cbInstNode.Text    = "Node.js  ─  検出済み（インストール不要）"
    $cbInstNode.Checked = $false
    $cbInstNode.Enabled = $false
} elseif (-not $hasWinget) {
    $cbInstNode.Text    = "Node.js  ─  未インストール（winget も未検出のため自動導入できません。手動で導入してください）"
    $cbInstNode.Checked = $false
    $cbInstNode.Enabled = $false
} else {
    $cbInstNode.Text    = "Node.js  ─  未インストール → セットアップ時にインストールします  (winget install OpenJS.NodeJS.LTS)"
    $cbInstNode.Checked = $true
    $cbInstNode.Enabled = $true
}
$cbInstNode.Location = New-Object System.Drawing.Point(12, 24)
$cbInstNode.Size     = New-Object System.Drawing.Size(538, 22)
$gbTools.Controls.Add($cbInstNode)

# Python checkbox (winget) — prerequisite for the guardrail hook itself
$cbInstPython = New-Object System.Windows.Forms.CheckBox
if ($hasPython) {
    $cbInstPython.Text    = "Python  ─  検出済み（インストール不要）"
    $cbInstPython.Checked = $false
    $cbInstPython.Enabled = $false
} elseif (-not $hasWinget) {
    $cbInstPython.Text    = "Python  ─  未インストール（winget も未検出のため自動導入できません。手動で導入してください）"
    $cbInstPython.Checked = $false
    $cbInstPython.Enabled = $false
} else {
    $cbInstPython.Text    = "Python  ─  未インストール → セットアップ時にインストールします  (winget install Python.Python.3.12)"
    $cbInstPython.Checked = $true
    $cbInstPython.Enabled = $true
}
$cbInstPython.Location = New-Object System.Drawing.Point(12, 52)
$cbInstPython.Size     = New-Object System.Drawing.Size(538, 22)
$gbTools.Controls.Add($cbInstPython)

# Claude Code checkbox
$cbInstClaude = New-Object System.Windows.Forms.CheckBox
if ($hasClaude) {
    $cbInstClaude.Text    = "Claude Code  ─  インストール済み（このステップはスキップされます）"
    $cbInstClaude.Checked = $false
    $cbInstClaude.Enabled = $false
} else {
    $cbInstClaude.Text    = "Claude Code  ─  未インストール → セットアップ時にインストールします  (npm install -g @anthropic-ai/claude-code)"
    $cbInstClaude.Checked = $true
    $cbInstClaude.Enabled = $true
}
$cbInstClaude.Location = New-Object System.Drawing.Point(12, 80)
$cbInstClaude.Size     = New-Object System.Drawing.Size(538, 22)
$gbTools.Controls.Add($cbInstClaude)

# Codex checkbox
$cbInstCodex = New-Object System.Windows.Forms.CheckBox
if ($hasCodex) {
    $cbInstCodex.Text    = "Codex  ─  インストール済み（このステップはスキップされます）"
    $cbInstCodex.Checked = $false
    $cbInstCodex.Enabled = $false
} else {
    $cbInstCodex.Text    = "Codex  ─  未インストール → セットアップ時にインストールします  (npm install -g @openai/codex)"
    $cbInstCodex.Checked = $true
    $cbInstCodex.Enabled = $true
}
$cbInstCodex.Location = New-Object System.Drawing.Point(12, 108)
$cbInstCodex.Size     = New-Object System.Drawing.Size(538, 22)
$gbTools.Controls.Add($cbInstCodex)

# Git checkbox (winget) — needed by Claude Code to pull git-based plugin
# marketplaces (e.g. extraKnownMarketplaces entries) configured via the
# Gateway's authentication settings.
$cbInstGit = New-Object System.Windows.Forms.CheckBox
if ($hasGit) {
    $cbInstGit.Text    = "Git  ─  検出済み（インストール不要）"
    $cbInstGit.Checked = $false
    $cbInstGit.Enabled = $false
} elseif (-not $hasWinget) {
    $cbInstGit.Text    = "Git  ─  未インストール（winget も未検出のため自動導入できません。手動で導入してください）"
    $cbInstGit.Checked = $false
    $cbInstGit.Enabled = $false
} else {
    $cbInstGit.Text    = "Git  ─  未インストール → セットアップ時にインストールします  (winget install Git.Git)"
    $cbInstGit.Checked = $true
    $cbInstGit.Enabled = $true
}
$cbInstGit.Location = New-Object System.Drawing.Point(12, 136)
$cbInstGit.Size     = New-Object System.Drawing.Size(538, 22)
$gbTools.Controls.Add($cbInstGit)

# Claude Code / Codex need npm (Node.js). If Node.js is absent and the user
# unchecks its auto-install box, disable the two npm-dependent checkboxes so
# the install can't silently fail later for a reason the user can't see here.
function Update-ClaudeCodexAvailability {
    $nodeWillBeAvailable = $hasNode -or $cbInstNode.Checked
    if (-not $hasClaude) {
        $cbInstClaude.Enabled = $nodeWillBeAvailable
        if (-not $nodeWillBeAvailable) { $cbInstClaude.Checked = $false }
    }
    if (-not $hasCodex) {
        $cbInstCodex.Enabled = $nodeWillBeAvailable
        if (-not $nodeWillBeAvailable) { $cbInstCodex.Checked = $false }
    }
}
$cbInstNode.Add_CheckedChanged({ Update-ClaudeCodexAvailability })
Update-ClaudeCodexAvailability

# ---- Group: Authentication settings ---------------------------------------
# Always show these controls. Tool detection only controls installation; it
# must never hide the credentials needed to refresh an existing setup.
# Two modes per tool: "Gateway" (paste output from an internal AI Gateway's Set
# Up screen, format-specific) or "API" (generic Key/Model/Base URL, works with
# any Anthropic/OpenAI-compatible endpoint). Radio buttons live in their own
# Panel per tool because WinForms treats all RadioButtons sharing one direct
# parent as a single mutually-exclusive group — without separate Panels the
# Claude and Codex radios would fight each other.
$gbAuth = New-Object System.Windows.Forms.GroupBox
$gbAuth.Text      = "  認証設定  "
$gbAuth.Location  = New-Object System.Drawing.Point(14, 356)
$gbAuth.Size      = New-Object System.Drawing.Size(562, 184)
$gbAuth.BackColor = $clrWhite
$form.Controls.Add($gbAuth)

function New-AuthModeRadio([string]$text, [int]$x, [int]$y) {
    $rb = New-Object System.Windows.Forms.RadioButton
    $rb.Text     = $text
    $rb.Location = New-Object System.Drawing.Point($x, $y)
    $rb.AutoSize = $true
    $rb
}

# ---- Claude Code auth ----
$lblClaudeAuth = New-Object System.Windows.Forms.Label
$lblClaudeAuth.Text     = "Claude Code の認証設定"
$lblClaudeAuth.Location = New-Object System.Drawing.Point(10, 19)
$lblClaudeAuth.AutoSize = $true
$gbAuth.Controls.Add($lblClaudeAuth)

$pnlClaudeRadio = New-Object System.Windows.Forms.Panel
$pnlClaudeRadio.Location  = New-Object System.Drawing.Point(160, 16)
$pnlClaudeRadio.Size      = New-Object System.Drawing.Size(388, 20)
$pnlClaudeRadio.BackColor = $clrWhite
$gbAuth.Controls.Add($pnlClaudeRadio)
$rbClaudeGateway = New-AuthModeRadio "Gateway形式で貼り付け" 0 0
$rbClaudeGateway.Checked = $true
$rbClaudeApi     = New-AuthModeRadio "APIを直接指定" 180 0
$pnlClaudeRadio.Controls.Add($rbClaudeGateway)
$pnlClaudeRadio.Controls.Add($rbClaudeApi)

$pnlClaudeGateway = New-Object System.Windows.Forms.Panel
$pnlClaudeGateway.Location  = New-Object System.Drawing.Point(10, 38)
$pnlClaudeGateway.Size      = New-Object System.Drawing.Size(538, 38)
$pnlClaudeGateway.BackColor = $clrWhite
$gbAuth.Controls.Add($pnlClaudeGateway)
$tbClaudeAuth = New-Object System.Windows.Forms.TextBox
$tbClaudeAuth.Multiline  = $true
$tbClaudeAuth.ScrollBars = "Vertical"
$tbClaudeAuth.Location   = New-Object System.Drawing.Point(0, 0)
$tbClaudeAuth.Size       = New-Object System.Drawing.Size(538, 38)
$tbClaudeAuth.Font       = $fntSmall
$pnlClaudeGateway.Controls.Add($tbClaudeAuth)

$pnlClaudeApi = New-Object System.Windows.Forms.Panel
$pnlClaudeApi.Location  = New-Object System.Drawing.Point(10, 38)
$pnlClaudeApi.Size      = New-Object System.Drawing.Size(538, 38)
$pnlClaudeApi.BackColor = $clrWhite
$pnlClaudeApi.Visible   = $false
$gbAuth.Controls.Add($pnlClaudeApi)

function New-AuthField($parent, [string]$label, [int]$x, [int]$width) {
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text     = $label
    $lbl.Font     = $fntSmall
    $lbl.Location = New-Object System.Drawing.Point($x, 0)
    $lbl.AutoSize = $true
    $parent.Controls.Add($lbl)
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Location = New-Object System.Drawing.Point($x, 16)
    $tb.Size     = New-Object System.Drawing.Size($width, 20)
    $tb.Font     = $fntSmall
    $parent.Controls.Add($tb)
    $tb
}

$tbClaudeApiKey     = New-AuthField $pnlClaudeApi "APIキー"          0   170
$tbClaudeApiModel   = New-AuthField $pnlClaudeApi "モデル名"        184  170
$tbClaudeApiBaseUrl = New-AuthField $pnlClaudeApi "Base URL（任意）" 368  170

# ---- Codex auth ----
$lblCodexAuth = New-Object System.Windows.Forms.Label
$lblCodexAuth.Text     = "Codex の認証設定"
$lblCodexAuth.Location = New-Object System.Drawing.Point(10, 81)
$lblCodexAuth.AutoSize = $true
$gbAuth.Controls.Add($lblCodexAuth)

$pnlCodexRadio = New-Object System.Windows.Forms.Panel
$pnlCodexRadio.Location  = New-Object System.Drawing.Point(160, 78)
$pnlCodexRadio.Size      = New-Object System.Drawing.Size(388, 20)
$pnlCodexRadio.BackColor = $clrWhite
$gbAuth.Controls.Add($pnlCodexRadio)
$rbCodexGateway = New-AuthModeRadio "Gateway形式で貼り付け" 0 0
$rbCodexGateway.Checked = $true
$rbCodexApi     = New-AuthModeRadio "APIを直接指定" 180 0
$pnlCodexRadio.Controls.Add($rbCodexGateway)
$pnlCodexRadio.Controls.Add($rbCodexApi)

$pnlCodexGateway = New-Object System.Windows.Forms.Panel
$pnlCodexGateway.Location  = New-Object System.Drawing.Point(10, 100)
$pnlCodexGateway.Size      = New-Object System.Drawing.Size(538, 38)
$pnlCodexGateway.BackColor = $clrWhite
$gbAuth.Controls.Add($pnlCodexGateway)
$tbCodexAuth = New-Object System.Windows.Forms.TextBox
$tbCodexAuth.Multiline  = $true
$tbCodexAuth.ScrollBars = "Vertical"
$tbCodexAuth.Location   = New-Object System.Drawing.Point(0, 0)
$tbCodexAuth.Size       = New-Object System.Drawing.Size(538, 38)
$tbCodexAuth.Font       = $fntSmall
$pnlCodexGateway.Controls.Add($tbCodexAuth)

$pnlCodexApi = New-Object System.Windows.Forms.Panel
$pnlCodexApi.Location  = New-Object System.Drawing.Point(10, 100)
$pnlCodexApi.Size      = New-Object System.Drawing.Size(538, 38)
$pnlCodexApi.BackColor = $clrWhite
$pnlCodexApi.Visible   = $false
$gbAuth.Controls.Add($pnlCodexApi)

$tbCodexApiKey     = New-AuthField $pnlCodexApi "APIキー"          0   170
$tbCodexApiModel   = New-AuthField $pnlCodexApi "モデル名"        184  170
$tbCodexApiBaseUrl = New-AuthField $pnlCodexApi "Base URL（任意）" 368  170

$lblAuthNote = New-Object System.Windows.Forms.Label
$lblAuthNote.Text      = "Gateway形式: Set Up 画面で生成した内容を貼り付け（組織指定の認証サービス 専用形式）。APIを直接指定: Anthropic / OpenAI 互換のAPIキー・モデル名を入力（Base URLは空欄なら公式デフォルト）。貼り付け・入力内容は画面ログ・インストールログに出力しません。"
$lblAuthNote.Font      = $fntSmall
$lblAuthNote.ForeColor = [System.Drawing.Color]::Gray
$lblAuthNote.Location  = New-Object System.Drawing.Point(10, 141)
$lblAuthNote.Size      = New-Object System.Drawing.Size(542, 40)
$gbAuth.Controls.Add($lblAuthNote)

function Update-ClaudeAuthMode {
    $pnlClaudeGateway.Visible = $rbClaudeGateway.Checked
    $pnlClaudeApi.Visible     = $rbClaudeApi.Checked
}
$rbClaudeGateway.Add_CheckedChanged({ Update-ClaudeAuthMode })
$rbClaudeApi.Add_CheckedChanged({ Update-ClaudeAuthMode })
Update-ClaudeAuthMode

function Update-CodexAuthMode {
    $pnlCodexGateway.Visible = $rbCodexGateway.Checked
    $pnlCodexApi.Visible     = $rbCodexApi.Checked
}
$rbCodexGateway.Add_CheckedChanged({ Update-CodexAuthMode })
$rbCodexApi.Add_CheckedChanged({ Update-CodexAuthMode })
Update-CodexAuthMode

# Preserve the editable Claude JSON across reruns when it is already present.
# Codex's Gateway input is an executable setup script and is deliberately not
# persisted; config.toml is its output, not a script which may safely be
# executed again.
$existingClaudeSettings = Join-Path $env:USERPROFILE ".claude\settings.json"
if (Test-Path -LiteralPath $existingClaudeSettings -PathType Leaf) {
    try { $tbClaudeAuth.Text = Get-Content -LiteralPath $existingClaudeSettings -Raw -Encoding UTF8 } catch { }
}

# ---- Group: Install path --------------------------------------------------
$gbPath = New-Object System.Windows.Forms.GroupBox
$gbPath.Text      = "  インストール先  "
$gbPath.Location  = New-Object System.Drawing.Point(14, 550)
$gbPath.Size      = New-Object System.Drawing.Size(562, 74)
$gbPath.BackColor = $clrWhite
$form.Controls.Add($gbPath)

$lblPathLbl = New-Object System.Windows.Forms.Label
$lblPathLbl.Text     = "インストール先フォルダ（ガードレール）:"
$lblPathLbl.Location = New-Object System.Drawing.Point(10, 20)
$lblPathLbl.AutoSize = $true
$gbPath.Controls.Add($lblPathLbl)

$tbPath = New-Object System.Windows.Forms.TextBox
$tbPath.Text     = $defaultInstallPath
$tbPath.Location = New-Object System.Drawing.Point(10, 42)
$tbPath.Size     = New-Object System.Drawing.Size(440, 22)
$gbPath.Controls.Add($tbPath)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text      = "参照..."
$btnBrowse.Location  = New-Object System.Drawing.Point(458, 40)
$btnBrowse.Size      = New-Object System.Drawing.Size(90, 26)
$btnBrowse.FlatStyle = "System"
$gbPath.Controls.Add($btnBrowse)

$btnBrowse.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description       = "インストール先フォルダを選択してください"
    $fbd.ShowNewFolderButton = $true
    $fbd.SelectedPath = if (Test-Path $tbPath.Text -ErrorAction SilentlyContinue) {
        $tbPath.Text
    } else { $env:USERPROFILE }
    if ($fbd.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $tbPath.Text = $fbd.SelectedPath
    }
})

# ---- Group: Guardrail options ---------------------------------------------
$gbOpts = New-Object System.Windows.Forms.GroupBox
$gbOpts.Text      = "  ガードレール設定  "
$gbOpts.Location  = New-Object System.Drawing.Point(14, 634)
$gbOpts.Size      = New-Object System.Drawing.Size(562, 140)
$gbOpts.BackColor = $clrWhite
$form.Controls.Add($gbOpts)

$cbClaude = New-Object System.Windows.Forms.CheckBox
$cbClaude.Text     = "Claude Code の設定を配置する（managed-settings.json + hook）[推奨]"
$cbClaude.Checked  = $true
$cbClaude.Location = New-Object System.Drawing.Point(12, 24)
$cbClaude.Size     = New-Object System.Drawing.Size(540, 22)
$gbOpts.Controls.Add($cbClaude)

$cbCodexConfig = New-Object System.Windows.Forms.CheckBox
$cbCodexConfig.Text     = "Codex の設定を配置する（.codex/config.toml + requirements.toml）"
$cbCodexConfig.Checked  = $true
$cbCodexConfig.Location = New-Object System.Drawing.Point(12, 52)
$cbCodexConfig.Size     = New-Object System.Drawing.Size(540, 22)
$gbOpts.Controls.Add($cbCodexConfig)

$cbAddPath = New-Object System.Windows.Forms.CheckBox
$cbAddPath.Text     = "ai-pip / ai-npm をユーザー PATH に追加する"
$cbAddPath.Checked  = $true
$cbAddPath.Location = New-Object System.Drawing.Point(12, 80)
$cbAddPath.Size     = New-Object System.Drawing.Size(540, 22)
$gbOpts.Controls.Add($cbAddPath)

$lblWorkspaceShortcut = New-Object System.Windows.Forms.Label
$lblWorkspaceShortcut.Text      = "デスクトップに「AI Agent Workspace」ショートカットを作成します（起動後に Claude Code / Codex を選択できます）。"
$lblWorkspaceShortcut.Location  = New-Object System.Drawing.Point(12, 110)
$lblWorkspaceShortcut.Size      = New-Object System.Drawing.Size(540, 22)
$lblWorkspaceShortcut.ForeColor = [System.Drawing.Color]::DarkGreen
$gbOpts.Controls.Add($lblWorkspaceShortcut)
# ---- Notes label (fixed install destination) ------------------------------
$lblNote = New-Object System.Windows.Forms.Label
$lblNote.Text      = "Claude Code のバイナリ（~\.local\bin\claude.exe）と設定（~\.claude\）はツール側が管理するため、移動できません。"
$lblNote.Font      = $fntSmall
$lblNote.ForeColor = [System.Drawing.Color]::Gray
$lblNote.Location  = New-Object System.Drawing.Point(14, 812)
$lblNote.Size      = New-Object System.Drawing.Size(562, 30)
$form.Controls.Add($lblNote)

# ---- Install button -------------------------------------------------------
$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text      = "インストール実行"
$btnInstall.Location  = New-Object System.Drawing.Point(14, 848)
$btnInstall.Size      = New-Object System.Drawing.Size(562, 52)
$btnInstall.Font      = $fntBtn
$btnInstall.BackColor = $clrInstall
$btnInstall.ForeColor = $clrInstallFg
$btnInstall.FlatStyle = "Flat"
$btnInstall.FlatAppearance.BorderSize = 0
$btnInstall.Cursor    = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($btnInstall)

# ---- Log area -------------------------------------------------------------
$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text     = "インストールログ:"
$lblLog.Location = New-Object System.Drawing.Point(14, 912)
$lblLog.AutoSize = $true
$form.Controls.Add($lblLog)

$rtbLog = New-Object System.Windows.Forms.RichTextBox
$rtbLog.Location    = New-Object System.Drawing.Point(14, 932)
$rtbLog.Size        = New-Object System.Drawing.Size(562, 186)
$rtbLog.Font        = $fntLog
$rtbLog.ReadOnly    = $true
$rtbLog.BackColor   = $clrWhite
$rtbLog.BorderStyle = "FixedSingle"
$rtbLog.ScrollBars  = "Vertical"
$rtbLog.Text        = "「インストール実行」をクリックするとここにログが表示されます。`n"
$form.Controls.Add($rtbLog)

# ---- Done button ----------------------------------------------------------
$btnDone = New-Object System.Windows.Forms.Button
$btnDone.Text      = "（インストール完了後に有効になります）"
$btnDone.Location  = New-Object System.Drawing.Point(14, 1130)
$btnDone.Size      = New-Object System.Drawing.Size(562, 38)
$btnDone.Font      = $fntUI
$btnDone.Enabled   = $false
$btnDone.FlatStyle = "Flat"
$btnDone.BackColor = $clrDisabled
$btnDone.ForeColor = $clrDisabledFg
$btnDone.FlatAppearance.BorderSize = 0
$form.Controls.Add($btnDone)

$btnDone.Add_Click({ $form.Close() })

# ---- Shared state ---------------------------------------------------------
$script:installJob = $null
$script:pollTimer  = $null

# ---- Helpers --------------------------------------------------------------
function AppendLog {
    param(
        [string]$text,
        [System.Drawing.Color]$color = [System.Drawing.Color]::Black
    )
    if ([string]::IsNullOrEmpty($text)) {
        $rtbLog.AppendText("`n"); return
    }
    $rtbLog.SelectionStart  = $rtbLog.TextLength
    $rtbLog.SelectionLength = 0
    $rtbLog.SelectionColor  = $color
    $rtbLog.AppendText($text + "`n")
    $rtbLog.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Get-LineColor([string]$line) {
    if ($line -match "WARNING:|WARN:|非 admin|管理者権限がない|ACL設定に失敗|制限されます|npm warn") {
        return [System.Drawing.Color]::DarkOrange
    }
    if ($line -match "エラー|[Ee]rror|FAIL|failed|Exception|Cannot|npm ERR") {
        return [System.Drawing.Color]::Red
    }
    if ($line -match "完了|installed|added \d+|追加しました|配置しました|ACL設定完了|OK|成功|hash") {
        return [System.Drawing.Color]::DarkGreen
    }
    if ($line -match "^===") {
        return [System.Drawing.Color]::DarkBlue
    }
    return [System.Drawing.Color]::Black
}

# ---- Install button click -------------------------------------------------
$btnInstall.Add_Click({
    $installPath = $tbPath.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($installPath)) {
        [System.Windows.Forms.MessageBox]::Show(
            "インストール先フォルダを指定してください。",
            "入力エラー",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return
    }

    $claudeAuthMode = if ($rbClaudeApi.Checked) { "api" } else { "gateway" }
    $codexAuthMode  = if ($rbCodexApi.Checked)  { "api" } else { "gateway" }

    $claudeAuth        = $tbClaudeAuth.Text.Trim()
    $claudeApiKey      = $tbClaudeApiKey.Text.Trim()
    $claudeApiModel    = $tbClaudeApiModel.Text.Trim()
    $claudeApiBaseUrl  = $tbClaudeApiBaseUrl.Text.Trim()
    $codexAuth         = $tbCodexAuth.Text.Trim()
    $codexApiKey       = $tbCodexApiKey.Text.Trim()
    $codexApiModel     = $tbCodexApiModel.Text.Trim()
    $codexApiBaseUrl   = $tbCodexApiBaseUrl.Text.Trim()

    if ($claudeAuthMode -eq "gateway" -and [string]::IsNullOrWhiteSpace($claudeAuth)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Claude Code の認証設定を、組織指定の認証サービス の Set Up 画面から貼り付けてください。",
            "入力エラー",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return
    }
    if ($claudeAuthMode -eq "api" -and ([string]::IsNullOrWhiteSpace($claudeApiKey) -or [string]::IsNullOrWhiteSpace($claudeApiModel))) {
        [System.Windows.Forms.MessageBox]::Show(
            "Claude Code の APIキーとモデル名を入力してください（Base URLは任意です）。",
            "入力エラー",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return
    }
    if ($codexAuthMode -eq "gateway" -and [string]::IsNullOrWhiteSpace($codexAuth)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Codex の認証設定を、組織指定の認証サービス の Set Up 画面から貼り付けてください。",
            "入力エラー",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return
    }
    if ($codexAuthMode -eq "api" -and ([string]::IsNullOrWhiteSpace($codexApiKey) -or [string]::IsNullOrWhiteSpace($codexApiModel))) {
        [System.Windows.Forms.MessageBox]::Show(
            "Codex の APIキーとモデル名を入力してください（Base URLは任意です）。",
            "入力エラー",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return
    }

    # Lock UI
    $btnInstall.Enabled   = $false
    $btnInstall.Text      = "インストール中..."
    $btnInstall.BackColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
    $btnBrowse.Enabled    = $false
    $tbPath.ReadOnly      = $true
    $tbClaudeAuth.ReadOnly = $true
    $tbCodexAuth.ReadOnly  = $true
    $tbClaudeApiKey.ReadOnly     = $true
    $tbClaudeApiModel.ReadOnly   = $true
    $tbClaudeApiBaseUrl.ReadOnly = $true
    $tbCodexApiKey.ReadOnly      = $true
    $tbCodexApiModel.ReadOnly    = $true
    $tbCodexApiBaseUrl.ReadOnly  = $true
    $rbClaudeGateway.Enabled = $false
    $rbClaudeApi.Enabled     = $false
    $rbCodexGateway.Enabled  = $false
    $rbCodexApi.Enabled      = $false
    $cbInstNode.Enabled    = $false
    $cbInstPython.Enabled  = $false
    $cbInstClaude.Enabled  = $false
    $cbInstCodex.Enabled   = $false
    $cbClaude.Enabled     = $false
    $cbCodexConfig.Enabled = $false
    $cbAddPath.Enabled    = $false

    $rtbLog.Clear()
    AppendLog "=== AI Agent Guardrail セットアップ開始 ===" ([System.Drawing.Color]::DarkBlue)
    AppendLog "ガードレール先 : $installPath"
    AppendLog "管理者権限    : $(if ($isAdmin) { 'あり' } else { 'なし（制限あり）' })"
    AppendLog ""

    # Snapshot
    $snap_script       = $installerScript
    $snap_path         = $installPath
    $snap_instNode     = $cbInstNode.Checked
    $snap_instPython   = $cbInstPython.Checked
    $snap_instGit      = $cbInstGit.Checked
    $snap_instClaude   = $cbInstClaude.Checked
    $snap_instCodex    = $cbInstCodex.Checked
    $snap_claude       = $cbClaude.Checked
    $snap_codex        = $cbCodexConfig.Checked
    $snap_addpath      = $cbAddPath.Checked
    $snap_workspaceShortcutScript = $workspaceShortcutScript
    $snap_workspaceRuntimeScript = $workspaceRuntimeScript
    $snap_hasNode      = $hasNode
    $snap_hasPython    = $hasPython
    $snap_hasGit       = $hasGit
    $snap_hasClaude    = $hasClaude
    $snap_hasCodex     = $hasCodex
    $snap_claudeAuthMode   = $claudeAuthMode
    $snap_claudeAuth       = $claudeAuth
    $snap_claudeApiKey     = $claudeApiKey
    $snap_claudeApiModel   = $claudeApiModel
    $snap_claudeApiBaseUrl = $claudeApiBaseUrl
    $snap_codexAuthMode    = $codexAuthMode
    $snap_codexAuth        = $codexAuth
    $snap_codexApiKey      = $codexApiKey
    $snap_codexApiModel    = $codexApiModel
    $snap_codexApiBaseUrl  = $codexApiBaseUrl

    # Background job
    $script:installJob = Start-Job -ScriptBlock {
        param(
            [string]$scriptPath,
            [string]$installRoot,
            [bool]$instNode,
            [bool]$instPython,
            [bool]$instGit,
            [bool]$instClaude,
            [bool]$instCodex,
            [bool]$optClaude,
            [bool]$optCodex,
            [bool]$optPath,
            [bool]$nodeDetected,
            [bool]$pythonDetected,
            [bool]$gitDetected,
            [bool]$claudeDetected,
            [bool]$codexDetected,
            [string]$claudeAuthMode,
            [string]$claudeAuth,
            [string]$claudeApiKey,
            [string]$claudeApiModel,
            [string]$claudeApiBaseUrl,
            [string]$codexAuthMode,
            [string]$codexAuth,
            [string]$codexApiKey,
            [string]$codexApiModel,
            [string]$codexApiBaseUrl,
            [string]$workspaceShortcutScript,
            [string]$workspaceRuntimeScript,
            [string]$repoRoot
        )

        # winget installs write PATH to the registry but don't update the
        # current process's environment; re-read it so later steps in this
        # same job (npm install -g, python validate_allowlist.py) can find
        # the newly installed binaries without requiring a terminal restart.
        function Update-SessionPath {
            $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
            $user    = [Environment]::GetEnvironmentVariable("Path", "User")
            $env:Path = "$machine;$user"
        }

        # SETUP.bat switches the console to UTF-8. Keep the job's external
        # command output in the same encoding so Japanese winget/npm messages
        # appear correctly in the installation log.
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
        $OutputEncoding = [Console]::OutputEncoding

        if ($instNode -or $instPython -or $instGit) {
            Write-Output "注意: 管理者権限がない場合、Node.js/Python/Gitのインストールが権限不足で失敗することがあります。"
            Write-Output ""
        }

        function Set-ClaudeGatewayAuthentication {
            param([string]$Value)
            # The Gateway "Set Up" screen sometimes emits a raw JSON object, and
            # sometimes a full PowerShell script (like the Codex box) that writes
            # settings.json via a here-string. In the script form, earlier lines
            # (e.g. an `if (...) { ... }` guard) contain their own brace pair, so
            # naively taking the first "{" to the last "}" in the whole pasted
            # text swallows that unrelated code into the "JSON" and breaks
            # parsing. Prefer the here-string body when one is present.
            $hereStringPattern = '(?ms)^[ \t]*@["''][ \t]*\r?\n(?<body>.*?)^[ \t]*["'']@'
            $hereMatch = [regex]::Match($Value, $hereStringPattern)
            $source = if ($hereMatch.Success) { $hereMatch.Groups['body'].Value } else { $Value }

            $first = $source.IndexOf('{')
            $last = $source.LastIndexOf('}')
            if ($first -lt 0 -or $last -le $first) {
                throw "Claude Code の認証設定から JSON を読み取れませんでした。"
            }
            $json = $source.Substring($first, $last - $first + 1)
            try { $settings = $json | ConvertFrom-Json -ErrorAction Stop } catch {
                throw "Claude Code の認証設定の JSON が不正です。"
            }
            if ($null -eq $settings.env -or @($settings.env.PSObject.Properties).Count -eq 0) {
                throw "Claude Code の認証設定に env がありません（空です）。Set Up 画面で生成した内容を貼り付けてください。"
            }
            $claudeDir = Join-Path $env:USERPROFILE '.claude'
            New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
            $target = Join-Path $claudeDir 'settings.json'
            Set-Content -LiteralPath $target -Value $json -Encoding UTF8
            # Verify the write actually landed: a silent failure here (wrong path,
            # locked file, redirected profile) previously went unnoticed and left
            # Claude Code with no Gateway credentials at all.
            if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
                throw "settings.json の書き込みを確認できませんでした ($target)。"
            }
        }

        # Generic Anthropic-API-compatible path: merge only the ANTHROPIC_*
        # keys inside `env`, preserving any other top-level keys (permissions
        # etc.) and any other env entries a prior Gateway paste may have left
        # behind. Unlike the Gateway path this never overwrites the whole file.
        function Set-ClaudeApiAuthentication {
            param(
                [Parameter(Mandatory = $true)][string]$ApiKey,
                [Parameter(Mandatory = $true)][string]$Model,
                [string]$BaseUrl
            )
            $claudeDir = Join-Path $env:USERPROFILE '.claude'
            New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
            $target = Join-Path $claudeDir 'settings.json'

            $settings = $null
            if (Test-Path -LiteralPath $target -PathType Leaf) {
                try { $settings = Get-Content -LiteralPath $target -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop } catch {
                    throw "既存の settings.json を読み取れませんでした。手動で確認してください ($target)。"
                }
            }
            if ($null -eq $settings) { $settings = [PSCustomObject]@{} }
            if ($null -eq $settings.env) {
                $settings | Add-Member -MemberType NoteProperty -Name env -Value ([PSCustomObject]@{}) -Force
            }

            function Set-EnvKey($obj, [string]$key, [string]$value) {
                if ([string]::IsNullOrWhiteSpace($value)) {
                    if ($obj.PSObject.Properties[$key]) { $obj.PSObject.Properties.Remove($key) }
                } elseif ($obj.PSObject.Properties[$key]) {
                    $obj.$key = $value
                } else {
                    $obj | Add-Member -MemberType NoteProperty -Name $key -Value $value -Force
                }
            }
            Set-EnvKey $settings.env "ANTHROPIC_API_KEY"  $ApiKey
            Set-EnvKey $settings.env "ANTHROPIC_MODEL"    $Model
            Set-EnvKey $settings.env "ANTHROPIC_BASE_URL" $BaseUrl

            $json = $settings | ConvertTo-Json -Depth 10
            Set-Content -LiteralPath $target -Value $json -Encoding UTF8
            if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
                throw "settings.json の書き込みを確認できませんでした ($target)。"
            }
        }

        function Invoke-CodexGatewayAuthentication {
            param([string]$Value)
            $configPath = Join-Path $env:USERPROFILE ".codex\config.toml"
            $beforeHash = if (Test-Path -LiteralPath $configPath) { (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash } else { $null }

            $tempScript = Join-Path ([IO.Path]::GetTempPath()) ("aiagent_codex_auth_" + [guid]::NewGuid().ToString('N') + '.ps1')
            try {
                Set-Content -LiteralPath $tempScript -Value $Value -Encoding UTF8
                # The official Gateway output is a PowerShell setup script. Do not
                # relay its stdout/stderr, as it can contain credential values.
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tempScript 1>$null 2>$null
                if ($LASTEXITCODE -ne 0) { throw "Codex の認証設定スクリプトの実行に失敗しました (exit $LASTEXITCODE)。" }
            } finally {
                Remove-Item -LiteralPath $tempScript -Force -ErrorAction SilentlyContinue
            }

            # The script is expected to write ~/.codex/config.toml. If the file is
            # missing or byte-for-byte unchanged, the script silently did nothing
            # (e.g. wrong target, needed interactive input) and Codex would be left
            # without Gateway credentials despite the log showing "success".
            if (-not (Test-Path -LiteralPath $configPath)) {
                throw "Codex の認証設定スクリプトを実行しましたが、$configPath が作成されませんでした。貼り付け内容を確認してください。"
            }
            $afterHash = (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash
            if ($afterHash -eq $beforeHash) {
                throw "Codex の認証設定スクリプトを実行しましたが、$configPath の内容が更新されませんでした（内容は伏せています）。貼り付け内容を確認してください。"
            }
        }

        # Generic OpenAI-API-compatible path. Unlike the Gateway path (which
        # executes an arbitrary pasted script), this only ever writes a
        # marker-delimited block it fully controls, so it never needs to
        # trust or execute pasted content. The block is prepended because TOML
        # root keys (model = ..., model_provider = ...) must appear before the
        # first table header; Set-CodexWindowsSection (install_standard.ps1)
        # separately manages a [windows] table appended at the end, so the two
        # blocks never overlap. Uses explicit begin/end markers (not an
        # implicit "next [section]" boundary) because this block can itself
        # contain a child table ([model_providers.custom]).
        function Set-CodexApiAuthentication {
            param(
                [Parameter(Mandatory = $true)][string]$ApiKey,
                [Parameter(Mandatory = $true)][string]$Model,
                [string]$BaseUrl
            )
            $codexDir = Join-Path $env:USERPROFILE ".codex"
            New-Item -ItemType Directory -Path $codexDir -Force | Out-Null
            $configPath = Join-Path $codexDir "config.toml"

            $beginMarker = "# --- AI Agent Guardrail: API auth settings (managed automatically) ---"
            $endMarker   = "# --- AI Agent Guardrail: end API auth settings ---"

            $lines = @()
            $lines += $beginMarker
            $lines += "model = `"$Model`""
            $envKeyName = if ([string]::IsNullOrWhiteSpace($BaseUrl)) { "OPENAI_API_KEY" } else { "AIAGENT_CODEX_API_KEY" }
            if (-not [string]::IsNullOrWhiteSpace($BaseUrl)) {
                $lines += "model_provider = `"custom`""
                $lines += ""
                $lines += "[model_providers.custom]"
                $lines += "base_url = `"$BaseUrl`""
                $lines += "env_key = `"$envKeyName`""
                $lines += "wire_api = `"chat`""
            }
            $lines += $endMarker
            $newBlock = ($lines -join "
") + "
"

            if (Test-Path -LiteralPath $configPath) {
                Copy-Item -LiteralPath $configPath "$configPath.bak.$(Get-Date -Format yyyyMMddHHmmssfff)"
                $existing = Get-Content -LiteralPath $configPath -Raw
                if ($existing -match [regex]::Escape($beginMarker)) {
                    $pattern = [regex]::Escape($beginMarker) + '(?s).*?' + [regex]::Escape($endMarker) + '\r?\n?'
                    $existing = [regex]::Replace($existing, $pattern, '')
                }
                $existing = $existing.TrimStart("`r", "`n")
                $final = "$newBlock
$existing"
            } else {
                $final = $newBlock
            }
            Set-Content -LiteralPath $configPath -Encoding UTF8 -Value $final -NoNewline

            # User+Process scope so the key is visible both to future terminal
            # sessions and to any step later in this same job that shells out.
            [Environment]::SetEnvironmentVariable($envKeyName, $ApiKey, 'User')
            Set-Item -Path "Env:$envKeyName" -Value $ApiKey
        }

        # ---- Step 0: Node.js (winget) ----
        if ($instNode -and -not $nodeDetected) {
            Write-Output "=== Node.js のインストール ==="
            Write-Output "winget install --id OpenJS.NodeJS.LTS を実行しています..."
            & winget install --id OpenJS.NodeJS.LTS -e --silent --accept-package-agreements --accept-source-agreements 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Output "ERROR: Node.js のインストールに失敗しました (exit $LASTEXITCODE)"
                exit 1
            }
            Update-SessionPath
            Write-Output "Node.js のインストール完了"
            Write-Output ""
        } elseif ($nodeDetected) {
            Write-Output "=== Node.js: 検出済み（スキップ）==="
            Write-Output ""
        }

        # ---- Step 0.5: Python (winget) ----
        if ($instPython -and -not $pythonDetected) {
            Write-Output "=== Python のインストール ==="
            Write-Output "winget install --id Python.Python.3.12 を実行しています..."
            & winget install --id Python.Python.3.12 -e --silent --accept-package-agreements --accept-source-agreements 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Output "ERROR: Python のインストールに失敗しました (exit $LASTEXITCODE)"
                exit 1
            }
            Update-SessionPath
            Write-Output "Python のインストール完了"
            Write-Output ""
        } elseif ($pythonDetected) {
            Write-Output "=== Python: 検出済み（スキップ）==="
            Write-Output ""
        }

        # ---- Step 0.75: Git (winget) ----
        if ($instGit -and -not $gitDetected) {
            Write-Output "=== Git のインストール ==="
            Write-Output "winget install --id Git.Git を実行しています..."
            & winget install --id Git.Git -e --silent --accept-package-agreements --accept-source-agreements 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Output "ERROR: Git のインストールに失敗しました (exit $LASTEXITCODE)"
                exit 1
            }
            Update-SessionPath
            Write-Output "Git のインストール完了"
            Write-Output ""
        } elseif ($gitDetected) {
            Write-Output "=== Git: 検出済み（スキップ）==="
            Write-Output ""
        }

        # ---- Step 1: Claude Code ----
        if ($instClaude -and -not $claudeDetected) {
            Write-Output "=== Claude Code のインストール ==="
            Write-Output "npm install -g @anthropic-ai/claude-code を実行しています..."
            & npm install -g @anthropic-ai/claude-code 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Output "ERROR: Claude Code のインストールに失敗しました (exit $LASTEXITCODE)"
                exit 1
            }
            Write-Output "Claude Code のインストール完了"
            Write-Output ""
        } elseif ($claudeDetected) {
            Write-Output "=== Claude Code: インストール済み（スキップ）==="
            Write-Output ""
        }

        # ---- Step 2: Codex ----
        if ($instCodex -and -not $codexDetected) {
            Write-Output "=== Codex のインストール ==="
            Write-Output "npm install -g @openai/codex を実行しています..."
            & npm install -g @openai/codex 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Output "ERROR: Codex のインストールに失敗しました (exit $LASTEXITCODE)"
                exit 1
            }
            Write-Output "Codex のインストール完了"
            Write-Output ""
        } elseif ($codexDetected) {
            Write-Output "=== Codex: インストール済み（スキップ）==="
            Write-Output ""
        }

        # ---- Step 3: Authentication ----
        Write-Output "=== Claude Code の認証設定を適用 ($claudeAuthMode) ==="
        try {
            if ($claudeAuthMode -eq "api") {
                Set-ClaudeApiAuthentication -ApiKey $claudeApiKey -Model $claudeApiModel -BaseUrl $claudeApiBaseUrl
            } else {
                Set-ClaudeGatewayAuthentication -Value $claudeAuth
            }
        } catch {
            Write-Output "ERROR: $($_.Exception.Message)"
            exit 1
        }
        Write-Output "Claude Code の認証設定を適用しました"
        Write-Output ""

        Write-Output "=== Codex の認証設定を適用 ($codexAuthMode) ==="
        try {
            if ($codexAuthMode -eq "api") {
                Set-CodexApiAuthentication -ApiKey $codexApiKey -Model $codexApiModel -BaseUrl $codexApiBaseUrl
            } else {
                Invoke-CodexGatewayAuthentication -Value $codexAuth
            }
        } catch {
            Write-Output "ERROR: $($_.Exception.Message)"
            exit 1
        }
        Write-Output "Codex の認証設定を適用しました"
        Write-Output ""

        # ---- Step 4: Guardrail ----
        Write-Output "=== ガードレールのインストール ==="
        $argList = @(
            "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", $scriptPath,
            "-InstallRoot", (Join-Path $installRoot "guardrails")
        )
        if ($optClaude) { $argList += "-ConfigureClaude" }
        if ($optCodex)  { $argList += "-ConfigureCodex" }
        if ($optPath)   { $argList += "-AddWrappersToUserPath" }
        & powershell.exe @argList 2>&1

        # ---- Step 5: workspace runtime (independent of the downloaded ZIP) ----
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $workspaceRuntimeScript -WorkspaceRoot $installRoot -PackageRoot $repoRoot 2>&1
        if ($LASTEXITCODE -ne 0) { throw "ワークスペース資産の配置に失敗しました" }

        # ---- Step 6: AI Agent Workspace shortcut ----
        Write-Output ""
        Write-Output "=== AI Agent Workspace ショートカットの作成 ==="
        try {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $workspaceShortcutScript -WorkspaceRoot $installRoot 2>&1
            if ($LASTEXITCODE -ne 0) { throw "ショートカット作成スクリプトが exit $LASTEXITCODE で終了しました。" }
        } catch {
            Write-Output "WARNING: AI Agent Workspace のショートカット作成に失敗しました: $($_.Exception.Message)"
        }

        # Register the installed silent mount launcher after its configuration
        # has been copied into the installed workspace.
        $boxStartupScript = Join-Path $installRoot 'launcher\register_box_startup.ps1'
        if (Test-Path -LiteralPath $boxStartupScript -PathType Leaf) {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $boxStartupScript 2>&1
            if ($LASTEXITCODE -ne 0) { Write-Output "WARNING: 共有ドライブのスタートアップ登録に失敗しました。" }
        }
    } -ArgumentList $snap_script, $snap_path,
                    $snap_instNode, $snap_instPython, $snap_instGit,
                    $snap_instClaude, $snap_instCodex,
                    $snap_claude, $snap_codex, $snap_addpath,
                    $snap_hasNode, $snap_hasPython, $snap_hasGit,
                    $snap_hasClaude, $snap_hasCodex,
                    $snap_claudeAuthMode, $snap_claudeAuth,
                    $snap_claudeApiKey, $snap_claudeApiModel, $snap_claudeApiBaseUrl,
                    $snap_codexAuthMode, $snap_codexAuth,
                    $snap_codexApiKey, $snap_codexApiModel, $snap_codexApiBaseUrl,
                    $snap_workspaceShortcutScript, $snap_workspaceRuntimeScript, $repoRoot

    # Poll timer
    $script:pollTimer = New-Object System.Windows.Forms.Timer
    $script:pollTimer.Interval = 400
    $script:pollTimer.Add_Tick({
        try {
            $lines = @(Receive-Job $script:installJob -ErrorAction SilentlyContinue)
            foreach ($raw in $lines) {
                $txt = if ($raw -is [System.Management.Automation.ErrorRecord]) {
                    "WARN: $($raw.Exception.Message)"
                } else { "$raw" }
                AppendLog $txt (Get-LineColor $txt)
            }
        } catch { }

        if ($script:installJob.State -ne 'Running') {
            $script:pollTimer.Stop()
            $succeeded = ($script:installJob.State -eq 'Completed')

            try {
                $final = @(Receive-Job $script:installJob -ErrorAction SilentlyContinue)
                foreach ($raw in $final) { AppendLog "$raw" (Get-LineColor "$raw") }
            } catch { }

            Remove-Job $script:installJob -Force -ErrorAction SilentlyContinue
            $script:installJob = $null

            AppendLog ""
            if ($succeeded) {
                AppendLog "============================================" ([System.Drawing.Color]::DarkGreen)
                AppendLog "  インストール完了！" ([System.Drawing.Color]::DarkGreen)
                AppendLog ""
                AppendLog "  次のステップ:" ([System.Drawing.Color]::DarkGreen)
                AppendLog "  1. ターミナルを再起動して PATH を更新してください。" ([System.Drawing.Color]::DarkGreen)
                AppendLog "  2. Restart Claude Code completely before use." ([System.Drawing.Color]::DarkGreen)
                AppendLog "============================================" ([System.Drawing.Color]::DarkGreen)
                $btnDone.Text      = "閉じる"
                $btnDone.BackColor = $clrDone
                $btnDone.ForeColor = $clrDoneFg
            } else {
                AppendLog "============================================" ([System.Drawing.Color]::Red)
                AppendLog "  インストール失敗" ([System.Drawing.Color]::Red)
                AppendLog "  上記ログを確認し、管理者に連絡してください。" ([System.Drawing.Color]::Red)
                AppendLog "============================================" ([System.Drawing.Color]::Red)
                $btnDone.Text      = "閉じる"
                $btnDone.BackColor = $clrFail
                $btnDone.ForeColor = [System.Drawing.Color]::White
            }
            $btnDone.Enabled                     = $true
            $btnDone.FlatAppearance.BorderSize    = 0
        }
    })
    $script:pollTimer.Start()
})

# ---- Form close: cleanup --------------------------------------------------
$form.Add_FormClosing({
    if ($script:pollTimer -ne $null) {
        $script:pollTimer.Stop()
        $script:pollTimer.Dispose()
        $script:pollTimer = $null
    }
    if ($script:installJob -ne $null) {
        Stop-Job   $script:installJob -ErrorAction SilentlyContinue
        Remove-Job $script:installJob -Force -ErrorAction SilentlyContinue
        $script:installJob = $null
    }
})

# ---- Run ------------------------------------------------------------------
[void]$form.ShowDialog()

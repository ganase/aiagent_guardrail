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

$isAdmin       = Test-IsAdmin
$hasNode       = Test-Command "node"
$hasNpm        = Test-Command "npm"
$hasClaude     = Test-Command "claude"
$hasCodex      = Test-Command "codex"
$hasWinget     = Test-Command "winget"

# Python detection: check PATH first (python / python3), then common
# Miniforge / Mambaforge / Conda / Anaconda installation directories.
function Find-PythonExe {
    foreach ($name in @('python', 'python3')) {
        $c = Get-Command $name -ErrorAction SilentlyContinue
        if ($c) { return $c.Source }
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
        if (Test-Path $py -ErrorAction SilentlyContinue) { return $py }
    }
    return $null
}

$pythonExePath = Find-PythonExe
$hasPython     = $null -ne $pythonExePath
# If Python found outside PATH (conda/miniforge), add its directory to the session
# PATH so the background install job inherits it and can call python directly.
if ($hasPython) {
    $pyDir = Split-Path $pythonExePath -Parent
    if ($env:Path -notlike "*$pyDir*") {
        $env:Path = "$pyDir;$env:Path"
    }
}

$nodeVer   = if ($hasNode)   { (node --version 2>$null) -replace '^v','' } else { $null }
$claudeVer = if ($hasClaude) {
    $v = (claude --version 2>$null); if ($v) { "$v" } else { "検出済み" }
} else { $null }
$codexVer  = if ($hasCodex)  { "検出済み" } else { $null }

$defaultInstallPath = Join-Path $env:USERPROFILE "AIAgent"

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
$form = New-Object System.Windows.Forms.Form
$form.Text            = "AI Agent Guardrail セットアップ v0.2"
$form.Size            = New-Object System.Drawing.Size(600, 930)
$form.StartPosition   = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox     = $false
$form.BackColor       = $clrBg
$form.Font            = $fntUI

# ---- Header ---------------------------------------------------------------
$pnlHeader = New-Object System.Windows.Forms.Panel
$pnlHeader.Location  = New-Object System.Drawing.Point(0, 0)
$pnlHeader.Size      = New-Object System.Drawing.Size(600, 82)
$pnlHeader.BackColor = $clrHeader
$form.Controls.Add($pnlHeader)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text      = "AI Agent Guardrail"
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
    $condaName = Split-Path (Split-Path $pythonExePath -Parent) -Leaf
    "Python 検出済み（$condaName）"
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
$gbTools.Size      = New-Object System.Drawing.Size(562, 144)
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

# ---- Group: Install path --------------------------------------------------
$gbPath = New-Object System.Windows.Forms.GroupBox
$gbPath.Text      = "  インストール先  "
$gbPath.Location  = New-Object System.Drawing.Point(14, 328)
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
$gbOpts.Location  = New-Object System.Drawing.Point(14, 412)
$gbOpts.Size      = New-Object System.Drawing.Size(562, 112)
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

# ---- Notes label (fixed install destination) ------------------------------
$lblNote = New-Object System.Windows.Forms.Label
$lblNote.Text      = "Claude Code のバイナリ（~\.local\bin\claude.exe）と設定（~\.claude\）はツール側が管理するため、移動できません。"
$lblNote.Font      = $fntSmall
$lblNote.ForeColor = [System.Drawing.Color]::Gray
$lblNote.Location  = New-Object System.Drawing.Point(14, 534)
$lblNote.Size      = New-Object System.Drawing.Size(562, 30)
$form.Controls.Add($lblNote)

# ---- Install button -------------------------------------------------------
$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text      = "インストール実行"
$btnInstall.Location  = New-Object System.Drawing.Point(14, 570)
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
$lblLog.Location = New-Object System.Drawing.Point(14, 634)
$lblLog.AutoSize = $true
$form.Controls.Add($lblLog)

$rtbLog = New-Object System.Windows.Forms.RichTextBox
$rtbLog.Location    = New-Object System.Drawing.Point(14, 654)
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
$btnDone.Location  = New-Object System.Drawing.Point(14, 852)
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

    # Lock UI
    $btnInstall.Enabled   = $false
    $btnInstall.Text      = "インストール中..."
    $btnInstall.BackColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
    $btnBrowse.Enabled    = $false
    $tbPath.ReadOnly      = $true
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
    $snap_instClaude   = $cbInstClaude.Checked
    $snap_instCodex    = $cbInstCodex.Checked
    $snap_claude       = $cbClaude.Checked
    $snap_codex        = $cbCodexConfig.Checked
    $snap_addpath      = $cbAddPath.Checked
    $snap_hasNode      = $hasNode
    $snap_hasPython    = $hasPython
    $snap_hasClaude    = $hasClaude
    $snap_hasCodex     = $hasCodex

    # Background job
    $script:installJob = Start-Job -ScriptBlock {
        param(
            [string]$scriptPath,
            [string]$installRoot,
            [bool]$instNode,
            [bool]$instPython,
            [bool]$instClaude,
            [bool]$instCodex,
            [bool]$optClaude,
            [bool]$optCodex,
            [bool]$optPath,
            [bool]$nodeDetected,
            [bool]$pythonDetected,
            [bool]$claudeDetected,
            [bool]$codexDetected
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

        if ($instNode -or $instPython) {
            Write-Output "注意: 管理者権限がない場合、Node.js/Pythonのインストールが権限不足で失敗することがあります。"
            Write-Output ""
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

        # ---- Step 3: Guardrail ----
        Write-Output "=== ガードレールのインストール ==="
        $argList = @(
            "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", $scriptPath,
            "-InstallRoot", $installRoot
        )
        if ($optClaude) { $argList += "-ConfigureClaude" }
        if ($optCodex)  { $argList += "-ConfigureCodex" }
        if ($optPath)   { $argList += "-AddWrappersToUserPath" }
        & powershell.exe @argList 2>&1

    } -ArgumentList $snap_script, $snap_path,
                    $snap_instNode, $snap_instPython,
                    $snap_instClaude, $snap_instCodex,
                    $snap_claude, $snap_codex, $snap_addpath,
                    $snap_hasNode, $snap_hasPython,
                    $snap_hasClaude, $snap_hasCodex

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
                AppendLog "  2. Claude Code を再起動してガードレールが有効か確認してください。" ([System.Drawing.Color]::DarkGreen)
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

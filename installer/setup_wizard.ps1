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
$hasPython     = Test-Command "python"
$hasClaude     = Test-Command "claude"
$hasCodex      = Test-Command "codex"

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
$form.Size            = New-Object System.Drawing.Size(600, 870)
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
$pyText  = if ($hasPython) { "Python 検出済み" } else { "Python 未検出" }

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

# ---- Group: AI tool installation ------------------------------------------
$gbTools = New-Object System.Windows.Forms.GroupBox
$gbTools.Text      = "  AI ツール  "
$gbTools.Location  = New-Object System.Drawing.Point(14, 174)
$gbTools.Size      = New-Object System.Drawing.Size(562, 84)
$gbTools.BackColor = $clrWhite
$form.Controls.Add($gbTools)

# Claude Code checkbox
$cbInstClaude = New-Object System.Windows.Forms.CheckBox
if ($hasClaude) {
    $cbInstClaude.Text    = "Claude Code  ─  インストール済み（スキップ）"
    $cbInstClaude.Checked = $false
    $cbInstClaude.Enabled = $false
} else {
    $cbInstClaude.Text    = "Claude Code をインストールする  （npm install -g @anthropic-ai/claude-code）"
    $cbInstClaude.Checked = $hasNode   # auto-check only if Node.js present
    $cbInstClaude.Enabled = $hasNode
}
$cbInstClaude.Location = New-Object System.Drawing.Point(12, 24)
$cbInstClaude.Size     = New-Object System.Drawing.Size(538, 22)
$gbTools.Controls.Add($cbInstClaude)

# Codex checkbox
$cbInstCodex = New-Object System.Windows.Forms.CheckBox
if ($hasCodex) {
    $cbInstCodex.Text    = "Codex  ─  インストール済み（スキップ）"
    $cbInstCodex.Checked = $false
    $cbInstCodex.Enabled = $false
} else {
    $cbInstCodex.Text    = "Codex をインストールする  （npm install -g @openai/codex）"
    $cbInstCodex.Checked = $hasNode
    $cbInstCodex.Enabled = $hasNode
}
$cbInstCodex.Location = New-Object System.Drawing.Point(12, 52)
$cbInstCodex.Size     = New-Object System.Drawing.Size(538, 22)
$gbTools.Controls.Add($cbInstCodex)

# ---- Group: Install path --------------------------------------------------
$gbPath = New-Object System.Windows.Forms.GroupBox
$gbPath.Text      = "  インストール先  "
$gbPath.Location  = New-Object System.Drawing.Point(14, 268)
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
$gbOpts.Location  = New-Object System.Drawing.Point(14, 352)
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
$cbCodexConfig.Checked  = $false
$cbCodexConfig.Location = New-Object System.Drawing.Point(12, 52)
$cbCodexConfig.Size     = New-Object System.Drawing.Size(540, 22)
$gbOpts.Controls.Add($cbCodexConfig)

$cbAddPath = New-Object System.Windows.Forms.CheckBox
$cbAddPath.Text     = "ai-pip / ai-npm をユーザー PATH に追加する"
$cbAddPath.Checked  = $false
$cbAddPath.Location = New-Object System.Drawing.Point(12, 80)
$cbAddPath.Size     = New-Object System.Drawing.Size(540, 22)
$gbOpts.Controls.Add($cbAddPath)

# ---- Notes label (fixed install destination) ------------------------------
$lblNote = New-Object System.Windows.Forms.Label
$lblNote.Text      = "Claude Code のバイナリ（~\.local\bin\claude.exe）と設定（~\.claude\）はツール側が管理するため、移動できません。"
$lblNote.Font      = $fntSmall
$lblNote.ForeColor = [System.Drawing.Color]::Gray
$lblNote.Location  = New-Object System.Drawing.Point(14, 474)
$lblNote.Size      = New-Object System.Drawing.Size(562, 30)
$form.Controls.Add($lblNote)

# ---- Install button -------------------------------------------------------
$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text      = "インストール実行"
$btnInstall.Location  = New-Object System.Drawing.Point(14, 510)
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
$lblLog.Location = New-Object System.Drawing.Point(14, 574)
$lblLog.AutoSize = $true
$form.Controls.Add($lblLog)

$rtbLog = New-Object System.Windows.Forms.RichTextBox
$rtbLog.Location    = New-Object System.Drawing.Point(14, 594)
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
$btnDone.Location  = New-Object System.Drawing.Point(14, 792)
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
    $snap_instClaude   = $cbInstClaude.Checked
    $snap_instCodex    = $cbInstCodex.Checked
    $snap_claude       = $cbClaude.Checked
    $snap_codex        = $cbCodexConfig.Checked
    $snap_addpath      = $cbAddPath.Checked
    $snap_hasClaude    = $hasClaude
    $snap_hasCodex     = $hasCodex

    # Background job
    $script:installJob = Start-Job -ScriptBlock {
        param(
            [string]$scriptPath,
            [string]$installRoot,
            [bool]$instClaude,
            [bool]$instCodex,
            [bool]$optClaude,
            [bool]$optCodex,
            [bool]$optPath,
            [bool]$claudeDetected,
            [bool]$codexDetected
        )

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
                    $snap_instClaude, $snap_instCodex,
                    $snap_claude, $snap_codex, $snap_addpath,
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

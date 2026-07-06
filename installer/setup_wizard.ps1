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
$repoRoot        = Split-Path -Parent $PSScriptRoot   # installer\ -> repo root
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

# ---- Environment checks ---------------------------------------------------
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-Python {
    $null -ne (Get-Command python -ErrorAction SilentlyContinue)
}

$isAdmin   = Test-IsAdmin
$hasPython = Test-Python
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

# Japanese-compatible fonts
$fntTitle = New-Object System.Drawing.Font("Meiryo UI", 14, [System.Drawing.FontStyle]::Bold)
$fntSub   = New-Object System.Drawing.Font("Meiryo UI",  9)
$fntUI    = New-Object System.Drawing.Font("Meiryo UI",  9)
$fntBtn   = New-Object System.Drawing.Font("Meiryo UI", 11, [System.Drawing.FontStyle]::Bold)
$fntLog   = New-Object System.Drawing.Font("Consolas",   9)

# ---- Form -----------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text            = "AI Agent Guardrail セットアップ v0.2"
$form.Size            = New-Object System.Drawing.Size(600, 760)
$form.StartPosition   = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox     = $false
$form.BackColor       = $clrBg
$form.Font            = $fntUI

# ---- Header panel ---------------------------------------------------------
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

# ---- Group: Install path --------------------------------------------------
$gbPath = New-Object System.Windows.Forms.GroupBox
$gbPath.Text      = "  インストール先  "
$gbPath.Location  = New-Object System.Drawing.Point(14, 98)
$gbPath.Size      = New-Object System.Drawing.Size(562, 74)
$gbPath.BackColor = $clrWhite
$form.Controls.Add($gbPath)

$lblPathLabel = New-Object System.Windows.Forms.Label
$lblPathLabel.Text     = "インストール先フォルダ:"
$lblPathLabel.Location = New-Object System.Drawing.Point(10, 20)
$lblPathLabel.AutoSize = $true
$gbPath.Controls.Add($lblPathLabel)

$tbPath = New-Object System.Windows.Forms.TextBox
$tbPath.Text     = $defaultInstallPath
$tbPath.Location = New-Object System.Drawing.Point(10, 42)
$tbPath.Size     = New-Object System.Drawing.Size(440, 22)
$gbPath.Controls.Add($tbPath)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text     = "参照..."
$btnBrowse.Location = New-Object System.Drawing.Point(458, 40)
$btnBrowse.Size     = New-Object System.Drawing.Size(90, 26)
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

# ---- Group: Options -------------------------------------------------------
$gbOpts = New-Object System.Windows.Forms.GroupBox
$gbOpts.Text      = "  設定オプション  "
$gbOpts.Location  = New-Object System.Drawing.Point(14, 182)
$gbOpts.Size      = New-Object System.Drawing.Size(562, 112)
$gbOpts.BackColor = $clrWhite
$form.Controls.Add($gbOpts)

$cbClaude = New-Object System.Windows.Forms.CheckBox
$cbClaude.Text     = "Claude Code の設定を配置する（managed-settings.json + hook）[推奨]"
$cbClaude.Checked  = $true
$cbClaude.Location = New-Object System.Drawing.Point(12, 24)
$cbClaude.Size     = New-Object System.Drawing.Size(540, 22)
$gbOpts.Controls.Add($cbClaude)

$cbCodex = New-Object System.Windows.Forms.CheckBox
$cbCodex.Text     = "Codex の設定を配置する（.codex/config.toml + requirements.toml）"
$cbCodex.Checked  = $false
$cbCodex.Location = New-Object System.Drawing.Point(12, 52)
$cbCodex.Size     = New-Object System.Drawing.Size(540, 22)
$gbOpts.Controls.Add($cbCodex)

$cbAddPath = New-Object System.Windows.Forms.CheckBox
$cbAddPath.Text     = "ai-pip / ai-npm をユーザー PATH に追加する"
$cbAddPath.Checked  = $false
$cbAddPath.Location = New-Object System.Drawing.Point(12, 80)
$cbAddPath.Size     = New-Object System.Drawing.Size(540, 22)
$gbOpts.Controls.Add($cbAddPath)

# ---- Status indicator panel -----------------------------------------------
$pnlStatus = New-Object System.Windows.Forms.Panel
$pnlStatus.Location    = New-Object System.Drawing.Point(14, 304)
$pnlStatus.Size        = New-Object System.Drawing.Size(562, 52)
$pnlStatus.BackColor   = $clrWhite
$pnlStatus.BorderStyle = "FixedSingle"
$form.Controls.Add($pnlStatus)

$adminIcon  = if ($isAdmin)   { "[OK]" } else { "[!]" }
$adminColor = if ($isAdmin)   { [System.Drawing.Color]::DarkGreen } else { [System.Drawing.Color]::DarkOrange }
$adminText  = if ($isAdmin)   { "管理者権限あり  -  ACL保護・システム配置が有効です" } `
                              else { "管理者権限なし  -  ACL保護なし・一部機能が制限されます" }

$lblAdmin = New-Object System.Windows.Forms.Label
$lblAdmin.Text      = "$adminIcon  $adminText"
$lblAdmin.Location  = New-Object System.Drawing.Point(8, 6)
$lblAdmin.AutoSize  = $true
$lblAdmin.ForeColor = $adminColor
$pnlStatus.Controls.Add($lblAdmin)

$pyIcon  = if ($hasPython) { "[OK]" } else { "[!]" }
$pyColor = if ($hasPython) { [System.Drawing.Color]::DarkGreen } else { [System.Drawing.Color]::DarkOrange }
$pyText  = if ($hasPython) { "Python 検出済み" } `
                           else { "Python 未検出  -  ガードレールの一部機能（スモークテスト等）に Python が必要です" }

$lblPy = New-Object System.Windows.Forms.Label
$lblPy.Text      = "$pyIcon  $pyText"
$lblPy.Location  = New-Object System.Drawing.Point(8, 28)
$lblPy.AutoSize  = $true
$lblPy.ForeColor = $pyColor
$pnlStatus.Controls.Add($lblPy)

# ---- Install button -------------------------------------------------------
$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text      = "インストール実行"
$btnInstall.Location  = New-Object System.Drawing.Point(14, 370)
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
$lblLog.Location = New-Object System.Drawing.Point(14, 435)
$lblLog.AutoSize = $true
$form.Controls.Add($lblLog)

$rtbLog = New-Object System.Windows.Forms.RichTextBox
$rtbLog.Location    = New-Object System.Drawing.Point(14, 455)
$rtbLog.Size        = New-Object System.Drawing.Size(562, 196)
$rtbLog.Font        = $fntLog
$rtbLog.ReadOnly    = $true
$rtbLog.BackColor   = $clrWhite
$rtbLog.BorderStyle = "FixedSingle"
$rtbLog.ScrollBars  = "Vertical"
$rtbLog.Text        = "「インストール実行」をクリックするとここにログが表示されます。`n"
$form.Controls.Add($rtbLog)

# ---- Done / Close button --------------------------------------------------
$btnDone = New-Object System.Windows.Forms.Button
$btnDone.Text      = "（インストール完了後に有効になります）"
$btnDone.Location  = New-Object System.Drawing.Point(14, 664)
$btnDone.Size      = New-Object System.Drawing.Size(562, 40)
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
        $rtbLog.AppendText("`n")
        return
    }
    $rtbLog.SelectionStart  = $rtbLog.TextLength
    $rtbLog.SelectionLength = 0
    $rtbLog.SelectionColor  = $color
    $rtbLog.AppendText($text + "`n")
    $rtbLog.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Get-LineColor([string]$line) {
    if ($line -match "WARNING:|WARN:|非 admin|管理者権限がない|ACL設定に失敗|制限されます") {
        return [System.Drawing.Color]::DarkOrange
    }
    if ($line -match "エラー|[Ee]rror|FAIL|failed|Exception|Cannot|拒否|不一致") {
        return [System.Drawing.Color]::Red
    }
    if ($line -match "完了|installed|追加しました|配置しました|ACL設定完了|OK|成功|hash") {
        return [System.Drawing.Color]::DarkGreen
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
    $cbClaude.Enabled     = $false
    $cbCodex.Enabled      = $false
    $cbAddPath.Enabled    = $false

    $rtbLog.Clear()
    AppendLog "=== AI Agent Guardrail インストール開始 ===" ([System.Drawing.Color]::DarkBlue)
    AppendLog "インストール先 : $installPath"
    AppendLog "管理者権限    : $(if ($isAdmin) { 'あり' } else { 'なし（制限あり）' })"
    AppendLog "Claude 設定    : $($cbClaude.Checked)"
    AppendLog "Codex 設定     : $($cbCodex.Checked)"
    AppendLog "PATH 追加      : $($cbAddPath.Checked)"
    AppendLog ""

    # Snapshot options (capture values before closure)
    $snap_script   = $installerScript
    $snap_path     = $installPath
    $snap_claude   = $cbClaude.Checked
    $snap_codex    = $cbCodex.Checked
    $snap_addpath  = $cbAddPath.Checked

    # Launch background job
    $script:installJob = Start-Job -ScriptBlock {
        param(
            [string]$scriptPath,
            [string]$installRoot,
            [bool]$optClaude,
            [bool]$optCodex,
            [bool]$optPath
        )
        $argList = @(
            "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", $scriptPath,
            "-InstallRoot", $installRoot
        )
        if ($optClaude) { $argList += "-ConfigureClaude" }
        if ($optCodex)  { $argList += "-ConfigureCodex" }
        if ($optPath)   { $argList += "-AddWrappersToUserPath" }

        & powershell.exe @argList 2>&1
    } -ArgumentList $snap_script, $snap_path, $snap_claude, $snap_codex, $snap_addpath

    # Poll timer: fetch job output every 400ms
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

            # Drain any remaining output
            try {
                $final = @(Receive-Job $script:installJob -ErrorAction SilentlyContinue)
                foreach ($raw in $final) {
                    $txt = "$raw"
                    AppendLog $txt (Get-LineColor $txt)
                }
            } catch { }

            Remove-Job $script:installJob -Force -ErrorAction SilentlyContinue
            $script:installJob = $null

            AppendLog ""
            if ($succeeded) {
                AppendLog "============================================" ([System.Drawing.Color]::DarkGreen)
                AppendLog "  インストール完了！" ([System.Drawing.Color]::DarkGreen)
                AppendLog ""
                AppendLog "  次のステップ:" ([System.Drawing.Color]::DarkGreen)
                AppendLog "  1. Claude Code を再起動してください。" ([System.Drawing.Color]::DarkGreen)
                AppendLog "  2. ガードレールが有効なことを確認: pip install pandas (hook が動作するか)" ([System.Drawing.Color]::DarkGreen)
                AppendLog "============================================" ([System.Drawing.Color]::DarkGreen)
                $btnDone.Text      = "閉じる"
                $btnDone.BackColor = $clrDone
                $btnDone.ForeColor = $clrDoneFg
            } else {
                AppendLog "============================================" ([System.Drawing.Color]::Red)
                AppendLog "  インストール失敗" ([System.Drawing.Color]::Red)
                AppendLog "  上記のログを確認し、管理者に連絡してください。" ([System.Drawing.Color]::Red)
                AppendLog "============================================" ([System.Drawing.Color]::Red)
                $btnDone.Text      = "閉じる"
                $btnDone.BackColor = $clrFail
                $btnDone.ForeColor = [System.Drawing.Color]::White
            }
            $btnDone.Enabled   = $true
            $btnDone.FlatAppearance.BorderSize = 0
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
        Stop-Job  $script:installJob -ErrorAction SilentlyContinue
        Remove-Job $script:installJob -Force -ErrorAction SilentlyContinue
        $script:installJob = $null
    }
})

# ---- Run ------------------------------------------------------------------
[void]$form.ShowDialog()

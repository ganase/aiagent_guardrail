#Requires -Version 5.1

$winget = Get-Command winget.exe -ErrorAction SilentlyContinue
if ($winget) {
    exit 0
}

Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()

[System.Windows.Forms.MessageBox]::Show(
    'セットアップには Windows App Installer（winget）が必要です。OK を押すと Microsoft Store の公式 App Installer ページを開きます。インストール後に SETUP.bat を再実行してください。',
    'App Installer が必要です',
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Information
) | Out-Null

try {
    Start-Process 'ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1' -ErrorAction Stop
    [System.Windows.Forms.MessageBox]::Show(
        'Microsoft Store を開きました。App Installer をインストールしてから、SETUP.bat を再実行してください。',
        'セットアップを停止しました',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}
catch {
    [System.Windows.Forms.MessageBox]::Show(
        'Microsoft Store を開けませんでした。Microsoft Store で「App Installer」を検索してインストールし、その後 SETUP.bat を再実行してください。',
        'セットアップを停止しました',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
}

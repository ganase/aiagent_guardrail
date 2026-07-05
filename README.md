# AI Agent Guardrail Installer

Windows 11 環境で Codex / Claude Code などのコーディングエージェントを企業利用するための、**汎用的な標準ガードレール・インストーラーのテンプレート**です。

本リポジトリは、特定企業の内部設定や秘密情報を含まない公開用テンプレートです。導入時は各社のソフトウェア導入ルール、セキュリティポリシー、ネットワーク制約に合わせて調整してください。

## 何をするものか

| 目的 | 内容 |
|---|---|
| 標準導入 | ガードレール、テンプレート、許可済みパッケージリストを標準インストーラーで配布する |
| ライブラリ制御 | `pip install` / `npm install` などを許可済みパッケージリストでチェックする |
| 危険操作の抑止 | 危険コマンド、ランタイム導入、未許可パッケージ導入を検知して止める |
| Claude Code対応 | managed settings / hook テンプレートを配布する |
| Codex対応 | Windows sandbox 設定テンプレート、`AGENTS.md`、補助ラッパーを配布する |

## 重要な前提

- これは初期実装テンプレートです。本番展開前に、AI管理者、IT管理者、セキュリティ担当のレビューを受けてください。
- Python / Node.js / Git などのランタイム本体は、各社のソフトウェア導入許可リスト・指定手順に従って導入してください。
- 本パッケージの許可済みパッケージリストは、`pip` / `npm` などで導入されるライブラリを対象にします。
- 許可リスト外、`review` 扱い、または判断できないライブラリは、個人判断で導入せず、AI管理者またはIT管理者に相談してください。
- ガードレールは完全ではありません。利用者教育、レビュー、ログ確認、例外申請フローと組み合わせてください。

## ディレクトリ構成

```text
installer/
  install_standard.bat
  install_standard.ps1
  uninstall_standard.ps1
  check_status.ps1

guardrails/
  config/
    manifest.json
    guardrail_policy.json
    package_allowlist.json
    package_allowlist.schema.json
    runtime_policy.json
    claude_managed_settings.template.json
    codex_config.template.toml
    codex_requirements.template.toml
  hooks/
    aiagent_guardrail_check.py
    validate_allowlist.py
  bin/
    ai-pip.ps1
    ai-npm.ps1
    ai-pip.bat
    ai-npm.bat
  templates/
    claude/CLAUDE.md
    codex/AGENTS.md

docs/
  導入手順.md
  ガードレール設計.md
  許可済みパッケージリスト運用.md
  必要な仕組み一覧.md
```

## インストール方法

PowerShell を管理者として開き、リポジトリのルートで実行します。

```powershell
.\installer\install_standard.ps1 -ConfigureClaude -ConfigureCodex
.\installer\check_status.ps1
```

ユーザーPATHに `ai-pip` / `ai-npm` を追加する場合は、次のオプションを付けます。

```powershell
.\installer\install_standard.ps1 -ConfigureClaude -ConfigureCodex -AddWrappersToUserPath
```

管理者権限がない場合はユーザー領域にインストールされます。その場合、Claude Code の managed settings など一部の強制力は弱くなります。

## 動作確認

許可済みパッケージの例です。

```powershell
ai-pip install pandas
```

未許可パッケージの例です。停止されることを確認します。

```powershell
ai-pip install unknown-package-for-test
```

ランタイムやグローバルツール導入の例です。会社のソフトウェア導入許可リストに従うべき操作として停止されます。

```powershell
python .\guardrails\hooks\aiagent_guardrail_check.py --command "winget install Python.Python.3.12"
```

## 設定ファイルの確認

許可済みパッケージリストの構造検証は次で実行できます。

```powershell
python .\guardrails\hooks\validate_allowlist.py .\guardrails\config\package_allowlist.json
```

## 公開用テンプレートとしての注意

このリポジトリには、以下を含めない方針です。

- 実在する社名、組織名、個人名
- APIキー、アクセストークン、秘密鍵、接続文字列
- 社内URL、社内リポジトリURL、社内サーバー名
- 実運用中の許可済みパッケージリスト
- 顧客情報、本番データ、ログ本文

## 実装上の限界

| 項目 | 限界 |
|---|---|
| Claude Code | managed settings / hooks により比較的強い制御が可能ですが、配置方法は組織の管理方式に合わせて検証してください |
| Codex | Windows sandbox、`AGENTS.md`、補助ラッパーを併用します。Codex側のネイティブhook連携は環境仕様に合わせて確認してください |
| pip/npm制御 | `ai-pip` / `ai-npm` を経由しない直接実行は、Hookや端末管理で補完が必要です |
| 許可リスト | 許可済みパッケージでも将来脆弱性が見つかる可能性があります。定期更新してください |

## 次に整備するもの

- 許可外ライブラリ申請フロー
- MCP / Plugin 台帳
- セルフ・セキュリティ・チェック連携
- 導入ログ・ハートビート収集
- Level 3 など業務利用移行時のチェックリスト

# AI Agent Guardrail Installer

Windows 11 環境で Codex / Claude Code などのコーディングエージェントを企業利用するための、**汎用的な標準ガードレール・インストーラーのテンプレート**です。

本リポジトリは、特定企業の内部設定や秘密情報を含まない公開用テンプレートです。導入時は各社のソフトウェア導入ルール、セキュリティポリシー、ネットワーク制約に合わせて調整してください。

## 何をするものか

| 目的 | 内容 |
|---|---|
| 標準導入 | ガードレール、テンプレート、許可済みパッケージリストを標準インストーラーで配布する |
| ライブラリ制御（3層） | `pip install` / `npm install` 等を allow（自動）/ ask（人間承認）/ deny（ブロック）の3層でチェックする |
| 危険操作の抑止 | 危険コマンド、ランタイム導入、未許可パッケージ導入を検知して止める |
| fail-closed | 設定が壊れた場合もガードが素通りにならない（exit 2 でブロック） |
| Claude Code 対応 | managed settings / hook テンプレートを配布する（hook は run_guardrail_hook.cmd 経由） |
| Codex 対応 | Windows sandbox 設定テンプレート、`AGENTS.md`、補助ラッパーを配布する |

## 重要な前提

- これは初期実装テンプレートです。本番展開前に、AI 管理者、IT 管理者、セキュリティ担当のレビューを受けてください。
- Python / Node.js / Git などのランタイム本体は、各社のソフトウェア導入許可リスト・指定手順に従って導入してください。
- **管理者権限での導入を原則必須とします**（ACL 保護と Claude Code managed-settings のシステム配置に必要）。
- 非 admin 導入は評価用途限定です。ACL 保護がなく、設定ファイルがユーザーによって改変可能な状態になります。

## ディレクトリ構成

```text
installer/
  install_standard.bat
  install_standard.ps1       # ACL保護付きインストーラー
  uninstall_standard.ps1
  check_status.ps1           # スモークテスト付きステータス確認

guardrails/
  config/
    manifest.json
    guardrail_policy.json    # v0.2: パターン拡充（pip3/uv/poetry/conda/iex 等）
    package_allowlist.json   # allow / review / deny の3区分
    package_allowlist.schema.json
    runtime_policy.json
    claude_managed_settings.template.json  # ask から pip install 削除（二重摩擦解消）
    codex_config.template.toml
    codex_requirements.template.toml
  hooks/
    aiagent_guardrail_check.py  # v0.2: 3層ポリシー・fail-closed・改ざん検知等
    run_guardrail_hook.cmd      # fail-closed ラッパー（Python不在でも exit 2）
    validate_allowlist.py
  bin/
    ai-pip.ps1 / ai-pip.bat
    ai-npm.ps1 / ai-npm.bat
  templates/
    claude/CLAUDE.md
    codex/AGENTS.md

docs/
  導入手順.md
  ガードレール設計.md
  許可済みパッケージリスト運用.md
  必要な仕組み一覧.md
  既知の限界.md              # v0.2 新規: 実証済みの穴と恒久対策

tests/
  test_guardrail_check.py    # v0.2 新規: 28 ケースの回帰テスト

CHANGELOG.md
```

## インストール方法

PowerShell を**管理者として**開き、リポジトリのルートで実行します。

```powershell
.\installer\install_standard.ps1 -ConfigureClaude -ConfigureCodex
.\installer\check_status.ps1
```

ユーザー PATH に `ai-pip` / `ai-npm` を追加する場合は、次のオプションを付けます。

```powershell
.\installer\install_standard.ps1 -ConfigureClaude -ConfigureCodex -AddWrappersToUserPath
```

## 動作確認

```powershell
# 許可済みパッケージ → 自動許可（ダイアログなし）
ai-pip install pandas

# 未知パッケージ → 人間承認ダイアログ
ai-pip install new-library

# 禁止パッケージ → ブロック
ai-pip install example-malicious-package
```

## テスト実行

```powershell
python -m pytest tests/ -v
```

## 設定ファイルの確認

```powershell
python .\guardrails\hooks\validate_allowlist.py .\guardrails\config\package_allowlist.json
```

## v0.2 の主な変更点

| 変更 | 内容 |
|---|---|
| fail-closed | hook 内部エラー・設定ファイル破損でも exit 2（ブロック）。exit 1 の素通りを排除 |
| 信頼の起点固定 | claude-hook モードは `__file__` から config パスを導出。env 変数で偽 config に差し替え不可 |
| 3層ポリシー | deny（exit 2）/ allow（exit 0 + JSON allow）/ ask（exit 0 + JSON ask）。二重摩擦解消 |
| typosquat 検出 | Levenshtein 距離 ≤ 2 で類似パッケージを deny |
| パターン拡充 | pip3、uv add、uv pip、poetry add、conda、npm ci、yarn install、iex、pwsh -enc 等 |
| requirements.txt 対応 | -r ファイル内パッケージを個別照合。社外レジストリ指定は deny |
| npm 引数なし対応 | package.json を読んで各パッケージを照合 |
| blocked_paths 実装 | cat .env / Get-Content secrets/key.pem 等を exit 2 でブロック |
| Remove-Item | -Recurse と -Force の両方がどの順序でもブロック |
| 改ざん検知 | installed_hashes.csv と SHA256 を起動時に照合 |
| run_guardrail_hook.cmd | Python 不在でも exit 2（fail-closed ラッパー） |
| ACL 保護 | admin 導入時に Users の書込権限を制限（icacls） |
| 導入ログ | logs/package_decisions.csv に全判定を記録 |
| 回帰テスト | tests/test_guardrail_check.py (28 ケース、全グリーン) |

## 既知の限界

**ガードレールは完全ではありません。** 主な限界:

- **Codex 側に強制力なし**: AGENTS.md は助言。素の pip/npm は制限されません。
- **文字列マッチの回避**: `python -c`、スクリプト経由は検知できません。
- **推移的依存の未検査**: pandas が依存するライブラリは個別チェックされません。
- **非 admin 導入時の改変可能性**: ACL なし。設定ファイルを書き換え可能。
- **承認疲れ**: ask が頻出すると誤承認リスクが高まります。
- **ユーザー自身のターミナル**: 直接実行は hook 対象外。

詳細は [docs/既知の限界.md](docs/既知の限界.md) を参照してください。

**恒久対策の最優先事項**: 社内 PyPI/npm ミラー + egress プロキシによるネットワーク境界の構築（[docs/必要な仕組み一覧.md](docs/必要な仕組み一覧.md) 参照）。

## 公開用テンプレートとしての注意

このリポジトリには、以下を含めない方針です。

- 実在する社名、組織名、個人名
- API キー、アクセストークン、秘密鍵、接続文字列
- 社内 URL、社内リポジトリ URL、社内サーバー名
- 実運用中の許可済みパッケージリスト
- 顧客情報、本番データ、ログ本文

## 次に整備するもの（ロードマップ）

- **[最優先] 社内 PyPI/npm ミラー + egress プロキシ**（hook/ラッパーに依存しない一次防御）
- 許可外ライブラリ申請フロー
- MCP / Plugin 台帳
- セルフ・セキュリティ・チェック連携
- pip-audit / npm audit 定期スキャン
- 導入ログ・ハートビート収集

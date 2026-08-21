# AI Agent Guardrail 現状調査報告

調査日: 2026-08-13  
対象: Windows 11 向け AI Agent ガードレール・インストーラーテンプレート  
調査範囲: リポジトリ全体（特に `README.md`、`installer/`、`guardrails/`、`docs/`）

> 本報告は調査結果のみであり、調査時点で設定・コードの変更は行っていない。

## 結論

Claude Code 向けには、managed settings、PreToolUse Hook、ACL、インストール後のハッシュ照合を組み合わせた制御がある。一方、Codex には同等の Hook 機構がなく、直接実行される `pip` / `npm` 等を強制的に制御できない。

また、パッケージポリシーは名称に反して許可リスト方式ではない。現在は **deny-list-only** であり、未知パッケージ、`review` パッケージ、および一部の解析不能な導入経路を許可する。企業の標準ガードレールとして展開する前には、パッケージ制御、外部通信・Secret保護、公開前スキャンを優先して補強する必要がある。

## 1. 現在のカバー範囲

| 項目 | 現在の対応状況 | 該当ファイル | 不足点 | 評価 |
|---|---|---|---|---|
| 標準インストーラー | 対応済み | `SETUP.bat`、`installer/install_standard.ps1` | GUIが共有フォルダ・認証まで扱い、公開用テンプレートとして責務が広い | 要改善 |
| Claude Code設定 | 対応済み | `guardrails/config/claude_managed_settings.template.json` | 製品仕様変更に対する継続的な互換性確認が必要 | 要改善 |
| Codex設定 | 一部対応 | `codex_config.template.toml`、`codex_requirements.template.toml` | Hookがなく、`approval_policy`も設定・強制していない | 要実装 |
| ガードレールポリシー | 対応済み | `guardrail_policy.json`、`aiagent_guardrail_check.py` | 文字列・正規表現検知が中心で回避経路がある | 要改善 |
| 危険コマンド制御 | 一部対応 | `guardrail_policy.json` | Claude Hook経由のみ。対象外のコマンドがある | 要実装 |
| Secret読取制限 | 一部対応 | policy、Claude managed settings、Hook | `.pfx`、`.p12`、credentials等が対象外 | 要実装 |
| 外部送信・ネットワーク制御 | 一部対応 | Hook、Claude設定 | 通常のダウンロード・通信先を制限しない | 要実装 |
| pip制御 | 一部対応 | `bin/ai-pip.ps1`、Hook | ラッパーまたはClaude Hook利用時のみ。未知パッケージは許可 | 要実装 |
| npm制御 | 一部対応 | `bin/ai-npm.ps1`、Hook | ラッパーまたはClaude Hook利用時のみ。未知パッケージは許可 | 要実装 |
| winget等ランタイム導入制御 | 一部対応 | `runtime_policy.json`、Hook | OSレベルでの直接実行の強制制御はない | 要実装 |
| 許可済みパッケージリスト | 一部対応 | `package_allowlist.json`、schema、validator | `review`とバージョン制約を強制せず、実態はdeny-list-only | 要実装 |
| bypass禁止 | 一部対応 | Claude managed settings、`check_status.ps1` | Codex自動承認は警告のみ。セットアップはExecutionPolicy Bypassを使用 | 要実装 |
| 利用者プロファイル | 一部対応 | `docs/user/利用ルールブック.md` | 権限、例外申請、承認者の技術的な連携がない | 要改善 |
| 設定ハッシュ・改変検知 | 対応済み | installer、Hook、`check_status.ps1` | Claude/Codexのユーザー設定・認証情報は対象外 | 要改善 |
| 導入状態確認 | 対応済み | `installer/check_status.ps1` | 実際の製品設定の有効性確認は限定的 | 要改善 |
| 公開前スキャン | 未対応 | `.gitignore` のみ | Secret scan、CI、release gate、履歴確認がない | 要実装 |
| README / docs | 一部対応 | `README.md`、`docs/` | 実装との不整合と企業・製品依存の説明が残る | 要改善 |

評価基準は、`OK`（初期テンプレートとして十分）、`要改善`（軽微な追加で改善可能）、`要実装`（重要機能が不足）、`対象外`（単体テンプレートでは対応しない）とした。

## 2. パッケージ導入制御

### 2.1 ai-pip / ai-npm

以下の全ファイルが存在する。

- `guardrails/bin/ai-pip.ps1`
- `guardrails/bin/ai-npm.ps1`
- `guardrails/bin/ai-pip.bat`
- `guardrails/bin/ai-npm.bat`

PowerShellラッパーは、実行前に `aiagent_guardrail_check.py` を呼び、成功時だけ `python -m pip` または `npm` を実行する。チェッカーが拒否・異常終了した場合は後続のパッケージマネージャを呼ばないため、**ラッパー利用時は安全側に停止する**。

ただし、ラッパーは実際の `pip` / `npm` を呼び出すだけであり、直接 `pip` / `npm` を実行させない仕組みはない。

### 2.2 allowlist / runtime policy

`package_allowlist.json`、`package_allowlist.schema.json`、`runtime_policy.json` はすべて存在する。PythonとJavaScriptを扱い、エントリには `allow` / `review` / `deny`、バージョン範囲、レビュー担当・日付・期限の項目がある。サンプルデータであることも明記されている。

しかし実行時の判定は次の通りである。

| 状態 | 実際の動作 |
|---|---|
| `deny` | ブロック |
| タイポスクワット疑い | ブロック |
| 期限切れ | ブロック |
| `allow` | 許可 |
| `review` | 許可 |
| 未知パッケージ | 許可 |

`allowed_versions` は記録されるだけで実行時に検証されない。ローカル/VCS由来のパッケージ、requirementsファイルの読取エラー、解析不能なパッケージ指定も許可方向である。

加えて、JSON Schemaは `default_policy` を `deny` に限定している一方、実データは `deny_list_only` を使用している。独自validatorは両方を許容するため、Schema検証をCI等で実施すると不整合になる。

### 2.3 直接実行の限界

| 経路 | 状態 | 根拠 |
|---|---|---|
| Claude CodeのBash経由 | 部分制御 | PreToolUse Hookで検査 |
| `ai-pip` / `ai-npm` 経由 | 部分制御 | ラッパーで検査 |
| Codexからの直接 `pip` / `npm` | 未対応 | Codexに同等Hookがない |
| 端末からの直接 `pip` / `npm` | 未対応 | PATH置換、WDAC、AppLocker等の強制制御がない |

## 3. 危険コマンド制御の確認

| コマンド/パターン | 現在の扱い | 該当ファイル | 評価 | 備考 |
|---|---|---|---|---|
| `rm -rf` | 条件付き拒否 | policy | block | `/` または `~` 対象の形のみ |
| `del /s` | 拒否 | policy | block | |
| `rmdir /s` | 拒否 | policy | block | `rd /s`も対象 |
| `format` | 条件付き拒否 | policy | block | ドライブ文字指定時 |
| `diskpart` | 未対象 | — | not covered | |
| `sudo` | 未対象 | — | not covered | WSL/Git Bashも考慮が必要 |
| `curl` | パイプ実行時のみ拒否 | policy | review | 通常の取得・送信は未制御 |
| `wget` | パイプ実行時のみ拒否 | policy | review | 通常の取得・送信は未制御 |
| `Invoke-WebRequest` / `iwr` | `iex`等へのパイプ時のみ拒否 | policy | review | 通常通信は未制御 |
| `Invoke-RestMethod` / `irm` | `iex`へのパイプ時のみ拒否 | policy | review | 通常通信は未制御 |
| `Start-Process` | 未対象 | — | not covered | |
| `powershell -EncodedCommand` | 拒否 | policy | block | `pwsh`も対象 |
| `winget install` | 拒否 | policy / runtime policy | block | Hook経由に限る |
| `choco install` | 拒否 | policy / runtime policy | block | Hook経由に限る |
| `scoop install` | 拒否 | policy / runtime policy | block | Hook経由に限る |
| `npm install -g` | 拒否 | policy | block | Hook経由に限る |
| `pip install --user` | パッケージ名に依存 | Hook | allow | unknown packageは許可 |
| `pip install --break-system-packages` | パッケージ名に依存 | Hook | allow | 危険オプション自体は未検出 |

## 4. Secret / 認証情報保護の確認

| パターン | 現在の扱い | 該当ファイル | 評価 | 備考 |
|---|---|---|---|---|
| `.env` / `.env.*` | Claude Read・一部Bash読取を拒否 | policy、Claude設定、Hook | block | `.example`等は許可 |
| `*.pem` / `*.key` | Claude Read・一部Bash読取を拒否 | policy、Claude設定、Hook | block | |
| `id_rsa` / `id_ed25519` | Hookで拒否 | policy、Hook | block | Claude managed denyには未明示 |
| `secrets/` | Hookで拒否 | policy、Hook | block | |
| `*.pfx` / `*.p12` | 未対象 | — | not covered | |
| `credentials` / `credentials.json` | 未対象 | — | not covered | |
| `token` / `secret` / `password` | ファイル名として未対象 | — | not covered | 既知形式の値はPrompt/出力検知あり |
| DB接続文字列 | Promptは拒否、PostToolUseは警告 | Hook | review | ファイル読取・外部送信の包括制御ではない |
| Private Key block | Promptは拒否、PostToolUseは警告 | Hook | review | |
| 公開前のSecret検出 | `.gitignore`のみ | `.gitignore` | not covered | CI/pre-commit/release gateなし |

認証情報を扱うGUIは、Claude設定ファイルへのAPIキー保存、Codex用のユーザー環境変数設定を行う。これはリポジトリに認証情報が含まれることを意味しないが、端末上の保管、ACL、ローテーション、削除の運用設計が必要である。

## 5. 公開リポジトリ適性

高確度の検索では、実在社名、実在個人名、社内URL、社内リポジトリURL、メールアドレス、実APIキー、アクセストークン、秘密鍵、顧客情報、本番接続文字列は確認されなかった。テストコードに含まれるキー形式・接続文字列は検知機能用のダミーであり、実認証情報とは判断していない。

一方、公開用の汎用テンプレートとして次の情報・機能は整理が必要である。

| ファイル | 問題 |
|---|---|
| `CHANGELOG.md` | 内部フォルダ名、Box共有ドライブ、社内AI Gateway、別配布物に関する履歴説明が残る |
| `docs/admin/SETUP統合設計_Box連携・認証設定貼り付け_案.md` | Boxドライブ、社内AI Gateway、社内向け資料を前提とする設計書。公開対象に含めないか、汎用化が必要 |
| `docs/user/コード管理ルール.md` | 組織指定のGit基盤を必須の保存先としている。組織指定のGitホスティング等に抽象化することが望ましい |
| `SETUP.bat` とBox関連installer | Box共有フォルダ設定を標準導入フローに含む。ガードレールの公開テンプレートからは分離することが望ましい |
| `installer/setup_wizard.ps1` | 貼り付けたGateway PowerShellスクリプトを実行する認証設定フローがある。公開テンプレートの安全原則と分離して検討する必要がある |

公開前には、追跡対象を確定したクリーンなリリース成果物に対し、履歴を含むSecret scanを実行することが必要である。

## 6. 優先対応事項

1. Codexおよび端末からの直接実行を含む、強制可能なパッケージ・危険コマンド制御を設計する。
2. パッケージポリシーをdefault-denyまたは明示的な承認フローへ変更し、`review`・バージョン制約を実行時に強制する。
3. Secret対象を拡張し、外部通信先・外部送信・ファイルアップロードの制御を設計する。
4. Secret scan、依存関係スキャン、履歴スキャンをCIまたはリリースゲートとして導入する。
5. Box、Gateway、組織指定のGit基盤等の企業・製品依存要素を任意モジュールへ分離する。
6. Codexの承認方針をテンプレートで明示し、設定値を監査・強制する方法を整備する。


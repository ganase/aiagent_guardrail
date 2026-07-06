# CHANGELOG

## v0.2.0 (2026-07-06)

### Breaking Changes

- `claude_managed_settings.template.json`: hook コマンドが `python ... aiagent_guardrail_check.py` から `run_guardrail_hook.cmd` 経由に変更。`managed-settings.json` を再生成してください（`install_standard.ps1 -ConfigureClaude` を再実行）。
- `claude_managed_settings.template.json`: `ask` から `Bash(pip install *)` / `Bash(npm install *)` 等のパッケージ導入系ルールを削除。3層判定は hook JSON に一元化。
- パッケージ判定の挙動変更: 以前は allowlist 外 = deny でしたが、v0.2 では allowlist 外 = ask（人間承認）に変更。deny は `deny` ステータスまたは typosquat 検出時のみ。

### Security Fixes

- **B. fail-closed**: `aiagent_guardrail_check.py` の `check_command()` が try/except で包まれ、いかなる例外でも claude-hook モードでは exit 2 を返すように変更。従来は例外 → exit 1（非ブロッキング）= 素通りの脆弱性があった。
- **B. run_guardrail_hook.cmd 新規作成**: Python 不在・パス不正でも exit 2 を返す CMD ラッパー。hook 基盤自体の故障も fail-closed に。
- **C. 信頼の起点固定**: claude-hook モードでは `AIAGENT_GUARDRAIL_HOME` 環境変数を参照しない。`__file__` からのみ config パスを導出。偽 config ディレクトリへの差し替えによる無力化を防止。
- **C. ACL 保護**: admin 導入時に `icacls` で Users の書込権限を制限。非 admin 導入時は Write-Warning で明示的に警告し、`install_log.csv` に `protected=false` を記録。
- **C. 改ざん検知（実装化）**: 起動時に `installed_hashes.csv` と `guardrail_policy.json` / `package_allowlist.json` の SHA256 を照合。不一致なら claude-hook モードで exit 2。

### New Features

- **A. 3層ポリシー**: allow（exit 0 + JSON `permissionDecision: allow`）/ ask（exit 0 + JSON `permissionDecision: ask`）/ deny（exit 2）の3層に変更。
- **A. typosquat 検出**: Levenshtein 距離 ≤ 2 で allowlist の allow エントリに類似したパッケージ名を deny（exit 2）。stdlib のみで実装。
- **A. 導入ログ**: `logs/package_decisions.csv`（`timestamp,user,ecosystem,package,decision,command`）に全判定を記録。書込失敗はベストエフォートで無視。
- **D. パターン拡充**: `pip3`、`pip3.x`、`python3 -m pip`、`uv pip install`、`uv add`、`poetry add`、`conda install`、`npm ci`、`yarn install`、`pnpm install` を追加。
- **D. requirements.txt 個別照合**: `-r` / `-c` ファイルを読み、パッケージを個別に allowlist 照合。全 allow → allow、1 つでも deny → deny、未知混在 → ask。
- **D. npm 引数なしインストール対応**: `npm install`（引数なし）で `package.json` を読み、`dependencies` / `devDependencies` を照合。
- **D. ローカルパス・VCS・wheel は ask 扱い**: 従来の擬似パッケージ deny をやめ、人間承認に委ねる。
- **D. 危険コマンド追加**: `iex`、`irm ... | iex`、`pwsh -enc`、`del /s`、`rd /s`、`Set-MpPreference`、`Stop-Service`、`schtasks /create`、`bitsadmin /transfer`。
- **D. Remove-Item フラグ順非依存**: `-Recurse` と `-Force` がコマンド中のどこかに両存在したらブロック（regex ではなくコード判定）。
- **E. blocked_paths 実装化**: `cat .env`、`Get-Content secrets/prod.pem` 等を exit 2 でブロック。`.env.example` / `.env.template` / `.env.sample` は除外。
- **G. Codex 限界の明記**: `docs/ガードレール設計.md` と `README.md` に Codex 側の enforcement の限界を追記。
- **G. ネットワーク境界ロードマップ**: `docs/必要な仕組み一覧.md` に社内 PyPI/npm ミラー + egress プロキシを最優先ロードマップとして追記。

### Documentation

- `docs/ガードレール設計.md`: 3層ポリシー、限界列を実証結果に基づき更新。
- `docs/許可済みパッケージリスト運用.md`: 未知パッケージのフロー（ask → ログ → レビュー → allowlist 反映）、導入ログの場所・形式を追記。
- `docs/導入手順.md`: admin 実行を「推奨」から「原則必須」に変更。非 admin の限界を明記。
- `docs/必要な仕組み一覧.md`: ネットワーク境界を最優先ロードマップとして追加。
- `docs/既知の限界.md`: **新規作成**。Codex 無強制、文字列マッチ回避、推移的依存未検査、非 admin 改変、承認疲れ、ユーザーターミナル対象外、hash ファイル改ざん、バージョン未検証等を記載。
- `README.md`: v0.2 変更点サマリ・既知の限界セクションを更新。

### Tests

- `tests/test_guardrail_check.py`: 28 ケースの回帰テストを新規作成。全ケースグリーン確認済み。
  - fail-closed（壊れた JSON、config 不存在）
  - 3層判定（allow / ask / deny / typosquat）
  - パターンカバレッジ（pip3 / uv add / uv pip / npm no-args / -r ファイル / 外部レジストリ）
  - 危険コマンド（iex / pwsh -enc / Remove-Item フラグ順逆）
  - blocked_paths（.env / .pem / .env.example 除外）
  - 改ざん検知（ハッシュ不一致 / 一致 / ファイル不存在）

## v0.1.0 (2026-07-06)

- 初版リリース。基本的な allowlist 照合、危険コマンドパターン、Claude Code managed-settings テンプレートを含む。

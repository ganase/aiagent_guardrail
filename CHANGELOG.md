# CHANGELOG

## 未リリース

### New Features（ローカライズの汎用化）

- **AI Agent 操作ログの Box 同期**: `launch_ai_workspace.bat` が Codex / Claude Code の起動前・終了後に `sync_ai_agent_logs.ps1` を実行し、履歴・セッション・診断ログを `Sandbox\<ユーザー>\AI-Agent-Audit` へ一方向同期する。`auth.json`、`.credentials.json`、`config.toml` はコピー対象外。強制終了などで終了後同期が行えなかった場合は、次回起動前に補完同期する。

- **認証設定の2モード化**: `installer\setup_wizard.ps1` の認証設定欄に、Claude Code / Codex それぞれ「Gateway形式で貼り付け」（組織指定の認証サービス 専用フォーマット、既存動作）と「APIを直接指定」（Anthropic / OpenAI 互換の APIキー・モデル名・Base URL[任意]を入力）のラジオボタンを追加。API方式はGateway方式のような任意コード実行・丸ごと上書きを行わず、既存設定への差分マージ（Claude: `settings.json` の `env` 内3キーのみ）またはマーカー管理された追記（Codex: `config.toml` 先頭に専用ブロックをprepend）で書き込む。
- **共有ドライブマウントの指定可能化**: `installer\configure_box_mount.ps1`（新規）が `SETUP.bat` 実行時に一度だけ、共有フォルダのパスとドライブ文字を確認するダイアログを表示し、`installer\box_mount.local.cmd`（gitignore対象）に保存する。以後は同ファイルを `mount_box_drive.bat` / `register_box_startup.ps1` / `launch_ai_workspace.bat` が共通で読み込む。従来ハードコードされていた `<共有ワークスペース>` という社内固有フォルダ名は削除。「使用しない」を選択すれば共有ドライブ連携自体を無効化できる。
- `installer\uninstall.bat`: 共有ドライブの `subst` 解除と `box_mount.local.cmd` の削除を追加。

### Bug Fixes（実装 vs 設計文書の不整合）

- **`expires_at` の実行時チェックを deny-list-only 方式に結線**: `is_expired()` は v0.2.1 で実装されていたが `evaluate_packages()` から一度も呼び出されておらず、期限切れの allow / review エントリも実際には allow のままだった（`docs/既知の限界.md` §8 が記述していた「ask へ降格」も、v0.2.0 で ask 判定自体が廃止された後は実態と食い違っていた）。期限切れは `deny(expired)` として明示的にブロックし、`package_decisions.csv` に記録するように修正。
- `install_standard.ps1` の `Set-CodexWindowsSection` のバックアップファイル名を秒精度からミリ秒精度に変更（同一インストール内で新規追加の認証設定書き込みと連続してバックアップが走った場合の命名衝突を防止）。

### Documentation

- `README.md`、利用者向け文書、運用設計書、既知の限界、文書一覧に、Box への生ログ同期・認証情報非同期・監査上の留意事項を追記。`docs/admin/AIエージェントログ同期設計.md` を追加。

- `docs/admin/既知の限界.md` §11: API方式の追加とモード切替時の残留設定リスクを追記。
- `docs/user/導入手順書.md`: 共有ドライブの初回設定ダイアログ、認証設定2モードの説明に更新。

### Tests

- `tests/test_guardrail_check.py`: `test_expired_allow_package_is_denied` を deny 期待に修正（従来は allow のまま通過することを検証していた）。

## v0.3.0 (2026-08-05)

### New Features

- **Box ドライブ自動マウント**: `SETUP.bat` 実行時に `subst` で Box 共有フォルダ（`<共有ワークスペース>`）を `I:` ドライブとしてマウントし、Windows スタートアップ（`shell:startup`）にも自動登録する（`installer\mount_box_drive.bat` / `installer\mount_box_drive_silent.vbs` / `installer\register_box_startup.ps1`、いずれも admin 不要・冪等）。
- **Git for Windows の自動導入をGUIウィザードに統合**: Node.js/Python と同様のパターンで検出・`winget install --id Git.Git` 経由の自動導入・手動導入リンクを追加。従来この仕組みは存在しなかった。
- **Claude Code / Codex 認証設定の貼り付け機能**: 組織指定の認証サービス の Set Up 画面で生成した内容を GUI ウィザードに貼り付けることで、`~/.claude/settings.json`（JSON抽出・検証のみ）と `~/.codex/config.toml`（生成スクリプトを実行）へ自動適用する。従来は別配布の zip パッケージ（Codex_Setup_Package / Claude_Code_Setup_Package）で個別に行っていた作業を統合。認証設定の貼り付けは必須（空欄では「インストール実行」がエラーになる）。
- **Codex config.toml のマージ書き込み**: `install_standard.ps1 -ConfigureCodex` を「テンプレートで丸ごと上書き」から「`[windows]` セクションのみをマーカーコメント付きで追記・更新」する方式に変更。認証設定貼り付け（Codex）が書き込んだ他のセクションを保持したまま、ガードレールの sandbox 設定を必ず最後に適用する。

### Documentation

- `docs/user/導入手順書.md`: Box自動マウント・Git自動導入・認証設定貼り付け（必須）の手順を追記。
- `docs/admin/既知の限界.md`: 認証設定貼り付けにおける一時ファイルの平文残留リスク、Codex側の任意コード実行の信頼モデルを追記。
- `docs/admin/SETUP統合設計_Box連携・認証設定貼り付け_案.md`: 本リリースの設計文書（実装済み）。

## v0.2.2 (2026-07-06)

### New Features

- **GUI ウィザードに Node.js / Python の自動導入を追加**: これまで Claude Code / Codex のみ対象だった「未導入なら自動インストール」の仕組みを、その前提となる Node.js（`winget install OpenJS.NodeJS.LTS`）と Python（`winget install Python.Python.3.12`）にも拡張。「ランタイム / AI ツール」欄に4つのチェックボックス（Node.js / Python / Claude Code / Codex）を表示し、未導入分のみ自動導入を提案する。
- **winget 未検出時のフォールバック**: `winget` コマンド自体が見つからない環境では、Node.js/Pythonの自動導入チェックボックスを無効化し、手動導入を促すメッセージを表示する。
- **依存関係を考慮したチェックボックス制御**: Claude Code / Codex は npm（Node.js）に依存するため、「Node.js を自動導入する」のチェックを外すと（かつ Node.js 未導入の場合）Claude Code / Codex のチェックボックスも自動的に無効化し、後工程での分かりにくい失敗を防ぐ。
- **インストール順序**: Node.js → Python → Claude Code → Codex → ガードレール本体の順で導入し、winget インストール直後にプロセス内の `PATH` を再読込することで、同一ジョブ内の後続コマンド（`npm`、`python`）が新規導入したバイナリを認識できるようにした。

### Documentation

- `docs/導入手順書.md`: GUIウィザードの手順にランタイム自動導入の説明を追加。auto-installは個人試行・評価用途の簡易手段であり、部内業務利用（Level 3）では会社の指定手順を優先する旨を明記。
- `README.md`: クイックスタートの手順にランタイム自動導入の一文を追加。

## v0.2.1 (2026-07-06)

設計レビュー（実装 vs 設計文書の整合性チェック）で見つかった、公開ポリシー違反・設計との乖離・ドキュメント重複を修正。

### Security / Compliance

- **社内URL・組織名の除去**: `docs/運用設計書.md`・`docs/導入手順書.md`・`docs/コード管理ルール.md`・`docs/利用ルールブック.md` に残っていた実在の組織指定のGitリポジトリドメインと固有チーム名を汎用表現に置換。README.md が謳う「公開用テンプレートには社名・社内URLを含めない」方針との矛盾を解消。

### Bug Fixes（実装 vs 設計文書の不整合）

- **改ざん検知の対象範囲を拡張**: `verify_hashes()` が `guardrail_policy.json` / `package_allowlist.json` のみを検証していたのを、hook本体（`aiagent_guardrail_check.py`）・`run_guardrail_hook.cmd`・`runtime_policy.json`・テンプレート（CLAUDE.md / AGENTS.md）にも拡張。ハッシュ自体は既に `installed_hashes.csv` に記録されていたが検証対象外だった。
- **改ざん検知を CLI モードにも適用**: 従来 claude-hook モード限定だった `verify_hashes()` 呼び出しを cli モード（`ai-pip` / `ai-npm`）にも適用。
- **`runtime_policy.json` を hook に配線**: これまで実装から一切参照されていなかった孤立設定ファイルを、`guardrail_policy.json` の `runtime_install_patterns` とマージする形で実際にブロック判定へ反映。
- **`expires_at` の実行時チェックを実装**: 許可済みパッケージリストの `expires_at` が過去日付・不正な形式の場合、`allow` を `ask`（再審査待ち）へ自動的に降格するようにした。日付未設定は従来どおり期限なし扱い。
- **typosquat 検出の対象を review ステータスにも拡張**: 従来 `allow` ステータスのパッケージ名としか比較していなかったため、`selenium` や `requests`（review）のタイポは無審査扱いだった。`allow` + `review` を比較対象に変更。
- **`check_status.ps1` に実ハッシュ照合を追加**: 従来は `installed_hashes.csv` の存在確認のみだったが、SHA256 を再計算して実際に照合するように変更。
- **`check_status.ps1` に ACL 保護状態の表示を追加**: `install_log.csv` の `protected` 列を読み、非admin導入（ACL保護なし）の場合は Level 3（部内業務利用）に進めない旨を警告表示。
- **バージョン番号の整合性を修正**: `manifest.json` が `0.1.0` のまま更新されておらず、他ファイル（`guardrail_policy.json` の `policy_version` 等）が示す `v0.2` と食い違っていたのを是正。

### Documentation

- **ドキュメント間のファイル名相互参照を修正**: `docs/README.md` と `docs/運用設計書.md` 内の文書一覧表が、実ファイル名と異なる名前（`運用設計.md` / `導入運用設計.md`）を指していたのを実ファイル名 `運用設計書.md` に統一。両表に不足していた `ガードレール設計.md` / `許可済みパッケージリスト運用.md` / `必要な仕組み一覧.md` / `既知の限界.md` を追加。`CHANGELOG.md` 内の `docs/導入手順.md` 参照も `docs/導入手順書.md` に修正。
- **重複の集約**: `ガードレール設計.md` と `許可済みパッケージリスト運用.md` に重複していた「3層ポリシーとhookの動作」表を `ガードレール設計.md` に一本化。`ガードレール設計.md` と `既知の限界.md` に重複していた「既知の限界」表を `既知の限界.md` に一本化。
- **依存関係チェックの記載を実態に合わせる**: `docs/コード管理ルール.md` が `pip-audit` 等の依存関係チェックを既存手順であるかのように記載していたのを、未実装であることが分かるように修正。
- **`README.md` を全面的に書き直し**: v0.2 変更点の全文・ロードマップ全文・ディレクトリ構成の逐次コメントなど、`CHANGELOG.md` / `docs/必要な仕組み一覧.md` と重複する詳細説明を削除し、クイックスタートと docs への導線に絞った構成に変更（認知負荷の低減）。

### Tests

- `tests/test_guardrail_check.py`: 10 ケース追加（38 ケース、全グリーン）。改ざん検知のCLIモード適用・hook本体の改ざん検知・`runtime_policy.json`配線・`expires_at`期限切れ/未設定・reviewパッケージのtyposquat検出を新規カバー。

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
- `docs/導入手順書.md`: admin 実行を「推奨」から「原則必須」に変更。非 admin の限界を明記。
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

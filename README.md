# aiagent_workspace

Windows 11 で Codex / Claude Code を企業利用するための、**標準ガードレール・インストーラーの公開テンプレート**です。

AI エージェントは便利な反面、未承認パッケージの導入・危険なコマンドの実行・機密ファイルへのアクセスを意図せず提案することがあります。本ツールは、エージェントの操作を組織のポリシーに基づき審査・承認・抑止する仕組みを配布し、担当者が安心してエージェントを業務利用できる状態を作ります。

本リポジトリは特定企業の内部設定・秘密情報を含まない公開用テンプレートです。導入時は各社のルールに合わせて調整してください（社名・社内URL・実運用リストは含めない方針です）。

---

## クイックスタート

**一般ユーザー向け（推奨）**

1. 配布されたリポジトリを ZIP でダウンロードして解凍する
2. 解凍したフォルダ内の **`SETUP.bat` をダブルクリック**する
3. UAC 画面で「はい」を選択する
4. GUI ウィザードでインストール先を確認し「インストール実行」をクリックする（Node.js・Python・Claude Code・Codex が未導入の場合は自動導入するか選択できる）

デフォルトのインストール先: `C:\Users\<ユーザー名>\AIAgent_Workspace\`

**上級者・自動化向け（コマンドライン）**

管理者 PowerShell でリポジトリのルートから実行します。

```powershell
.\installer\install_standard.ps1 -ConfigureClaude -ConfigureCodex
.\installer\check_status.ps1
```

**導入後の動作確認**

```powershell
ai-pip install pandas                    # 許可済み → 自動許可
ai-pip install new-library               # 未知     → 自動許可（deny リスト外）
ai-pip install example-malicious-package # 禁止     → ブロック
```

---

## これだけは知っておくこと

- **管理者権限での導入が原則必須**です（ACL 保護・Claude Code managed-settings の配置に必要）。非admin導入は評価用途限定で、業務利用（Level 3）には進めないでください。`check_status.ps1` の「ACL protection / install level」欄で確認できます。
- **ガードレールは完全ではありません。** 文字列マッチである以上、`python -c` 経由などの回避策が原理的に存在します。詳細は [docs/admin/既知の限界.md](docs/admin/既知の限界.md)。
- **これは初期実装テンプレートです。** 本番展開前に、AI管理者・IT管理者・セキュリティ担当のレビューを受けてください。

---

## 何をするものか（要約）

- `pip install` / `npm install` 等を **deny リスト・typosquat → ブロック、それ以外 → 自動許可** の deny-list-only ポリシーで審査する
- `iex`・`pwsh -enc`・`rm -rf` 等の危険コマンドと、`.env` / `*.pem` 等の機密ファイルアクセスを検知・ブロックする
- fail-closed設計・ACL保護・起動時ハッシュ照合により、ガードレール自体の迂回・改ざんを防ぐ
- Claude Code / Codex の標準設定をテンプレートとして一括配布し、組織全体で一貫させる

仕組みの詳細・限界・設計判断は [docs/](docs/README.md) にまとめています。

---

## もっと詳しく知りたいときは

**AIを使う方（ユーザー）**

| 知りたいこと | 参照先 |
|---|---|
| 守るべきルール・活用度レベル | [docs/user/利用ルールブック.md](docs/user/利用ルールブック.md) |
| 導入手順の詳細・トラブル対応 | [docs/user/導入手順書.md](docs/user/導入手順書.md) |
| コード管理・組織指定のGit基盤 保存 | [docs/user/コード管理ルール.md](docs/user/コード管理ルール.md) |

**環境を管理する方（管理者）**

| 知りたいこと | 参照先 |
|---|---|
| リスクと設計方針の全体像 | [docs/admin/運用設計書.md](docs/admin/運用設計書.md) |
| ガードレールの設計・deny-list-only ポリシー | [docs/admin/ガードレール設計.md](docs/admin/ガードレール設計.md) |
| 許可済みパッケージリストの運用 | [docs/admin/許可済みパッケージリスト運用.md](docs/admin/許可済みパッケージリスト運用.md) |
| 既知の限界・恒久対策ロードマップ | [docs/admin/既知の限界.md](docs/admin/既知の限界.md) |
| 未実装項目・優先度 | [docs/admin/必要な仕組み一覧.md](docs/admin/必要な仕組み一覧.md) |

| その他 | 参照先 |
|---|---|
| 変更履歴 | [CHANGELOG.md](CHANGELOG.md) |
| 文書一覧（全体像） | [docs/README.md](docs/README.md) |

**開発者向け:**

```powershell
python -m pytest tests/ -v                                                    # 回帰テスト
python .\guardrails\hooks\validate_allowlist.py .\guardrails\config\package_allowlist.json  # 許可リスト検証
```

ディレクトリ構成は `installer/`（導入）・`guardrails/`（ガードレール本体）・`docs/`（設計・運用文書）・`tests/` の4つに分かれています。各ファイルの役割は上表のリンク先を参照してください。

## 利用方針（Level 1）

本テンプレートの初期対象は、ローカル・個人利用・事務効率化を中心とする Level 1 です。目的は利用を一律に止めることではなく、作成物を見える場所に残してブラックボックス化を避け、危険な操作を検知可能にすることです。

- コード、スクリプト、README、手順、設定、必要なログは、管理された共有ワークスペース配下に保存します。Box、OneDrive、SharePoint、Google Drive、組織指定の共有フォルダ等を利用でき、現在の利用想定ではBoxを例示します。
- ワークスペースランチャーで Codex または Claude Code を起動すると、操作履歴・セッションログが Box の個人用 `Sandbox\<ユーザー>\AI-Agent-Audit` に同期されます。認証情報と設定は同期対象外です。
- bypass、auto approval、危険な自動承認モードは使用しません。承認時は対象ファイル、コマンド、外部送信先、影響範囲を確認します。
- Secret読取、認証情報の外部送信、破壊的コマンドはブロック対象です。未知パッケージと軽微な外部取得は、初期方針では警告・記録・利用者確認を中心に扱います。
- AGENTS.md / CLAUDE.md、Hook、policy、利用者確認、運用レビューを組み合わせます。これらのテンプレート単体で全リスクを完全に防ぐものではなく、CodexではClaude Codeと同等のHook強制はできません。
- Docker、Dev Container等の強い隔離環境は、エンジニア向けの後日検討事項です。
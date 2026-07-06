# aiagent_guardrail

Windows 11 で Codex / Claude Code を企業利用するための、**標準ガードレール・インストーラーの公開テンプレート**です。

AI エージェントは便利な反面、未承認パッケージの導入・危険なコマンドの実行・機密ファイルへのアクセスを意図せず提案することがあります。本ツールは、エージェントの操作を組織のポリシーに基づき審査・承認・抑止する仕組みを配布し、担当者が安心してエージェントを業務利用できる状態を作ります。

本リポジトリは特定企業の内部設定・秘密情報を含まない公開用テンプレートです。導入時は各社のルールに合わせて調整してください（社名・社内URL・実運用リストは含めない方針です）。

---

## クイックスタート

**一般ユーザー向け（推奨）**

1. GitHub からリポジトリを ZIP でダウンロードして解凍する
2. 解凍したフォルダ内の **`SETUP.bat` をダブルクリック**する
3. UAC 画面で「はい」を選択する
4. GUI ウィザードでインストール先を確認し「インストール実行」をクリックする（Node.js・Python・Claude Code・Codex が未導入の場合は自動導入するか選択できる）

デフォルトのインストール先: `C:\Users\<ユーザー名>\AIAgent\`

**上級者・自動化向け（コマンドライン）**

管理者 PowerShell でリポジトリのルートから実行します。

```powershell
.\installer\install_standard.ps1 -ConfigureClaude -ConfigureCodex
.\installer\check_status.ps1
```

**導入後の動作確認**

```powershell
ai-pip install pandas                    # 許可済み → 自動許可
ai-pip install new-library               # 未知     → 人間承認ダイアログ
ai-pip install example-malicious-package # 禁止     → ブロック
```

---

## これだけは知っておくこと

- **管理者権限での導入が原則必須**です（ACL 保護・Claude Code managed-settings の配置に必要）。非admin導入は評価用途限定で、業務利用（Level 3）には進めないでください。`check_status.ps1` の「ACL protection / install level」欄で確認できます。
- **ガードレールは完全ではありません。** 文字列マッチである以上、`python -c` 経由などの回避策が原理的に存在します。詳細は [docs/admin/既知の限界.md](docs/admin/既知の限界.md)。
- **これは初期実装テンプレートです。** 本番展開前に、AI管理者・IT管理者・セキュリティ担当のレビューを受けてください。

---

## 何をするものか（要約）

- `pip install` / `npm install` 等を **allow（自動許可）/ ask（人間承認）/ deny（ブロック）** の3層で審査する
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
| コード管理・Bitbucket 保存 | [docs/user/コード管理ルール.md](docs/user/コード管理ルール.md) |

**環境を管理する方（管理者）**

| 知りたいこと | 参照先 |
|---|---|
| リスクと設計方針の全体像 | [docs/admin/運用設計書.md](docs/admin/運用設計書.md) |
| ガードレールの設計・3層ポリシー | [docs/admin/ガードレール設計.md](docs/admin/ガードレール設計.md) |
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

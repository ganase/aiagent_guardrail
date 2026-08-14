# AIエージェントログ同期設計

## 目的

Codex と Claude Code の業務操作ログを Box の個人用 Sandbox に保管する。認証情報と設定は各ユーザーのローカル領域に残す。

## 保存先

`<Box共有フォルダ>\Sandbox\<Windowsユーザー名>\AI-Agent-Audit\` 配下に、ツール別に保存する。リポジトリ外のため Git の追跡対象にはしない。

## 同期対象

同期スクリプトはエージェントの状態ディレクトリ全体をコピーせず、以下だけをホワイトリストで選択する。

| ツール | コピー対象 |
|---|---|
| Codex | `history.jsonl`、`sessions/`、`archived_sessions/`、`logs/` |
| Claude Code | `history.jsonl`、`projects/`、`debug/` |

`auth.json`、`.credentials.json`、`config.toml` は明示的に除外する。Claude Code の Windows 標準ログイン資格情報は `%USERPROFILE%\.claude\.credentials.json` に残る。

## 実行契機と障害時の挙動

ワークスペースランチャーは、選択したツールの起動前と終了後に同期を実行する。起動前同期は、前回の強制終了などで終了後同期が実行されなかった場合の補完である。同期失敗は警告として表示するが、ツールの起動・終了コードを変更しない。

コピーは一方向であり、Box 側に既にあるログを削除しない。会話内容やコマンド出力に含まれる情報は加工せず、生ログとしてコピーする。Box 上の閲覧権限、保持期間、監査手順は組織の運用ルールで管理する。

## AIターン使用時間の通知

Codex / Claude Code の `UserPromptSubmit` HookでAIターンを開始し、`Stop` Hookで終了する。ユーザーの入力待ち時間は積算せず、AIターン中だけ30分、60分、以後30分ごとの境界で警告を表示する。記録は監査フォルダ直下の `turn_usage.csv` に開始・終了（UTC）、ターン実行秒数、累積時間として保存する。警告は通知のみで、AI Agentの停止や制限は行わない。


# Dotfiles テスト戦略

新しい MacBook で `./setup/setup.zsh` を走らせたとき、すべての設定が正しく反映されることを担保するためのテスト体系。

## 2 段構え

| レイヤ | 実行頻度 | 完全性 | コスト |
|---|---|---|---|
| **GitHub Actions CI** | 毎 push / 月 1 cron | △ runner はプリインストール済みツールあり | 自動・無料 |
| **Tart VM**（ローカル） | リリース前 / 大きな変更時 | ◎ 真のクリーン macOS | 手動・初回 25GB DL |

## レイヤ 1: GitHub Actions CI

`.github/workflows/ci.yml` で 5 段の assertion を実行:

1. **Symlink 検証**: `.zshrc`, `~/.claude/*`, `~/.config/*` が dotfiles へリンクされているか
2. **Brewfile formulas**: `gh`, `jq`, `starship`, `uv`, `mise` 等 12 件が PATH に乗っているか
3. **Skills inventory**: `~/.claude/skills` 配下に SKILL.md が 20 件以上あるか
4. **settings.json**: valid JSON か
5. **SKILL.md frontmatter**: 全 SKILL.md に `name:` フィールドがあるか

実行:
```bash
# 手動トリガー
gh workflow run CI --ref main

# ログ確認
gh run watch
```

**限界**:
- GitHub Actions の macOS runner は Xcode / brew / node / python などプリインストール済 → 「Homebrew が無い真のゼロ状態」は再現できない
- Cask (Slack, Cursor 等) は GUI 起動できないため「インストール後に起動できるか」は検証不能
- Keychain / iCloud / 認証連動は範囲外

## レイヤ 2: Tart VM（ローカル）

新 MacBook 相当のクリーン macOS VM 上で、setup.zsh + assertion を実機検証する。

### 前提

- Apple Silicon Mac（Tart は arm64 必須）
- 30GB 以上の空きディスク
- 初回のみ macOS VM image (~25GB) ダウンロード

### 実行

```bash
bash setup/test-tart.sh             # フル実行（クリーン → setup → 検証 → VM 削除）
bash setup/test-tart.sh --keep      # VM を残す（再利用したい時）
bash setup/test-tart.sh --shell     # 検証完了後に VM 内シェルへ入る
```

### 内部の動き

1. Tart を未インストールなら `brew install` で導入
2. ベース macOS image を pull（初回のみ、~25GB）
3. クリーン状態の VM をクローン（`dotfiles-test`）
4. VM をヘッドレス起動 → SSH 待ち
5. VM 内で `brew install` → `git clone dotfiles` → `setup.zsh` 実行
6. VM 内で CI と同じ assertion を実行
7. 完了後 VM を削除（`--keep` 指定時はキープ）

### 何が CI と違うのか

| | CI runner | Tart VM |
|---|---|---|
| Homebrew | プリインストール済 | **無い**（VM 内で `brew install` から） |
| Xcode | プリインストール済 | 無い |
| 真の「新マシン」体感 | ✕ | ◎ |
| Cask の DL 検証 | ◎ | ◎ |
| GUI 起動 | ✕ | ○（`tart run` で window モード） |

### トラブルシューティング

**`tart pull` が遅い**:
- 初回 25GB DL。WiFi より有線推奨。スリープすると中断するので `caffeinate -dis bash setup/test-tart.sh`

**SSH が繋がらない**:
- VM の boot に 30 秒以上かかる場合あり。test-tart.sh は最大 120 秒待つが、それでもダメなら macOS guest の Network 設定確認

**`sshpass` で失敗**:
- `brew install hudochenkov/sshpass/sshpass` 手動で

**brew インストールが途中で止まる**:
- VM のメモリ不足の可能性。`tart set dotfiles-test --memory 16384` で拡大

## 推奨運用

- **日常**: CI が毎 push で構造的バグを検出 → 安全網
- **大きな変更後**: `setup/test-tart.sh` を 1 回走らせて新マシン挙動を確認
- **新 MacBook 購入直後**: 同じ `setup.zsh` を実機で走らせるだけ。Tart で事前検証済みなので安心

## 検証されない範囲

以下は CI / Tart のいずれでも検証できない（人手で確認が必要）:

- Keychain への OAuth トークン復元（Notion / Slack / Linear など）
- iCloud Drive / Documents の同期
- 1Password での SSH キー復元
- App Store 経由のアプリ
- Apple ID 紐付くアプリの設定
- フォント設定（書道用フォント等）
- カスタム壁紙・スクリーンセーバー

新マシン初期セットアップ時はこれらを別途手動で行う前提とする。

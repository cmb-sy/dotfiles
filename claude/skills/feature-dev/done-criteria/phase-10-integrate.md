---
phase: 10
name: integrate
max_retries: 3
audit: lite
---

## Criteria

### D10-01: ユーザーが統合方法を選択済み
- **severity**: blocker
- **verify_type**: automated
- **verification**:
  1. Phase 10 で4オプション（`wt merge` / PR 作成 / ブランチ保持 / 破棄）がユーザーに提示された記録があるか確認する
  2. ユーザーの選択値が `wt-merge`, `pr`, `branch-keep`, `discard` のいずれかとして記録されているか確認する
- **pass_condition**: 手順1の提示記録が存在し、手順2の選択値が4値のいずれかであること
- **fail_diagnosis_hint**: 選択肢の提示が行われていない場合は4オプションを提示する。提示済みで応答がない場合は PAUSE し、オーケストレーターの推測で統合方法を決めない
- **depends_on_artifacts**: []

### D10-02: 選択されたアクションが完了している
- **severity**: blocker
- **verify_type**: automated
- **verification**:
  D10-01 で記録された選択値に応じて完了を確認する:
  - `wt-merge`: `git log --oneline -1` でマージ先ブランチに作業ブランチのコミットが取り込まれていることを確認し、`wt list` で当該 worktree が一覧に存在しないことを確認する
  - `pr`: `gh pr view --json url` で PR URL が取得できることを確認し、`wt list` で当該 worktree が一覧に存在しないことを確認する
  - `branch-keep`: `git branch --list <artifacts.branch_name>` で作業ブランチが存在することを確認し、`wt list` に当該 worktree が存在することを確認する
  - `discard`: `wt list` で当該 worktree が一覧に存在せず、`git branch --list <artifacts.branch_name>` の出力が空であることを確認する
- **pass_condition**: 選択値に対応する上記の全確認項目が成立すること
- **fail_diagnosis_hint**: merge 失敗は `git status` でコンフリクトを確認する。PR 作成失敗は `gh auth status` で認証状態を確認する。worktree が残っている場合は `wt list` で状態を確認し `wt remove` を実行する。`discard` でブランチが残っている場合は worktree のみ削除されている
- **depends_on_artifacts**: []

### D10-03: マージ先に追随済みでコンフリクトも未コミット変更もない
- **severity**: blocker
- **verify_type**: automated
- **verification**:
  1. `git status --porcelain` を実行し、未コミット変更とコンフリクト（`UU` ステータス）を検出する
  2. `Grep("^<<<<<<<|^=======|^>>>>>>>")` で作業ツリー内のコンフリクトマーカー残存を検索する
  3. 選択値が `wt-merge` または `pr` の場合、`git fetch <remote> <マージ先ブランチ>` の後に `git rev-list --count HEAD..<マージ先ブランチ>` でマージ先の未取り込みコミット数を数える
  4. 選択値が `branch-keep` または `discard` の場合、手順3は対象外（N/A）として記録する
- **pass_condition**: 手順1の出力が空、手順2の検出結果が0件、かつ（手順3のコミット数が0、または手順4の N/A が記録されていること）
- **fail_diagnosis_hint**: コンフリクトがある場合は `git diff --diff-filter=U` で対象ファイルを特定する。コンフリクトマーカーが残存している場合はマージ解決が不完全である。手順3が0でない場合はマージ先が先に進んでおり、`wt merge` のリベースを再実行するか PR の base を更新する
- **depends_on_artifacts**: []

### D10-04: 統合後の HEAD でテストが PASS している
- **severity**: blocker
- **verify_type**: automated
- **verification**:
  1. 選択値が `branch-keep` または `discard` の場合、統合が発生していないため本基準は対象外（N/A）として記録する
  2. 選択値が `wt-merge` の場合、`wt merge` の pre-merge フックが実行したテスト・ビルド検証の出力（実行コマンドと exit code）が記録されているか確認する
  3. 選択値が `pr` の場合、push した HEAD に対するテスト実行結果（CI の結論、またはローカル実行時の実行コマンドと出力サマリー）が記録されているか確認する
  4. 手順2または手順3で記録された結果の exit code と failed 件数を読み取る
- **pass_condition**: 手順1の N/A が記録されていること、または手順4の exit code が 0 かつ failed 件数が 0 であること
- **fail_diagnosis_hint**: pre-merge フックの出力が記録されていない場合、`wt merge` がフックをスキップして実行された可能性があるため、マージ後の HEAD でテストコマンドを直接実行して確認する。`pr` で CI 未完了の場合は結論が出るまで待つか、ローカルでテストを実行してその出力を記録する。失敗している場合はマージ後に初めて衝突した退行であり、Phase 8/9 の Re-gate では検出できない種類の失敗として扱う
- **depends_on_artifacts**: []

### D10-05: 各コミットメッセージが変更理由を含む
- **severity**: quality
- **verify_type**: inspection
- **verification**:
  1. 選択値が `discard` の場合、コミットが破棄されるため本基準は対象外（N/A）として記録する
  2. `git log --format='%H%n%s%n%b%n---' <artifacts.branch_base>..HEAD` でブランチの全コミットのメッセージを取得する
  3. 各コミットについて、subject が変更内容を示しているかを確認する
  4. 各コミットについて、subject または body に変更の理由（なぜその変更が必要か）の記述が含まれるかを確認する
  5. 手順4の記述が無いコミットをリストアップする
- **pass_condition**: 手順1の N/A が記録されていること、または手順5のリストが0件
- **fail_diagnosis_hint**: 理由の記述が無いコミットを特定する。`wt merge` はスカッシュを伴うため、スカッシュ後の1コミットのメッセージに各変更の理由が集約されているかを確認する。マージ済みで書き換えができない場合は quality 警告として記録し、以降のフェーズでのコミット手順に反映する
- **depends_on_artifacts**: []

## Observation Collection

phase-auditor は verdict 出力時に observations[] を必ず含めること。
PASS 判定の criteria でも quality/warning レベルの所見があれば記録する。
observations は project-state.json の phase_observations[] に蓄積される。

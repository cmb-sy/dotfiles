# === カスタム設定領域 (2023年11月更新) ===
# このセクションは自分でカスタマイズした設定です

# Lean styleの設定
# シンプルで軽量なスタイルに変更
typeset -g POWERLEVEL9K_MODE=lean

# プロンプトの色をカスタマイズ
typeset -g POWERLEVEL9K_DIR_FOREGROUND=27  # 青色
typeset -g POWERLEVEL9K_DIR_BACKGROUND=11  # 黄色

# GitステータスのFOREGROUND色
typeset -g POWERLEVEL9K_VCS_CLEAN_FOREGROUND=2    # 緑色
typeset -g POWERLEVEL9K_VCS_MODIFIED_FOREGROUND=3 # 黄色
typeset -g POWERLEVEL9K_VCS_UNTRACKED_FOREGROUND=1 # 赤色

# コマンドの実行時間の色
typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_FOREGROUND=0
typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_BACKGROUND=3

# プロンプトの表示要素を設定
# 左側のプロンプト要素
typeset -g POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(

  # --- 基本情報 ---
  dir           # カレントディレクトリ
  vcs           # Gitステータス
  kubecontext   # Kubernetes context
)

# 右側のプロンプト要素
typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(
  status                  # 前回のコマンドの終了コード
  command_execution_time  # 前回のコマンドの実行時間
  background_jobs         # バックグラウンドジョブの存在を表示
  # コメント: 長い処理をしているときに便利な情報
)

# === Gitステータス表示のカスタマイズ ===
# コメント: Gitリポジトリでの作業をより視覚的に把握するための設定
typeset -g POWERLEVEL9K_VCS_CLEAN_FOREGROUND=2
typeset -g POWERLEVEL9K_VCS_CLEAN_BACKGROUND=0
typeset -g POWERLEVEL9K_VCS_UNTRACKED_FOREGROUND=220
typeset -g POWERLEVEL9K_VCS_UNTRACKED_BACKGROUND=0
typeset -g POWERLEVEL9K_VCS_MODIFIED_FOREGROUND=1
typeset -g POWERLEVEL9K_VCS_MODIFIED_BACKGROUND=0

# Gitブランチアイコンをカスタマイズ
# コメント: オリジナルのブランチアイコンに変更
typeset -g POWERLEVEL9K_VCS_BRANCH_ICON='\uF126 '

# === ディレクトリ表示のカスタマイズ ===
# コメント: 長いパス名を省略して表示を簡潔に
typeset -g POWERLEVEL9K_SHORTEN_STRATEGY=truncate_to_last
typeset -g POWERLEVEL9K_SHORTEN_DIR_LENGTH=3

# === アイコンのカスタマイズ ===
# コメント: わかりやすさのためにアイコンを変更
typeset -g POWERLEVEL9K_HOME_ICON='\uF015'
typeset -g POWERLEVEL9K_HOME_SUB_ICON='\uF07C'
typeset -g POWERLEVEL9K_FOLDER_ICON='\uF115'

# === Lean style の追加設定 ===
# コメント: シンプルで軽量なプロンプトスタイルに調整
typeset -g POWERLEVEL9K_PROMPT_ADD_NEWLINE=false  # 改行を追加しない
typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_PREFIX=''
typeset -g POWERLEVEL9K_MULTILINE_LAST_PROMPT_PREFIX='%F{blue}❯%f '
typeset -g POWERLEVEL9K_PROMPT_ON_NEWLINE=false   # プロンプトを1行に表示
typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VIINS_CONTENT_EXPANSION='❯'
typeset -g POWERLEVEL9K_PROMPT_CHAR_OK_VIINS_FOREGROUND=76
typeset -g POWERLEVEL9K_PROMPT_CHAR_ERROR_VIINS_FOREGROUND=196 
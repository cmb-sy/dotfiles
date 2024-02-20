# zplugがなければインストールし、ホームディレクトリに.plugが作成される。
if [[ ! -d ~/.zplug ]]; then
  git clone https://github.com/zplug/zplug ~/.zplug
fi
# Zplugの初期化で、定義されている設定を有効化。
source ~/.zplug/init.zsh

# plugin
zplug romkatv/powerlevel10k, as:theme, depth:1
zplug load --verbose
zplug install

# zplugプラグインがインストールされていない場合に、
# ユーザーが 'y' を入力するとプラグインをインストールするという動作をする。
if ! zplug check --verbose; then
  printf "Install? [y/N]: "
  if read -q; then
    echo; zplug install
  fi
fi

-- Packerの自動インストール
local ensure_packer = function()
  local fn = vim.fn
  local install_path = fn.stdpath('data')..'/site/pack/packer/start/packer.nvim'
  if fn.empty(fn.glob(install_path)) > 0 then
    fn.system({'git', 'clone', '--depth', '1', 'https://github.com/wbthomason/packer.nvim', install_path})
    vim.cmd [[packadd packer.nvim]]
    return true
  end
  return false
end

local packer_bootstrap = ensure_packer()

-- pcallでPackerのロードを試みる
local status_ok, packer = pcall(require, 'packer')
if not status_ok then
  print("Packer could not be loaded!")
  return
end

-- パッカーの初期化と設定
packer.init({
  display = {
    open_fn = function()
      return require('packer.util').float({ border = 'rounded' })
    end,
    prompt_border = 'rounded',
  },
  git = {
    clone_timeout = 300,
  },
  auto_clean = true,
  compile_on_sync = true,
})

return packer.startup(function(use)
  -- Packer自体
  use 'wbthomason/packer.nvim'  -- Packer 自体を管理
  
  -- LSPとTreesitter
  use 'neovim/nvim-lspconfig'   -- LSP 設定用プラグイン
  use {
    'nvim-treesitter/nvim-treesitter',
    run = ':TSUpdate'
  }
 
  -- 補完プラグイン
  use {
    'hrsh7th/nvim-cmp',  -- 補完エンジン
    requires = {
      'hrsh7th/cmp-nvim-lsp',  -- LSP 補完用
      'hrsh7th/cmp-buffer',    -- バッファ補完用
      'hrsh7th/cmp-path'       -- パス補完用
    }
  }
 
  -- 最初のインストール時に自動的にプラグインをセットアップ
  if packer_bootstrap then
    packer.sync()
  end
end)
 
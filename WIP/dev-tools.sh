#!/usr/bin/env bash
# ==============================================================================
# Dev Workflow Setup — Debian/Ubuntu
# Instala e configura: Zsh + plugins, Powerlevel10k, Kitty, Tmux, LunarVim,
# Neofetch e todas as dependências necessárias.
#
# Fluxo final: Kitty abre → Tmux inicia automaticamente → cada painel usa Zsh
# ==============================================================================
# 0.2
# AVISO NAO EXECUTE

set -euo pipefail

# ------------------------------------------------------------------------------
# Cores e helpers de log
# ------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log()    { echo -e "${GREEN}[✔]${NC} $1"; }
warn()   { echo -e "${YELLOW}[!]${NC} $1"; }
erro()   { echo -e "${RED}[✘]${NC} $1"; exit 1; }
titulo() { echo -e "\n${BLUE}══════════════════════════════════════${NC}"; \
           echo -e "${CYAN}  $1${NC}"; \
           echo -e "${BLUE}══════════════════════════════════════${NC}"; }

# ------------------------------------------------------------------------------
# Verificações iniciais
# ------------------------------------------------------------------------------
verificar_sistema() {
    titulo "Verificando sistema"

    if ! command -v apt &>/dev/null; then
        erro "Este script requer apt (Debian/Ubuntu). Sistema não suportado."
    fi

    if [ "$EUID" -eq 0 ]; then
        erro "Não execute este script como root. Use seu usuário normal com sudo."
    fi

    log "Sistema: $(. /etc/os-release && echo "$PRETTY_NAME")"
    log "Usuário: $USER"
}

# ------------------------------------------------------------------------------
# Dependências base do sistema
# Inclui tudo necessário para compilar, baixar e rodar as ferramentas
# ------------------------------------------------------------------------------
instalar_dependencias() {
    titulo "Instalando dependências base"

    sudo apt update
    sudo apt install -y \
        zsh \
        git \
        curl \
        wget \
        unzip \
        tar \
        make \
        gcc \
        build-essential \ 
        fontconfig \
        neofetch \
        tmux \
        python3 \
        python3-pip \
        npm \
        nodejs \
        ripgrep 
        fd-find \
        fzf \
        xclip \ #
        luarocks \
        cmake \ # 
        libfuse2 \
        gettext \
        python3-full \
        python3-pip \
        pipx \
        python3-pynvim
        

    log "Dependências base instaladas."
}

# Adicione esta nova função antes de instalar_lunarvim
configurar_ambientes_runtime() {
    titulo "Configurando Runtimes (Python & Node)"

    # --- Configuração NPM (Evita EACCES / Permissão negada) ---
    log "Configurando diretório global do NPM no HOME..."
    mkdir -p "$HOME/.npm-global"
    npm config set prefix "$HOME/.npm-global"
    
    # Exportar para a sessão atual do script poder usar
    export PATH="$HOME/.npm-global/bin:$PATH"

    # --- Configuração Python (PEP 668) ---
    # Como você já instalou python3-pynvim via APT, o Neovim já terá acesso.
    # Garantimos apenas que o pipx (para apps isolados) esteja no PATH
    if command -v pipx &>/dev/null; then
        pipx ensurepath --force
        log "Pipx configurado."
    fi
}
# ------------------------------------------------------------------------------
# Kitty Terminal
# Instalado via script oficial (versão mais recente, sem depender do apt)
# ------------------------------------------------------------------------------
instalar_kitty() {
    titulo "Instalando Kitty Terminal"

    if command -v kitty &>/dev/null; then
        warn "Kitty já instalado. Pulando."
        return
    fi

    curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin

    # Criar symlink para o PATH
    mkdir -p ~/.local/bin
    ln -sf ~/.local/kitty.app/bin/kitty ~/.local/bin/kitty
    ln -sf ~/.local/kitty.app/bin/kitten ~/.local/bin/kitten

    # Adicionar ~/.local/bin ao PATH se ainda não estiver
    if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' ~/.profile 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.profile
    fi

    log "Kitty instalado em ~/.local/kitty.app"
}

# ------------------------------------------------------------------------------
# Neovim — versão mais recente via AppImage (apt costuma ter versão antiga)
# LunarVim exige Neovim >= 0.9
# ------------------------------------------------------------------------------
instalar_neovim() {
    titulo "Instalando Neovim (AppImage)"

    if command -v nvim &>/dev/null; then
        local version
        version=$(nvim --version | head -1)
        warn "Neovim já instalado: $version. Pulando."
        return
    fi

    mkdir -p ~/.local/bin
    curl -Lfo ~/.local/bin/nvim https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.appimage
    chmod +x ~/.local/bin/nvim

    log "Neovim instalado em ~/.local/bin/nvim"
}

# ------------------------------------------------------------------------------
# Nerd Fonts — MesloLGS NF (necessária para Powerlevel10k e ícones do LunarVim)
# ------------------------------------------------------------------------------
instalar_fontes() {
    titulo "Instalando Nerd Fonts (MesloLGS NF)"

    local FONT_DIR="$HOME/.local/share/fonts/MesloLGS"
    mkdir -p "$FONT_DIR"

    local BASE_URL="https://github.com/romkatv/powerlevel10k-media/raw/master"
    local FONTS=(
        "MesloLGS%20NF%20Regular.ttf"
        "MesloLGS%20NF%20Bold.ttf"
        "MesloLGS%20NF%20Italic.ttf"
        "MesloLGS%20NF%20Bold%20Italic.ttf"
    )

    for fonte in "${FONTS[@]}"; do
        local nome
        nome=$(echo "$fonte" | sed 's/%20/ /g')
        if [ ! -f "$FONT_DIR/$nome" ]; then
            wget -q -O "$FONT_DIR/$nome" "$BASE_URL/$fonte"
            log "Baixada: $nome"
        else
            warn "Já existe: $nome"
        fi
    done

    # Atualizar cache de fontes do sistema
    fc-cache -fv &>/dev/null
    log "Cache de fontes atualizado."
}

# ------------------------------------------------------------------------------
# Plugins Zsh + Powerlevel10k
# Todos clonados em ~/.zsh/plugins para organização
# ------------------------------------------------------------------------------
instalar_plugins_zsh() {
    titulo "Instalando plugins do Zsh"

    local PLUGIN_DIR="$HOME/.zsh/plugins"
    mkdir -p "$PLUGIN_DIR"

    declare -A PLUGINS=(
        ["zsh-autosuggestions"]="https://github.com/zsh-users/zsh-autosuggestions"
        ["zsh-syntax-highlighting"]="https://github.com/zsh-users/zsh-syntax-highlighting"
        ["zsh-completions"]="https://github.com/zsh-users/zsh-completions"
        ["zsh-history-substring-search"]="https://github.com/zsh-users/zsh-history-substring-search"
        ["gitstatus"]="https://github.com/romkatv/gitstatus.git"
        ["powerlevel10k"]="https://github.com/romkatv/powerlevel10k.git"
    )

    for nome in "${!PLUGINS[@]}"; do
        if [ -d "$PLUGIN_DIR/$nome" ]; then
            warn "Plugin '$nome' já existe. Atualizando..."
            git -C "$PLUGIN_DIR/$nome" pull --quiet
        else
            log "Clonando $nome..."
            git clone --depth=1 "${PLUGINS[$nome]}" "$PLUGIN_DIR/$nome"
        fi
    done

    log "Todos os plugins instalados."
}

# ------------------------------------------------------------------------------
# LunarVim
# Instala via script oficial. Depende de: nvim, node, npm, pip3, cargo (rust)
# ------------------------------------------------------------------------------
instalar_rust() {
    if ! command -v cargo &>/dev/null; then
        log "Instalando Rust (necessário para LunarVim)..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --quiet
        # shellcheck source=/dev/null
        source "$HOME/.cargo/env"
        log "Rust instalado."
    else
        warn "Rust já instalado. Pulando."
    fi
}

instalar_lunarvim() {
    titulo "Instalando LunarVim"

    instalar_rust

    if command -v lvim &>/dev/null; then
        warn "LunarVim já instalado. Pulando."
        return
    fi

    log "Iniciando instalador oficial (contornando PEP 668)..."
    
    # Exportamos a variável para que todos os processos filhos do bash vejam
    export PIP_BREAK_SYSTEM_PACKAGES=1
    
    LV_BRANCH='release-1.3/neovim-0.9' \
        bash <(curl -s https://raw.githubusercontent.com/LunarVim/LunarVim/release-1.3/neovim-0.9/utils/installer/install.sh) --yes
    
    # Desativa após a instalação por segurança
    unset PIP_BREAK_SYSTEM_PACKAGES
}
# ------------------------------------------------------------------------------
# Configuração do Zsh (.zshrc)
# History aumentado, plugins carregados na ordem correta,
# Powerlevel10k como tema, neofetch ao abrir shell
# ------------------------------------------------------------------------------
configurar_zsh() {
    titulo "Configurando Zsh (~/.zshrc)"

    # Backup do .zshrc anterior se existir
    [ -f ~/.zshrc ] && cp ~/.zshrc ~/.zshrc.bak && warn "Backup salvo em ~/.zshrc.bak"

    cat > ~/.zshrc << 'EOF'
    # PATH — garante binários locais, Rust, NPM global e Pipx
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"
# ==============================================================================
# ~/.zshrc — Configuração do Zsh
# ==============================================================================

# Diretório base dos plugins
ZSH_PLUGINS="$HOME/.zsh/plugins"

# ------------------------------------------------------------------------------
# Histórico — aumentado para 50.000 linhas
# ------------------------------------------------------------------------------
HISTSIZE=50000
SAVEHIST=50000
HISTFILE=~/.zsh_history

setopt HIST_IGNORE_DUPS       # Não salva duplicatas consecutivas
setopt HIST_IGNORE_ALL_DUPS   # Remove entradas duplicadas do histórico
setopt HIST_FIND_NO_DUPS      # Não exibe duplicatas na busca
setopt HIST_SAVE_NO_DUPS      # Não salva duplicatas no arquivo
setopt SHARE_HISTORY          # Compartilha histórico entre terminais abertos
setopt HIST_REDUCE_BLANKS     # Remove espaços extras antes de salvar
setopt INC_APPEND_HISTORY     # Salva imediatamente, não só ao fechar

# ------------------------------------------------------------------------------
# Completions
# ------------------------------------------------------------------------------
autoload -Uz compinit
compinit

# Completions extras (zsh-completions)
fpath=($ZSH_PLUGINS/zsh-completions/src $fpath)

# Estilo de menu para completions
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'  # Case-insensitive

# ------------------------------------------------------------------------------
# PATH — garante ~/.local/bin na frente (Kitty, Neovim, LunarVim)
# ------------------------------------------------------------------------------
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

# ------------------------------------------------------------------------------
# Plugins — ordem importa: syntax-highlighting SEMPRE por último
# ------------------------------------------------------------------------------
source "$ZSH_PLUGINS/zsh-autosuggestions/zsh-autosuggestions.zsh"
source "$ZSH_PLUGINS/zsh-history-substring-search/zsh-history-substring-search.zsh"

# Atalhos para history-substring-search (setas para cima/baixo)
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down

# ------------------------------------------------------------------------------
# Tema Powerlevel10k
# ------------------------------------------------------------------------------
source "$ZSH_PLUGINS/powerlevel10k/powerlevel10k.zsh-theme"

# Carrega configuração do p10k se existir (gerada com: p10k configure)
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh

# syntax-highlighting deve ser carregado DEPOIS do tema
source "$ZSH_PLUGINS/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"

# ------------------------------------------------------------------------------
# Aliases úteis
# ------------------------------------------------------------------------------
alias ls='ls --color=auto'
alias ll='ls -lah --color=auto'
alias la='ls -A --color=auto'
alias grep='grep --color=auto'
alias vim='lvim'           # Usa LunarVim como editor padrão
alias vi='lvim'
alias update='sudo apt update && sudo apt upgrade -y'
alias cls='clear'

# ------------------------------------------------------------------------------
# Neofetch ao abrir o shell (apenas em sessões interativas sem tmux)
# Dentro do tmux o neofetch roda pela config do tmux para não repetir
# ------------------------------------------------------------------------------
if [[ -z "$TMUX" ]]; then
    neofetch
fi
EOF

    # Definir Zsh como shell padrão do usuário
    if [ "$SHELL" != "$(which zsh)" ]; then
        chsh -s "$(which zsh)"
        log "Shell padrão alterado para Zsh."
    else
        warn "Zsh já é o shell padrão."
    fi

    log "Zsh configurado."
}

# ------------------------------------------------------------------------------
# Configuração do Tmux (.tmux.conf)
# Shell padrão: Zsh | Mouse ativo | Prefixo: Ctrl+A | Histórico: 50.000 linhas
# ------------------------------------------------------------------------------
configurar_tmux() {
    titulo "Configurando Tmux (~/.tmux.conf)"

    [ -f ~/.tmux.conf ] && cp ~/.tmux.conf ~/.tmux.conf.bak && warn "Backup salvo em ~/.tmux.conf.bak"

    cat > ~/.tmux.conf << 'EOF'
# ==============================================================================
# ~/.tmux.conf — Configuração do Tmux
# ==============================================================================

# ------------------------------------------------------------------------------
# Shell padrão: Zsh em todos os painéis
# ------------------------------------------------------------------------------
set-option -g default-shell /usr/bin/zsh
set-option -g default-command /usr/bin/zsh

# ------------------------------------------------------------------------------
# Prefixo: substituir Ctrl+B por Ctrl+A (mais ergonômico)
# ------------------------------------------------------------------------------
unbind C-b
set-option -g prefix C-a
bind-key C-a send-prefix

# ------------------------------------------------------------------------------
# Funcionalidades gerais
# ------------------------------------------------------------------------------
set -g mouse on                    # Mouse: resize, scroll, clicar em painéis
set -g history-limit 50000         # Histórico de scrollback aumentado
set -g base-index 1                # Janelas começam em 1 (não 0)
setw -g pane-base-index 1          # Painéis começam em 1
set -g renumber-windows on         # Renumera janelas ao fechar uma
set -g escape-time 0               # Sem delay ao pressionar ESC (melhora nvim)
set -g focus-events on             # Eventos de foco (melhora integração nvim)
set -g default-terminal "screen-256color"
set -ag terminal-overrides ",xterm-256color:RGB"

# ------------------------------------------------------------------------------
# Atalhos de divisão de painel (mais intuitivos)
# ------------------------------------------------------------------------------
bind | split-window -h -c "#{pane_current_path}"   # Dividir na vertical
bind - split-window -v -c "#{pane_current_path}"   # Dividir na horizontal
bind c new-window -c "#{pane_current_path}"         # Nova janela no dir atual
unbind '"'
unbind %

# ------------------------------------------------------------------------------
# Navegação entre painéis com Ctrl+hjkl (sem prefixo)
# ------------------------------------------------------------------------------
bind -n C-h select-pane -L
bind -n C-j select-pane -D
bind -n C-k select-pane -U
bind -n C-l select-pane -R

# ------------------------------------------------------------------------------
# Recarregar config sem reiniciar
# ------------------------------------------------------------------------------
bind r source-file ~/.tmux.conf \; display-message "Config recarregada!"

# ------------------------------------------------------------------------------
# Barra de status minimalista
# ------------------------------------------------------------------------------
set -g status-position bottom
set -g status-style 'bg=#1e1e2e fg=#cdd6f4'
set -g status-left '#[fg=#89b4fa,bold] #S '
set -g status-right '#[fg=#a6e3a1] %d/%m %H:%M '
set -g window-status-current-format '#[fg=#f5c2e7,bold] #I:#W '
set -g window-status-format ' #I:#W '

# ------------------------------------------------------------------------------
# Neofetch ao criar nova janela/painel
# ------------------------------------------------------------------------------
set-hook -g after-new-window   'run "tmux send-keys neofetch Enter"'
set-hook -g after-new-session  'run "tmux send-keys neofetch Enter"'
EOF

    log "Tmux configurado."
}

# ------------------------------------------------------------------------------
# Configuração do Kitty (kitty.conf)
# Fonte MesloLGS NF, abre Tmux automaticamente ao iniciar
# ------------------------------------------------------------------------------
configurar_kitty() {
    titulo "Configurando Kitty (~/.config/kitty/kitty.conf)"

    mkdir -p ~/.config/kitty
    [ -f ~/.config/kitty/kitty.conf ] && \
        cp ~/.config/kitty/kitty.conf ~/.config/kitty/kitty.conf.bak && \
        warn "Backup salvo em ~/.config/kitty/kitty.conf.bak"

    cat > ~/.config/kitty/kitty.conf << 'EOF'
# ==============================================================================
# ~/.config/kitty/kitty.conf — Configuração do Kitty Terminal
# ==============================================================================

# ------------------------------------------------------------------------------
# Fonte — MesloLGS NF (necessária para Powerlevel10k e ícones)
# ------------------------------------------------------------------------------
font_family      MesloLGS NF
bold_font        MesloLGS NF Bold
italic_font      MesloLGS NF Italic
bold_italic_font MesloLGS NF Bold Italic
font_size        12.0

# ------------------------------------------------------------------------------
# Comportamento
# ------------------------------------------------------------------------------
enable_audio_bell        no      # Sem bipe sonoro
confirm_os_window_close  0       # Fechar sem confirmação
scrollback_lines         10000   # Histórico de scroll

# ------------------------------------------------------------------------------
# Ao iniciar o Kitty, abre o Tmux automaticamente
# - Se já existir uma sessão "dev", reconecta
# - Caso contrário, cria uma nova sessão chamada "dev"
# ------------------------------------------------------------------------------
startup_session ~/.config/kitty/startup.conf
EOF

    # Arquivo de sessão do Kitty: define o que roda ao abrir
    cat > ~/.config/kitty/startup.conf << 'EOF'
# Abre uma janela e inicia/reconecta ao Tmux na sessão "dev"
new_tab
launch --type=background zsh -c 'tmux new-session -A -s dev'
EOF

    log "Kitty configurado (abrirá Tmux automaticamente)."
}

# ------------------------------------------------------------------------------
# Alterar shell padrão para Zsh (caso ainda não tenha sido feito)
# ------------------------------------------------------------------------------
definir_zsh_padrao() {
    titulo "Definindo Zsh como shell padrão"

    local ZSH_PATH
    ZSH_PATH=$(which zsh)

    # Adicionar zsh à lista de shells válidos se não estiver
    if ! grep -q "$ZSH_PATH" /etc/shells; then
        echo "$ZSH_PATH" | sudo tee -a /etc/shells
    fi

    if [ "$SHELL" != "$ZSH_PATH" ]; then
        chsh -s "$ZSH_PATH"
        log "Shell alterado para $ZSH_PATH. Faça logout/login para aplicar."
    else
        warn "Zsh já é o shell padrão."
    fi
}

# ------------------------------------------------------------------------------
# Mensagem final com próximos passos
# ------------------------------------------------------------------------------
mensagem_final() {
    titulo "Setup Concluído!"

    echo -e "${GREEN}"
    echo "  ✔ Dependências base instaladas"
    echo "  ✔ Kitty instalado e configurado"
    echo "  ✔ Neovim (AppImage) instalado"
    echo "  ✔ Fontes MesloLGS NF instaladas"
    echo "  ✔ Plugins Zsh instalados"
    echo "  ✔ LunarVim instalado"
    echo "  ✔ Zsh configurado (.zshrc)"
    echo "  ✔ Tmux configurado (.tmux.conf)"
    echo "  ✔ Kitty configurado (inicia Tmux automaticamente)"
    echo -e "${NC}"

    echo -e "${YELLOW}Próximos passos:${NC}"
    echo "  1. Faça logout e login novamente (ou rode: exec zsh)"
    echo "  2. Abra o Kitty — o Tmux iniciará automaticamente"
    echo "  3. Configure o tema: p10k configure"
    echo "  4. Configure a fonte do seu emulador para: MesloLGS NF"
    echo ""
    echo -e "${CYAN}Atalhos Tmux (prefixo: Ctrl+A):${NC}"
    echo "  Ctrl+A + |   → dividir painel na vertical"
    echo "  Ctrl+A + -   → dividir painel na horizontal"
    echo "  Ctrl+A + r   → recarregar config do tmux"
    echo "  Ctrl+H/J/K/L → navegar entre painéis"
    echo ""
}

# ------------------------------------------------------------------------------
# MAIN — Execução em ordem
# ------------------------------------------------------------------------------
main() {
    verificar_sistema
    instalar_dependencias
	configurar_ambientes_runtime
    instalar_kitty
    instalar_neovim
    instalar_fontes
    instalar_plugins_zsh
    instalar_lunarvim
    configurar_zsh
    configurar_tmux
    configurar_kitty
    definir_zsh_padrao
    mensagem_final
}

main

#!/bin/bash

#############################################################################################
#   conjunto de ferraments para desenvolvimento
#############################################################################################
# versão 2.0
# autor: Euriandes Jales

#set -euo pipefail # 

# Variaveis GLOBAIS
pacotes_pacman=(
    "base-devel"   # Ferramentas de desenvolvimento essenciais
    "git"          # Controle de versão
    "curl"         # Ferramenta de transferência de dados
    "wget"         # Ferramenta de download
    "make"         # Ferramenta de construção de software
    "cmake"        # Ferramenta de construção de software
    "python3"      # Linguagem de programação
    "tmux"         # Multiplexador de terminal
    "unzip"        # Ferramenta de descompactação
    "kitty"        # Emulador de terminal moderno e personalizável
    "ranger"       # Gerenciador de arquivos em terminal
    "fastfetch"    # Ferramenta de informação do sistema
)
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
# Verificar se o script está sendo executado como root
# ------------------------------------------------------------------------------
 if [ "$EUID" -eq 0 ]; then
        erro "Não execute este script como root. Use seu usuário normal com sudo."
    return 1
    fi

# Garante que estamos em um sistema com pacman (Arch/derivados)
command -v pacman &>/dev/null || erro "pacman não encontrado. Este script é exclusivo para Arch Linux e derivados."

# ------------------------------------------------------------------------------
sudo pacman -Syu --noconfirm # Atualiza o sistema
log "Sistema atualizado com sucesso."

#
cd ~/Downloads || erro "Não foi possível acessar a pasta Downloads."
wget -qO- https://astral.sh/uv/install.sh | sh #script de isntalação do uv
uv install ipython # instala o ipython usando o uv
uv install tdlr # instala o tldr usando o uv
sh -c "$(wget https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -O -)" # instala o ohmyzsh
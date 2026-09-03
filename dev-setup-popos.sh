#!/usr/bin/env bash
# ==============================================================================
# dev-setup-popos.sh — Ambiente de Desenvolvimento para Pop!_OS / Ubuntu
# ==============================================================================
# Versão: 1.0.0
# Autor:  Platform Engineering
# Adaptado de: dev-setup-cachyos.sh (CachyOS / Arch Linux)
#
# DESCRIÇÃO:
#   Script modular que automatiza a instalação e configuração de um ambiente
#   de desenvolvimento completo no Pop!_OS (e qualquer derivado Ubuntu/Debian).
#
# ESTRATÉGIA DE GESTÃO DE PACOTES:
#   • apt      → ferramentas de sistema, compiladores, libs nativas
#   • repositórios oficiais de terceiros (Docker, Microsoft/VS Code) → pacotes
#     que não têm versão atualizada nos repos do Ubuntu
#   • uv       → TODAS as ferramentas Python (conformidade PEP 668)
#   • rustup   → toolchain Rust (via installer oficial, não apt)
#
# USO:
#   chmod +x dev-setup-popos.sh
#   ./dev-setup-popos.sh
#
# AVISO: Não execute como root. O script usa sudo internamente quando necessário.
# ==============================================================================

# ──────────────────────────────────────────────────────────────────────────────
# CONFIGURAÇÃO DE SEGURANÇA DO BASH
# ──────────────────────────────────────────────────────────────────────────────
# Não usamos `set -e` global porque queremos que módulos falhem de forma isolada.
# Em vez disso, verificamos exit codes manualmente em pontos críticos.
# `set -u` garante que variáveis não inicializadas causem erro imediato.
# `set -o pipefail` captura falhas dentro de pipes (ex: cmd1 | cmd2).
set -uo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# CONSTANTES E CONFIGURAÇÃO GLOBAL
# ──────────────────────────────────────────────────────────────────────────────
readonly SCRIPT_VERSION="1.0.0"
readonly LOG_FILE="/tmp/dev_setup_$(date +%Y%m%d_%H%M%S).log"
readonly PLUGIN_DIR="$HOME/.zsh/plugins"
readonly FONT_DIR="$HOME/.local/share/fonts/MesloLGS"

# Garante que o apt nunca pare para perguntar algo interativamente
export DEBIAN_FRONTEND=noninteractive

# Contador global de falhas — permite continuar e reportar no final
FALHAS=0
MODULOS_OK=()
MODULOS_FALHOS=()

# ──────────────────────────────────────────────────────────────────────────────
# SISTEMA DE CORES (compatível com terminais que suportam ANSI)
# ──────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color / Reset

# ──────────────────────────────────────────────────────────────────────────────
# SISTEMA DE LOGGING
# Grava em stdout (com cores) E em arquivo de log (sem escape codes ANSI)
# ──────────────────────────────────────────────────────────────────────────────

# Remove códigos de escape ANSI para o arquivo de log ficar legível
_strip_ansi() {
    sed 's/\x1b\[[0-9;]*m//g'
}

# Função base de log — todas as outras dependem desta
_log_raw() {
    local nivel="$1"
    local msg="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    # Escreve no arquivo de log (sem cor, com timestamp)
    echo "[${timestamp}] [${nivel}] ${msg}" | _strip_ansi >> "$LOG_FILE"
}

log()       {
    local msg="$1"
    echo -e "${GREEN}[✔ OK]${NC}    $msg"
    _log_raw "OK   " "$msg"
}

info()      {
    local msg="$1"
    echo -e "${CYAN}[ℹ INFO]${NC}  $msg"
    _log_raw "INFO " "$msg"
}

warn()      {
    local msg="$1"
    echo -e "${YELLOW}[⚠ AVISO]${NC} $msg"
    _log_raw "AVISO" "$msg"
}

erro()      {
    local msg="$1"
    echo -e "${RED}[✘ ERRO]${NC}  $msg" >&2
    _log_raw "ERRO " "$msg"
    # Não fazemos exit aqui para permitir que o caller decida
}

titulo()    {
    local msg="$1"
    echo -e "\n${BOLD}${BLUE}══════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}  ► $msg${NC}"
    echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════${NC}"
    _log_raw "====" "MÓDULO: $msg"
}

subtitulo() {
    local msg="$1"
    echo -e "\n${CYAN}  ┌─ $msg${NC}"
    _log_raw "----" "  $msg"
}

# ──────────────────────────────────────────────────────────────────────────────
# UTILITÁRIOS
# ──────────────────────────────────────────────────────────────────────────────

# Verifica se um comando está disponível no PATH
cmd_existe() {
    command -v "$1" &>/dev/null
}

# Executa um apt install de forma idempotente
# Retorna o exit code para que o caller decida como lidar
apt_install() {
    sudo apt-get install -y --no-install-recommends "$@" 2>>"$LOG_FILE"
}

# Registra resultado de um módulo para o relatório final
_registrar_resultado() {
    local nome="$1"
    local exit_code="$2"
    if [[ "$exit_code" -eq 0 ]]; then
        MODULOS_OK+=("$nome")
    else
        MODULOS_FALHOS+=("$nome")
        (( FALHAS++ )) || true  # '|| true' evita que set -e interrompa aqui
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# MÓDULO 0: VERIFICAÇÕES PRÉ-REQUISITO
# Valida ambiente antes de qualquer instalação
# ──────────────────────────────────────────────────────────────────────────────
verificar_sistema() {
    titulo "Verificações de Sistema"

    # Impede execução como root — muitas ferramentas (rustup, uv) quebram com root
    if [[ "$EUID" -eq 0 ]]; then
        erro "Não execute este script como root. Use seu usuário normal."
        exit 1
    fi

    # Verifica que estamos num sistema baseado em Debian/Ubuntu
    if ! cmd_existe apt-get; then
        erro "apt-get não encontrado. Este script é exclusivo para Pop!_OS / Ubuntu / Debian."
        exit 1
    fi

    # Verifica conectividade básica com um ping no servidor do Ubuntu
    if ! ping -c 1 -W 3 archive.ubuntu.com &>/dev/null; then
        warn "Sem conectividade com archive.ubuntu.com. Verifique sua rede."
        warn "Continuando mesmo assim (repositórios em cache podem funcionar)..."
    fi

    log "Sistema: $(uname -srm)"
    log "Usuário: $USER (UID: $EUID)"
    log "Log gravado em: ${BOLD}$LOG_FILE${NC}"

    # Atualiza a base de dados do apt antes de qualquer instalação
    info "Sincronizando base de dados do apt..."
    sudo apt-get update -y 2>>"$LOG_FILE" || warn "Falha ao sincronizar apt. Prosseguindo..."

    # Garante suporte a HTTPS e chaves de repositório para os passos seguintes
    apt_install ca-certificates gnupg lsb-release software-properties-common apt-transport-https &>>"$LOG_FILE" \
        || warn "Falha ao instalar pré-requisitos de repositório."
}

# ──────────────────────────────────────────────────────────────────────────────
# MÓDULO 1: DEPENDÊNCIAS DO SISTEMA (via apt)
# Apenas ferramentas disponíveis nos repositórios oficiais do Ubuntu/Pop!_OS
# ──────────────────────────────────────────────────────────────────────────────

# Pacotes divididos em grupos temáticos para facilitar manutenção

readonly -a PKGS_BASE=(
    git             # VCS — obrigatório para clonar plugins e repositórios
    curl            # Transferências HTTP — usado por instaladores (rustup, etc.)
    wget            # Downloader alternativo — alguns scripts preferem wget
    unzip           # Extração de .zip (fontes, binários)
    tar             # Extração de tarballs
    p7zip-full      # Extração de arquivos .7z (fornece o comando `7z`)
    make            # Build system — necessário para compilar muitos plugins
    build-essential # Meta-pacote: gcc, g++, binutils — base para compilação
    pkg-config      # Permite ao compilador localizar libs instaladas no sistema
)

readonly -a PKGS_SHELL=(
    zsh                       # Shell principal do ambiente
    tmux                      # Multiplexador de terminal
    byobu                     # Wrapper do tmux, com teclas de atalhos mais intuitivas (opcional, mas recomendado)
    fontconfig                # Gerenciamento de fontes (necessário para fc-cache)
    fzf                       # Fuzzy finder — integrado ao Zsh e Tmux
    ripgrep                   # Busca de texto ultrarrápida (substituto ao grep)
    fd-find                   # Localizador de arquivos moderno (substituto ao find; binário é `fdfind`)
    ranger                    # Gerenciador de arquivos TUI
    tldr                      # Resumos práticos de comandos man
    zoxide                    # Navegação inteligente de diretórios (substituto ao cd)
    bat                       # Cat com syntax highlighting (binário é `batcat` no Ubuntu)
    etckeeper                 # Versionamento do /etc (útil para sysadmins e devops)
    figlet                    # Gerador de texto ASCII (usado para banners divertidos no terminal)
    lolcat                    # Exibe texto com cores aleatórias (divertido para banners e mensagens de erro)
)

readonly -a PKGS_DEV=(
    luarocks      # Gerenciador de pacotes Lua (necessário para plugins Neovim)
    cmake         # Build system multiplataforma (dependência de muitas libs C/C++)
    neovim        # Editor de texto/IDE modal — base para LunarVim
    # gcc e g++ já vêm no build-essential
)

readonly -a PKGS_RUST_DEPS=(
    # rustc e cargo NÃO são instalados via apt aqui —
    # usamos rustup para ter controle de versão (stable/nightly/toolchains)
    # Os pacotes abaixo são dependências nativas que o ecossistema Rust precisa
    libssl-dev    # Criptografia — muitos crates Rust dependem de openssl-sys
    libgit2-dev   # Acesso a repositórios Git por bibliotecas Rust
)

readonly -a PKGS_SEGURANCA=(
    nmap             # Scanner de rede e auditoria de portas
    wireshark        # Analisador de pacotes (instala GUI e CLI juntos no Ubuntu)
    netcat-openbsd   # Ferramenta clássica de rede (nc)
    postgresql       # Banco de dados relacional — dependência do Metasploit (msfdb)
)

readonly -a PKGS_PYTHON_SYSTEM=(
    # Apenas o mínimo necessário via apt.
    # Ferramentas Python SEMPRE via `uv tool install` (ver módulo setup_python_tools)
    python3          # Interpretador Python 3 base
    python3-pip      # pip — necessário para bootstrap do uv se ele não estiver instalado
    python3-venv     # Necessário para venvs (pyenv e uv dependem de build deps do Python)
    # Dependências de build do pyenv (para compilar versões do Python do zero)
    libbz2-dev libreadline-dev libsqlite3-dev libffi-dev liblzma-dev zlib1g-dev
)

install_sys_deps() {
    titulo "Módulo 1: Dependências do Sistema (apt)"
    local modulo_ok=true

    # Função local para instalar um grupo e capturar falhas individualmente
    _instalar_grupo() {
        local nome_grupo="$1"
        shift
        local pacotes=("$@")

        subtitulo "Instalando: $nome_grupo"
        for pkg in "${pacotes[@]}"; do
            if apt_install "$pkg"; then
                log "  $pkg"
            else
                erro "  Falha ao instalar: $pkg (veja $LOG_FILE)"
                modulo_ok=false
                # Continuamos — um pacote quebrado não deve bloquear os outros
            fi
        done
    }

    _instalar_grupo "Ferramentas Base"         "${PKGS_BASE[@]}"
    _instalar_grupo "Shell e Terminal"         "${PKGS_SHELL[@]}"
    _instalar_grupo "Desenvolvimento"          "${PKGS_DEV[@]}"
    _instalar_grupo "Dependências Rust Nativas" "${PKGS_RUST_DEPS[@]}"
    _instalar_grupo "Python (sistema)"         "${PKGS_PYTHON_SYSTEM[@]}"

    # Cria aliases de compatibilidade para binários renomeados pelo Debian/Ubuntu
    # (evita conflito de nome com pacotes antigos já existentes na distro)
    mkdir -p "$HOME/.local/bin"
    if cmd_existe batcat && ! cmd_existe bat; then
        ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
        info "Link simbólico criado: bat -> batcat"
    fi
    if cmd_existe fdfind && ! cmd_existe fd; then
        ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
        info "Link simbólico criado: fd -> fdfind"
    fi

    if $modulo_ok; then
        log "Dependências de sistema instaladas com sucesso."
        _registrar_resultado "Dependências do Sistema" 0
    else
        warn "Algumas dependências falharam. Verifique o log: $LOG_FILE"
        _registrar_resultado "Dependências do Sistema" 1
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# MÓDULO 1.5: FASTFETCH e EZA (via repositórios próprios dos projetos)
# Esses dois nem sempre estão disponíveis (ou atualizados) nos repos do Ubuntu,
# então instalamos os .deb oficiais publicados pelos próprios projetos.
# ──────────────────────────────────────────────────────────────────────────────
install_fastfetch_eza() {
    titulo "Módulo 1.5: Fastfetch e Eza"
    local modulo_ok=true

    subtitulo "Fastfetch (substituto ao neofetch)"
    if cmd_existe fastfetch; then
        info "fastfetch já instalado."
    elif apt_install fastfetch; then
        log "fastfetch instalado via apt."
    else
        info "fastfetch não disponível nos repos — baixando .deb oficial do GitHub..."
        local tmp_deb
        tmp_deb=$(mktemp --suffix=.deb)
        local url
        url=$(curl -s https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest \
            | grep -o '"browser_download_url": "[^"]*linux-amd64\.deb"' | head -1 | cut -d'"' -f4)
        if [[ -n "$url" ]] && wget -q -O "$tmp_deb" "$url" && sudo apt-get install -y "$tmp_deb" 2>>"$LOG_FILE"; then
            log "fastfetch instalado via .deb oficial."
        else
            erro "Falha ao instalar fastfetch."
            modulo_ok=false
        fi
        rm -f "$tmp_deb"
    fi

    subtitulo "Eza (ls moderno com ícones e cores)"
    if cmd_existe eza; then
        info "eza já instalado."
    elif apt_install eza; then
        log "eza instalado via apt."
    else
        info "eza não disponível nos repos — adicionando repositório oficial (deb.gierens.de)..."
        sudo mkdir -p /etc/apt/keyrings
        if wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc \
            | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg 2>>"$LOG_FILE"; then
            echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" \
                | sudo tee /etc/apt/sources.list.d/gierens.list > /dev/null
            sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
            sudo apt-get update -y 2>>"$LOG_FILE"
            if apt_install eza; then
                log "eza instalado via repositório oficial."
            else
                erro "Falha ao instalar eza."
                modulo_ok=false
            fi
        else
            erro "Falha ao configurar repositório do eza."
            modulo_ok=false
        fi
    fi

    $modulo_ok && _registrar_resultado "Fastfetch/Eza" 0 || _registrar_resultado "Fastfetch/Eza" 1
}

# ──────────────────────────────────────────────────────────────────────────────
# MÓDULO 2: VISUAL STUDIO CODE (via repositório oficial da Microsoft)
# No Arch isso vinha do AUR; no Ubuntu/Pop!_OS a Microsoft distribui um
# repositório apt oficial, que é a forma recomendada de instalação.
# ──────────────────────────────────────────────────────────────────────────────
install_vscode() {
    titulo "Módulo 2: Visual Studio Code (repositório oficial Microsoft)"

    if cmd_existe code; then
        info "VS Code já instalado: $(code --version | head -1)"
        _registrar_resultado "VS Code" 0
        return
    fi

    subtitulo "Configurando repositório da Microsoft"
    local tmp_gpg
    tmp_gpg=$(mktemp)
    if wget -q https://packages.microsoft.com/keys/microsoft.asc -O "$tmp_gpg" \
        && gpg --dearmor < "$tmp_gpg" > /tmp/packages.microsoft.gpg \
        && sudo install -D -o root -g root -m 644 /tmp/packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg; then

        echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
            | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null

        sudo apt-get update -y 2>>"$LOG_FILE"

        if apt_install code; then
            log "VS Code instalado: $(code --version | head -1)"
            _registrar_resultado "VS Code" 0
        else
            erro "Falha ao instalar o pacote 'code'."
            _registrar_resultado "VS Code" 1
        fi
    else
        erro "Falha ao configurar o repositório da Microsoft."
        _registrar_resultado "VS Code" 1
    fi

    rm -f "$tmp_gpg" /tmp/packages.microsoft.gpg
}

# ──────────────────────────────────────────────────────────────────────────────
# MÓDULO 3: RUST (via rustup)
# Usamos rustup em vez do apt para controle granular de toolchains.
# O apt instala uma versão estática e geralmente desatualizada; rustup permite
# `rustup update`, múltiplas toolchains (stable, nightly) e targets extras.
# ──────────────────────────────────────────────────────────────────────────────
setup_rust() {
    titulo "Módulo 3: Rust Toolchain (rustup)"

    if cmd_existe rustup; then
        info "rustup já instalado. Atualizando toolchain stable..."
        rustup update stable 2>>"$LOG_FILE"
        log "Rust atualizado: $(rustc --version)"
        _registrar_resultado "Rust Toolchain" 0
        return
    fi

    info "Instalando rustup (installer oficial)..."
    # --profile minimal: só instala rustc, cargo, rust-std (sem docs, clippy extra)
    # Adicionamos clippy e rustfmt separadamente por serem úteis no dev
    if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --profile minimal --quiet 2>>"$LOG_FILE"; then

        # Carrega o ambiente Rust na sessão atual sem exigir logout
        # shellcheck source=/dev/null
        source "$HOME/.cargo/env"

        # Componentes adicionais úteis para desenvolvimento
        rustup component add clippy rustfmt 2>>"$LOG_FILE"
        log "Rust instalado: $(rustc --version)"
        log "Cargo instalado: $(cargo --version)"
        _registrar_resultado "Rust Toolchain" 0
    else
        erro "Falha ao instalar Rust via rustup."
        _registrar_resultado "Rust Toolchain" 1
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# MÓDULO 4: FERRAMENTAS PYTHON (via uv)
# PEP 668 proíbe pip install --global em distros modernas (Pop!_OS/Ubuntu 23.04+
# também aplicam essa política em python3-pip).
# `uv tool install` cria ambientes isolados por ferramenta, evitando conflitos
# e sem precisar de `--break-system-packages`.
# ──────────────────────────────────────────────────────────────────────────────

readonly -a PYTHON_TOOLS=(
    ipython   # Shell interativo avançado para Python (REPL com autocompletar)
    ruff      # Linter e formatter Python ultrarrápido (escrito em Rust)
    #black     # Formatter Python — padrão de mercado
    #mypy      # Type checker estático para Python
    #httpie    # Cliente HTTP para terminal — alternativa amigável ao curl
    #poetry    # Gerenciador de dependências e build para projetos Python
)

_instalar_uv() {
    info "Instalando uv (gerenciador de pacotes Python da Astral)..."
    # O installer oficial do uv é o método recomendado — não via pip
    if curl -LsSf https://astral.sh/uv/install.sh | sh 2>>"$LOG_FILE"; then
        # O installer do uv adiciona ~/.local/bin ao PATH
        # Forçamos a atualização do PATH na sessão atual
        export PATH="$HOME/.local/bin:$PATH"
        log "uv instalado: $(uv --version)"
    else
        erro "Falha ao instalar uv."
        return 1
    fi
}

_instalar_pyenv() {
    info "Instalando pyenv (gerenciador de versões Python)..."
    if curl -fsSL https://pyenv.run | bash 2>>"$LOG_FILE"; then
        log "pyenv instalado com sucesso."
    else
        warn "Falha ao instalar pyenv. Prosseguindo sem ele."
    fi
}

setup_python_tools() {
    titulo "Módulo 4: Ferramentas Python (uv + pyenv)"

    # pyenv não existe como pacote apt — instalamos via installer oficial
    if ! cmd_existe pyenv && [[ ! -d "$HOME/.pyenv" ]]; then
        _instalar_pyenv
    else
        info "pyenv já instalado."
    fi

    # Garante que uv está disponível
    if ! cmd_existe uv; then
        _instalar_uv || { _registrar_resultado "Ferramentas Python" 1; return; }
    else
        info "uv já instalado: $(uv --version)"
    fi

    local modulo_ok=true
    subtitulo "Instalando ferramentas Python via 'uv tool install'"

    for tool in "${PYTHON_TOOLS[@]}"; do
        info "  Instalando: $tool"
        # `uv tool install` cria um venv isolado para cada ferramenta
        # Isso é equivalente ao pipx, mas mais rápido e com melhor resolução de deps
        if uv tool install "$tool" 2>>"$LOG_FILE"; then
            log "  $tool"
        else
            erro "  Falha ao instalar tool Python: $tool"
            modulo_ok=false
        fi
    done

    # Garante que o diretório de binários do uv está no PATH permanentemente
    # Adicionamos ao .zshrc para persistir entre sessões
    local uv_bin_path='export PATH="$HOME/.local/bin:$PATH"'
    if ! grep -qF "$uv_bin_path" "$HOME/.zshrc" 2>/dev/null; then
        echo "# uv tools" >> "$HOME/.zshrc"
        echo "$uv_bin_path" >> "$HOME/.zshrc"
        info "PATH do uv adicionado ao .zshrc"
    fi

    $modulo_ok && _registrar_resultado "Ferramentas Python" 0 || _registrar_resultado "Ferramentas Python" 1
}
# ──────────────────────────────────────────────────────────────────────────────
# Lunavim
# ──────────────────────────────────────────────────────────────────────────────
instalar_lunarvim() {

    titulo "Instalando LunarVim"

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

# ──────────────────────────────────────────────────────────────────────────────
# MÓDULO 5: DOCKER (via repositório oficial Docker)
# No Ubuntu/Pop!_OS, o pacote 'docker.io' dos repos costuma ficar bem atrás da
# versão upstream. Usamos o repositório oficial da Docker Inc. para ter a
# versão mais recente do Engine + Compose v2 (plugin).
# ──────────────────────────────────────────────────────────────────────────────
setup_docker() {
    titulo "Módulo 5: Docker"

    local modulo_ok=true

    if cmd_existe docker; then
        info "Docker já instalado: $(docker --version)"
    else
        subtitulo "Configurando repositório oficial da Docker"

        sudo install -m 0755 -d /etc/apt/keyrings
        if curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
            | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>>"$LOG_FILE"; then
            sudo chmod a+r /etc/apt/keyrings/docker.gpg

            local codename
            codename=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")

            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${codename} stable" \
                | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

            sudo apt-get update -y 2>>"$LOG_FILE"

            subtitulo "Instalando pacotes Docker"
            if apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
                log "Docker instalado: $(docker --version)"
            else
                erro "Falha ao instalar pacotes Docker."
                modulo_ok=false
            fi
        else
            erro "Falha ao configurar o repositório da Docker."
            modulo_ok=false
        fi
    fi

    subtitulo "Habilitando serviço Docker via systemd"
    # `enable --now`: habilita no boot E inicia imediatamente
    if sudo systemctl enable --now docker.service 2>>"$LOG_FILE"; then
        log "docker.service habilitado e iniciado."
    else
        erro "Falha ao habilitar docker.service."
        modulo_ok=false
    fi

    subtitulo "Adicionando $USER ao grupo 'docker'"
    # Sem isso, `docker run` exige sudo. O grupo permite acesso ao socket Unix.
    # AVISO: O novo grupo só tem efeito após logout/login (ou `newgrp docker`)
    if getent group docker &>/dev/null; then
        if sudo usermod -aG docker "$USER" 2>>"$LOG_FILE"; then
            log "Usuário '$USER' adicionado ao grupo 'docker'."
            warn "Faça logout/login (ou execute: newgrp docker) para ativar."
        else
            erro "Falha ao adicionar $USER ao grupo docker."
            modulo_ok=false
        fi
    else
        erro "Grupo 'docker' não existe. Verifique a instalação do Docker."
        modulo_ok=false
    fi

    $modulo_ok && _registrar_resultado "Docker" 0 || _registrar_resultado "Docker" 1
}

# ──────────────────────────────────────────────────────────────────────────────
# MÓDULO 6: POSTGRESQL + METASPLOIT
# O Metasploit usa PostgreSQL como backend para armazenar dados de sessões,
# hosts e vulnerabilidades encontradas. Sem o PostgreSQL configurado,
# o Metasploit funciona mas sem persistência de dados.
#
# Diferença em relação ao Arch: no Ubuntu/Pop!_OS o pacote 'postgresql' já
# cria e inicializa o cluster automaticamente via 'pg_createcluster', então
# não é necessário rodar 'initdb' manualmente.
# ──────────────────────────────────────────────────────────────────────────────
configure_services() {
    titulo "Módulo 6: PostgreSQL + Metasploit"

    subtitulo "Instalando PostgreSQL"
    local modulo_ok=true

    for pkg in "${PKGS_SEGURANCA[@]}"; do
        if apt_install "$pkg"; then
            log "  $pkg"
        else
            erro "  Falha ao instalar: $pkg"
            modulo_ok=false
        fi
    done

    subtitulo "Habilitando serviço PostgreSQL"
    # No Ubuntu/Pop!_OS o cluster já é criado e inicializado pelo próprio
    # pacote (via pg_createcluster), diferente do Arch que exige initdb manual.
    if sudo systemctl enable --now postgresql.service 2>>"$LOG_FILE"; then
        log "postgresql.service habilitado e iniciado."
    else
        erro "Falha ao habilitar postgresql.service."
        modulo_ok=false
    fi

    subtitulo "Instalando Metasploit Framework (instalador oficial Rapid7)"
    # Metasploit não está nos repos do Ubuntu/Pop!_OS — usamos o instalador
    # oficial da Rapid7, que baixa e instala um pacote .deb com tudo incluso.
    if cmd_existe msfconsole; then
        info "Metasploit já instalado."
    else
        local tmp_installer
        tmp_installer=$(mktemp)
        if curl -fsSL https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb \
            -o "$tmp_installer" 2>>"$LOG_FILE"; then
            chmod 755 "$tmp_installer"
            if sudo "$tmp_installer" 2>>"$LOG_FILE"; then
                log "Metasploit Framework instalado com sucesso."
            else
                erro "Falha ao executar o instalador do Metasploit."
                modulo_ok=false
            fi
        else
            erro "Falha ao baixar o instalador do Metasploit."
            modulo_ok=false
        fi
        rm -f "$tmp_installer"
    fi

    subtitulo "Inicializando banco de dados do Metasploit (msfdb)"
    # msfdb init: cria usuário PostgreSQL 'msf' e banco 'msf',
    # e configura o database.yml do Metasploit para apontar para ele.
    if cmd_existe msfdb; then
        if sudo msfdb init 2>>"$LOG_FILE"; then
            log "msfdb inicializado com sucesso."
        else
            warn "msfdb init retornou erro. Pode já estar inicializado."
        fi
    else
        warn "msfdb não encontrado. Metasploit pode não estar instalado corretamente."
        modulo_ok=false
    fi

    $modulo_ok && _registrar_resultado "PostgreSQL + Metasploit" 0 || _registrar_resultado "PostgreSQL + Metasploit" 1
}

# ──────────────────────────────────────────────────────────────────────────────
# MÓDULO 7: NERD FONTS (MesloLGS NF)
# Necessária para renderizar ícones no Powerlevel10k, LunarVim e eza.
# ──────────────────────────────────────────────────────────────────────────────
instalar_fontes() {
    titulo "Módulo 7: Nerd Fonts — MesloLGS NF"

    mkdir -p "$FONT_DIR"

    local BASE_URL="https://github.com/romkatv/powerlevel10k-media/raw/master"
    # Os nomes dos arquivos têm espaços — usamos URL encoding (%20)
    local -a FONTS=(
        "MesloLGS%20NF%20Regular.ttf"
        "MesloLGS%20NF%20Bold.ttf"
        "MesloLGS%20NF%20Italic.ttf"
        "MesloLGS%20NF%20Bold%20Italic.ttf"
    )

    local modulo_ok=true
    for fonte_encoded in "${FONTS[@]}"; do
        # Decodifica o nome para uso no sistema de arquivos local
        local nome_arquivo
        nome_arquivo=$(echo "$fonte_encoded" | sed 's/%20/ /g')

        if [[ -f "$FONT_DIR/$nome_arquivo" ]]; then
            info "  Já existe: $nome_arquivo"
            continue
        fi

        info "  Baixando: $nome_arquivo"
        if wget -q -O "$FONT_DIR/$nome_arquivo" "$BASE_URL/$fonte_encoded" 2>>"$LOG_FILE"; then
            log "  $nome_arquivo"
        else
            erro "  Falha ao baixar: $nome_arquivo"
            modulo_ok=false
        fi
    done

    # Reconstrói o cache de fontes do sistema para que as novas fontes sejam reconhecidas
    info "Atualizando cache de fontes (fc-cache)..."
    fc-cache -fv &>>"$LOG_FILE"
    log "Cache de fontes atualizado."

    $modulo_ok && _registrar_resultado "Nerd Fonts" 0 || _registrar_resultado "Nerd Fonts" 1
}

# ──────────────────────────────────────────────────────────────────────────────
# MÓDULO 8: ZSH — PLUGINS E POWERLEVEL10K
# ──────────────────────────────────────────────────────────────────────────────
instalar_plugins_zsh() {
    titulo "Módulo 8: Plugins Zsh + Powerlevel10k"

    mkdir -p "$PLUGIN_DIR"

    # Declaração associativa: nome → URL do repositório
    declare -A PLUGINS=(
        ["zsh-autosuggestions"]="https://github.com/zsh-users/zsh-autosuggestions"
        ["zsh-syntax-highlighting"]="https://github.com/zsh-users/zsh-syntax-highlighting"
        ["zsh-completions"]="https://github.com/zsh-users/zsh-completions"
        ["zsh-history-substring-search"]="https://github.com/zsh-users/zsh-history-substring-search"
        ["gitstatus"]="https://github.com/romkatv/gitstatus.git"
        ["powerlevel10k"]="https://github.com/romkatv/powerlevel10k.git"
    )

    local modulo_ok=true
    for nome in "${!PLUGINS[@]}"; do
        local url="${PLUGINS[$nome]}"
        local dest="$PLUGIN_DIR/$nome"

        if [[ -d "$dest" ]]; then
            info "  Atualizando: $nome"
            if git -C "$dest" pull --quiet 2>>"$LOG_FILE"; then
                log "  $nome (atualizado)"
            else
                warn "  Falha ao atualizar $nome. Usando versão atual."
            fi
        else
            info "  Clonando: $nome"
            # --depth=1: clone raso — só o último commit (mais rápido, menos espaço)
            if git clone --depth=1 "$url" "$dest" 2>>"$LOG_FILE"; then
                log "  $nome"
            else
                erro "  Falha ao clonar: $nome"
                modulo_ok=false
            fi
        fi
    done

    $modulo_ok && _registrar_resultado "Plugins Zsh" 0 || _registrar_resultado "Plugins Zsh" 1
}

# ──────────────────────────────────────────────────────────────────────────────
# MÓDULO 9: CONFIGURAÇÃO DO .ZSHRC
# Gera um .zshrc funcional que carrega todos os plugins instalados.
# Se já existir um .zshrc, faz backup antes de modificar.
# ──────────────────────────────────────────────────────────────────────────────
configurar_zshrc() {
    titulo "Módulo 9: Configuração do .zshrc"

    local ZSHRC="$HOME/.zshrc"

    # Backup se existir
    if [[ -f "$ZSHRC" ]]; then
        local backup="${ZSHRC}.bak.$(date +%Y%m%d_%H%M%S)"
        cp "$ZSHRC" "$backup"
        info "Backup do .zshrc existente criado em: $backup"
    fi

    info "Gerando .zshrc..."

    cat > "$ZSHRC" << 'ZSHRC_EOF'
# ==============================================================================
# .zshrc — Gerado por dev-setup-popos.sh
# ==============================================================================

# ── Powerlevel10k: instant prompt (deve ser o PRIMEIRO bloco do .zshrc)
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
    source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# ── Diretório de plugins
PLUGIN_DIR="$HOME/.zsh/plugins"

# ── Powerlevel10k (tema)
source "$PLUGIN_DIR/powerlevel10k/powerlevel10k.zsh-theme"

# ── Completions (deve ser carregado antes de compinit)
fpath+=("$PLUGIN_DIR/zsh-completions/src")
autoload -Uz compinit && compinit

# ── Plugins de UX
source "$PLUGIN_DIR/zsh-autosuggestions/zsh-autosuggestions.zsh"
source "$PLUGIN_DIR/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
source "$PLUGIN_DIR/zsh-history-substring-search/zsh-history-substring-search.zsh"

# ── Keybindings para history-substring-search (setas ↑↓)
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down

# ── Configurações do histórico
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt SHARE_HISTORY          # Compartilha histórico entre terminais
setopt HIST_IGNORE_DUPS       # Não salva duplicatas consecutivas
setopt HIST_IGNORE_SPACE      # Não salva comandos que começam com espaço

# ── PATH — Rust, uv, pyenv, binários locais (bat/fd apontam para cá)
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

# ── Rust: carrega o ambiente se rustup estiver instalado
[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

# ── pyenv
if [[ -d "$HOME/.pyenv" ]]; then
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init --path)"
    eval "$(pyenv init -)"
fi

# ── zoxide (substituto inteligente do cd)
command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"

# ── fzf
[[ -f /usr/share/doc/fzf/examples/key-bindings.zsh ]] && source /usr/share/doc/fzf/examples/key-bindings.zsh
[[ -f /usr/share/doc/fzf/examples/completion.zsh ]]    && source /usr/share/doc/fzf/examples/completion.zsh

# ── Compatibilidade de nomes (Debian/Ubuntu renomeiam alguns binários)
command -v batcat &>/dev/null && ! command -v bat &>/dev/null && alias bat='batcat'
command -v fdfind &>/dev/null && ! command -v fd &>/dev/null && alias fd='fdfind'

# ── Aliases úteis
command -v eza &>/dev/null && alias ls='eza --icons' || alias ls='ls --color=auto'
command -v eza &>/dev/null && alias ll='eza -lh --icons --git'
command -v eza &>/dev/null && alias la='eza -lha --icons --git'
alias cat='bat --style=plain'
alias grep='rg'
alias find='fd'
alias vim='nvim'
alias vi='nvim'

# ── Powerlevel10k: configuração pessoal (gerada por `p10k configure`)
[[ -f "$HOME/.p10k.zsh" ]] && source "$HOME/.p10k.zsh"

ZSHRC_EOF

    log ".zshrc gerado em $ZSHRC"
    _registrar_resultado "Configuração Zsh" 0
}

# ──────────────────────────────────────────────────────────────────────────────
# MÓDULO 10: ZSH COMO SHELL PADRÃO
# ──────────────────────────────────────────────────────────────────────────────
definir_zsh_padrao() {
    titulo "Módulo 10: Shell Padrão"

    local ZSH_PATH
    ZSH_PATH=$(command -v zsh)

    if [[ -z "$ZSH_PATH" ]]; then
        erro "zsh não encontrado. Instale primeiro (Módulo 1)."
        _registrar_resultado "Shell Padrão" 1
        return
    fi

    # Adiciona zsh à lista de shells válidos do sistema se ainda não estiver
    if ! grep -qF "$ZSH_PATH" /etc/shells; then
        echo "$ZSH_PATH" | sudo tee -a /etc/shells > /dev/null
        log "Adicionado $ZSH_PATH a /etc/shells"
    fi

    if [[ "$SHELL" != "$ZSH_PATH" ]]; then
        chsh -s "$ZSH_PATH"
        log "Shell padrão alterado para: $ZSH_PATH"
        warn "Faça logout/login para que o novo shell entre em vigor."
        _registrar_resultado "Shell Padrão" 0
    else
        info "Zsh já é o shell padrão ($SHELL). Nenhuma alteração necessária."
        _registrar_resultado "Shell Padrão" 0
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# RELATÓRIO FINAL
# Consolida o status de todos os módulos e orienta os próximos passos
# ──────────────────────────────────────────────────────────────────────────────
relatorio_final() {
    echo ""
    echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}  ► Relatório Final — dev-setup-popos.sh ${SCRIPT_VERSION}${NC}"
    echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════${NC}"
    echo ""

    if [[ ${#MODULOS_OK[@]} -gt 0 ]]; then
        echo -e "${GREEN}  Módulos concluídos com sucesso:${NC}"
        for m in "${MODULOS_OK[@]}"; do
            echo -e "    ${GREEN}✔${NC} $m"
        done
    fi

    echo ""

    if [[ ${#MODULOS_FALHOS[@]} -gt 0 ]]; then
        echo -e "${RED}  Módulos com falhas:${NC}"
        for m in "${MODULOS_FALHOS[@]}"; do
            echo -e "    ${RED}✘${NC} $m"
        done
        echo ""
        echo -e "  ${DIM}Detalhes em: ${BOLD}$LOG_FILE${NC}"
    fi

    echo ""
    echo -e "${YELLOW}  Próximos passos obrigatórios:${NC}"
    echo    "  1. Faça logout e login (grupos docker/novos PATHs exigem nova sessão)"
    echo    "  2. Configure o tema Powerlevel10k:  ${BOLD}p10k configure${NC}"
    echo    "  3. Configure a fonte do emulador para: ${BOLD}MesloLGS NF${NC}"
    echo    "  4. Valide o Docker:                 ${BOLD}docker run hello-world${NC}"
    echo    "  5. Valide o Metasploit:             ${BOLD}msfconsole -x 'db_status; exit'${NC}"
    echo    "  6. Inicie o LunarVim:               ${BOLD}lvim${NC}"
    echo ""
    echo -e "  ${DIM}Log completo: $LOG_FILE${NC}"

    if [[ "$FALHAS" -gt 0 ]]; then
        echo ""
        echo -e "${RED}  ${BOLD}$FALHAS módulo(s) com falhas.${NC} Revise o log antes de prosseguir."
        echo ""
        return 1
    else
        echo ""
        echo -e "${GREEN}  ${BOLD}Setup concluído sem falhas. Ambiente pronto!${NC}"
        echo ""
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# MAIN — Ponto de entrada
# Ordem de execução é importante: base antes de ferramentas que dependem dela
# ──────────────────────────────────────────────────────────────────────────────
main() {
    # Inicializa o arquivo de log com cabeçalho
    {
        echo "======================================================"
        echo "  dev-setup-popos.sh v${SCRIPT_VERSION}"
        echo "  Iniciado em: $(date)"
        echo "  Usuário: $USER | Sistema: $(uname -srm)"
        echo "======================================================"
    } > "$LOG_FILE"

    echo ""
    echo -e "${BOLD}${MAGENTA}"
    echo "  ██████╗  ██████╗ ██████╗ ██╗    ██████╗ ███████╗"
    echo "  ██╔══██╗██╔═══██╗██╔══██╗██║   ██╔═══██╗██╔════╝"
    echo "  ██████╔╝██║   ██║██████╔╝██║   ██║   ██║███████╗"
    echo "  ██╔═══╝ ██║   ██║██╔═══╝ ██║   ██║   ██║╚════██║"
    echo "  ██║     ╚██████╔╝██║     ██║██╗╚██████╔╝███████║"
    echo "  ╚═╝      ╚═════╝ ╚═╝     ╚═╝╚═╝ ╚═════╝ ╚══════╝"
    echo -e "${NC}"
    echo -e "  ${DIM}Pop!_OS / Ubuntu — Platform Engineering v${SCRIPT_VERSION}${NC}"
    echo -e "  ${DIM}Log: $LOG_FILE${NC}"
    echo ""

    verificar_sistema      # Pré-requisitos — falha fatal se não passar
    install_sys_deps       # apt: ferramentas base
    install_fastfetch_eza  # fastfetch/eza: repositórios próprios quando necessário
    install_vscode         # Microsoft repo: VS Code
    setup_rust             # rustup: toolchain Rust
    setup_python_tools     # uv + pyenv: ferramentas Python isoladas
    instalar_lunarvim      # LunarVim
    setup_docker           # Docker (repo oficial) + systemd + grupo
    configure_services     # PostgreSQL + Metasploit
    instalar_fontes        # MesloLGS NF para Powerlevel10k
    instalar_plugins_zsh   # Plugins Zsh + Powerlevel10k
    configurar_zshrc       # Gera .zshrc funcional
    definir_zsh_padrao     # chsh para Zsh

    relatorio_final
}

main "$@"

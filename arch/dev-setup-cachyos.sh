#!/usr/bin/env bash
# ==============================================================================
# dev-setup-cachyos.sh — Ambiente de Desenvolvimento para CachyOS / Arch Linux
# ==============================================================================
# Versão: 1.0.0
# Autor:  Platform Engineering
#
# DESCRIÇÃO:
#   Script modular que automatiza a instalação e configuração de um ambiente
#   de desenvolvimento completo no CachyOS (e qualquer Arch Linux com yay).
#
# ESTRATÉGIA DE GESTÃO DE PACOTES:
#   • pacman  → ferramentas de sistema, compiladores, libs nativas
#   • yay     → pacotes exclusivos do AUR (ex: visual-studio-code-bin)
#   • uv      → TODAS as ferramentas Python (conformidade PEP 668)
#   • rustup  → toolchain Rust (via installer oficial, não pacman)
#
# USO:
#   chmod +x dev-setup-cachyos.sh
#   ./dev-setup-cachyos.sh
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

# Executa um pacman install de forma idempotente (--needed evita reinstalação)
# Retorna o exit code para que o caller decida como lidar
pacman_install() {
    sudo pacman -S --noconfirm --needed "$@" 2>>"$LOG_FILE"
}

# Instala via yay (AUR), também idempotente
yay_install() {
    # yay não deve ser executado como root
    yay -S --noconfirm --needed "$@" 2>>"$LOG_FILE"
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

    # Impede execução como root — muitas ferramentas (yay, rustup) quebram com root
    if [[ "$EUID" -eq 0 ]]; then
        erro "Não execute este script como root. Use seu usuário normal."
        exit 1
    fi

    # Verifica que estamos num sistema baseado em Arch
    if ! cmd_existe pacman; then
        erro "pacman não encontrado. Este script é exclusivo para Arch Linux / CachyOS."
        exit 1
    fi

    # Verifica conectividade básica com um ping no servidor do Arch
    if ! ping -c 1 -W 3 archlinux.org &>/dev/null; then
        warn "Sem conectividade com archlinux.org. Verifique sua rede."
        warn "Continuando mesmo assim (repositórios locais podem funcionar)..."
    fi

    log "Sistema: $(uname -srm)"
    log "Usuário: $USER (UID: $EUID)"
    log "Log gravado em: ${BOLD}$LOG_FILE${NC}"

    # Atualiza a base de dados do pacman antes de qualquer instalação
    info "Sincronizando base de dados do pacman..."
    sudo pacman -Sy --noconfirm 2>>"$LOG_FILE" || warn "Falha ao sincronizar pacman. Prosseguindo..."
}

# ──────────────────────────────────────────────────────────────────────────────
# MÓDULO 1: DEPENDÊNCIAS DO SISTEMA (via pacman)
# Apenas ferramentas disponíveis nos repositórios oficiais do Arch/CachyOS
# ──────────────────────────────────────────────────────────────────────────────

# Pacotes divididos em grupos temáticos para facilitar manutenção

readonly -a PKGS_BASE=(
    git           # VCS — obrigatório para clonar plugins e repositórios
    curl          # Transferências HTTP — usado por instaladores (rustup, etc.)
    wget          # Downloader alternativo — alguns scripts preferem wget
    unzip         # Extração de .zip (fontes, binários)
    tar           # Extração de tarballs
    7z            # Extração de arquivos .7z (alguns releases usam esse formato)
    make          # Build system — necessário para compilar muitos plugins
    base-devel    # Meta-pacote: gcc, binutils, fakeroot — base para AUR e compilação
    pkg-config    # Permite ao compilador localizar libs instaladas no sistema
)

readonly -a PKGS_SHELL=(
    zsh                       # Shell principal do ambiente
    tmux                      # Multiplexador de terminal
    byobu                     # Wrapper do tmux, com teclas de atalhos mais intuitivas (opcional, mas recomendado)
    fontconfig                # Gerenciamento de fontes (necessário para fc-cache)
    fastfetch                 # Exibição de informações do sistema (substituto ao neofetch)
    fzf                       # Fuzzy finder — integrado ao Zsh e Tmux
    ripgrep                   # Busca de texto ultrarrápida (substituto ao grep)
    fd                        # Localizador de arquivos moderno (substituto ao find)
    ranger                    # Gerenciador de arquivos TUI
    tldr                      # Resumos práticos de comandos man
    zoxide                    # Navegação inteligente de diretórios (substituto ao cd)
    bat                       # Cat com syntax highlighting
    eza                       # ls moderno com ícones e cores
    etckeeper                 # Versionamento do /etc (útil para sysadmins e devops)
    figlet                    # Gerador de texto ASCII (usado para banners divertidos no terminal
    lolcat                    # Exibe texto com cores aleatórias (divertido para banners e mensagens de erro)

)

readonly -a PKGS_DEV=(
    luarocks      # Gerenciador de pacotes Lua (necessário para plugins Neovim)
    cmake         # Build system multiplataforma (dependência de muitas libs C/C++)
    neovim        # Editor de texto/IDE modal — base para LunarVim
    # gcc e binutils já vêm no base-devel
)

readonly -a PKGS_RUST_DEPS=(
    # rustc e cargo NÃO são instalados via pacman aqui —
    # usamos rustup para ter controle de versão (stable/nightly/toolchains)
    # Os pacotes abaixo são dependências nativas que o ecossistema Rust precisa
    openssl       # Criptografia — muitos crates Rust dependem de openssl-sys
    libgit2       # Acesso a repositórios Git por bibliotecas Rust
)

readonly -a PKGS_DOCKER=(
    docker         # Engine do Docker (daemon + CLI)
    docker-compose # Orquestração de múltiplos contêineres via YAML
    # Nota: no Arch, docker-compose v2 também pode ser obtido como plugin
    # via 'docker compose' (sem hífen). Instalamos ambos para compatibilidade.
)

readonly -a PKGS_SEGURANCA=(
    nmap           # Scanner de rede e auditoria de portas
    wireshark-qt   # Analisador de pacotes com GUI (wireshark-cli para só TUI)
    netcat         # Ferramenta clássica de rede (ncat/nc)
    metasploit     # Framework de pentesting (disponível nos repos CachyOS/BlackArch)
    postgresql     # Banco de dados relacional — dependência do Metasploit (msfdb)
)

readonly -a PKGS_PYTHON_SYSTEM=(
    # Apenas o mínimo necessário via pacman.
    # Ferramentas Python SEMPRE via `uv tool install` (ver módulo setup_python_tools)
    python          # Interpretador Python 3 base
    python-pip      # pip — necessário para bootstrap do uv se ele não estiver instalado
    pyenv           # Gerenciador de versões Python (permite alternar entre 3.x)
)

install_sys_deps() {
    titulo "Módulo 1: Dependências do Sistema (pacman)"
    local modulo_ok=true

    # Função local para instalar um grupo e capturar falhas individualmente
    _instalar_grupo() {
        local nome_grupo="$1"
        shift
        local pacotes=("$@")

        subtitulo "Instalando: $nome_grupo"
        for pkg in "${pacotes[@]}"; do
            if pacman_install "$pkg"; then
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

    if $modulo_ok; then
        log "Dependências de sistema instaladas com sucesso."
        _registrar_resultado "Dependências do Sistema" 0
    else
        warn "Algumas dependências falharam. Verifique o log: $LOG_FILE"
        _registrar_resultado "Dependências do Sistema" 1
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# MÓDULO 2: PACOTES AUR (via yay)
# yay deve já estar instalado no CachyOS. Verificamos e instalamos se ausente.
# ──────────────────────────────────────────────────────────────────────────────

readonly -a PKGS_AUR=(
    visual-studio-code-bin   # VS Code (binário oficial Microsoft — não o open-source)
    # Adicione aqui outros pacotes AUR conforme necessário
    # Ex: google-chrome, slack-desktop, etc.
)

_instalar_yay() {
    # yay não está disponível nos repositórios oficiais — compilamos do AUR
    # Isso é um bootstrap manual: clonar → makepkg → instalar
    info "yay não encontrado. Instalando via makepkg..."
    local tmp_dir
    tmp_dir=$(mktemp -d)

    git clone --depth=1 https://aur.archlinux.org/yay.git "$tmp_dir/yay" 2>>"$LOG_FILE"
    pushd "$tmp_dir/yay" > /dev/null
    # makepkg -si: build + instalação de dependências + install silencioso
    makepkg -si --noconfirm 2>>"$LOG_FILE"
    popd > /dev/null
    rm -rf "$tmp_dir"

    if cmd_existe yay; then
        log "yay instalado com sucesso."
    else
        erro "Falha ao instalar yay."
        return 1
    fi
}

install_aur_packages() {
    titulo "Módulo 2: Pacotes AUR (yay)"

    # Garante que yay está disponível antes de prosseguir
    if ! cmd_existe yay; then
        _instalar_yay || { _registrar_resultado "Pacotes AUR" 1; return; }
    else
        info "yay já instalado: $(yay --version | head -1)"
    fi

    local modulo_ok=true
    subtitulo "Instalando pacotes do AUR"

    for pkg in "${PKGS_AUR[@]}"; do
        if yay_install "$pkg"; then
            log "  $pkg (AUR)"
        else
            erro "  Falha ao instalar AUR: $pkg"
            modulo_ok=false
        fi
    done

    $modulo_ok && _registrar_resultado "Pacotes AUR" 0 || _registrar_resultado "Pacotes AUR" 1
}

# ──────────────────────────────────────────────────────────────────────────────
# MÓDULO 3: RUST (via rustup)
# Usamos rustup em vez do pacman para controle granular de toolchains.
# O pacman instala uma versão estática; rustup permite `rustup update`,
# múltiplas toolchains (stable, nightly, MSVC cross-compile), e targets.
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
# PEP 668 proíbe pip install --global em distros modernas.
# `uv tool install` cria ambientes isolados por ferramenta, evitando conflitos
# e sem precisar de `--break-system-packages`.
# ──────────────────────────────────────────────────────────────────────────────

readonly -a PYTHON_TOOLS=(
    ipython   # Shell interativo avançado para Python (REPL com autocompletar)
    ruff      # Linter e formatter Python ultrarrápido (escrito em Rust)
    black     # Formatter Python — padrão de mercado
    mypy      # Type checker estático para Python
    httpie    # Cliente HTTP para terminal — alternativa amigável ao curl
    poetry    # Gerenciador de dependências e build para projetos Python
)

_instalar_uv() {
    info "Instalando uv (gerenciador de pacotes Python da Astral)..."
    # O installer oficial do uv é o método recomendado — não via pip
    if curl -LsSf https://astral.sh/uv/install.sh | sh 2>>"$LOG_FILE"; then
        # O installer do uv adiciona ~/.cargo/bin ou ~/.local/bin ao PATH
        # Forçamos a atualização do PATH na sessão atual
        export PATH="$HOME/.local/bin:$PATH"
        log "uv instalado: $(uv --version)"
    else
        erro "Falha ao instalar uv."
        return 1
    fi
}

setup_python_tools() {
    titulo "Módulo 4: Ferramentas Python (uv)"

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
# MÓDULO 5: DOCKER
# Instalação + habilitação do serviço + adição do usuário ao grupo docker.
# Sem o grupo docker, o usuário precisa de sudo para cada comando docker.
# ──────────────────────────────────────────────────────────────────────────────
setup_docker() {
    titulo "Módulo 5: Docker"

    subtitulo "Instalando pacotes Docker"
    local modulo_ok=true

    for pkg in "${PKGS_DOCKER[@]}"; do
        if pacman_install "$pkg"; then
            log "  $pkg"
        else
            erro "  Falha ao instalar: $pkg"
            modulo_ok=false
        fi
    done

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
# ──────────────────────────────────────────────────────────────────────────────
configure_services() {
    titulo "Módulo 6: PostgreSQL + Metasploit"

    subtitulo "Instalando PostgreSQL e Metasploit"
    local modulo_ok=true

    for pkg in "${PKGS_SEGURANCA[@]}"; do
        if pacman_install "$pkg"; then
            log "  $pkg"
        else
            erro "  Falha ao instalar: $pkg"
            modulo_ok=false
        fi
    done

    subtitulo "Inicializando cluster PostgreSQL"
    # initdb cria o diretório de dados do PostgreSQL.
    # No Arch, o diretório padrão é /var/lib/postgres/data.
    # Se já existe, initdb falha — por isso verificamos antes.
    local PG_DATA="/var/lib/postgres/data"
    if [[ ! -d "$PG_DATA/global" ]]; then
        info "Inicializando banco de dados PostgreSQL em $PG_DATA..."
        # No Arch, initdb é executado como o usuário 'postgres'
        if sudo -u postgres initdb --locale=C.UTF-8 -D "$PG_DATA" 2>>"$LOG_FILE"; then
            log "PostgreSQL inicializado com sucesso."
        else
            erro "Falha ao inicializar PostgreSQL (initdb)."
            modulo_ok=false
        fi
    else
        info "PostgreSQL já inicializado. Pulando initdb."
    fi

    subtitulo "Habilitando serviço PostgreSQL"
    if sudo systemctl enable --now postgresql.service 2>>"$LOG_FILE"; then
        log "postgresql.service habilitado e iniciado."
    else
        erro "Falha ao habilitar postgresql.service."
        modulo_ok=false
    fi

    subtitulo "Inicializando banco de dados do Metasploit (msfdb)"
    # msfdb init: cria usuário PostgreSQL 'msf' e banco 'msf',
    # e configura o database.yml do Metasploit para apontar para ele.
    if cmd_existe msfdb; then
        if msfdb init 2>>"$LOG_FILE"; then
            log "msfdb inicializado com sucesso."
        else
            warn "msfdb init retornou erro. Pode já estar inicializado."
        fi
    else
        warn "msfdb não encontrado. Metasploit pode não estar instalado corretamente."
        warn "Tente instalar manualmente: yay -S metasploit"
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
# .zshrc — Gerado por dev-setup-cachyos.sh
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

# ── PATH — Rust, uv, pipx, pyenv
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

# ── Rust: carrega o ambiente se rustup estiver instalado
[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

# ── pyenv
if command -v pyenv &>/dev/null; then
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init --path)"
    eval "$(pyenv init -)"
fi

# ── zoxide (substituto inteligente do cd)
command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"

# ── fzf
[[ -f /usr/share/fzf/key-bindings.zsh ]]  && source /usr/share/fzf/key-bindings.zsh
[[ -f /usr/share/fzf/completion.zsh ]]    && source /usr/share/fzf/completion.zsh

# ── Aliases úteis
alias ls='eza --icons'
alias ll='eza -lh --icons --git'
alias la='eza -lha --icons --git'
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
    echo -e "${BOLD}${BLUE}  ► Relatório Final — dev-setup-cachyos.sh ${SCRIPT_VERSION}${NC}"
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
        echo "  dev-setup-cachyos.sh v${SCRIPT_VERSION}"
        echo "  Iniciado em: $(date)"
        echo "  Usuário: $USER | Sistema: $(uname -srm)"
        echo "======================================================"
    } > "$LOG_FILE"

    echo ""
    echo -e "${BOLD}${MAGENTA}"
    echo "  ██████╗ ███████╗██╗   ██╗    ███████╗███████╗████████╗██╗   ██╗██████╗ "
    echo "  ██╔══██╗██╔════╝██║   ██║    ██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗"
    echo "  ██║  ██║█████╗  ██║   ██║    ███████╗█████╗     ██║   ██║   ██║██████╔╝"
    echo "  ██║  ██║██╔══╝  ╚██╗ ██╔╝    ╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝ "
    echo "  ██████╔╝███████╗ ╚████╔╝     ███████║███████╗   ██║   ╚██████╔╝██║     "
    echo "  ╚═════╝ ╚══════╝  ╚═══╝      ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝     "
    echo -e "${NC}"
    echo -e "  ${DIM}CachyOS / Arch Linux — Platform Engineering v${SCRIPT_VERSION}${NC}"
    echo -e "  ${DIM}Log: $LOG_FILE${NC}"
    echo ""

    verificar_sistema      # Pré-requisitos — falha fatal se não passar
    install_sys_deps       # pacman: ferramentas base
    install_aur_packages   # yay: VS Code e outros pacotes AUR
    setup_rust             # rustup: toolchain Rust
    setup_python_tools     # uv: ferramentas Python isoladas
    instalar_lunarvim      # LunarVim
    setup_docker           # Docker + systemd + grupo
    configure_services     # PostgreSQL + Metasploit
    instalar_fontes        # MesloLGS NF para Powerlevel10k
    instalar_plugins_zsh   # Plugins Zsh + Powerlevel10k
    configurar_zshrc       # Gera .zshrc funcional
    definir_zsh_padrao     # chsh para Zsh

    relatorio_final
}

main "$@"

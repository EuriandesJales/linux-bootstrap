#!/bin/bash

# ==============================================================================
#  PÓS-INSTALAÇÃO — Pop!_OS / Ubuntu
#  Autor: Euriandes jales
#  Adaptado de: post-install.sh (CachyOS / Arch Linux)
#  Descrição: Instala e configura automaticamente o ambiente completo após
#             uma instalação limpa do Pop!_OS ou qualquer derivado Ubuntu/Debian.
#
#  EXECUÇÃO:
#    chmod +x post-install-popos.sh && ./post-install-popos.sh
#
#  ATENÇÃO: Não execute como root! O script pede sudo quando necessário.
# ==============================================================================
# versão 1.0


set -euo pipefail   # Aborta em erros, variáveis não definidas e pipes quebrados

export DEBIAN_FRONTEND=noninteractive   # Garante que o apt nunca pare para perguntar

# ── Cores para output ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # Sem cor (reset)

# ── Funções de log ─────────────────────────────────────────────────────────────
log()       { echo -e "${GREEN}[✔ INFO]${NC}  $1"; }
warn()      { echo -e "${YELLOW}[⚠ AVISO]${NC} $1"; }
erro()      { echo -e "${RED}[✘ ERRO]${NC}  $1"; exit 1; }
titulo()    { echo -e "\n${BOLD}${BLUE}══════════════════════════════════════════${NC}"; \
              echo -e "${BOLD}${BLUE}  ► $1${NC}"; \
              echo -e "${BOLD}${BLUE}══════════════════════════════════════════${NC}"; }
subtitulo() { echo -e "\n${CYAN}  ┌─ $1${NC}"; }

# ==============================================================================
#  VERIFICAÇÕES INICIAIS
# ==============================================================================

# Garante que o script não está rodando como root
[[ "$EUID" -eq 0 ]] && erro "Não execute este script como root. Use seu usuário normal (com sudo configurado)."

# Garante que estamos em um sistema com apt (Ubuntu/Pop!_OS/Debian)
command -v apt-get &>/dev/null || erro "apt-get não encontrado. Este script é exclusivo para Pop!_OS, Ubuntu e derivados."

# ==============================================================================
#  DEPENDÊNCIAS DO SISTEMA
#  Instaladas ANTES dos pacotes principais, pois outros softwares dependem delas.
#  Separadas por categoria para facilitar manutenção.
# ==============================================================================

# ── Ferramentas base de build e download ───────────────────────────────────────
# Necessárias para compilar coisas fora do apt e baixar arquivos
dependencias_base=(
    "build-essential"   # gcc, g++, make, binutils etc. — indispensável para qualquer compilação
    "git"               # Clonar repositórios e projetos
    "curl"              # Download via URL; usado por instaladores e scripts
    "wget"              # Download de arquivos grandes (AppImages, tarballs)
    "ca-certificates"   # Certificados TLS — necessário para repositórios HTTPS de terceiros
    "gnupg"             # Verificação de chaves GPG de repositórios de terceiros
    "software-properties-common"  # Fornece o comando 'add-apt-repository' (PPAs)
)

# ── Suporte a aplicações 32 bits (Wine, Steam, jogos legados) ──────────────────
# Requer a arquitetura i386 habilitada via 'dpkg --add-architecture i386'
dependencias_jogos_32bits=(
    "libc6:i386"                 # Biblioteca C GNU em 32 bits — base para qualquer binário 32-bit
    "libgcc-s1:i386"              # Biblioteca de runtime GCC 32 bits — requerido por Wine e Steam
    "libpulse0:i386"             # Servidor de áudio PulseAudio 32 bits — som para Wine/jogos antigos
    "libopenal1:i386"            # OpenAL 32 bits — áudio 3D para jogos mais antigos via Wine
    "libvulkan1:i386"            # Loader Vulkan 32 bits — necessário para DXVK (DirectX via Proton/Wine)
)

# ── Suporte a execução de AppImages ───────────────────────────────────────────
# AppImages mais antigos usam FUSE2; modernos usam FUSE3
dependencias_appimage=(
    "libfuse2"    # FUSE versão 2 — exigido por AppImages empacotados com versões antigas do runtime
    "fuse3"       # FUSE versão 3 — exigido por AppImages mais recentes
)

# ── Módulos de kernel para VirtualBox ─────────────────────────────────────────
# Necessário para compilar os módulos do VirtualBox (vboxdrv) via DKMS
dependencias_virtualbox=(
    "linux-headers-generic"   # Headers do kernel genérico do Ubuntu/Pop!_OS
    "dkms"                     # Dynamic Kernel Module Support — recompila módulos a cada kernel novo
)

# ==============================================================================
#  PACOTES APT — Repositórios Oficiais (Ubuntu / Pop!_OS)
#  Critério de escolha: disponível nos repos oficiais = mais seguro, integração
#  melhor com apt upgrade, sem necessidade de compilação local.
# ==============================================================================

pacotes_apt=(
    # ── Ferramentas de desenvolvimento ──────────────────────────────────────
    "python3"            # Python 3
    "python3-pip"        # Gerenciador de pacotes pip para Python
    "python3-venv"       # Ambientes virtuais Python (dependência de uv/pyenv/poetry)
    #"uv"                # Instalado via installer oficial (ver instalando_uv_tools)

    # ── Shell e terminal ─────────────────────────────────────────────────────
    "zsh"               # Shell avançado com autocomplete, temas (Oh My Zsh etc.)
    "tmux"              # Multiplexador de terminal: múltiplas sessões em uma janela
    "micro"             # Editor de texto no terminal com atalhos familiares (Ctrl+S, Ctrl+C...)

    # ── Utilitários do sistema ────────────────────────────────────────────────
    "flatpak"           # Suporte a pacotes Flatpak (já vem pré-instalado no Pop!_OS, mas garantimos)

    # ── Multimídia ───────────────────────────────────────────────────────────
    "vlc"               # Player de vídeo/áudio completo, suporta quase qualquer formato

    # ── Jogos ────────────────────────────────────────────────────────────────
    "steam-installer"   # Plataforma de jogos da Valve (requer i386 e libs 32 bits acima)
    "wine"              # Camada de compatibilidade para rodar executáveis Windows no Linux
    "winetricks"        # Ferramenta auxiliar para instalar DLLs/runtime Windows no Wine (vcredist, dotnet...)

    # ── Virtualização ────────────────────────────────────────────────────────
    "virtualbox"        # Hipervisor para rodar VMs (Windows, outros Linux etc.)
    "virtualbox-dkms"   # Módulos de kernel do VirtualBox recompilados via DKMS a cada kernel
)

# ==============================================================================
#  PACOTES VIA REPOSITÓRIOS PRÓPRIOS / PPA
#  Critério de escolha: não disponível nos repos oficiais do Ubuntu/Pop!_OS,
#  ou versão desatualizada. Equivalente ao papel do AUR na versão CachyOS.
# ==============================================================================

# fastfetch: normalmente ausente (ou muito antigo) nos repos do Ubuntu/Pop!_OS.
# Baixamos o .deb oficial publicado pelo próprio projeto no GitHub.
# appimagelauncher: distribuído via PPA oficial da equipe do projeto.
readonly APPIMAGELAUNCHER_PPA="ppa:appimagelauncher-team/stable"

# ==============================================================================
#  PACOTES FLATPAK — Flathub
#  Critério de escolha: apps proprietários complexos, apps que o desenvolvedor
#  distribui oficialmente pelo Flathub, ou que se beneficiam do sandbox.
#  Heroic Games Launcher entrou aqui (era pacote AUR '-bin' na versão CachyOS).
#  IDs verificados no Flathub em abril/2026.
# ==============================================================================

pacotes_flatpak=(
    # ── Navegação ────────────────────────────────────────────────────────────
    "com.google.Chrome"             # Google Chrome — navegador proprietário da Google

    # ── Comunicação ──────────────────────────────────────────────────────────
    "org.telegram.desktop"          # Telegram Desktop — mensageiro multiplataforma
    "com.discordapp.Discord"        # Discord — comunicação por voz, texto e vídeo para gamers

    # ── Multimídia / Streaming ────────────────────────────────────────────────
    "com.spotify.Client"            # Spotify — streaming de música (pacote da comunidade no Flathub)

    # ── Desenvolvimento ───────────────────────────────────────────────────────
    #"com.visualstudio.code"         # Visual Studio Code — preferimos o repo oficial da Microsoft (apt)

    # ── Jogos e compatibilidade ───────────────────────────────────────────────
    "net.lutris.Lutris"             # Lutris — gerenciador de jogos (Wine, scripts, emuladores)
    "net.davidotek.pupgui2"         # ProtonUp-Qt — instala/gerencia versões do Proton-GE e Wine-GE
    "com.heroicgameslauncher.hgl"   # Heroic Games Launcher — Epic Games, GOG e Amazon Games (era AUR no CachyOS)
    "com.github.tchx84.Flatseal"    # Gerenciamento de permissões dos flatpaks
)

# ==============================================================================
#  APPIMAGES — Downloads diretos
#  Critério de escolha: não há pacote apt/PPA/Flatpak confiável e atualizado,
#  ou o desenvolvedor distribui oficialmente apenas como AppImage.
# ==============================================================================

# Array associativo: nome_do_app → URL de download
declare -A appimages

# URL estável que redireciona para o AppImage mais recente do Hydra via GitHub API
# Formato: github.com/<owner>/<repo>/releases/latest/download/<arquivo>
appimages["hydra"]="https://github.com/hydralauncher/hydra/releases/latest/download/hydralauncher-latest.AppImage"

# Diretório onde os AppImages ficam armazenados (padrão XDG)
APPIMAGE_DIR="$HOME/.local/share/AppImages"

# ==============================================================================
#  FUNÇÕES AUXILIARES
# ==============================================================================

# ── Habilita a arquitetura i386 no apt ─────────────────────────────────────────
# Necessário para Steam, Wine e dependências 32 bits (equivalente ao [multilib])
habilitar_multilib() {
    titulo "Habilitando arquitetura i386 (equivalente ao multilib)"
    if dpkg --print-foreign-architectures | grep -q "^i386$"; then
        log "Arquitetura i386 já está habilitada. Pulando."
        return 0
    fi

    warn "Habilitando i386 via 'dpkg --add-architecture i386'..."
    sudo dpkg --add-architecture i386
    sudo apt-get update -y
    log "i386 habilitada e índices atualizados."
}

# ── Instala as dependências separadas por categoria ────────────────────────────
instalar_dependencias() {
    titulo "Instalando Dependências do Sistema"

    subtitulo "Base (build tools, git, curl, wget, gnupg)"
    sudo apt-get install -y --no-install-recommends "${dependencias_base[@]}"

    subtitulo "Jogos/Wine/Steam — bibliotecas 32 bits (requer i386)"
    sudo apt-get install -y --no-install-recommends "${dependencias_jogos_32bits[@]}"

    subtitulo "AppImage (FUSE2 e FUSE3)"
    sudo apt-get install -y --no-install-recommends "${dependencias_appimage[@]}"

    subtitulo "VirtualBox — headers de kernel e DKMS"
    sudo apt-get install -y --no-install-recommends "${dependencias_virtualbox[@]}"

    log "Todas as dependências instaladas."
}

# ── Instala pacotes dos repositórios oficiais via apt ──────────────────────────
instalar_apt() {
    titulo "Instalando Pacotes Oficiais via apt"
    sudo apt-get update -y
    sudo apt-get install -y --no-install-recommends "${pacotes_apt[@]}"
    log "Pacotes apt instalados."
}

# ── Instala o fastfetch (não costuma estar nos repos do Ubuntu/Pop!_OS) ───────
instalar_fastfetch() {
    titulo "Instalando Fastfetch"

    if command -v fastfetch &>/dev/null; then
        log "fastfetch já instalado."
        return 0
    fi

    if sudo apt-get install -y fastfetch 2>/dev/null; then
        log "fastfetch instalado via apt."
        return 0
    fi

    warn "fastfetch não disponível nos repos — baixando .deb oficial do GitHub..."
    local tmp_deb
    tmp_deb=$(mktemp --suffix=.deb)
    local url
    url=$(curl -s https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest \
        | grep -o '"browser_download_url": "[^"]*linux-amd64\.deb"' | head -1 | cut -d'"' -f4)

    if [[ -n "$url" ]] && wget -q -O "$tmp_deb" "$url" && sudo apt-get install -y "$tmp_deb"; then
        log "fastfetch instalado via .deb oficial."
    else
        warn "Não foi possível instalar o fastfetch. Pulando."
    fi
    rm -f "$tmp_deb"
}



# ── Configura o Flathub e instala os Flatpaks ─────────────────────────────────
instalar_flatpak() {
    titulo "Instalando Pacotes Flatpak (Flathub)"

    # Adiciona o repositório Flathub se ainda não estiver presente
    if ! flatpak remotes | grep -q "flathub"; then
        warn "Repositório Flathub não encontrado. Adicionando..."
        flatpak remote-add --if-not-exists flathub \
            https://dl.flathub.org/repo/flathub.flatpakrepo
        log "Flathub adicionado."
    else
        log "Flathub já configurado. Pulando."
    fi

    # Instala todos os Flatpaks da lista
    # -y responde 'sim' automaticamente
    flatpak install -y flathub "${pacotes_flatpak[@]}"
    log "Pacotes Flatpak instalados."
}

# ── Baixa e configura AppImages ───────────────────────────────────────────────
instalar_appimages() {
    titulo "Instalando AppImages"
    mkdir -p "$APPIMAGE_DIR"
    log "Diretório de AppImages: $APPIMAGE_DIR"

    # Itera sobre cada entrada do dicionário associativo
    for nome in "${!appimages[@]}"; do
        local url="${appimages[$nome]}"
        local destino="$APPIMAGE_DIR/${nome}.AppImage"

        subtitulo "Baixando: $nome"
        echo "  URL: $url"
        echo "  Destino: $destino"

        # Baixa o AppImage com barra de progresso
        if wget --show-progress -q -O "$destino" "$url"; then
            chmod +x "$destino"   # Torna executável
            log "$nome baixado com sucesso."

            # Integra ao sistema via appimagelauncher (se instalado)
            if command -v ail-cli &>/dev/null; then
                ail-cli integrate "$destino" \
                    && log "$nome integrado ao menu do sistema via appimagelauncher."
            else
                warn "appimagelauncher não encontrado. Para integrar $nome ao menu:"
                warn "  Execute o AppImage uma vez: $destino"
                warn "  O appimagelauncher fará a integração automaticamente."
            fi
        else
            warn "Falha ao baixar '$nome'. Verifique a URL ou sua conexão e tente novamente."
        fi
    done

    log "AppImages processados. Arquivos em: $APPIMAGE_DIR"
}

instalando_uv_tools(){
    titulo "Instalando uv (gerenciador de ambientes Python)"

    if ! command -v uv &>/dev/null; then
        curl -LsSf https://astral.sh/uv/install.sh | sh
    fi

    if ! command -v uv &>/dev/null; then
        # uv acabou de ser instalado em ~/.local/bin, mas ainda não está no
        # PATH desta sessão — checamos diretamente antes de desistir.
        if [[ -x "$HOME/.local/bin/uv" ]]; then
            export PATH="$HOME/.local/bin:$PATH"
        else
            log "Erro: uv não está disponível após instalação."
            return 1
        fi
    fi

    # ── Configurando path uv ──────────────────────────────────────────────

    LOCAL_BIN="$HOME/.local/bin" # variável para facilitar manutenção do path
    LINE='export PATH="$HOME/.local/bin:$PATH"' # linha a ser adicionada ao .zshrc para persistência do PATH

    # 1. Runtime (sessão atual)
    if [[ ":$PATH:" != *":$LOCAL_BIN:"* ]]; then # Verifica se o path já está presente para evitar duplicação
        export PATH="$LOCAL_BIN:$PATH" # Adiciona o diretório ao PATH para a sessão atual
        log "Path '$LOCAL_BIN' adicionado ao PATH da sessão atual."
    fi

    # 2. Persistência (zsh)
    if ! grep -qxF "$LINE" "$HOME/.zshrc" 2>/dev/null; then # Verifica se a linha já existe no .zshrc para evitar duplicação
        echo "$LINE" >> "$HOME/.zshrc" # Adiciona a linha ao final do .zshrc para persistência
        log "Path '$LOCAL_BIN' adicionado ao .zshrc para persistência."
    fi

  # Instalando ferramentas Python via uv
  uv tool install ipython # Instala o IPython, um shell interativo avançado para Python, com recursos como autocompletar, histórico de comandos e suporte a rich media. Útil para desenvolvimento e experimentação em Python.
  uv tool install tldr    # Instala o tldr, uma alternativa simplificada às páginas de manual (man), com exemplos práticos de uso.

}

# ── Configurações pós-instalação ──────────────────────────────────────────────
configuracoes_pos_install() {
    titulo "Configurações Finais"

    # Adiciona o usuário ao grupo vboxusers (necessário para VirtualBox funcionar sem root)
    if id -nG "$USER" | grep -qw vboxusers; then
        log "Usuário já está no grupo vboxusers."
    else
        sudo usermod -aG vboxusers "$USER"
        warn "Usuário adicionado ao grupo vboxusers. Faça logout e login para efetivar."
    fi

    # Carrega os módulos do VirtualBox no kernel atual (sem precisar reiniciar)
    sudo modprobe vboxdrv 2>/dev/null && log "Módulo vboxdrv carregado." \
        || warn "Não foi possível carregar vboxdrv. Reinicie o sistema."

    log "Configurações aplicadas."


# ── Configurações do Docker ──────────────────────────────────────────────

    # Instalando Docker via repositório oficial (mais atualizado que docker.io do apt)
    if ! command -v docker &>/dev/null; then
        subtitulo "Instalando Docker Engine (repositório oficial)"
        sudo install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
            | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg

        local codename
        codename=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")

        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${codename} stable" \
            | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

        sudo apt-get update -y
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        log "Docker Engine instalado."
    else
        log "Docker já instalado."
    fi

    # Criando e configurando grupo docker
    if getent group docker &>/dev/null; then
        log "Grupo 'docker' já existe."
    else
        sudo groupadd docker
        log "Grupo 'docker' criado."
    fi

    if id -nG "$USER" | grep -qw docker; then
        log "Usuário já está no grupo 'docker'."
    else
        sudo usermod -aG docker "$USER"
        log "Usuário adicionado ao grupo 'docker'. Faça logout e login para usar o Docker sem sudo."
    fi

    # Configurando daemon do Docker para iniciar com o sistema
    if systemctl is-enabled docker &>/dev/null; then
        log "Docker já está habilitado para iniciar com o sistema."
    else
        sudo systemctl enable --now docker.service
        log "Docker habilitado para iniciar com o sistema e iniciado agora."
    fi

}

# ==============================================================================
#  EXECUÇÃO PRINCIPAL
# ==============================================================================

main() {
    clear
    titulo "PÓS-INSTALAÇÃO — Pop!_OS / Ubuntu"

    # Resumo do que será instalado
    echo ""
    echo -e "  ${BOLD}Resumo da instalação:${NC}"
    echo -e "  📦 apt          → ${#pacotes_apt[@]} pacotes"
    echo -e "  🔧 dependências → $((${#dependencias_base[@]} + ${#dependencias_jogos_32bits[@]} + ${#dependencias_appimage[@]} + ${#dependencias_virtualbox[@]})) pacotes"
    echo -e "  🏗  PPA          → AppImageLauncher"
    echo -e "  📦 Flatpak      → ${#pacotes_flatpak[@]} pacotes"
    echo -e "  🖼  AppImages    → ${#appimages[@]} app(s)"
    echo ""

    # Confirmação antes de continuar
    read -rp "  Deseja iniciar a instalação? [s/N] " resposta
    echo ""
    [[ "$resposta" =~ ^[Ss]$ ]] || { echo "  Instalação cancelada."; exit 0; }

    # ── Ordem de execução ─────────────────────────────────────────────────────
    # 1. i386 primeiro (Steam e dependências 32-bit precisam dele)
    habilitar_multilib

    # 2. Dependências antes dos pacotes principais
    instalar_dependencias

    # 3. Pacotes oficiais
    instalar_apt

    # 4. Fastfetch (fora dos repos oficiais na maioria das versões)
    instalar_fastfetch

    # 5. AppImageLauncher (PPA — equivalente ao pacote AUR do CachyOS)
    #instalar_appimagelauncher

    # 6. Flatpak (requer o pacote 'flatpak' instalado no passo 3)
    instalar_flatpak

    # 7. AppImages (requer wget e FUSE, instalados anteriormente)
    instalar_appimages

    # 8. Configurações finais (grupos, módulos, Docker)
    configuracoes_pos_install

    # 9. Instalação do uv e ferramentas Python via uv
    instalando_uv_tools

    # ── Sumário final ─────────────────────────────────────────────────────────
    titulo "✅ Instalação Concluída!"
    echo ""
    echo -e "  ${GREEN}Tudo pronto! Algumas observações importantes:${NC}"
    echo ""
    echo -e "  ${YELLOW}►${NC} ${BOLD}Reinicie o sistema${NC} para garantir que todos os módulos de kernel carreguem"
    echo -e "    corretamente (VirtualBox, módulos 32-bit etc.)"
    echo ""
    echo -e "  ${YELLOW}►${NC} ${BOLD}Steam${NC}: Após o primeiro login, ative o Proton em:"
    echo -e "    Steam → Configurações → Steam Play → Habilitar para todos os títulos"
    echo ""
    echo -e "  ${YELLOW}►${NC} ${BOLD}Wine${NC}: Configure com 'winecfg' para ajustar versão do Windows e drives"
    echo ""
    echo -e "  ${YELLOW}►${NC} ${BOLD}Zsh${NC}: Para definir como shell padrão: chsh -s \$(which zsh)"
    echo ""
    echo -e "  ${YELLOW}►${NC} ${BOLD}VirtualBox${NC}: Você foi adicionado ao grupo vboxusers."
    echo -e "    Faça logout e login para que o grupo seja reconhecido."
    echo ""
    echo -e "  ${YELLOW}►${NC} ${BOLD}Docker${NC}: Você foi adicionado ao grupo docker e o serviço foi habilitado."
    echo -e "  ${YELLOW}►${NC} Ferramentas Python (IPython, tldr) estão disponíveis via 'uv tool list' e podem ser usadas com 'uv run <ferramenta>'."
}

# Chama a função principal passando todos os argumentos recebidos pelo script
main "$@"
#!/bin/bash

# ==============================================================================
#  PÓS-INSTALAÇÃO — CachyOS / Arch Linux
#  Autor: Euriandes jales
#  Descrição: Instala e configura automaticamente o ambiente completo após
#             uma instalação limpa do CachyOS ou qualquer derivado Arch.
#
#  EXECUÇÃO:
#    chmod +x pos_install.sh && ./pos_install.sh
#
#  ATENÇÃO: Não execute como root! O script pede sudo quando necessário.
# ==============================================================================
# versão 1.0


set -euo pipefail   # Aborta em erros, variáveis não definidas e pipes quebrados

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

# Garante que estamos em um sistema com pacman (Arch/derivados)
command -v pacman &>/dev/null || erro "pacman não encontrado. Este script é exclusivo para Arch Linux e derivados."

# ==============================================================================
#  DEPENDÊNCIAS DO SISTEMA
#  Instaladas ANTES dos pacotes principais, pois outros softwares dependem delas.
#  Separadas por categoria para facilitar manutenção.
# ==============================================================================

# ── Ferramentas base de build e download ───────────────────────────────────────
# Necessárias para compilar pacotes do AUR e baixar arquivos
dependencias_base=(
    "base-devel"    # gcc, make, binutils etc. — indispensável para qualquer compilação (AUR)
    "git"           # Clonar repositórios AUR e projetos; exigido pelo makepkg
    "curl"          # Download via URL; usado por instaladores e scripts
    "wget"          # Download de arquivos grandes (AppImages, tarballs)
)

# ── Suporte a aplicações 32 bits (Wine, Steam, jogos legados) ──────────────────
# Requer o repositório [multilib] habilitado no /etc/pacman.conf
dependencias_jogos_32bits=(
    "lib32-glibc"               # Biblioteca C GNU em 32 bits — base para qualquer binário 32-bit
    "lib32-gcc-libs"            # Bibliotecas de runtime GCC 32 bits — requerido por Wine e Steam
    "lib32-libpulse"            # Servidor de áudio PulseAudio 32 bits — som para Wine/jogos antigos
    "lib32-openal"              # OpenAL 32 bits — áudio 3D para jogos mais antigos via Wine
    "lib32-vulkan-icd-loader"   # Loader Vulkan 32 bits — necessário para DXVK (DirectX via Proton/Wine)
)

# ── Suporte a execução de AppImages ───────────────────────────────────────────
# AppImages mais antigos usam FUSE2; modernos usam FUSE3
dependencias_appimage=(
    "fuse2"      # FUSE versão 2 — exigido por AppImages empacotados com versões antigas do runtime
    "fuse3"         # FUSE versão 3 — exigido por AppImages mais recentes
)

# ── Módulos de kernel para VirtualBox ─────────────────────────────────────────
# IMPORTANTE: Se você usa um kernel customizado do CachyOS (ex: linux-cachyos),
# substitua "virtualbox-host-modules-arch" por "virtualbox-host-dkms"
# e certifique-se de ter o pacote "linux-cachyos-headers" instalado.
dependencias_virtualbox=(
    "linux-headers"     # Headers do kernel padrão (linux) — necessário para compilar módulos do VBox
    # "linux-cachyos-headers"  # ← Descomente se usar o kernel linux-cachyos
)

# ==============================================================================
#  PACOTES PACMAN — Repositórios Oficiais (Arch / CachyOS)
#  Critério de escolha: disponível nos repos oficiais = mais seguro, integração
#  melhor com pacman -Syu, sem necessidade de compilação local.
# ==============================================================================

pacotes_pacman=(
    # ── Ferramentas de desenvolvimento ──────────────────────────────────────
    "python"            # Python 3 (em Arch, 'python' já é Python 3; não instale 'python3' separado)
    "python-pip"        # Gerenciador de pacotes pip para Python
    #"uv"                # Gerenciador de ambientes/projetos Python moderno e ultrarrápido (Rust)
    "docker"            # Plataforma de containerização para desenvolvimento e deploy de aplicações
    "docker-compose"    # Ferramenta para definir e rodar aplicações Docker multi-container
    "docker-buildx"     # Extensão do Docker para builds avançados (multi-arch, cache, etc.)
    # ── Shell e terminal ─────────────────────────────────────────────────────
    "zsh"               # Shell avançado com autocomplete, temas (Oh My Zsh etc.)
    "tmux"              # Multiplexador de terminal: múltiplas sessões em uma janela
    "alacritty"         # Emulador de terminal acelerado por GPU, escrito em Rust
    "micro"             # Editor de texto no terminal com atalhos familiares (Ctrl+S, Ctrl+C...)

    # ── Utilitários do sistema ────────────────────────────────────────────────
    "fastfetch"         # Exibe informações do sistema de forma elegante (alternativa ao neofetch)
    "flatpak"           # Suporte a pacotes Flatpak (sandbox via bubblewrap + OSTree)

    # ── Multimídia ───────────────────────────────────────────────────────────
    "vlc"               # Player de vídeo/áudio completo, suporta quase qualquer formato

    # ── Jogos ────────────────────────────────────────────────────────────────
    "steam"             # Plataforma de jogos da Valve (requer multilib e pacotes 32 bits acima)
    "wine"              # Camada de compatibilidade para rodar executáveis Windows no Linux
    "winetricks"        # Ferramenta auxiliar para instalar DLLs/runtime Windows no Wine (vcredist, dotnet...)

    # ── Virtualização ────────────────────────────────────────────────────────
    "virtualbox"                    # Hipervisor para rodar VMs (Windows, outros Linux etc.)
    #"virtualbox-host-modules-arch"  # Módulos VirtualBox para o kernel 'linux' padrão
    "virtualbox-host-dkms"        # ← Use este se usar kernel customizado (linux-cachyos, linux-zen...)
)

# ==============================================================================
#  PACOTES AUR — Arch User Repository (via yay ou paru)
#  Critério de escolha: não disponível nos repos oficiais, ou versão do repo
#  está muito desatualizada. Pacotes AUR são compilados localmente.
# ==============================================================================

pacotes_aur=(
    # ── Launchers de jogos ───────────────────────────────────────────────────
    "heroic-games-launcher-bin"  # Launcher para Epic Games, GOG e Amazon Games com suporte a Proton
                                 # Usamos o '-bin' (binário pré-compilado), que é o suportado oficialmente
                                 # pelo projeto: https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher

    # ── Suporte a AppImage ───────────────────────────────────────────────────
    "appimagelauncher"           # Integra AppImages ao menu do sistema (ícones, associações, atualizações)
                                 # Alternativa mais estável: appimagelauncher-bin (binário, sem compilação)
)

# ==============================================================================
#  PACOTES FLATPAK — Flathub
#  Critério de escolha: apps proprietários complexos, apps que o desenvolvedor
#  distribui oficialmente pelo Flathub, ou que se beneficiam do sandbox.
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
    #"com.visualstudio.code"         # Visual Studio Code — editor de código da Microsoft (não tem integracao com o sistema.)

    # ── Jogos e compatibilidade ───────────────────────────────────────────────
    "net.lutris.Lutris"             # Lutris — gerenciador de jogos (Wine, scripts, emuladores)
    "net.davidotek.pupgui2"         # ProtonUp-Qt — instala/gerencia versões do Proton-GE e Wine-GE
    # ── Jogos e compatibilidade ───────────────────────────────────────────────
    "com.github.tchx84.Flatseal"    # Gerenciamento de permissões dos flatpack

)

# ==============================================================================
#  APPIMAGES — Downloads diretos
#  Critério de escolha: não há pacote pacman/AUR/Flatpak confiável e atualizado,
#  ou o desenvolvedor distribui oficialmente apenas como AppImage.
#
#  NOTA SOBRE O HYDRA: O projeto também oferece um pacote .pacman nativo para Arch
#  (https://github.com/hydralauncher/hydra/releases). A URL abaixo usa a API do
#  GitHub para baixar automaticamente a versão mais recente do AppImage.
#  Se preferir o .pacman, comente a entrada "hydra" e use a função
#  instalar_hydra_pacman() ao final deste arquivo.
# ==============================================================================

# Array associativo: nome_do_app → URL de download
# A URL abaixo é resolvida dinamicamente via API do GitHub (sempre pega o latest)
declare -A appimages

# URL estável que redireciona para o AppImage mais recente do Hydra via GitHub API
# Formato: github.com/<owner>/<repo>/releases/latest/download/<arquivo>
appimages["hydra"]="https://github.com/hydralauncher/hydra/releases/latest/download/hydralauncher-latest.AppImage"

# Diretório onde os AppImages ficam armazenados (padrão XDG)
APPIMAGE_DIR="$HOME/.local/share/AppImages"

# ==============================================================================
#  FUNÇÕES AUXILIARES
# ==============================================================================

# ── Habilita o repositório [multilib] no pacman ────────────────────────────────
# Necessário para Steam, Wine e dependências 32 bits
habilitar_multilib() {
    titulo "Habilitando repositório [multilib]"
    if grep -q "^\[multilib\]" /etc/pacman.conf; then
        log "Repositório [multilib] já está habilitado. Pulando."
        return 0
    fi

    warn "Habilitando [multilib] no /etc/pacman.conf..."
    # Remove o '#' das linhas [multilib] e Include correspondente
    sudo sed -i '/^#\[multilib\]/{
        s/^#//          # descomenta [multilib]
        n               # avança para a próxima linha
        s/^#//          # descomenta o Include
    }' /etc/pacman.conf

    sudo pacman -Sy --noconfirm
    log "Multilib habilitado e índices atualizados."
}

# ── Instala as dependências separadas por categoria ────────────────────────────
instalar_dependencias() {
    titulo "Instalando Dependências do Sistema"

    subtitulo "Base (build tools, git, curl, wget)"
    sudo pacman -S --needed --noconfirm "${dependencias_base[@]}"

    subtitulo "Jogos/Wine/Steam — bibliotecas 32 bits (requer multilib)"
    sudo pacman -S --needed --noconfirm "${dependencias_jogos_32bits[@]}"

    subtitulo "AppImage (FUSE2 e FUSE3)"
    sudo pacman -S --needed --noconfirm "${dependencias_appimage[@]}"

    subtitulo "VirtualBox — headers de kernel"
    sudo pacman -S --needed --noconfirm "${dependencias_virtualbox[@]}"

    log "Todas as dependências instaladas."
}

# ── Instala pacotes dos repositórios oficiais via pacman ───────────────────────
# --needed evita reinstalar pacotes já em dia
instalar_pacman() {
    titulo "Instalando Pacotes Oficiais via pacman"
    sudo pacman -S --needed --noconfirm "${pacotes_pacman[@]}"
    log "Pacotes pacman instalados."
}

# ── Verifica ou instala um AUR helper (yay ou paru) ───────────────────────────
verificar_aur_helper() {
    if command -v yay &>/dev/null; then
        AUR_HELPER="yay"
    elif command -v paru &>/dev/null; then
        AUR_HELPER="paru"
    else
        warn "Nenhum AUR helper encontrado. Instalando yay via bootstrap..."
        instalar_yay_bootstrap
    fi
    log "AUR helper em uso: ${BOLD}$AUR_HELPER${NC}"
}

# ── Bootstrap do yay: instala sem AUR helper prévio ───────────────────────────
# Clona o PKGBUILD do yay-bin do AUR e compila com makepkg
instalar_yay_bootstrap() {
    titulo "Bootstrap: Instalando yay"
    local tmpdir
    tmpdir=$(mktemp -d)
    trap "rm -rf '$tmpdir'" EXIT   # garante limpeza mesmo em caso de erro

    git clone https://aur.archlinux.org/yay-bin.git "$tmpdir/yay-bin"
    (cd "$tmpdir/yay-bin" && makepkg -si --noconfirm)

    AUR_HELPER="yay"
    log "yay instalado via bootstrap com sucesso."
}

# ── Instala pacotes do AUR ────────────────────────────────────────────────────
instalar_aur() {
    titulo "Instalando Pacotes AUR"
    verificar_aur_helper

    # Nota: AUR helpers não devem ser executados como root
    # --needed evita reinstalações desnecessárias
    "$AUR_HELPER" -S --needed --noconfirm "${pacotes_aur[@]}"
    log "Pacotes AUR instalados."
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
    # -y responde 'sim' automaticamente; --noninteractive suprime progresso verboso
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
                warn "  O appimagelauncher (instalado via AUR) fará a integração automaticamente."
            fi
        else
            warn "Falha ao baixar '$nome'. Verifique a URL ou sua conexão e tente novamente."
        fi
    done

    log "AppImages processados. Arquivos em: $APPIMAGE_DIR"
}

instalando_uv_tools(){
    titulo "Instalando uv (gerenciador de ambientes Python)"
    curl -Ls https://uv.link/install.sh | sh
    
    if ! command -v uv &>/dev/null; then
    log "Erro: uv não está disponível após instalação."
    return 1
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
  uv tool install tdlr    # Instala o tldr, uma alternativa simpl

}


# ── (Alternativa) Instala o Hydra como pacote .pacman nativo do Arch ──────────
# Mais integrado ao sistema do que AppImage. Descomente para usar.
# instalar_hydra_pacman() {
#     titulo "Instalando Hydra Launcher (.pacman nativo)"
#     local tmpdir; tmpdir=$(mktemp -d)
#     local api_url="https://api.github.com/repos/hydralauncher/hydra/releases/latest"
#
#     # Usa a API do GitHub para obter a URL do .pacman mais recente
#     local pkg_url
#     pkg_url=$(curl -s "$api_url" | grep -o '"browser_download_url": "[^"]*\.pacman"' \
#               | cut -d'"' -f4)
#
#     [[ -z "$pkg_url" ]] && { warn "Não foi possível obter a URL do Hydra. Pulando."; return 1; }
#
#     log "Baixando Hydra: $pkg_url"
#     wget -P "$tmpdir" "$pkg_url"
#     sudo pacman -U --noconfirm "$tmpdir"/*.pacman
#     rm -rf "$tmpdir"
#     log "Hydra instalado via pacman."
# }

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
    
    # Crinando e configurando grupo docker
    if getent group docker &>/dev/null; then
        log "Grupo 'docker' já existe."
    else
        sudo groupadd docker
        log "Grupo 'docker' criado."
        sudo usermod -aG docker $USER
        log "Usuário adicionado ao grupo 'docker'. Faça logout e login para usar o Docker sem sudo."
        newgrp docker # Aplica o novo grupo na sessão atual sem precisar de logout/login
    fi

    # Configurando daemon do Docker para iniciar com o sistema
    if systemctl is-enabled docker &>/dev/null; then
        log "Docker já está habilitado para iniciar com o sistema."
    else
        sudo systemctl enable --now docker.service
        sudo systemctl enable docker.service
        log "Docker habilitado para iniciar com o sistema e iniciado agora."
    fi

}

# ==============================================================================
#  EXECUÇÃO PRINCIPAL
# ==============================================================================

main() {
    clear
    titulo "PÓS-INSTALAÇÃO — CachyOS / Arch Linux"

    # Resumo do que será instalado
    echo ""
    echo -e "  ${BOLD}Resumo da instalação:${NC}"
    echo -e "  📦 pacman       → ${#pacotes_pacman[@]} pacotes"
    echo -e "  🔧 dependências → $((${#dependencias_base[@]} + ${#dependencias_jogos_32bits[@]} + ${#dependencias_appimage[@]} + ${#dependencias_virtualbox[@]})) pacotes"
    echo -e "  🏗  AUR          → ${#pacotes_aur[@]} pacotes"
    echo -e "  📦 Flatpak      → ${#pacotes_flatpak[@]} pacotes"
    echo -e "  🖼  AppImages    → ${#appimages[@]} app(s)"
    echo ""

    # Confirmação antes de continuar
    read -rp "  Deseja iniciar a instalação? [s/N] " resposta
    echo ""
    [[ "$resposta" =~ ^[Ss]$ ]] || { echo "  Instalação cancelada."; exit 0; }

    # ── Ordem de execução ─────────────────────────────────────────────────────
    # 1. Multilib primeiro (Steam e dependências 32-bit precisam dele)
    habilitar_multilib

    # 2. Dependências antes dos pacotes principais
    instalar_dependencias

    # 3. Pacotes oficiais
    instalar_pacman

    # 4. AUR (requer yay/paru e base-devel, já instalados nos passos anteriores)
    instalar_aur

    # 5. Flatpak (requer o pacote 'flatpak' instalado no passo 3)
    instalar_flatpak

    # 6. AppImages (requer wget e FUSE, instalados anteriormente)
    instalar_appimages

    # 7. Configurações finais (grupos, módulos)
    configuracoes_pos_install

    # 8. (Opcional) Instalação do uv e ferramentas Python via uv
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
    echo -e "uv Ferramentas Python (IPython, tldr) estão disponíveis via 'uv tool list' e podem ser usadas com 'uv run <ferramenta>'."
}

# Chama a função principal passando todos os argumentos recebidos pelo script
main "$@"

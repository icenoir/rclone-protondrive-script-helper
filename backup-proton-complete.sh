#!/bin/bash
# Nome: backup-proton-complete.sh
# Descrizione: Script completo per gestire daemon rclone e backup sicuro

# =============================================================================
# CONFIGURAZIONE
# =============================================================================

# Configurazione Daemon
SERVE_PORT=8080
SERVE_HOST="127.0.0.1"
PID_FILE="$HOME/.rclone-daemon.pid"
LOG_FILE="$HOME/.rclone-daemon.log"
DAEMON_LOG_LEVEL="INFO"

# Configurazione Backup
REMOTE_NAME="protondrive"
BACKUP_BASE_DIR="$REMOTE_NAME:/backup"
BACKUP_LOG_FILE="$HOME/backup-complete.log"
DATE=$(date +%Y%m%d_%H%M%S)

# Directory da fare backup (personalizza queste)
BACKUP_SOURCES=(
    "/opt/etc:backup-etc"
    "$HOME/.env:backup-env"
    "$HOME/docker:backup-docker"
)

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# FUNZIONI DAEMON
# =============================================================================

# Funzione per avviare daemon
start_daemon() {
    echo -e "${BLUE}🚀 Avvio daemon rclone...${NC}"
    
    # Verifica se già in esecuzione
    if is_daemon_running; then
        echo -e "${YELLOW}⚠️  Daemon già in esecuzione${NC}"
        return 0
    fi
    
    # Test connessione prima di avviare daemon
    echo -e "${YELLOW}🔍 Verifico connessione a $REMOTE_NAME...${NC}"
    if ! timeout 30 rclone lsf "$REMOTE_NAME:" > /dev/null 2>&1; then
        echo -e "${RED}❌ Impossibile connettersi a $REMOTE_NAME${NC}"
        echo -e "${YELLOW}💡 Assicurati di aver configurato rclone: rclone config${NC}"
        return 1
    fi
    
    # Avvia rclone serve in background
    nohup rclone serve http "$REMOTE_NAME:" \
        --addr "$SERVE_HOST:$SERVE_PORT" \
        --read-only \
        --log-file "$LOG_FILE" \
        --log-level "$DAEMON_LOG_LEVEL" \
        --dir-cache-time 1000h \
        --poll-interval 15s > /dev/null 2>&1 &
    
    # Salva PID
    echo $! > "$PID_FILE"
    
    # Aspetta che il daemon si avvii
    sleep 3
    
    if is_daemon_running; then
        echo -e "${GREEN}✅ Daemon avviato con successo${NC}"
        echo -e "${BLUE}📋 PID: $(cat $PID_FILE)${NC}"
        echo -e "${BLUE}🌐 Accessibile su: http://$SERVE_HOST:$SERVE_PORT${NC}"
        return 0
    else
        echo -e "${RED}❌ Errore nell'avvio del daemon${NC}"
        return 1
    fi
}

# Funzione per fermare daemon
stop_daemon() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        echo -e "${YELLOW}🛑 Fermando daemon (PID: $PID)...${NC}"
        
        if kill $PID 2>/dev/null; then
            # Aspetta che il processo termini
            sleep 2
            if ! ps -p $PID > /dev/null 2>&1; then
                rm "$PID_FILE"
                echo -e "${GREEN}✅ Daemon fermato correttamente${NC}"
                return 0
            else
                echo -e "${YELLOW}⚠️  Forzo terminazione...${NC}"
                kill -9 $PID 2>/dev/null
                rm "$PID_FILE"
                echo -e "${GREEN}✅ Daemon terminato forzatamente${NC}"
                return 0
            fi
        else
            echo -e "${RED}❌ Impossibile fermare il daemon${NC}"
            rm "$PID_FILE"
            return 1
        fi
    else
        echo -e "${YELLOW}⚠️  Daemon non in esecuzione${NC}"
        return 0
    fi
}

# Funzione per verificare se daemon è in esecuzione
is_daemon_running() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p $PID > /dev/null 2>&1; then
            # Verifica anche che risponda su HTTP
            if curl -s "http://$SERVE_HOST:$SERVE_PORT/" > /dev/null 2>&1; then
                return 0
            fi
        fi
        # Se arriviamo qui, il PID file esiste ma il processo no
        rm "$PID_FILE"
    fi
    return 1
}

# Funzione per verificare stato daemon
status_daemon() {
    if is_daemon_running; then
        PID=$(cat "$PID_FILE")
        echo -e "${GREEN}✅ Daemon attivo (PID: $PID)${NC}"
        echo -e "${BLUE}🌐 Accessibile su: http://$SERVE_HOST:$SERVE_PORT${NC}"
        echo -e "${BLUE}📊 Statistiche:${NC}"
        echo "   - Log file: $LOG_FILE"
        echo "   - Uptime: $(ps -o etime= -p $PID 2>/dev/null | tr -d ' ')"
        return 0
    else
        echo -e "${RED}❌ Daemon non attivo${NC}"
        return 1
    fi
}

# =============================================================================
# FUNZIONI BACKUP
# =============================================================================

# Funzione per test connessione
test_connection() {
    echo -e "${YELLOW}🔍 Verifico connessione...${NC}"
    
    # Prima prova il daemon se attivo
    if is_daemon_running; then
        echo -e "${BLUE}📡 Uso connessione daemon${NC}"
        if curl -s "http://$SERVE_HOST:$SERVE_PORT/" > /dev/null 2>&1; then
            echo -e "${GREEN}✅ Daemon risponde${NC}"
            return 0
        fi
    fi
    
    # Fallback a connessione diretta
    echo -e "${BLUE}🔗 Uso connessione diretta${NC}"
    if timeout 30 rclone lsf "$REMOTE_NAME:" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Connessione diretta OK${NC}"
        return 0
    else
        echo -e "${RED}❌ Nessuna connessione disponibile${NC}"
        return 1
    fi
}

# Funzione per backup di una directory
backup_directory() {
    local source_path="$1"
    local dest_name="$2"
    local dest_path="$BACKUP_BASE_DIR/$dest_name"
    local timestamp_dest="$dest_path-$DATE"
    
    echo -e "${BLUE}📦 Backup: $source_path → $dest_name${NC}"
    
    # Verifica che la directory sorgente esista
    if [ ! -e "$source_path" ]; then
        echo -e "${RED}❌ Sorgente non esistente: $source_path${NC}" | tee -a "$BACKUP_LOG_FILE"
        return 1
    fi
    
    # Determina se serve sudo
    local use_sudo=""
    if [ ! -r "$source_path" ]; then
        use_sudo="sudo"
        echo -e "${YELLOW}🔐 Uso sudo per accedere a $source_path${NC}"
    fi
    
    # Dry run prima
    echo -e "${YELLOW}🧪 Test dry-run...${NC}"
    if ! $use_sudo rclone copy "$source_path" "$dest_path" --dry-run -q 2>>$BACKUP_LOG_FILE; then
        echo -e "${RED}❌ Dry-run fallito per $source_path${NC}" | tee -a "$BACKUP_LOG_FILE"
        return 1
    fi
    
    # Backup attuale
    echo -e "${BLUE}☁️  Backup in corso...${NC}"
    if $use_sudo rclone copy "$source_path" "$dest_path" \
        --progress \
        --transfers 4 \
        --checkers 8 \
        --exclude "*.tmp" \
        --exclude "*.log" \
        --exclude "cache/**" \
        --log-file "$BACKUP_LOG_FILE.detailed" 2>>$BACKUP_LOG_FILE; then
        
        echo -e "${GREEN}✅ Backup completato: $dest_name${NC}"
        
        # Crea anche versione con timestamp
        echo -e "${BLUE}📅 Creo versione con timestamp...${NC}"
        $use_sudo rclone copy "$source_path" "$timestamp_dest" -q 2>>$BACKUP_LOG_FILE
        
        return 0
    else
        echo -e "${RED}❌ Backup fallito: $source_path${NC}" | tee -a "$BACKUP_LOG_FILE"
        return 1
    fi
}

# Funzione per backup completo
run_backup() {
    echo -e "${BLUE}🎯 Inizio backup completo: $(date)${NC}" | tee -a "$BACKUP_LOG_FILE"
    
    # Assicurati che il daemon sia attivo
    if ! is_daemon_running; then
        echo -e "${YELLOW}⚠️  Daemon non attivo, lo avvio...${NC}"
        start_daemon
    fi
    
    # Test connessione
    if ! test_connection; then
        echo -e "${RED}❌ Impossibile connettersi, backup annullato${NC}" | tee -a "$BACKUP_LOG_FILE"
        return 1
    fi
    
    # Esegui backup per ogni sorgente
    local success_count=0
    local total_count=${#BACKUP_SOURCES[@]}
    
    for source_entry in "${BACKUP_SOURCES[@]}"; do
        IFS=':' read -r source_path dest_name <<< "$source_entry"
        
        if backup_directory "$source_path" "$dest_name"; then
            ((success_count++))
        fi
        
        echo # Riga vuota per separare
    done
    
    # Statistiche finali
    echo -e "${BLUE}📊 Statistiche backup:${NC}" | tee -a "$BACKUP_LOG_FILE"
    echo "   - Completati: $success_count/$total_count" | tee -a "$BACKUP_LOG_FILE"
    echo "   - Data: $(date)" | tee -a "$BACKUP_LOG_FILE"
    
    # Mostra dimensioni backup
    echo -e "${BLUE}💾 Dimensioni backup:${NC}"
    rclone size "$BACKUP_BASE_DIR" 2>/dev/null | tee -a "$BACKUP_LOG_FILE"
    
    if [ $success_count -eq $total_count ]; then
        echo -e "${GREEN}🎉 Backup completo riuscito!${NC}" | tee -a "$BACKUP_LOG_FILE"
        return 0
    else
        echo -e "${YELLOW}⚠️  Backup parziale: $success_count/$total_count${NC}" | tee -a "$BACKUP_LOG_FILE"
        return 1
    fi
}

# =============================================================================
# FUNZIONI UTILITY
# =============================================================================

# Funzione per mostrare help
show_help() {
    echo -e "${BLUE}🛠️  Script Backup Completo con Daemon Rclone${NC}"
    echo
    echo "UTILIZZO:"
    echo "  $0 <comando> [opzioni]"
    echo
    echo "COMANDI DAEMON:"
    echo "  start          - Avvia il daemon rclone"
    echo "  stop           - Ferma il daemon rclone"
    echo "  restart        - Riavvia il daemon rclone"
    echo "  status         - Mostra stato del daemon"
    echo
    echo "COMANDI BACKUP:"
    echo "  backup         - Esegui backup completo"
    echo "  test           - Testa la connessione"
    echo
    echo "COMANDI GENERALI:"
    echo "  help           - Mostra questo help"
    echo "  logs           - Mostra i log"
    echo "  config         - Mostra configurazione"
    echo
    echo "ESEMPI:"
    echo "  $0 start       # Avvia daemon"
    echo "  $0 backup      # Esegui backup"
    echo "  $0 status      # Verifica stato"
}

# Funzione per mostrare logs
show_logs() {
    echo -e "${BLUE}📋 Log del daemon:${NC}"
    if [ -f "$LOG_FILE" ]; then
        tail -n 20 "$LOG_FILE"
    else
        echo "Nessun log del daemon disponibile"
    fi
    
    echo
    echo -e "${BLUE}📋 Log del backup:${NC}"
    if [ -f "$BACKUP_LOG_FILE" ]; then
        tail -n 20 "$BACKUP_LOG_FILE"
    else
        echo "Nessun log del backup disponibile"
    fi
}

# Funzione per mostrare configurazione
show_config() {
    echo -e "${BLUE}⚙️  Configurazione attuale:${NC}"
    echo
    echo "DAEMON:"
    echo "  - Host: $SERVE_HOST"
    echo "  - Porta: $SERVE_PORT"
    echo "  - PID File: $PID_FILE"
    echo "  - Log File: $LOG_FILE"
    echo
    echo "BACKUP:"
    echo "  - Remote: $REMOTE_NAME"
    echo "  - Base Dir: $BACKUP_BASE_DIR"
    echo "  - Log File: $BACKUP_LOG_FILE"
    echo
    echo "SORGENTI BACKUP:"
    for source_entry in "${BACKUP_SOURCES[@]}"; do
        IFS=':' read -r source_path dest_name <<< "$source_entry"
        echo "  - $source_path → $dest_name"
    done
}

# =============================================================================
# MAIN
# =============================================================================

# Gestione parametri
case "${1:-help}" in
    start)
        start_daemon
        ;;
    stop)
        stop_daemon
        ;;
    restart)
        stop_daemon
        sleep 2
        start_daemon
        ;;
    status)
        status_daemon
        ;;
    backup)
        run_backup
        ;;
    test)
        test_connection
        ;;
    logs)
        show_logs
        ;;
    config)
        show_config
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo -e "${RED}❌ Comando non riconosciuto: $1${NC}"
        echo -e "${YELLOW}💡 Usa '$0 help' per vedere i comandi disponibili${NC}"
        exit 1
        ;;
esac

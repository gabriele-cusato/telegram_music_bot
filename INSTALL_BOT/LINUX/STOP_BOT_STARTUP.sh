#!/usr/bin/env bash
#
# STOP_BOT_STARTUP.sh
# ---------------------------------------------------------------------------
# Ferma e rimuove completamente il servizio systemd installato da
# RUN_BOT_STARTUP.sh, riportando il sistema esattamente com'era prima:
# il bot smette di avviarsi automaticamente e il file di unità viene
# eliminato da /etc/systemd/system/, senza lasciare residui.
#
# Se il servizio non è mai stato installato, questo script non fallisce né
# allarma: dichiara che non c'era nulla da rimuovere e termina con esito
# positivo.
# ---------------------------------------------------------------------------

set -u

# Nome del servizio: unico riferimento condiviso con RUN_BOT_STARTUP.sh,
# usato sia per il nome del file di unità che per i comandi systemctl.
NOME_SERVIZIO="musicbot"
FILE_UNITA="${NOME_SERVIZIO}.service"
PERCORSO_UNITA_SISTEMA="/etc/systemd/system/${FILE_UNITA}"

# Cartella dove si trova questo script e radice del progetto, calcolata
# risalendo di due livelli: qui serve solo per indicare all'utente da dove
# è stato lanciato lo spegnimento dell'avvio automatico.
CARTELLA_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
RADICE_PROGETTO="$(cd "${CARTELLA_SCRIPT}/../.." && pwd)"

# Funzioni di stampa degli esiti, usate da tutti i passaggi dello script.
stampa_ok() {
    echo "[OK] $1"
}

stampa_info() {
    echo "[INFO] $1"
}

stampa_errore() {
    echo "[ERRORE] $1" >&2
}

# Verifica se il servizio è registrato in systemd, indipendentemente dal
# fatto che sia attivo, abilitato o solo presente come file di unità.
servizio_e_registrato() {
    if [ -f "${PERCORSO_UNITA_SISTEMA}" ]; then
        return 0
    fi
    systemctl list-unit-files "${FILE_UNITA}" 2>/dev/null | grep -q "${NOME_SERVIZIO}"
}

stampa_info "Rimuovo l'avvio automatico del bot in ${RADICE_PROGETTO}."

# Se non c'è nulla di installato, lo script termina subito senza provare
# comandi con sudo, che non avrebbero nulla su cui agire.
if ! servizio_e_registrato; then
    stampa_info "Il servizio ${NOME_SERVIZIO} non risulta installato: niente da rimuovere."
    exit 0
fi

# Ferma il servizio se in esecuzione.
if systemctl is-active --quiet "${NOME_SERVIZIO}" 2>/dev/null; then
    stampa_info "Fermo il servizio ${NOME_SERVIZIO}."
    sudo systemctl stop "${NOME_SERVIZIO}"
fi

# Disattiva l'avvio automatico ai riavvii successivi.
if systemctl is-enabled --quiet "${NOME_SERVIZIO}" 2>/dev/null; then
    stampa_info "Disattivo l'avvio automatico del servizio ${NOME_SERVIZIO}."
    sudo systemctl disable "${NOME_SERVIZIO}"
fi

# Elimina il file di unità dal sistema, per non lasciare configurazioni
# sporche una volta disattivato l'avvio automatico.
if [ -f "${PERCORSO_UNITA_SISTEMA}" ]; then
    stampa_info "Elimino il file di unità ${PERCORSO_UNITA_SISTEMA}."
    sudo rm -f "${PERCORSO_UNITA_SISTEMA}"
fi

# Ricarica la configurazione di systemd e ripulisce lo stato dei servizi
# non più esistenti, così "systemctl status" non mostra più riferimenti al
# servizio appena rimosso.
sudo systemctl daemon-reload
sudo systemctl reset-failed "${NOME_SERVIZIO}" >/dev/null 2>&1 || true

# Verifica finale: il servizio non deve risultare più né attivo né
# registrato in systemd.
if servizio_e_registrato; then
    stampa_errore "Il servizio ${NOME_SERVIZIO} risulta ancora registrato in systemd: verifica manualmente ${PERCORSO_UNITA_SISTEMA}."
    exit 1
fi

stampa_ok "Il servizio ${NOME_SERVIZIO} non è più né attivo né registrato in systemd."

# Riepiloga a video cosa è stato fatto e come riattivare l'avvio
# automatico, così l'utente non deve ricordarsi i comandi a memoria.
echo ""
echo "==================== Riepilogo ===================="
echo "Servizio rimosso: ${NOME_SERVIZIO}"
echo "Il bot non si avvia più automaticamente all'accensione della macchina."
echo "Per consultare eventuali log residui nel journal:"
echo "  journalctl -u ${NOME_SERVIZIO} -e"
echo "Per riattivare l'avvio automatico:"
echo "  ${CARTELLA_SCRIPT}/RUN_BOT_STARTUP.sh"
echo "======================================================"

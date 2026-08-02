#!/usr/bin/env bash
#
# RUN_BOT_STARTUP.sh
# ---------------------------------------------------------------------------
# Installa e avvia il bot Telegram come servizio systemd, così che riparta
# automaticamente ad ogni avvio della macchina e si riavvii da solo se il
# processo dovesse terminare inaspettatamente.
#
# Cosa installa nel sistema:
#   - il file di unità /etc/systemd/system/musicbot.service, generato a
#     partire dal modello "musicbot.service" presente in questa stessa
#     cartella, con i segnaposto sostituiti dai valori reali di questa
#     macchina (utente, gruppo, cartella del progetto, interprete Python
#     della venv).
#
# Come si annulla:
#   - lanciare STOP_BOT_STARTUP.sh, nella stessa cartella: ferma il servizio,
#     ne disattiva l'avvio automatico e rimuove il file di unità, riportando
#     il sistema com'era prima di questo script.
#
# L'installazione guidata (INSTALL_BOT.LINUX.sh) non lancia mai questo
# script: l'avvio automatico si attiva solo qui, quando l'utente lo vuole
# esplicitamente.
# ---------------------------------------------------------------------------

set -u

# Nome del servizio: unico riferimento condiviso con STOP_BOT_STARTUP.sh,
# usato sia per il nome del file di unità che per i comandi systemctl.
NOME_SERVIZIO="musicbot"
FILE_UNITA="${NOME_SERVIZIO}.service"
PERCORSO_UNITA_SISTEMA="/etc/systemd/system/${FILE_UNITA}"

# Cartella dove si trova questo script, usata per individuare il modello
# musicbot.service che sta accanto ad esso.
CARTELLA_SCRIPT="$(cd "$(dirname "$0")" && pwd)"

# Radice del progetto: due livelli sopra questo script (che sta in
# INSTALL_BOT/LINUX/), ricavata dal percorso reale dello script invece che
# scritta a mano, così lo script funziona indipendentemente da dove è stato
# clonato il progetto.
RADICE_PROGETTO="$(cd "${CARTELLA_SCRIPT}/../.." && pwd)"

PERCORSO_PYTHON="${RADICE_PROGETTO}/.venv/bin/python"
PERCORSO_ENV="${RADICE_PROGETTO}/data/.env"

# Funzioni di stampa degli esiti, usate da tutti i controlli dello script.
stampa_ok() {
    echo "[OK] $1"
}

stampa_errore() {
    echo "[ERRORE] $1" >&2
}

stampa_info() {
    echo "[INFO] $1"
}

# Controlla che l'installazione del bot sia completa prima di installare
# qualunque cosa: un servizio installato su un'installazione incompleta
# partirebbe e morirebbe in continuazione, senza che l'utente capisca perché.
verifica_installazione_completa() {
    local installazione_incompleta=0

    if [ ! -f "${RADICE_PROGETTO}/main.py" ]; then
        stampa_errore "Non trovo ${RADICE_PROGETTO}/main.py: il progetto non risulta completo in questa cartella."
        installazione_incompleta=1
    fi

    if [ ! -x "${PERCORSO_PYTHON}" ]; then
        stampa_errore "Non trovo l'interprete Python della venv del progetto (${PERCORSO_PYTHON})."
        installazione_incompleta=1
    fi

    if [ ! -f "${PERCORSO_ENV}" ]; then
        stampa_errore "Non trovo il file ${PERCORSO_ENV} con le impostazioni del bot."
        installazione_incompleta=1
    elif ! grep -Eq '^BOT_TOKEN=.+' "${PERCORSO_ENV}"; then
        stampa_errore "Il file ${PERCORSO_ENV} esiste ma BOT_TOKEN non è valorizzato."
        installazione_incompleta=1
    fi

    if [ "${installazione_incompleta}" -eq 1 ]; then
        stampa_errore "Installazione non completa: esegui prima INSTALL_BOT/INSTALL_BOT.LINUX.sh dalla radice del progetto, poi riprova."
        exit 1
    fi

    stampa_ok "Installazione del bot completa."
}

# Controlla che l'ambiente sia adatto a installare un servizio systemd:
# la distribuzione deve usare systemd e il modello musicbot.service deve
# essere presente accanto a questo script.
verifica_ambiente() {
    if ! command -v systemctl >/dev/null 2>&1; then
        stampa_errore "systemctl non è disponibile: questa distribuzione non usa systemd."
        stampa_errore "Configura l'avvio automatico con lo strumento previsto dalla tua distribuzione, questo script non può farlo."
        exit 1
    fi
    stampa_ok "systemd è disponibile su questa macchina."

    if [ ! -f "${CARTELLA_SCRIPT}/${FILE_UNITA}" ]; then
        stampa_errore "Non trovo il file modello ${CARTELLA_SCRIPT}/${FILE_UNITA}: reinstalla il progetto o ripristina la cartella INSTALL_BOT/LINUX/."
        exit 1
    fi
    stampa_ok "File modello ${FILE_UNITA} trovato."
}

# Genera il file di unità sostituendo i segnaposto del modello con i valori
# reali di questa macchina, poi lo installa in /etc/systemd/system/ e avvia
# il servizio. Se un servizio con lo stesso nome esiste già, questo comando
# lo sostituisce invece di duplicarlo, perché scrive sempre sullo stesso
# percorso.
installa_servizio() {
    local utente
    local gruppo
    local file_temporaneo
    utente="$(id -un)"
    gruppo="$(id -gn)"

    stampa_info "Genero il file di unità per l'utente ${utente} (gruppo ${gruppo})."

    # Il file generato viene prima scritto in una posizione temporanea
    # scrivibile dall'utente corrente, e solo dopo copiato con sudo nella
    # cartella di sistema: sudo serve solo per l'ultimo passaggio, non per
    # generare il contenuto del file.
    file_temporaneo="$(mktemp)"
    sed \
        -e "s|__UTENTE__|${utente}|g" \
        -e "s|__GRUPPO__|${gruppo}|g" \
        -e "s|__CARTELLA_PROGETTO__|${RADICE_PROGETTO}|g" \
        -e "s|__PYTHON__|${PERCORSO_PYTHON}|g" \
        "${CARTELLA_SCRIPT}/${FILE_UNITA}" > "${file_temporaneo}"

    if [ -f "${PERCORSO_UNITA_SISTEMA}" ]; then
        stampa_info "Un servizio ${NOME_SERVIZIO} esiste già: lo sostituisco con questa nuova configurazione."
    fi

    sudo cp "${file_temporaneo}" "${PERCORSO_UNITA_SISTEMA}"
    rm -f "${file_temporaneo}"

    sudo systemctl daemon-reload
    sudo systemctl enable --now "${NOME_SERVIZIO}"

    stampa_ok "Servizio ${NOME_SERVIZIO} installato e avviato."
}

# Controlla che il servizio sia effettivamente partito e avvisa l'utente
# sul vincolo del polling Telegram, che ammette un solo processo attivo per
# token alla volta.
verifica_stato_finale() {
    # Attende qualche istante prima di controllare, per dare al processo il
    # tempo di avviarsi e a systemd il tempo di aggiornarne lo stato.
    sleep 2

    if systemctl is-active --quiet "${NOME_SERVIZIO}"; then
        stampa_ok "Il servizio ${NOME_SERVIZIO} è attivo."
    else
        stampa_errore "Il servizio ${NOME_SERVIZIO} non risulta attivo."
        stampa_errore "Consulta i log per capire il motivo con: journalctl -u ${NOME_SERVIZIO} -e"
        exit 1
    fi

    stampa_info "Attenzione: un solo processo per volta può fare polling con lo stesso token Telegram."
    stampa_info "Se il bot gira già con questo BOT_TOKEN su un'altra macchina, fermalo prima, altrimenti i due processi si contenderanno i messaggi."
}

# Riepiloga a video cosa è stato fatto e come consultare i log o annullare
# l'operazione, così l'utente non deve ricordarsi i comandi a memoria.
stampa_riepilogo() {
    echo ""
    echo "==================== Riepilogo ===================="
    echo "Servizio installato e avviato: ${NOME_SERVIZIO}"
    echo "File di unità: ${PERCORSO_UNITA_SISTEMA}"
    echo "Cartella del progetto: ${RADICE_PROGETTO}"
    echo "Il bot si avvia automaticamente ad ogni accensione della macchina"
    echo "e riparte da solo se il processo dovesse terminare."
    echo ""
    echo "Log del bot in tempo reale: journalctl -u ${NOME_SERVIZIO} -f"
    echo "Per disattivare l'avvio automatico e rimuovere il servizio:"
    echo "  ${CARTELLA_SCRIPT}/STOP_BOT_STARTUP.sh"
    echo "======================================================"
}

verifica_installazione_completa
verifica_ambiente
installa_servizio
verifica_stato_finale
stampa_riepilogo

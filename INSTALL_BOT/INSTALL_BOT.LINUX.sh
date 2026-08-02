#!/usr/bin/env bash
#
# INSTALL_BOT.LINUX.sh
#
# Installa e configura il bot Telegram su Linux (bersaglio principale:
# Raspberry Pi OS / Debian). Lo script e' pensato per chi non ha esperienza
# di amministrazione di sistema: verifica ogni prerequisito, installa da solo
# quello che puo' installare, e spiega a schermo cosa fare per il resto.
#
# Puo' essere eseguito piu' volte senza danni: cio' che e' gia' a posto viene
# rilevato e dichiarato, non viene rifatto ne' sovrascritto.
#
# Uso: eseguire dalla cartella INSTALL_BOT del progetto con:
#   bash INSTALL_BOT.LINUX.sh
#

set -u

# --- Funzioni di supporto per stampare gli esiti in modo uniforme --------
#
# Ogni controllo dello script chiama una di queste funzioni. "avviso" ed
# "errore" alimentano gli array ERRORI e AVVISI, riletti alla fine per
# stampare il riepilogo conclusivo e per decidere il codice di uscita.

ERRORI=()
AVVISI=()
# pacchetti apt mancanti, popolato dai controlli su venv, ffmpeg e git e
# installato in un unico passaggio nella sezione "Pacchetti di sistema"
PACCHETTI_DA_INSTALLARE=()

stampa_ok() {
    echo "  [OK]      $1"
}

stampa_avviso() {
    echo "  [AVVISO]  $1"
    AVVISI+=("$1")
}

stampa_errore() {
    echo "  [ERRORE]  $1"
    ERRORI+=("$1")
}

stampa_titolo() {
    echo ""
    echo "== $1 =="
}

# --- Radice del progetto --------------------------------------------------
#
# Lo script si trova in INSTALL_BOT/, quindi la radice del progetto e' la
# cartella padre dello script stesso. Si ricava dal percorso dello script
# (mai da un percorso scritto a mano), cosi' l'installazione funziona anche
# se l'utente ha clonato il repository in una posizione diversa da quella
# prevista.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "############################################################"
echo "  Installazione guidata del bot Telegram - Linux"
echo "  Radice del progetto: $PROJECT_ROOT"
echo "############################################################"

# --- Controlli preliminari -------------------------------------------------
#
# Se main.py, requirements.txt o la cartella core non esistono nella radice
# calcolata, l'utente ha spostato la cartella INSTALL_BOT fuori dal progetto:
# senza questi file lo script non puo' fare nulla di utile, quindi si ferma
# subito invece di proseguire con controlli inutili.
stampa_titolo "Controlli preliminari"

PRECONDIZIONI_OK=true
if [[ ! -f "$PROJECT_ROOT/main.py" ]]; then
    stampa_errore "Non trovo main.py in $PROJECT_ROOT."
    PRECONDIZIONI_OK=false
fi
if [[ ! -f "$PROJECT_ROOT/requirements.txt" ]]; then
    stampa_errore "Non trovo requirements.txt in $PROJECT_ROOT."
    PRECONDIZIONI_OK=false
fi
if [[ ! -d "$PROJECT_ROOT/core" ]]; then
    stampa_errore "Non trovo la cartella core in $PROJECT_ROOT."
    PRECONDIZIONI_OK=false
fi

if [[ "$PRECONDIZIONI_OK" != true ]]; then
    echo ""
    echo "La cartella INSTALL_BOT deve restare dentro la cartella del progetto"
    echo "clonato da git, allo stesso livello di main.py e requirements.txt."
    echo "Sposta INSTALL_BOT nella posizione corretta e rilancia lo script."
    exit 1
fi
stampa_ok "main.py, requirements.txt e core/ trovati nella radice del progetto."

# --- Python ------------------------------------------------------------
#
# aiogram richiede Python 3.9 o superiore. Il modulo venv e' verificato a
# parte perche' su Debian e' distribuito in un pacchetto separato
# (python3-venv): puo' mancare anche se python3 e' gia' installato.
stampa_titolo "Python"

PYTHON_VERSIONE_OK=false
if command -v python3 >/dev/null 2>&1; then
    if python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' >/dev/null 2>&1; then
        PYTHON_VERSIONE_OK=true
        VERSIONE_PYTHON="$(python3 -c 'import platform; print(platform.python_version())')"
        stampa_ok "python3 trovato, versione $VERSIONE_PYTHON (>= 3.9 richiesta)."
    else
        VERSIONE_PYTHON="$(python3 -c 'import platform; print(platform.python_version())' 2>/dev/null || echo sconosciuta)"
        stampa_errore "python3 trovato ma la versione ($VERSIONE_PYTHON) e' inferiore a 3.9. Aggiorna Python (es. 'sudo apt install python3') e rilancia lo script."
    fi
else
    stampa_errore "python3 non trovato. Installa Python 3.9 o superiore con: sudo apt install python3"
fi

VENV_MODULO_OK=false
if [[ "$PYTHON_VERSIONE_OK" == true ]]; then
    if python3 -c 'import venv' >/dev/null 2>&1; then
        VENV_MODULO_OK=true
        stampa_ok "Modulo venv di Python disponibile."
    else
        stampa_avviso "Modulo venv non disponibile: verra' installato il pacchetto python3-venv."
        PACCHETTI_DA_INSTALLARE+=("python3-venv")
    fi
fi

# --- Pacchetti di sistema ------------------------------------------------
#
# ffmpeg e' obbligatorio: yt-dlp lo cerca nel PATH di sistema per estrarre
# l'audio e i metadati (core/services/youtube.py). git serve per aggiornare
# il progetto in futuro con git pull. I pacchetti mancanti vengono installati
# con apt; se apt non e' disponibile (distribuzione non Debian) lo script si
# limita a elencare cosa manca, perche' non gestisce altri package manager.
stampa_titolo "Pacchetti di sistema (ffmpeg, git)"

if command -v ffmpeg >/dev/null 2>&1; then
    stampa_ok "ffmpeg gia' installato."
else
    stampa_avviso "ffmpeg non trovato: verra' installato con apt."
    PACCHETTI_DA_INSTALLARE+=("ffmpeg")
fi

if command -v git >/dev/null 2>&1; then
    stampa_ok "git gia' installato."
else
    stampa_avviso "git non trovato: verra' installato con apt."
    PACCHETTI_DA_INSTALLARE+=("git")
fi

if [[ ${#PACCHETTI_DA_INSTALLARE[@]} -gt 0 ]]; then
    if command -v apt >/dev/null 2>&1; then
        echo "  Installazione di: ${PACCHETTI_DA_INSTALLARE[*]}"
        echo "  Viene chiesta la password sudo per installare i pacchetti di sistema."
        if sudo apt update && sudo apt install -y "${PACCHETTI_DA_INSTALLARE[@]}"; then
            stampa_ok "Pacchetti di sistema installati: ${PACCHETTI_DA_INSTALLARE[*]}"
            if [[ " ${PACCHETTI_DA_INSTALLARE[*]} " == *" python3-venv "* ]]; then
                VENV_MODULO_OK=true
            fi
        else
            stampa_errore "Installazione con apt fallita per: ${PACCHETTI_DA_INSTALLARE[*]}. Riprova a mano con: sudo apt update && sudo apt install -y ${PACCHETTI_DA_INSTALLARE[*]}"
        fi
    else
        stampa_errore "apt non disponibile su questo sistema: installa manualmente questi pacchetti con il gestore pacchetti della tua distribuzione: ${PACCHETTI_DA_INSTALLARE[*]}"
    fi
fi

# --- Ambiente virtuale ------------------------------------------------------
#
# Su Debian Bookworm e successivi il Python di sistema e' "externally
# managed" e rifiuta pip install: senza una venv il bot fallirebbe ad ogni
# avvio, perche' core/yt_dlp_update/yt_dlp_manager.py esegue
# 'pip install --upgrade yt-dlp' con sys.executable. La venv viene quindi
# creata una sola volta e riusata alle esecuzioni successive.
stampa_titolo "Ambiente virtuale (.venv)"

VENV_DIR="$PROJECT_ROOT/.venv"
VENV_PYTHON="$VENV_DIR/bin/python"
VENV_OK=false

if [[ "$PYTHON_VERSIONE_OK" != true || "$VENV_MODULO_OK" != true ]]; then
    stampa_errore "Impossibile creare l'ambiente virtuale: risolvi prima i problemi di Python segnalati sopra."
elif [[ -x "$VENV_PYTHON" ]]; then
    stampa_ok "Ambiente virtuale gia' presente in $VENV_DIR, viene riusato."
    VENV_OK=true
else
    if python3 -m venv "$VENV_DIR"; then
        stampa_ok "Ambiente virtuale creato in $VENV_DIR."
        VENV_OK=true
    else
        stampa_errore "Creazione dell'ambiente virtuale fallita. Riprova a mano con: python3 -m venv \"$VENV_DIR\""
    fi
fi

if [[ "$VENV_OK" == true ]]; then
    # segnala il tempo di compilazione lungo su architetture ARM a 32 bit,
    # dove RapidFuzz non ha una wheel precompilata e va costruito dal codice sorgente
    ARCHITETTURA="$(uname -m)"
    case "$ARCHITETTURA" in
        armv6l|armv7l|i686|i386)
            stampa_avviso "Architettura a 32 bit rilevata ($ARCHITETTURA): l'installazione di RapidFuzz puo' richiedere una compilazione lunga e strumenti di build (gcc, ecc.). E' normale, attendi il completamento."
            ;;
    esac

    echo "  Aggiornamento di pip e installazione delle dipendenze da requirements.txt..."
    if "$VENV_PYTHON" -m pip install --upgrade pip >/dev/null && \
       "$VENV_PYTHON" -m pip install -r "$PROJECT_ROOT/requirements.txt"; then
        stampa_ok "Dipendenze Python installate nell'ambiente virtuale."
    else
        stampa_errore "Installazione delle dipendenze Python fallita. Riprova a mano con: \"$VENV_PYTHON\" -m pip install -r \"$PROJECT_ROOT/requirements.txt\""
        VENV_OK=false
    fi
fi

# --- Cartelle di lavoro ------------------------------------------------
#
# data/ e temp/ sono elencate in .gitignore, quindi dopo un 'git clone' non
# esistono ancora: vanno create prima del primo avvio del bot.
stampa_titolo "Cartelle di lavoro (data, temp)"

DATA_DIR="$PROJECT_ROOT/data"
TEMP_DIR="$PROJECT_ROOT/temp"

if [[ -d "$DATA_DIR" ]]; then
    stampa_ok "Cartella data/ gia' presente."
else
    if mkdir -p "$DATA_DIR"; then
        stampa_ok "Cartella data/ creata."
    else
        stampa_errore "Impossibile creare la cartella $DATA_DIR."
    fi
fi

if [[ -d "$TEMP_DIR" ]]; then
    stampa_ok "Cartella temp/ gia' presente."
else
    if mkdir -p "$TEMP_DIR"; then
        stampa_ok "Cartella temp/ creata."
    else
        stampa_errore "Impossibile creare la cartella $TEMP_DIR."
    fi
fi

# --- File data/.env ---------------------------------------------------
#
# Contiene il token del bot e la configurazione letta da core/config.py
# tramite load_dotenv. Se esiste gia' non viene mai riscritto (contiene il
# token reale dell'utente): si controlla solo che le variabili obbligatorie
# siano presenti e valorizzate. Se manca, i valori vengono chiesti a schermo.
stampa_titolo "File di configurazione data/.env"

ENV_FILE="$DATA_DIR/.env"

leggi_valore_env() {
    # estrae il valore di una chiave da data/.env, senza eseguire il file
    # (a differenza di un 'source', che interpreterebbe il contenuto come
    # comandi shell): restituisce l'ultima occorrenza della chiave, o vuoto
    # se non presente
    local chiave="$1"
    grep -E "^${chiave}=" "$ENV_FILE" 2>/dev/null | tail -n1 | cut -d'=' -f2-
}

if [[ -f "$ENV_FILE" ]]; then
    stampa_ok "data/.env gia' presente: non viene modificato."
    BOT_TOKEN_ESISTENTE="$(leggi_valore_env BOT_TOKEN)"
    MUSIC_DIR_ESISTENTE="$(leggi_valore_env MUSIC_DIR)"
    if [[ -z "$BOT_TOKEN_ESISTENTE" ]]; then
        stampa_errore "In data/.env manca o e' vuoto BOT_TOKEN: aggiungilo a mano con il token ottenuto da @BotFather."
    else
        stampa_ok "BOT_TOKEN presente in data/.env."
    fi
    if [[ -z "$MUSIC_DIR_ESISTENTE" ]]; then
        stampa_errore "In data/.env manca o e' vuoto MUSIC_DIR: aggiungilo a mano con il percorso dove salvare la musica."
    else
        stampa_ok "MUSIC_DIR presente in data/.env."
    fi
    MUSIC_DIR_DA_VERIFICARE="$MUSIC_DIR_ESISTENTE"
else
    echo "  data/.env non esiste ancora: viene creato ora rispondendo a poche domande."
    echo ""

    BOT_TOKEN_INSERITO=""
    while [[ -z "$BOT_TOKEN_INSERITO" ]]; do
        echo "  Il token del bot si ottiene parlando con @BotFather su Telegram (comando /newbot)."
        read -rp "  BOT_TOKEN (obbligatorio, non puo' restare vuoto): " BOT_TOKEN_INSERITO
    done

    MUSIC_DIR_DEFAULT="$HOME/Music"
    echo "  Cartella dove il bot salva i brani scaricati."
    read -rp "  MUSIC_DIR [$MUSIC_DIR_DEFAULT]: " MUSIC_DIR_INSERITO
    MUSIC_DIR_INSERITO="${MUSIC_DIR_INSERITO:-$MUSIC_DIR_DEFAULT}"

    # L'uso in chat privata e' il modo normale di usare questo bot, quindi il
    # valore predefinito e' 'true': serve scrivere 'false' per disattivarlo.
    echo "  ALLOW_PRIVATE_CHAT: se 'true' il bot risponde anche in chat privata, non solo nei gruppi."
    read -rp "  ALLOW_PRIVATE_CHAT [true]: " ALLOW_PRIVATE_CHAT_INSERITO
    ALLOW_PRIVATE_CHAT_INSERITO="${ALLOW_PRIVATE_CHAT_INSERITO:-true}"

    echo "  ALLOWED_CHAT_ID: id delle chat di gruppo autorizzate, separati da virgola."
    echo "  Vuoto = tutte le chat di gruppo autorizzate. 'false' = nessuna chat autorizzata."
    read -rp "  ALLOWED_CHAT_ID [vuoto = tutte]: " ALLOWED_CHAT_ID_INSERITO

    echo "  MUSIC_CHANNEL_ID: id del canale Telegram dove pubblicare la musica. Vuoto = funzione disattivata."
    read -rp "  MUSIC_CHANNEL_ID [vuoto = disattivato]: " MUSIC_CHANNEL_ID_INSERITO

    echo "  MUSIC_STORAGE_CHANNEL_ID: id del canale usato come archivio dei file audio. Vuoto = funzione disattivata."
    read -rp "  MUSIC_STORAGE_CHANNEL_ID [vuoto = disattivato]: " MUSIC_STORAGE_CHANNEL_ID_INSERITO

    {
        echo "BOT_TOKEN=$BOT_TOKEN_INSERITO"
        echo "MUSIC_DIR=$MUSIC_DIR_INSERITO"
        echo "ALLOW_PRIVATE_CHAT=$ALLOW_PRIVATE_CHAT_INSERITO"
        echo "ALLOWED_CHAT_ID=$ALLOWED_CHAT_ID_INSERITO"
        echo "MUSIC_CHANNEL_ID=$MUSIC_CHANNEL_ID_INSERITO"
        echo "MUSIC_STORAGE_CHANNEL_ID=$MUSIC_STORAGE_CHANNEL_ID_INSERITO"
    } > "$ENV_FILE"

    # il file contiene il token del bot: viene reso leggibile solo dal
    # proprietario, per non esporlo agli altri utenti della macchina
    chmod 600 "$ENV_FILE"

    stampa_ok "data/.env creato e protetto con permessi 600 (lettura riservata al proprietario)."
    MUSIC_DIR_DA_VERIFICARE="$MUSIC_DIR_INSERITO"
fi

# --- Verifiche finali ----------------------------------------------------
#
# Confermano che l'installazione e' davvero utilizzabile: la cartella di
# destinazione della musica deve esistere e accettare scritture, ffmpeg deve
# rispondere, e l'ambiente virtuale deve poter importare le librerie
# principali del progetto.
stampa_titolo "Verifiche finali"

if [[ -n "${MUSIC_DIR_DA_VERIFICARE:-}" ]]; then
    if [[ -d "$MUSIC_DIR_DA_VERIFICARE" ]]; then
        if [[ -w "$MUSIC_DIR_DA_VERIFICARE" ]]; then
            stampa_ok "Cartella musica ($MUSIC_DIR_DA_VERIFICARE) esistente e scrivibile."
        else
            stampa_errore "Cartella musica ($MUSIC_DIR_DA_VERIFICARE) esistente ma non scrivibile. Correggi i permessi con: chmod u+w \"$MUSIC_DIR_DA_VERIFICARE\""
        fi
    else
        echo "  La cartella musica ($MUSIC_DIR_DA_VERIFICARE) non esiste ancora."
        read -rp "  Vuoi crearla ora? [s/N]: " CREA_MUSIC_DIR
        if [[ "$CREA_MUSIC_DIR" =~ ^[sS]$ ]]; then
            if mkdir -p "$MUSIC_DIR_DA_VERIFICARE"; then
                stampa_ok "Cartella musica creata in $MUSIC_DIR_DA_VERIFICARE."
            else
                stampa_errore "Impossibile creare la cartella musica $MUSIC_DIR_DA_VERIFICARE."
            fi
        else
            stampa_errore "Cartella musica ($MUSIC_DIR_DA_VERIFICARE) non esiste: creala tu stesso oppure correggi MUSIC_DIR in data/.env."
        fi
    fi
else
    stampa_errore "Impossibile verificare la cartella musica: MUSIC_DIR non e' noto (risolvi prima i problemi su data/.env)."
fi

if command -v ffmpeg >/dev/null 2>&1 && ffmpeg -version >/dev/null 2>&1; then
    stampa_ok "ffmpeg risponde correttamente."
else
    stampa_errore "ffmpeg non risponde. Verifica l'installazione con: ffmpeg -version"
fi

if [[ "$VENV_OK" == true ]]; then
    if "$VENV_PYTHON" -c "import aiogram, yt_dlp" >/dev/null 2>&1; then
        stampa_ok "L'ambiente virtuale importa correttamente aiogram e yt_dlp."
    else
        stampa_errore "L'ambiente virtuale non riesce a importare aiogram o yt_dlp. Riprova con: \"$VENV_PYTHON\" -m pip install -r \"$PROJECT_ROOT/requirements.txt\""
    fi
else
    stampa_errore "Impossibile verificare aiogram e yt_dlp: l'ambiente virtuale non e' pronto (vedi i problemi segnalati sopra)."
fi

# --- Riepilogo conclusivo -------------------------------------------------
stampa_titolo "Riepilogo"

if [[ ${#ERRORI[@]} -eq 0 ]]; then
    echo "  Nessun problema bloccante rilevato."
else
    echo "  Problemi da risolvere (${#ERRORI[@]}):"
    for errore in "${ERRORI[@]}"; do
        echo "   - $errore"
    done
fi

if [[ ${#AVVISI[@]} -gt 0 ]]; then
    echo ""
    echo "  Avvisi non bloccanti (${#AVVISI[@]}):"
    for avviso in "${AVVISI[@]}"; do
        echo "   - $avviso"
    done
fi

echo ""
if [[ ${#ERRORI[@]} -eq 0 ]]; then
    echo "  Installazione completata. Per avviare il bot a mano:"
    echo "    cd \"$PROJECT_ROOT\" && \"$VENV_PYTHON\" main.py"
    echo ""
    echo "  Per avviare il bot automaticamente all'accensione, usa lo script"
    echo "  separato INSTALL_BOT/LINUX/RUN_BOT_STARTUP.sh."
else
    echo "  Risolvi i problemi elencati sopra, poi rilancia questo script."
    echo "  I controlli gia' a posto non verranno rifatti."
fi

echo ""
echo "  Attenzione: un solo processo per volta puo' fare polling con lo stesso"
echo "  token del bot. Se il bot e' gia' in esecuzione su un'altra macchina,"
echo "  spegnilo prima di avviare questa copia: altrimenti i due processi si"
echo "  contendono i messaggi in arrivo."

if [[ ${#ERRORI[@]} -eq 0 ]]; then
    exit 0
else
    exit 1
fi

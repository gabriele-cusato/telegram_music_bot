# core\services\restart.py
# Riavvia il processo del bot dopo che core.yt_dlp_update.yt_dlp_manager.run_update() ha installato
# una versione nuova di yt-dlp. Il motivo del riavvio: main.py importa core.services.youtube, che a
# sua volta importa yt_dlp, quindi la libreria è già caricata in memoria quando pip scrive la
# versione nuova su disco. In Python un modulo già importato non si ricarica (e importlib.reload su
# yt_dlp non è affidabile, avendo decine di sottomoduli già caricati): l'unico modo perché la
# versione nuova entri in funzione è far ripartire il processo da zero.
#
# Il riavvio usa os.execv: il processo corrente sostituisce la propria immagine con una nuova
# istanza di main.py, senza dipendere da chi lo sorveglia (systemd su Linux, l'attività pianificata
# su Windows). Su Linux l'identificativo di processo resta lo stesso, quindi per systemd non succede
# nulla di visibile. Su Windows os.execv non sostituisce davvero l'immagine del processo: avvia un
# processo nuovo e termina quello corrente, quindi il processo figlio sopravvive ma l'attività
# pianificata lo perde di vista. L'installazione di riferimento è il Raspberry (Linux).
#
# Ripresa della ricerca: message_handler scarta i messaggi con data anteriore all'avvio del bot
# (BOT_START_TIME), quindi anche se Telegram riconsegnasse il comando dopo il riavvio verrebbe
# ignorato. Prima di riavviare, la richiesta in corso (chat, utente, testo cercato, messaggio a cui
# rispondere) viene quindi salvata in un file JSON dentro data/; all'avvio successivo main.py legge
# quel file, lo cancella subito e rilancia la stessa ricerca nella stessa chat.

import asyncio
import json
import logging
import os
import sys

from core.config import DATA_PATH, logger, download_semaphore, CONCURRENT_DOWNLOAD_LIMIT
from core.services import post_save_command

PENDING_REQUEST_PATH = os.path.join(DATA_PATH, "pending_restart_request.json")

_REQUIRED_FIELDS = ("chat_id", "user_id", "requester_name", "query", "reply_to_message_id")

# Limite di attesa per i download in corso prima di riavviare: acquisire tutti i permessi del
# semaforo è il modo di accertarsi che nessun download sia ancora in esecuzione.
_SEMAPHORE_WAIT_TIMEOUT_SECONDS = 120
# Limite più largo per il comando post-salvataggio: sul Raspberry dell'utente è un rclone bisync
# verso pcloud, che può durare più a lungo di un download.
_POST_SAVE_WAIT_TIMEOUT_SECONDS = 600


def save_pending_request(chat_id, user_id, requester_name, query, reply_to_message_id):
    """Salva su disco i dati della ricerca in corso, perché la ripresa dopo il riavvio possa
    rieseguirla senza dipendere dal messaggio Telegram originale, che dopo il riavvio non è più
    raggiungibile (BOT_START_TIME lo scarterebbe comunque)."""
    payload = {
        "chat_id": chat_id,
        "user_id": user_id,
        "requester_name": requester_name,
        "query": query,
        "reply_to_message_id": reply_to_message_id,
    }
    try:
        with open(PENDING_REQUEST_PATH, "w", encoding="utf-8") as f:
            json.dump(payload, f)
    except Exception:
        logger.exception("Failed to save the pending search request before restarting.")


def read_and_clear_pending_request():
    """Legge la richiesta pendente e cancella subito il file, prima ancora di restituirne il
    contenuto: se la ricerca ripresa fallisse, un file rimasto sul disco farebbe ripartire la stessa
    ricerca a ogni avvio successivo. File assente, JSON non valido o campi mancanti sono trattati
    come "nessuna richiesta pendente", senza sollevare eccezioni."""
    if not os.path.exists(PENDING_REQUEST_PATH):
        return None

    try:
        with open(PENDING_REQUEST_PATH, "r", encoding="utf-8") as f:
            payload = json.load(f)
    except Exception:
        payload = None

    try:
        os.remove(PENDING_REQUEST_PATH)
    except OSError:
        pass

    if not isinstance(payload, dict) or not all(field in payload for field in _REQUIRED_FIELDS):
        return None

    return payload


async def _wait_downloads_finished():
    """Attende che nessun download sia più in corso, acquisendo tutti i permessi del semaforo dei
    download: se il limite di tempo scade il riavvio prosegue comunque, un download bloccato non
    deve impedirlo per sempre."""
    async def _acquire_all_permits():
        for _ in range(CONCURRENT_DOWNLOAD_LIMIT):
            await download_semaphore.acquire()

    try:
        await asyncio.wait_for(_acquire_all_permits(), timeout=_SEMAPHORE_WAIT_TIMEOUT_SECONDS)
    except asyncio.TimeoutError:
        logger.warning("Timed out waiting for active downloads to finish before restarting; restarting anyway.")


async def restart_process():
    """Attende che il lavoro in corso (download, comando post-salvataggio) sia finito, svuota i
    buffer del log e sostituisce il processo con una nuova istanza di main.py tramite os.execv.

    La connessione verso Telegram non viene chiusa qui di proposito. Chiuderla mentre il ciclo di
    polling ha una richiesta `getUpdates` ancora aperta (è una long poll, resta in attesa fino a
    trenta secondi) la fa morire di schianto, e aiogram lo registra come `ServerDisconnectedError`:
    una riga di errore a ogni riavvio, per una connessione che sta comunque per sparire insieme al
    processo. I socket di Python non sopravvivono a `os.execv`, quindi la chiusura avviene lo stesso.
    """
    await _wait_downloads_finished()
    await post_save_command.wait_for_completion(_POST_SAVE_WAIT_TIMEOUT_SECONDS)

    for handler in logging.root.handlers:
        handler.flush()

    python_executable = sys.executable
    script_path = os.path.abspath(sys.argv[0])
    os.execv(python_executable, [python_executable, script_path] + sys.argv[1:])

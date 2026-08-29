import os
import time
import logging
import subprocess
import sys
import asyncio
from typing import Optional

logger = logging.getLogger(__name__)

EXPIRATION_SECONDS = 24 * 3600 

LAST_UPDATE_TIMESTAMP_FILE = 'data/yt_dlp_last_update.txt'

def _summarize_pip_output(output: str) -> str:
    """Riduce l'output di pip alla sola riga che dice se una nuova versione è stata installata.

    pip stampa decine di righe (risoluzione delle dipendenze, download, cache) che nel log servono
    solo a nascondere le altre voci. L'unica informazione utile è la riga conclusiva "Successfully
    installed ...", presente soltanto quando qualcosa è davvero cambiato: se manca, yt-dlp era già
    all'ultima versione e non è stato toccato nulla.
    """
    lines = [line.strip() for line in (output or "").splitlines() if line.strip()]
    for line in reversed(lines):
        if line.startswith("Successfully installed"):
            return line
    return "already up to date, nothing installed"


def _update_yt_dlp_package() -> Optional[str]:
    """Lancia `pip install --upgrade yt-dlp` e ritorna il riepilogo dell'esito.

    Ritorna il riepilogo prodotto da `_summarize_pip_output` quando pip è andato a buon fine (lo
    stesso valore dice anche se una versione nuova è stata davvero installata, guardando se inizia
    con "Successfully installed"), `None` quando pip fallisce per qualunque motivo.
    """
    logger.info("Attempting to update yt-dlp via pip...")
    try:
        command = [sys.executable, "-m", "pip", "install", "--upgrade", "yt-dlp"]

        result = subprocess.run(
            command,
            check=True,
            capture_output=True,
            text=True
        )
        # Dell'output di pip si registra solo la riga conclusiva: riversarlo per intero produceva un
        # record di log lungo migliaia di caratteri (log_reader accoda al record precedente ogni riga
        # priva di timestamp), che rendeva impossibile rileggere quel tratto di log con `/log`.
        summary = _summarize_pip_output(result.stdout)
        logger.info(f"yt-dlp package update finished: {summary}")

        try:
            with open(LAST_UPDATE_TIMESTAMP_FILE, 'w') as f:
                f.write(str(int(time.time())))
            logger.debug(f"Updated timestamp file: {LAST_UPDATE_TIMESTAMP_FILE}")
        except Exception as e:
            logger.error(f"Failed to write update timestamp: {e}")

        return summary
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to update yt-dlp via pip. Stderr: {e.stderr} Stdout: {e.stdout}")
        return None
    except FileNotFoundError:
        logger.error("pip command not found. Ensure pip is correctly installed.")
        return None
    except Exception as e:
        logger.error(f"An unexpected error occurred during pip update: {e}")
        return None

def check_and_update_needed() -> bool:
    try:
        if not os.path.exists(LAST_UPDATE_TIMESTAMP_FILE):
            logger.info("Update timestamp file not found. Update is needed.")
            return True
        
        with open(LAST_UPDATE_TIMESTAMP_FILE, 'r') as f:
            last_update_time = int(f.read().strip())
        
        current_time = int(time.time())
        if current_time - last_update_time > EXPIRATION_SECONDS:
            logger.info(f"Last update was over {EXPIRATION_SECONDS // 3600} hours ago. Update is needed.")
            return True
        
        logger.info("yt-dlp check interval not yet expired. No update needed.")
        return False
    except Exception as e:
        logger.warning(f"Error checking update timestamp, forcing update attempt: {e}")
        return True

async def run_update() -> bool:
    """Aggiorna yt-dlp fuori dal thread principale ed è il punto di ingresso usato dal comando `music`.

    Ritorna `True` solo quando una versione nuova è stata installata e il timestamp del controllo è
    stato scritto correttamente: sono le uniche condizioni in cui il riavvio del bot (task2) è sia
    utile (c'è davvero una versione nuova da caricare) sia sicuro (senza timestamp aggiornato,
    `check_and_update_needed()` continuerebbe a rispondere `True` a ogni ricerca, producendo un
    ciclo di riavvii infinito). In ogni altro caso ritorna `False` e la ricerca prosegue con la
    versione di yt-dlp già presente, che funziona anche se non è la più recente.
    """
    # subprocess.run è bloccante e la richiesta a pip (il gestore di pacchetti Python) può impiegare
    # secondi per interrogare PyPI: girare in un thread separato evita di fermare l'intero bot.
    summary = await asyncio.to_thread(_update_yt_dlp_package)

    if summary is None:
        logger.warning("yt-dlp update failed via pip; continuing the search with the currently installed version.")
        return False

    if not summary.startswith("Successfully installed"):
        # yt-dlp era già alla versione più recente: nessun riavvio serve.
        return False

    if check_and_update_needed():
        # Il pacchetto è stato aggiornato ma la scrittura del timestamp è fallita (vedi
        # _update_yt_dlp_package): il riavvio viene rimandato per non innescare un ciclo continuo.
        logger.warning("yt-dlp was updated but the update timestamp could not be persisted; restart postponed.")
        return False

    return True


def initialize() -> bool:
    """Garantisce che yt-dlp sia importabile all'avvio del bot, senza aggiornarlo.

    Il controllo dell'intervallo delle 24 ore e l'eventuale aggiornamento vero e proprio avvengono
    ora dentro il flusso del comando `music`, tramite `run_update()`: farli qui bloccava l'avvio del
    bot per i secondi necessari alla richiesta a pip, anche quando nessun aggiornamento era dovuto.
    """
    try:
        import yt_dlp
        logger.info("yt-dlp package is available.")
        return True
    except ImportError:
        logger.error("The 'yt-dlp' package is not installed and cannot be imported.")
        logger.info("Attempting installation of yt-dlp since import failed...")
        if _update_yt_dlp_package() is not None:
             try:
                 import yt_dlp
                 return True
             except ImportError:
                 pass

        raise RuntimeError("Failed to ensure yt-dlp package is ready. Cannot run the bot.")
# core\services\post_save_command.py
# Esegue il comando shell configurato in POST_SAVE_COMMAND dopo che una canzone è stata salvata
# nella libreria musicale locale. Serve tipicamente a sincronizzare la cartella della musica con un
# servizio remoto (per esempio "rclone copy /home/raspuser/Music pcloud:Music"), senza bloccare il
# bot mentre la copia è in corso.
#
# Il comando è una riga arbitraria, eseguita dall'interprete di comandi del sistema: PowerShell su
# Windows, bash su Linux. Quindi sono ammessi pipe, redirezioni, variabili d'ambiente e più comandi
# concatenati, con la sintassi propria di quell'interprete. Il contenuto arriva dal file di
# configurazione data/.env, che è già sotto il controllo di chi amministra il bot: nessun input
# proveniente da Telegram entra in questa riga di comando.
#
# Flusso: ogni salvataggio chiama schedule_post_save_command(), che non lancia subito il comando ma
# avvia (se non c'è già) un'unica attività asyncio in background. Questa attende
# POST_SAVE_COMMAND_DELAY secondi, così più salvataggi ravvicinati producono una sola esecuzione,
# poi avvia il processo e ne attende la fine. Se altri salvataggi arrivano mentre il comando è in
# esecuzione, il comando viene rilanciato una volta sola al termine: i file nuovi non restano fuori
# dalla sincronizzazione e i processi non si accumulano.
#
# Il comando non riceve il percorso del file appena salvato: è pensato per lavorare sull'intera
# cartella della musica.

import asyncio
import os
from typing import List, Optional

from core.config import logger, POST_SAVE_COMMAND, POST_SAVE_COMMAND_DELAY


def _shell_invocation(command: str) -> List[str]:
    """Costruisce la chiamata all'interprete di comandi che esegue la riga configurata.

    Su Windows si usa PowerShell disattivando il profilo utente e le richieste interattive, perché
    il bot gira senza console a cui rispondere; su Linux si usa bash con -c, che accetta la riga
    così com'è.
    """
    if os.name == "nt":
        return ["powershell", "-NoProfile", "-NonInteractive", "-Command", command]
    return ["/bin/bash", "-c", command]


if POST_SAVE_COMMAND:
    logger.info(f"Post-save command enabled (delay {POST_SAVE_COMMAND_DELAY}s): {POST_SAVE_COMMAND}")

# Attività in background attualmente in attesa o in esecuzione, e richiesta di un ulteriore giro
# arrivata mentre il comando era già partito.
_runner_task: Optional[asyncio.Task] = None
_rerun_requested = False


def schedule_post_save_command():
    """Richiede l'esecuzione del comando dopo un salvataggio, senza attenderne la fine."""
    global _runner_task, _rerun_requested

    if not POST_SAVE_COMMAND:
        return

    # Un'attività già viva copre anche questo salvataggio: basta segnalare che servirà un altro
    # giro nel caso il comando sia già partito.
    if _runner_task is not None and not _runner_task.done():
        _rerun_requested = True
        return

    _runner_task = asyncio.create_task(_run_pending_command())


async def _run_pending_command():
    """Attende la finestra di raggruppamento, esegue il comando e lo ripete se nel frattempo sono
    arrivati altri salvataggi."""
    global _rerun_requested

    while True:
        await asyncio.sleep(POST_SAVE_COMMAND_DELAY)
        # Da qui in poi il comando sta per partire, quindi i salvataggi successivi devono
        # provocare un nuovo giro: la richiesta accumulata durante l'attesa è già coperta.
        _rerun_requested = False

        await _execute_command()

        if not _rerun_requested:
            return


async def _execute_command():
    """Lancia il comando come processo separato tramite la shell di sistema e registra l'esito."""
    try:
        process = await asyncio.create_subprocess_exec(
            *_shell_invocation(POST_SAVE_COMMAND),
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.PIPE,
        )
    except Exception:
        logger.exception(f"Failed to start post-save command: {POST_SAVE_COMMAND}")
        return

    # L'output di errore serve solo per il log: nulla di questo comando viene mostrato su Telegram.
    _, stderr = await process.communicate()

    if process.returncode == 0:
        logger.info("Post-save command completed successfully.")
        return

    error_output = stderr.decode(errors="replace").strip() if stderr else ""
    logger.error(f"Post-save command exited with code {process.returncode}: {error_output}")

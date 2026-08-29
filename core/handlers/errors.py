# core\handlers\errors.py
# Rete di sicurezza per le eccezioni che nessun comando ha gestito per conto proprio.
#
# aiogram consente di registrare un handler dedicato agli errori (`dp.error`): quando un handler di
# messaggi o di bottoni solleva un'eccezione che non intercetta da sé, la libreria non la propaga al
# ciclo di polling ma la consegna a questo handler. Il polling prosegue in ogni caso, quindi un
# comando che fallisce non ferma gli altri; senza questo modulo, però, l'errore finirebbe soltanto
# nel log del server e chi ha scritto il comando resterebbe davanti al silenzio del bot.
#
# La divisione dei compiti è la stessa già usata dai download: descrizione breve su Telegram,
# traceback completo nel log (`data/bot.log`, leggibile in chat con `/log error`). Qui il traceback
# viene scritto con `logger.exception`, che è ciò che aiogram farebbe da sé se questo handler non
# esistesse: registrarlo non fa quindi perdere nessuna informazione di diagnosi.
#
# I comandi che gestiscono già i propri errori non passano di qui: `message_handler` in messages.py
# continua a mostrare i suoi messaggi specifici (nessun risultato, brano troppo lungo, file troppo
# grande, errore di yt-dlp) senza che questo handler intervenga.

from typing import Optional

from aiogram.types import ErrorEvent, Update

from core import strings
from core.config import dp, logger


def _describe_update(update: Optional[Update]) -> str:
    """Compone una descrizione dell'aggiornamento Telegram che ha provocato l'errore, per il log.

    Serve a capire dal log quale comando ha fallito e in quale chat, senza doverlo dedurre dal solo
    traceback. Restituisce una descrizione generica quando l'aggiornamento non è un messaggio né la
    pressione di un bottone.
    """
    if update is None:
        return "unknown update"

    if update.message is not None:
        return f"message from chat {update.message.chat.id}: {update.message.text!r}"

    if update.callback_query is not None:
        return f"callback from user {update.callback_query.from_user.id}: {update.callback_query.data!r}"

    return f"update id={update.update_id}"


@dp.error()
async def unhandled_error_handler(event: ErrorEvent) -> bool:
    """Registra l'eccezione non gestita e avvisa in chat che il comando è fallito.

    Restituisce sempre True: per aiogram significa che l'errore è stato preso in carico, quindi il
    ciclo di polling continua a leggere gli aggiornamenti successivi e gli altri comandi restano
    utilizzabili.
    """
    logger.exception(
        f"Unhandled error while processing {_describe_update(event.update)}",
        exc_info=event.exception,
    )

    # L'avviso in chat è un di più rispetto al log: se anche l'invio fallisce (chat non più
    # raggiungibile, bot bloccato dall'utente, limite di frequenza di Telegram) l'errore originale è
    # comunque già registrato, quindi il fallimento dell'avviso viene solo annotato e non rilanciato.
    try:
        if event.update.message is not None:
            await event.update.message.answer(strings.ERROR_UNEXPECTED)
        elif event.update.callback_query is not None:
            await event.update.callback_query.answer(strings.ERROR_UNEXPECTED, show_alert=True)
    except Exception as send_failure:
        logger.warning(f"Could not notify the chat about the failed command: {send_failure}")

    return True

# main.py

import asyncio
import os
import logging
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from aiogram.types import BotCommand, BotCommandScopeAllPrivateChats, BotCommandScopeDefault
from core import strings
from core.config import dp, bot, logger, CONCURRENT_DOWNLOAD_LIMIT, ENABLE_INLINE_SEARCH, CHAT_DB_PATH, CHANNEL_DB_PATH
from core.services import storage
from core.services import restart
from core.services.music_library import prune_orphan_pending
from core.services.youtube import close_global_session
from core.handlers import messages, callbacks
# Importato per il solo effetto della registrazione: il modulo non espone nulla da chiamare, ma
# contiene l'handler decorato con @dp.error che raccoglie le eccezioni non gestite dai comandi.
from core.handlers import errors  # noqa: F401
from core.handlers.channel_posts import router as channel_router
from core.yt_dlp_update.yt_dlp_manager import initialize as initialize_yt_dlp 

if ENABLE_INLINE_SEARCH:
    from core.handlers.inline_mode import router as inline_router
    from core.services.inline_search.database import init_db as init_inline_db


async def _resume_pending_search(pending: dict, status):
    """Rilancia la ricerca interrotta dal riavvio (core.services.restart), nella stessa chat.

    Gira come attività separata avviata da `main()`, fuori dal ciclo che gestisce gli aggiornamenti
    Telegram: l'handler `@dp.error` intercetta solo le eccezioni nate dagli aggiornamenti in arrivo,
    non quelle di un'attività creata a mano, che altrimenti resterebbero silenziose.
    """
    try:
        await messages.search_and_deliver(
            pending["chat_id"], pending["user_id"], pending["requester_name"],
            pending["query"], pending["reply_to_message_id"], status
        )
    except Exception:
        logger.exception("Unhandled error while resuming the search after a yt-dlp restart.")


async def main():
    logger.info("Starting bot initialization...")
    
    if not bot.token:
        logger.error("BOT_TOKEN is not set in the .env file. The bot cannot start.")
        return

    try:
        if not initialize_yt_dlp():
            logger.critical("FATAL: Failed to ensure yt-dlp package is ready. Aborting.")
            return
    except RuntimeError as e:
        logger.critical(f"FATAL: yt-dlp initialization failed: {e}")
        return
        
    if ENABLE_INLINE_SEARCH:
        try:
            logger.info("Inline Search module enabled. Initializing databases...")
            await init_inline_db(CHANNEL_DB_PATH)
            await init_inline_db(CHAT_DB_PATH)
            dp.include_router(inline_router)
            logger.info("Inline router registered successfully.")
        except Exception as e:
            logger.critical(f"FATAL ERROR during Inline Search initialization: {e}")
            
    dp.include_router(channel_router)
    logger.info("Channel indexing router registered successfully.")
            
    storage.cleanup_expired_data()

    # pulire i file rimasti in temp/pending orfani da un riavvio del bot (info in cache già scadute o mai riscritte)
    removed = prune_orphan_pending(lambda k: storage.get_song_data(k) is not None)
    if removed > 0:
        logger.info(f"Removed {removed} orphan pending file(s) on startup.")

    logger.info(f"Starting polling with {CONCURRENT_DOWNLOAD_LIMIT} concurrent download limit.")

    # registrare il menu comandi Telegram (autocomplete + pulsante Menu): un eventuale
    # fallimento non deve impedire l'avvio del polling.
    try:
        await bot.set_my_commands(
            [BotCommand(command="music", description="Search & download a song: /music <query>")],
            scope=BotCommandScopeDefault(),
        )
        await bot.set_my_commands(
            [
                BotCommand(command="music", description="Search & download a song"),
                BotCommand(command="log", description="View recent bot logs"),
                BotCommand(command="priority", description="Set music folder priority"),
                BotCommand(command="delete", description="Find & delete duplicate songs"),
            ],
            scope=BotCommandScopeAllPrivateChats(),
        )
        logger.info("Bot commands menu registered successfully.")
    except Exception as e:
        logger.warning(f"Failed to register bot commands menu: {e}")

    # Ripresa dopo un riavvio dovuto a un aggiornamento di yt-dlp (core.services.restart): se una
    # ricerca era in corso al momento del riavvio, il suo esito riparte da sola nella stessa chat,
    # senza che l'utente debba riscrivere il comando `music`.
    pending = restart.read_and_clear_pending_request()
    if pending:
        await bot.send_message(pending["chat_id"], strings.STATUS_RESUME_AFTER_UPDATE.format(pending["query"]))
        status = await bot.send_message(pending["chat_id"], strings.STATUS_SEARCHING)
        # asyncio.create_task, non await: attenderla qui ritarderebbe l'avvio del polling e il bot
        # resterebbe muto per tutta la durata della ricerca e del download ripresi.
        asyncio.create_task(_resume_pending_search(pending, status))

    try:
        await dp.start_polling(bot)
    finally:
        await close_global_session()
        logger.warning("Bot finished polling and closing global HTTP session.")

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except (KeyboardInterrupt, SystemExit):
        logger.warning("Bot stopped!")
    except Exception as e:
        logger.critical(f"Critical error during bot runtime: {e}")
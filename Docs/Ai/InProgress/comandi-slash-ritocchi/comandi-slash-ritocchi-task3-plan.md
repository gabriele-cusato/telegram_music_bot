# Task 3 — Comandi con `/` (retro-compatibili) + menu Telegram (set_my_commands)

## Obiettivo
1. Tutti i comandi devono funzionare sia come ora (`log`, `priority`, `delete`, `music <query>`) sia con lo slash (`/log`, `/priority`, `/delete`, `/music <query>`), gestendo anche il suffisso `@nomebot` che Telegram aggiunge nei gruppi.
2. Registrare i comandi nel menu di Telegram con `set_my_commands()` all'avvio, così compaiono guidati (autocomplete + pulsante Menu) senza configurare BotFather a mano.

## Prerequisiti bloccanti
- Devono esistere: `core/handlers/messages.py` (handler `log`, `priority`, `delete`/dedup, e `message_handler` per `music`), `core/config.py` (per `bot`), `main.py`, `core/strings.py`. Se manca, fermarsi.
- Eseguire DOPO il Task 2 (il comando è già rinominato in `delete`).
- Non toccare file diversi.
- Version control: git in sola lettura lato orchestratore. Agent-Code NON committa/pusha.
- Verifica: `.venv/Scripts/python.exe -m py_compile`.

## Fatti verificati
- `messages.py`:
  - `_is_log_command`, `_is_priority_command`, `_is_dedup_command` (dopo Task 2 matcha "delete"): ognuno controlla `text.lower() == prefix or text.lower().startswith(prefix + " ")`.
  - Il comando `log` estrae gli argomenti: `args_text = "" if text.lower() == LOG_COMMAND_PREFIX else text[len(LOG_COMMAND_PREFIX)+1:].strip()`.
  - `message_handler` (catch-all `@dp.message()`): `if not text.lower().startswith(strings.COMMAND_PREFIX): return` con `COMMAND_PREFIX = "music "`; poi `query = text[len(COMMAND_PREFIX):].strip()`.
- `strings.py`: `COMMAND_PREFIX = "music "`, `LOG_COMMAND_PREFIX = "log"`, `PRIORITY_COMMAND_PREFIX = "priority"`, `DEDUP_COMMAND_PREFIX = "delete"` (dopo Task 2).
- `config.py`: espone `bot` (aiogram Bot). aiogram v3: `from aiogram.types import BotCommand, BotCommandScopeAllPrivateChats, BotCommandScopeDefault`; `await bot.set_my_commands(commands, scope=...)`.
- `main.py`: funzione `async def main()`; registra router, `storage.cleanup_expired_data()`, `prune_orphan_pending(...)`, poi `await dp.start_polling(bot)`. Punto adatto per `set_my_commands`: subito prima di `start_polling`.

## Sottoproblemi (in ordine)
1. `messages.py` — helper di parsing comando robusto:
   ```python
   def _split_command(text: str):
       # ritorna (name, args) dove name è il comando normalizzato senza '/' né '@bot'
       t = (text or "").strip()
       if t.startswith("/"):
           t = t[1:]
       first, _, rest = t.partition(" ")
       first = first.split("@", 1)[0].lower()  # rimuove eventuale @nomebot
       return first, rest.strip()
   ```
2. Aggiornare i filtri comando a usarlo:
   - `_is_log_command(message)`: `name, _ = _split_command(message.text); return name == strings.LOG_COMMAND_PREFIX`.
   - `_is_priority_command`: `... name == strings.PRIORITY_COMMAND_PREFIX`.
   - `_is_dedup_command`: `... name == strings.DEDUP_COMMAND_PREFIX` (= "delete").
3. Aggiornare l'estrazione argomenti dove serve:
   - `log_command_handler`: ricavare `args_text` da `_split_command(message.text)[1]` invece del calcolo attuale basato sul prefisso.
   - `priority`/`delete`: non usano argomenti, nessun cambto necessario oltre al filtro.
4. `message_handler` (music): accettare sia `music ...` sia `/music ...`:
   - Sostituire il controllo `startswith(COMMAND_PREFIX)` con: `name, query = _split_command(text)`; se `name != "music"` → `return` (come prima ritorna presto per i non-comando). `query` è già gli argomenti (stringa dopo `music`). Se `query` vuoto → `return` come oggi.
   - Attenzione: mantenere TUTTI gli altri controlli iniziali del `message_handler` invariati (BOT_START_TIME, chat consentite, BLOCKED_USER_IDS, anti-spam). Cambia solo il riconoscimento del comando e l'estrazione della query.
   - NB: `COMMAND_PREFIX` = "music " resta usato altrove? Verificare con Grep; se non più usato, si può lasciare la costante ma il match ora passa da `_split_command`.
5. `main.py` — registrare il menu comandi con `set_my_commands` subito prima di `await dp.start_polling(bot)`:
   - Import: `from aiogram.types import BotCommand, BotCommandScopeAllPrivateChats, BotCommandScopeDefault`.
   - Comando pubblico (tutte le chat), scope default:
     ```python
     await bot.set_my_commands(
         [BotCommand(command="music", description="Search & download a song: /music <query>")],
         scope=BotCommandScopeDefault(),
     )
     ```
   - Comandi privati (log/priority/delete), scope private chat:
     ```python
     await bot.set_my_commands(
         [
             BotCommand(command="music", description="Search & download a song"),
             BotCommand(command="log", description="View recent bot logs"),
             BotCommand(command="priority", description="Set music folder priority"),
             BotCommand(command="delete", description="Find & delete duplicate songs"),
         ],
         scope=BotCommandScopeAllPrivateChats(),
     )
     ```
   - Avvolgere in `try/except Exception` con `logger.warning` (una eventuale failure di set_my_commands non deve impedire l'avvio del polling). Loggare INFO a successo.

## Note
- Le descrizioni dei comandi in inglese, coerenti con le stringhe app.
- `set_my_commands` non invia messaggi in chat: registra solo la lista lato Telegram (autocomplete `/` + pulsante Menu). Idempotente ad ogni avvio.
- I comandi privati restano gated `chat.type == 'private'` negli handler: lo scope private del menu è solo cosmetico/di visibilità.

## Skill di codice
Caricare `coding-standard`. Commenti in italiano forma infinito.

## Verifica finale
- `.venv/Scripts/python.exe -m py_compile` su messages.py, main.py, strings.py.
- Import reale via venv: `.venv/Scripts/python.exe -c "import core.handlers.messages, main"` per verificare che gli import aiogram (BotCommand, scope) siano corretti.
- Aggiornare il worklog: spuntare i sottoproblemi, marcare `DA TESTARE`.

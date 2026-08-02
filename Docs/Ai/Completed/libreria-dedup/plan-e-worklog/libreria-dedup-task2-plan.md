# Task 2 — Comando `priority` + riordino con bottoni ▲▼

## Obiettivo
Comando testuale `priority` (solo chat privata) che mostra le sottocartelle di `MUSIC_DIR` nell'ordine di priorità con bottoni ▲/▼ per riordinare; ogni spostamento aggiorna `priority.txt`.

## Prerequisiti bloccanti
- Devono esistere: `core/handlers/messages.py`, `core/handlers/callbacks.py`, `core/strings.py`, e `core/services/library_priority.py` (creato nel Task 1 di questa feature). Se manca il modulo priorità, fermarsi.
- Eseguire DOPO il Task 1.
- Non toccare file diversi.
- Version control: git in sola lettura lato orchestratore. Agent-Code NON committa/pusha.
- Verifica: `python -m py_compile`.

## File da toccare
- `core/handlers/messages.py` — nuovo handler comando `priority`.
- `core/handlers/callbacks.py` — handler dei bottoni ▲▼.
- `core/strings.py` — stringhe.

## Fatti verificati (pattern da riusare)
- Comando `log` (Task 3 di logging-e-salvataggio) in `messages.py`: usa un filtro-funzione `_is_log_command(message)` passato a `@dp.message(...)`, registrato PRIMA di `message_handler` (catch-all), con gate `message.chat.type != 'private'` → return. Riusare lo stesso pattern per `priority`.
- `library_priority.get_order()` → lista cartelle in ordine di priorità (riconciliata). `library_priority.apply_move(index, delta)` → nuovo ordine dopo lo spostamento.
- `callback_data` deve stare sotto 64 byte: usare indici, non nomi cartella.
- Cap bottoni: in `callbacks.py` esiste già `MAX_SAVE_FOLDER_BUTTONS = 90` come riferimento per limitare le righe.

## Sottoproblemi (in ordine)
1. `strings.py`: aggiungere
   - `PRIORITY_COMMAND_PREFIX = "priority"`
   - `PRIORITY_PROMPT = "📂 Folder priority (top = highest). Use ▲▼ to reorder:"`
   - `PRIORITY_EMPTY = "No subfolders in the music library yet."`
   - etichette bottoni: `BUTTON_PRIO_UP = "▲"`, `BUTTON_PRIO_DOWN = "▼"`.
2. `messages.py`: 
   - `_is_priority_command(message)`: `text.lower() == strings.PRIORITY_COMMAND_PREFIX or text.lower().startswith(prefix + " ")`. Evitare falsi positivi con `music`/`log`.
   - Handler `@dp.message(_is_priority_command)` registrato tra gli altri handler-filtro (come `log`), PRIMA del catch-all. Gate: solo `message.chat.type == 'private'` (return silenzioso altrimenti); mantenere il blocco `BLOCKED_USER_IDS`.
   - Costruire la keyboard con un helper (vedi sotto) da `library_priority.get_order()`. Se ordine vuoto → rispondere `PRIORITY_EMPTY`. Inviare `PRIORITY_PROMPT` + keyboard.
3. Helper di rendering keyboard (in `callbacks.py`, esportato/riusabile), es. `build_priority_kb(order) -> InlineKeyboardMarkup`:
   - Per ogni `idx, folder` in `order[:MAX]` una riga con 3 bottoni:
     `[InlineKeyboardButton(f"📁 {folder}", callback_data="prio_noop")]`, `[BUTTON_PRIO_UP → f"prio_up_{idx}"]`, `[BUTTON_PRIO_DOWN → f"prio_down_{idx}"]`.
   - Se il numero di cartelle supera il cap, troncare e loggare un warning (come per il save picker).
4. `callbacks.py`: handler `@dp.callback_query(F.data.startswith("prio_"))`:
   - `prio_noop` → `await cq.answer()` (nessuna azione).
   - `prio_up_{idx}` / `prio_down_{idx}`: parsare idx; `delta = -1` per up, `+1` per down; `new_order = library_priority.apply_move(idx, delta)`; ri-renderizzare la keyboard con `build_priority_kb(new_order)` via `cq.message.edit_reply_markup(...)`; `await cq.answer()`.
   - Robustezza edit con `try/except (TelegramBadRequest, AttributeError, TypeError)` + `logger.warning` (come gli altri handler). Se l'edit non cambia nulla (Telegram "message is not modified") ignorare.
   - Non applicare `check_callback_spam` (il riordino non va perso). Il contesto è già privato (il messaggio è stato inviato in privata).

## Note
- Import: `from core.services import library_priority` (o import diretto delle funzioni) in `messages.py` e `callbacks.py`.
- Nessuna restrizione requester sui bottoni: il messaggio esiste solo nella chat privata di chi ha lanciato il comando.

## Skill di codice
Caricare `coding-standard`. Stringhe in inglese, commenti in italiano forma infinito.

## Verifica finale
- `python -m py_compile` su messages.py, callbacks.py, strings.py.
- Aggiornare il worklog: spuntare i sottoproblemi, marcare `DA TESTARE` il flusso runtime.

# Task 4 (RIVISTO) — Bottone "Save Srv" sul messaggio audio, niente conferma, save per ultimo

> Questo plan SOSTITUISCE la versione precedente (che introduceva un messaggio "Is this the right song? [Sì][No]"). Quel messaggio è stato REVOCATO. Parte di quel lavoro è già in `callbacks.py`/`strings.py` e va disfatta/riadattata come indicato sotto.

## Obiettivo
1. NESSUN messaggio di conferma aggiuntivo ("Is this the right song?"): resta solo la preview della canzone con i bottoni `[🎵 requester (info)]` e `[🔎 Not the right song?]`.
2. Aggiungere un terzo bottone `[💾 Save Srv]` al MESSAGGIO AUDIO ESISTENTE (senza rimuovere "Not right?"). Cliccandolo compare il picker delle cartelle → salvataggio su PC. (Cliccare la preview salva sul telefono, nativo Telegram, non ci riguarda.)
3. Il bottone "Not the right song?" NON deve più sparire dopo 60s: rimuovere il timer `remove_not_right_button`.
4. Finestra di salvataggio T = `INFO_EXPIRATION_HOURS` (staging file + pending GC).
5. Prune di `temp/pending` all'avvio per gli orfani da riavvio.

## Prerequisiti bloccanti
- Devono esistere ed essere leggibili: `core/handlers/callbacks.py`, `core/handlers/messages.py`, `core/strings.py`, `core/services/music_library.py`, `core/config.py`, `main.py`, `core/services/storage.py`. Se manca uno, fermarsi.
- Eseguire su codice che contiene GIÀ i Task 1/2/3 e la PRIMA versione del Task 4. Mantenere i log INFO del Task 2 e l'handler `log` del Task 3.
- Non toccare file diversi da quelli elencati.
- Version control: git in sola lettura lato orchestratore. Agent-Code NON committa/pusha.
- Target di verifica: `python -m py_compile` su ogni file toccato.

## File da toccare
- `core/strings.py`
- `core/handlers/callbacks.py`
- `core/handlers/messages.py`
- `core/services/music_library.py`
- `core/config.py` (opzionale, vedi sotto)
- `main.py`

## Fatti verificati (stato attuale, DOPO la prima versione del Task 4)
- `strings.py` contiene ora: `SONG_CONFIRM_PROMPT = "🎵 Is this the right song?"`, `BUTTON_CONFIRM_YES = "✅ Yes"`, `BUTTON_CONFIRM_NO = "❌ No"` (aggiunte dalla prima versione, DA RIMUOVERE). Restano utili: `SAVE_PROMPT = "💾 Save this song to a folder?"`, `BUTTON_SAVE_ROOT`, `BUTTON_DONT_SAVE`, `SAVED_TO`, `NOT_SAVED`, `SAVE_FAILED`, `BUTTON_REQUESTER = "🎵{}"`, `BUTTON_NOT_RIGHT = "🔎 Not the right song?"`.
- `callbacks.py` (dopo prima versione Task 4):
  - `_build_save_folder_kb(key)` esiste già (root + subfolders + Don't save) → RIUSARE.
  - `offer_disk_save(bot, chat_id, key, audio_file_path, reply_to_message_id)`: attualmente fa stage + invia il messaggio di conferma Yes/No + avvia `_pending_cleanup_timeout`. DA MODIFICARE: solo stage + avvia timer, NESSUN messaggio.
  - Esiste l'handler `confirm_song` (`F.data.startswith("confirm_")`): DA RIMUOVERE (sostituito da `save_srv`).
  - `save_to_directory` (`savedir_`): resta INVARIATO.
  - `_pending_cleanup_timeout(key)`: `await asyncio.sleep(PENDING_SAVE_TIMEOUT_SEC)` poi `discard_pending(key)`. `PENDING_SAVE_TIMEOUT_SEC = 300` (riga ~25).
  - Import da `core.config`: `dp, bot, logger, MAX_SONG_DURATION_SEC, ANTI_SPAM_CALLBACK_INTERVAL`. Aggiungere `INFO_EXPIRATION_HOURS`.
- `messages.py`:
  - kb del `send_audio` (nel `message_handler`): `[[BUTTON_REQUESTER info, BUTTON_NOT_RIGHT alt]]` (una riga, due bottoni).
  - `offer_disk_save(...)` chiamata subito dopo `set_song_data(key, sent.message_id, ...)`.
  - `remove_not_right_button(sent_message, key, full_name)` (righe ~36-56): dopo 60s edita la kb lasciando solo `[BUTTON_REQUESTER]`. Schedulata con `asyncio.create_task(remove_not_right_button(sent, key, message.from_user.full_name))`. DA RIMUOVERE (funzione + schedulazione).
- `callbacks.py` `choose_song`: dopo aver scelto un'alternativa, imposta kb `[[BUTTON_REQUESTER info]]` (solo info) e chiama `offer_disk_save`.
- `storage.get_song_data(key)` → `None` se il record non c'è o è scaduto (DB `songs_cache`, scadenza `INFO_EXPIRATION_HOURS` via `cleanup_expired_data`). Ritorna `{f"info_{key}": {...}, f"msg_{key}": message_id}` se presente.
- `main.py:50`: `storage.cleanup_expired_data()` all'avvio. `PENDING_SAVE_PATH = temp/pending` (config). Nessuna pulizia di quella cartella all'avvio.
- `music_library.py` importa solo da `core.config` (no import Telegram). Può importare `core.services.storage`? Sì senza cicli (storage non importa music_library). MA per la prune preferire un predicato passato da `main.py` per non accoppiare i moduli (vedi sotto).

## Sottoproblemi (in ordine)

### 1. strings.py
- RIMUOVERE `SONG_CONFIRM_PROMPT`, `BUTTON_CONFIRM_YES`, `BUTTON_CONFIRM_NO` (non più usate).
- AGGIUNGERE `BUTTON_SAVE_SRV = "💾 Save Srv"`.
- (Facoltativo) `SAVE_EXPIRED = "⌛ This song can no longer be saved."` per il click su Save Srv scaduto.

### 2. callbacks.py — timer e offer_disk_save
- In cima: sostituire la costante fissa con quella da config, es.:
  ```python
  from core.config import ..., INFO_EXPIRATION_HOURS
  PENDING_SAVE_TIMEOUT_SEC = INFO_EXPIRATION_HOURS * 3600
  ```
- `offer_disk_save(bot, chat_id, key, audio_file_path, reply_to_message_id)`: FIRMA INVARIATA (così `messages.py`/`choose_song` non cambiano nella chiamata). Corpo:
  - `staged_path = stage_pending_file(key, audio_file_path)`; se None → return.
  - `logger.info(f"Staged song for save, key {key} in chat {chat_id}")` (coerente Task 2; il log "Save prompt offered" precedente non ha più senso).
  - `asyncio.create_task(_pending_cleanup_timeout(key))`.
  - NON inviare alcun messaggio. Il parametro `reply_to_message_id` diventa inutilizzato: lasciarlo nella firma (retrocompatibilità chiamanti) e ignorarlo.
- `_pending_cleanup_timeout(key)`: invariato nella logica (sleep `PENDING_SAVE_TIMEOUT_SEC` → `discard_pending(key)`), ora T ≈ 10h.

### 3. callbacks.py — rimuovere confirm_song, aggiungere save_srv
- RIMUOVERE l'handler `confirm_song` (`F.data.startswith("confirm_")`) e ogni riferimento alle stringhe confirm.
- NUOVO handler `@dp.callback_query(F.data.startswith("savesrv_"))` → `async def save_srv(cq)`:
  - Non decorare con `check_callback_spam`.
  - `key = cq.data[len("savesrv_"):]`.
  - `data_storage = get_song_data(key)`; se None → `await cq.answer(strings.INFO_EXPIRED, show_alert=True)`; `discard_pending(key)`; return.
  - Verificare che il file pending esista ancora: usare un nuovo helper `pending_exists(key)` (vedi sottoproblema 5). Se non esiste → `await cq.answer(strings.SAVE_EXPIRED, show_alert=True)` (o INFO_EXPIRED); return.
  - Inviare il messaggio col picker in reply all'audio:
    ```python
    if cq.message:
        await bot.send_message(
            chat_id=cq.message.chat.id,
            text=strings.SAVE_PROMPT,
            reply_markup=_build_save_folder_kb(key),
            reply_to_message_id=cq.message.message_id,
        )
    logger.info(f"Save folder picker offered for key {key}")
    await cq.answer()
    ```
  - Robustezza edit/send con `try/except (TelegramBadRequest, AttributeError, TypeError)` + `logger.warning`, come gli altri handler.
- `savedir_` (`save_to_directory`): INVARIATO, continua a operare sul messaggio del picker appena inviato.

### 4. messages.py — bottone Save Srv, rimuovere remove_not_right_button
- Nella kb del `send_audio` (`message_handler`), aggiungere una riga col bottone Save:
  ```python
  kb = InlineKeyboardMarkup(inline_keyboard=[
      [InlineKeyboardButton(text=btn_text, callback_data=f"info_{key}"),
       InlineKeyboardButton(text=strings.BUTTON_NOT_RIGHT, callback_data=f"alt_{key}")],
      [InlineKeyboardButton(text=strings.BUTTON_SAVE_SRV, callback_data=f"savesrv_{key}")],
  ])
  ```
- RIMUOVERE la funzione `remove_not_right_button` (righe ~36-56) e la sua schedulazione `asyncio.create_task(remove_not_right_button(...))` (riga ~157, ora shiftata). Così "Not right?" resta finché i dati non scadono.
- La chiamata a `offer_disk_save(...)` resta al suo posto (fa lo stage).

### 5. callbacks.py `choose_song` + music_library helper
- In `choose_song`, dopo la scelta dell'alternativa, la kb finale deve includere il bottone Save Srv:
  ```python
  kb = InlineKeyboardMarkup(inline_keyboard=[
      [InlineKeyboardButton(text=btn_text, callback_data=f"info_{key}")],
      [InlineKeyboardButton(text=strings.BUTTON_SAVE_SRV, callback_data=f"savesrv_{key}")],
  ])
  ```
  (mantiene la logica esistente che qui non ripristina "Not right?"). `offer_disk_save` continua a essere chiamata per lo stage.
- `music_library.py`: aggiungere helper `pending_exists(key) -> bool` che ritorna `os.path.exists(os.path.join(PENDING_SAVE_PATH, f"{key}.mp3"))`.

### 6. main.py — prune di temp/pending all'avvio
- `music_library.py`: aggiungere `prune_orphan_pending(is_valid_key) -> int`:
  - Elenca i file `*.mp3` in `PENDING_SAVE_PATH`; per ciascuno estrae `key = nome senza .mp3`; se `not is_valid_key(key)` → rimuove il file. Ritorna il conteggio rimossi. Best-effort, non solleva; logga a INFO il totale rimosso se > 0.
- `main.py`: dopo `storage.cleanup_expired_data()` (riga 50), aggiungere:
  ```python
  from core.services.music_library import prune_orphan_pending
  removed = prune_orphan_pending(lambda k: storage.get_song_data(k) is not None)
  ```
  (import in cima al file, non inline se lo stile del progetto lo preferisce). Logga il risultato.

## Verifica di coerenza
- `messages.py` e `choose_song` continuano a chiamare `offer_disk_save` con la stessa firma.
- Nessun residuo delle stringhe/handler di conferma.
- `savedir_` intatto e funzionante sul messaggio prodotto da `save_srv`.
- `INFO_EXPIRATION_HOURS` importato dove serve.

## Skill di codice
Caricare `coding-standard`. Stringhe app in inglese, commenti in italiano forma infinito.

## Verifica finale del task
- `python -m py_compile` su ogni file toccato, nessun errore.
- Aggiornare il worklog: spuntare i sottoproblemi, marcare `DA TESTARE` il flusso runtime.

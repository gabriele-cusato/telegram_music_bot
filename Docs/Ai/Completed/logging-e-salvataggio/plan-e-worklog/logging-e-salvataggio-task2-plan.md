# Task 2 — Logging su file + logInfo sulle operazioni

## Obiettivo
1. I `logger.info` devono finire anche in `data/bot.log` (oggi il file registra solo ERROR+). Console resta invariata (INFO).
2. Aggiungere log INFO sulle operazioni di salvataggio in libreria, così dal log si capisce cosa è successo (stage, prompt, scelta cartella, file salvato con path, skip, cleanup timeout).

## Prerequisiti bloccanti
- Devono esistere ed essere leggibili: `core/config.py`, `core/services/music_library.py`, `core/handlers/callbacks.py`, `core/handlers/messages.py`. Se manca uno, fermarsi senza modificare.
- Non toccare file diversi da quelli elencati in "File da toccare".
- Non leggere/modificare cartelle o file marcati sensibili (nessuno noto).
- Version control: git in sola lettura, lo usa l'orchestratore. Agent-Code NON committa/pusha.
- Target di verifica: import/compile dei moduli Python senza errori.

## File da toccare
- `core/config.py` — livello del `file_handler`.
- `core/services/music_library.py` — log INFO nelle operazioni FS.
- `core/handlers/callbacks.py` — log INFO nel flusso salvataggio.
- `core/handlers/messages.py` — (eventuale) log INFO mancante nel flusso salvataggio; NON duplicare quelli già presenti dal commit precedente.

## Fatti verificati (stato attuale)
- `core/config.py:25-46`: `file_handler = RotatingFileHandler(LOG_FILE, maxBytes=10MB, backupCount=3, encoding='utf-8')`; `file_handler.setLevel(logging.ERROR)` (riga 35); `console_handler = StreamHandler(sys.stdout)` senza setLevel esplicito; `logging.basicConfig(level=logging.INFO, handlers=[file_handler, console_handler])`. Quindi root a INFO, console eredita INFO, ma il file filtra a ERROR.
- `LOG_FILE = data/bot.log` (riga 18).
- `music_library.py`: `stage_pending_file` logga solo warning/exception su fallimento; `save_pending_to_folder` non logga nulla; `discard_pending` logga solo su exception; `list_subfolders` logga warning/exception.
- `callbacks.py`: `offer_disk_save` (righe 37-62) non logga il successo; `save_to_directory` (righe 322-384) logga solo warning/exception, non il successo del salvataggio.
- `messages.py`: già presenti dal commit precedente i log INFO su query ricevuta, top result, sending/sent audio. NON riaggiungerli.

## Sottoproblemi (in ordine)
1. `core/config.py:35`: cambiare `file_handler.setLevel(logging.ERROR)` in `file_handler.setLevel(logging.INFO)`. Aggiornare/aggiungere commento (forma all'infinito) sul perché: "portare INFO anche su file per la cronologia leggibile offline / comando log". Lasciare invariato tutto il resto della config.
2. `music_library.py`:
   - `save_pending_to_folder`: prima del `return dest_path`, `logger.info(f"Song saved to disk: {dest_path}")`.
   - `stage_pending_file`: dopo la copia riuscita, `logger.info(f"Staged pending file for key {key}: {dest_path}")`.
   - `discard_pending`: quando rimuove davvero il file, `logger.info(f"Discarded pending file for key {key}")`.
3. `callbacks.py`:
   - `offer_disk_save`: dopo aver inviato il messaggio picker, `logger.info(f"Save prompt offered for key {key} in chat {chat_id}")`.
   - `save_to_directory`: sul ramo `skip`, `logger.info(f"User skipped saving for key {key}")`; sul successo (dopo `save_pending_to_folder`, prima di `cq.answer("Saved")`), `logger.info(f"Song saved for key {key} to folder: {subfolder or 'MUSIC_DIR'}")`.
   - `_pending_cleanup_timeout`: prima/dopo il discard su timeout, `logger.info(f"Pending save timeout expired for key {key}, discarding")`.
4. `messages.py`: verificare che nel flusso salvataggio non manchi nulla; NON duplicare i log già presenti. Nessuna aggiunta se già coperto.

## Note
- Le stringhe di log in inglese, coerenti con quelle esistenti. Commenti in italiano forma infinito.
- NB coordinamento con Task 4: Task 4 sposterà il momento in cui `offer_disk_save` viene chiamato e introdurrà la conferma Sì/No. Task 2 va eseguito PRIMA di Task 4; se Task 4 rinomina/sposta funzioni, manterrà i log qui aggiunti.

## Skill di codice
Caricare `coding-standard`.

## Verifica finale del task
- Import/compile dei moduli senza errori.
- Aggiornare il worklog: spuntare i sottoproblemi.

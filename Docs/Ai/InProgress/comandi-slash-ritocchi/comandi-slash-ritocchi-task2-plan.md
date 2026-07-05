# Task 2 — Rinominare `dedup` in `delete` + elenco file eliminati

## Obiettivo
1. Il comando di deduplica non si chiama più `dedup` ma `delete` (più esplicativo).
2. Il messaggio finale, dopo la cancellazione, deve elencare **quali** file sono stati eliminati (cartella + nome), non solo il conteggio.

## Prerequisiti bloccanti
- Devono esistere: `core/handlers/messages.py` (handler comando dedup, `_is_dedup_command`), `core/handlers/callbacks.py` (`dedup_callback`, `build_dedup_session`, `_build_dedup_kb`, store `dedup_sessions`), `core/strings.py`. Se manca, fermarsi.
- Non toccare file diversi.
- Version control: git in sola lettura lato orchestratore. Agent-Code NON committa/pusha.
- Verifica: `.venv/Scripts/python.exe -m py_compile`.

## Fatti verificati
- `strings.py`: `DEDUP_COMMAND_PREFIX = "dedup"`, `DEDUP_DONE = "✅ Deleted {} file(s)."`, più `DEDUP_NONE`, `DEDUP_HEADER`, `DEDUP_CANCELLED`, `DEDUP_TRUNCATED`, bottoni.
- `messages.py`: `_is_dedup_command(message)` matcha `"dedup"`/`"dedup "`; handler invia sessione via `build_dedup_session`.
- `callbacks.py`: nella sessione ogni candidato ha `{"path", "label" (= "{name} @ {folder}"), "selected"}`. In `dedup_callback`, ramo `dd_ok`: itera i candidati `selected=True`, `os.remove(path)`, `deleted += 1`, poi `edit_text(DEDUP_DONE.format(deleted))`.

## Sottoproblemi (in ordine)
1. `strings.py`:
   - Cambiare `DEDUP_COMMAND_PREFIX` da `"dedup"` a `"delete"`.
   - Sostituire `DEDUP_DONE` con un formato a due parti, es.:
     - `DEDUP_DONE_HEADER = "✅ Deleted {} file(s):"`
     - il corpo sarà la lista dei file eliminati, una per riga.
   - (Se serve) `DEDUP_DONE_NONE = "No files deleted."` per il caso in cui l'utente confermi senza selezioni.
2. `messages.py` `_is_dedup_command`: matchare `"delete"`/`"delete "` invece di `"dedup"`. (I nomi interni di funzioni/handler possono restare invariati; cambia solo la parola-comando riconosciuta.)
   - Attenzione: NON confondere con altri comandi; `delete` è esatto.
3. `callbacks.py` `dedup_callback`, ramo `dd_ok`:
   - Mentre cancella, raccogliere le etichette dei file effettivamente eliminati in una lista, es. `deleted_labels.append(candidate["label"])` dopo `os.remove` riuscito.
   - Comporre il messaggio finale: se `deleted_labels` non vuoto → `header = DEDUP_DONE_HEADER.format(len(deleted_labels))` + `"\n".join(f"🗑 {lbl}" for lbl in deleted_labels)`; altrimenti `DEDUP_DONE_NONE`.
   - `edit_text(messaggio, reply_markup=None)`.
   - Cap lunghezza: se il messaggio supera ~3800 char (molti file), troncare la lista e aggiungere una riga "...". (Riusare eventualmente lo stesso limite usato altrove.)

## Note
- Il comportamento di ricerca duplicati resta invariato: `delete` avvia lo stesso flusso (trova duplicati cross-folder, mostra la lista deselezionabile, conferma).
- La sicurezza è invariata: si cancella solo ciò che è `selected=True`; la copia "keep" non è mai candidata.

## Skill di codice
Caricare `coding-standard`. Stringhe in inglese, commenti in italiano forma infinito.

## Verifica finale
- `.venv/Scripts/python.exe -m py_compile` su messages.py, callbacks.py, strings.py.
- Aggiornare il worklog: spuntare i sottoproblemi, marcare `DA TESTARE`.

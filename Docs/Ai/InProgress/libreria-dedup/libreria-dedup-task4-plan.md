# Task 4 — Fix "message is too long" nel delete + invariante di sicurezza

## Obiettivo
1. Il comando `delete` (dedup) non deve più fallire con `Bad Request: message is too long` quando ci sono molti duplicati: cappare ANCHE il testo (righe dei gruppi), non solo i bottoni.
2. **Invariante di sicurezza (critico):** possono essere cancellati SOLO i brani effettivamente mostrati nella lista. Se la lista viene troncata, i candidati non mostrati NON devono mai entrare nella sessione e quindi non devono mai essere cancellabili.
3. Se l'invio della lista fallisce comunque, mostrare un messaggio di fallback su Telegram (niente errore silenzioso).

## Prerequisiti bloccanti
- Devono esistere: `core/handlers/callbacks.py` (`build_dedup_session`, `_build_dedup_kb`, `dedup_callback`, store `dedup_sessions`), `core/handlers/messages.py` (`dedup_command_handler`), `core/strings.py`. Se manca, fermarsi.
- Non toccare file diversi.
- Version control: git in sola lettura lato orchestratore. Agent-Code NON committa/pusha.
- Verifica: `.venv/Scripts/python.exe -m py_compile`.

## Causa dell'errore (verificata dal traceback)
- `dedup_command_handler` (messages.py:208): `await message.answer(text, reply_markup=kb)` → `TelegramBadRequest: message is too long`.
- `build_dedup_session` compone `text` con una riga per OGNI gruppo (`🎵 {name} — keep in {folder}`). Con molti gruppi il testo supera il limite Telegram di **4096 caratteri**.
- Il cap attuale `MAX_DEDUP_CANDIDATES = 60` limita solo i **bottoni** (candidati), NON il testo → il testo cresce senza limite.
- Il comando non ha try/except sull'invio → l'errore è finito solo nel log, niente in chat.

## Fatti sul codice attuale
- `build_dedup_session(groups)`: cicla i gruppi; per ogni gruppo aggiunge `text_lines.append("🎵 {keep.name} — keep in {keep.folder}")` e per ogni candidato (fino a `MAX_DEDUP_CANDIDATES`) crea `candidates[cid] = {"path","label","selected":True}`. Ritorna `(sid, text, kb)`; salva `dedup_sessions[sid] = {"candidates": candidates}`.
- `_build_dedup_kb(sid, session)`: un bottone toggle per candidato in `session["candidates"]` + confirm/cancel.
- `dedup_callback` ramo `dd_ok`: cancella SOLO i candidati con `selected=True` presenti in `session["candidates"]`. → **Quindi la sicurezza dipende dal fatto che nella sessione ci siano solo i candidati mostrati.**

## Sottoproblemi (in ordine)
1. `build_dedup_session` — costruzione con doppio budget e invariante:
   - Definire due budget: `TEXT_CHAR_BUDGET` (es. 3500, per stare sotto 4096 lasciando margine a header e nota di troncamento) e `MAX_DEDUP_CANDIDATES` (bottoni, resta 60).
   - Costruire testo e candidati **incrementalmente**, gruppo per gruppo, candidato per candidato:
     - Per ogni gruppo, la sua "keep line" viene aggiunta al testo SOLO se poi si aggiunge almeno un suo candidato.
     - Aggiungere un candidato solo se: (a) `len(candidates) < MAX_DEDUP_CANDIDATES` E (b) la lunghezza corrente del testo + eventuale nuova keep-line resta sotto `TEXT_CHAR_BUDGET`.
     - Ogni candidato aggiunto a `candidates` DEVE corrispondere a un bottone reso da `_build_dedup_kb` (lo è già, perché la kb si costruisce da `session["candidates"]`).
     - Appena un budget è raggiunto: impostare `truncated = True` e **fermarsi** (break dai cicli), senza aggiungere altri candidati.
   - **Invariante da garantire e commentare nel codice:** `session["candidates"]` contiene ESATTAMENTE i candidati mostrati come bottoni. Nessun candidato non mostrato entra nella sessione → `dd_ok` non può cancellarlo.
   - Se `truncated`, aggiungere in coda al testo `strings.DEDUP_TRUNCATED` (già esistente) o una nota tipo "showing the first N; run /delete again after deleting these".
   - Nota: la kb va costruita DOPO aver finalizzato `candidates`, così bottoni e sessione coincidono.
2. `messages.py` `dedup_command_handler` — invio robusto:
   - Avvolgere `await message.answer(text, reply_markup=kb)` in `try/except TelegramBadRequest as e`: su errore, `logger.error(...)` e inviare un messaggio di fallback breve (es. una nuova stringa `DEDUP_SEND_FAILED = "⚠️ Could not show the duplicates list: {}"` con `html.escape`/troncamento, oppure un messaggio generico). Importare `TelegramBadRequest` se non già importato in messages.py.
   - In caso di fallimento dell'invio, eliminare la sessione appena creata (`dedup_sessions.pop(sid, None)`) per non lasciare candidati "orfani" cancellabili da una kb mai mostrata. (Recuperare `sid` come primo elemento del ritorno di `build_dedup_session`.)
3. (Difensivo, opzionale ma consigliato) In `dedup_callback` `dd_ok`, prima di `os.remove`, verificare che il path sia effettivamente sotto `MUSIC_DIR`/una sottocartella (evita cancellazioni fuori posto se un path fosse malformato). Non obbligatorio se il resto è corretto; NON aggiungere logica di scope non richiesta oltre a un controllo `os.path.exists` + path dentro MUSIC_DIR.

## Verifica dell'invariante (obbligatoria nel test scratchpad)
- Prova `build_dedup_session` con MOLTI gruppi/candidati finti (in memoria) tali da superare i budget: verificare che
  - il testo prodotto resti sotto ~3900 char,
  - `len(session["candidates"])` == numero di bottoni resi da `_build_dedup_kb`,
  - i candidati oltre il taglio NON siano presenti in `session["candidates"]`.
- Non serve Telegram: costruire `groups` finti come liste di dict con le stesse chiavi usate da `find_duplicate_groups` (`{"keep": {...}, "candidates": [{"path","name","folder"}, ...]}`).

## Skill di codice
Caricare `coding-standard`. Stringhe in inglese, commenti in italiano forma infinito.

## Verifica finale
- `.venv/Scripts/python.exe -m py_compile core/handlers/callbacks.py core/handlers/messages.py core/strings.py`.
- Prova scratchpad dell'invariante (sopra).
- Aggiornare il worklog: spuntare i sottoproblemi, marcare `DA TESTARE`.

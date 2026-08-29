# aggiornamento-e-robustezza — task3 — Errori isolati e `/log` che non esplode

## Prerequisiti bloccanti
- `core/handlers/messages.py`, `core/yt_dlp_update/yt_dlp_manager.py`, `core/strings.py`, `main.py` — da modificare.
- `data/` è vietata: contiene il `.env` con il token reale.
- Version control: git in **sola lettura** (`git status`, `git diff`, `git log`, `git show`).
- Verifica: `.venv\Scripts\python.exe -m py_compile <file>` (su Windows non c'è venv di progetto: usare `python -m py_compile`).

## Obiettivo
Tre difetti indipendenti che rendono fragile la diagnosi degli errori:

1. **`/log` fallisce sui record lunghi.** `_build_log_chunks` (`messages.py:97`) accumula i record in blocchi da `LOG_MAX_CHUNK_CHARS` (3800), ma non spezza mai il **singolo** record: alla riga 110 il record viene aggiunto al blocco comunque, anche quando da solo supera la soglia. Il blocco finisce in `<pre>…</pre>` a riga 150 e Telegram rifiuta con `Bad Request: message is too long` (limite 4096 caratteri).
2. **Il log si intasa con l'output di pip.** `yt_dlp_manager.py:24` scrive `f"yt-dlp package updated successfully: {result.stdout}"`, cioè l'intero output di pip su più righe. `log_reader._parse_records` accoda al record precedente ogni riga senza timestamp (`log_reader.py:68`), quindi tutto quell'output diventa **un solo record** enorme: è la causa concreta del difetto 1.
3. **Nessuna gestione centralizzata delle eccezioni.** Nel progetto non esiste alcun handler `@dp.error` (verificato: zero occorrenze in tutto il repo). Quando un comando solleva un'eccezione non gestita, aiogram la registra nel log e prosegue con il polling, ma **l'utente in chat non vede niente** e resta davanti al silenzio.

## Comportamento nativo che viene modificato — già approvato dall'utente
Registrare un handler `@dp.error` **sostituisce** la gestione predefinita di aiogram, che oggi scrive da sé il traceback completo nel log. Vincolo approvato: dentro l'handler si usa `logger.exception`, così il traceback originale resta integro in `data/bot.log` ed è leggibile con `/log`. In chat va solo un messaggio breve. Nessun'altra eccezione viene inghiottita.

## File da toccare
- `core/handlers/messages.py` — solo `_build_log_chunks`.
- `core/handlers/errors.py` — **nuovo**, contiene l'handler `@dp.error`.
- `core/yt_dlp_update/yt_dlp_manager.py` — solo la riga di log dell'esito di pip.
- `core/strings.py` — nuova stringa per il messaggio di errore generico.
- `main.py` — import del nuovo modulo degli errori, perché l'handler si registri.

## Sottoproblemi, nell'ordine

1. **`_build_log_chunks` spezza anche il record singolo.** Prima di accodare un record al blocco corrente, se il record da solo supera `LOG_MAX_CHUNK_CHARS`, va tagliato in pezzi da al massimo `LOG_MAX_CHUNK_CHARS` caratteri, ciascuno dei quali diventa un blocco a sé.
   **Trappola da evitare**: i record sono già passati da `html.escape` (riga 99), quindi contengono entità come `&amp;` e `&lt;`. Tagliare a metà un'entità produce HTML rotto e Telegram rifiuta il messaggio. Il taglio va quindi fatto **prima** dell'escape, sul testo grezzo, e l'escape applicato ai pezzi risultanti.
2. **Esito di pip conciso.** `_update_yt_dlp_package` non deve più riversare `result.stdout` nel log. Registrare solo l'esito e la versione: ricavare la versione installata da `yt_dlp.version.__version__` dopo l'aggiornamento, oppure dall'ultima riga utile di pip. Nessun output multiriga.
3. **Handler `@dp.error` in `core/handlers/errors.py`.** Riceve un `ErrorEvent` (aiogram 3.22). Deve:
   - registrare l'eccezione con `logger.exception`, includendo l'identificativo dell'aggiornamento Telegram e, quando disponibile, la chat e il testo del comando che l'ha provocata;
   - rispondere in chat con un messaggio breve, quando dall'evento si riesce a risalire a una chat (`event.update.message` o `event.update.callback_query`). Se non c'è chat a cui rispondere, ci si limita al log;
   - **non propagare oltre**: l'handler restituisce `True` perché il polling prosegua e gli altri comandi continuino a funzionare;
   - proteggere l'invio del messaggio con un `try/except` proprio: se anche la risposta di errore fallisce (chat inesistente, bot bloccato), non deve generare una seconda eccezione a cascata.
4. **Stringa nuova in `strings.py`**, sullo stile di quelle esistenti (inglese, prefisso con emoji): messaggio breve che dice che il comando è fallito e che il dettaglio è nel log, leggibile con `/log error`.
5. **Registrazione dell'handler**: `main.py` deve importare `core.handlers.errors` insieme agli altri handler (riga 15), altrimenti il decoratore non viene mai eseguito e l'handler non esiste.
6. **Verifica di sintassi** con `py_compile` su tutti i file toccati.

## Regole
- Commenti in italiano, presente indicativo in terza persona. I commenti esistenti non si riscrivono.
- Non toccare `log_reader.py`: l'accodamento delle righe di traceback a un unico record è voluto e va conservato.
- Non cambiare `LOG_MAX_CHUNK_CHARS`, `LOG_MAX_MESSAGES` né `LOG_DEFAULT_LIMIT`.
- Non introdurre dipendenze nuove.

## Al termine
Aggiornare `aggiornamento-e-robustezza-task3-worklog.md`: spuntare l'avanzamento e aggiungere il tag `DA TESTARE`. La sezione "Test" la compila l'orchestratore dopo le prove dell'utente.

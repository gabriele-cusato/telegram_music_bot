# aggiornamento-e-robustezza — task2 — Riavvio dopo l'aggiornamento e ripresa della ricerca

## Prerequisiti bloccanti
- `core/handlers/messages.py`, `core/services/post_save_command.py`, `main.py`, `core/strings.py` — da modificare.
- `core/services/restart.py` — **nuovo file** da creare.
- `core/config.py`, `INSTALL_BOT/LINUX/musicbot.service`, `INSTALL_BOT/WIN/RUN_BOT_STARTUP.ps1` — solo da **leggere**.
- `data/` è **vietata**: contiene il `.env` con il token reale. Il codice può comporre percorsi dentro `data/` e scriverci il file di ripresa, ma il file `.env` non va né letto né toccato.
- Version control: git in **sola lettura**.
- Verifica: `.venv\Scripts\python.exe -m py_compile <file>`.
- Da implementare **dopo** il task1, nella stessa sessione: usa la funzione `run_update()` introdotta lì.

## Obiettivo
Quando il task1 stabilisce che una versione nuova di yt-dlp è stata installata, il processo deve ripartire perché la versione nuova entri in funzione (yt-dlp è già caricato in memoria, vedi il task1). Il riavvio deve:
- non troncare lavoro in corso;
- non perdere la ricerca che lo ha innescato: dopo il riavvio la ricerca riparte da sola e i risultati arrivano nella stessa chat, senza che l'utente debba riscrivere il comando.

## Fatti già verificati — non ri-esplorare

### Perché la ripresa richiede un file e non basta Telegram
`message_handler` scarta i messaggi con data anteriore all'avvio del bot (`BOT_START_TIME`, `messages.py:226`). Anche se Telegram riconsegnasse il comando dopo il riavvio, verrebbe ignorato. La query va quindi salvata su disco prima di riavviare e riletta all'avvio.

### Come riavviare
Deciso dall'utente: **`os.execv`**, cioè il processo si sostituisce da solo con uno nuovo, senza dipendere da chi lo sorveglia.
- Su Linux `os.execv` conserva lo stesso identificativo di processo: per systemd non succede nulla di visibile e `Restart=always` (`musicbot.service:35`) non entra nemmeno in gioco.
- Su Windows `os.execv` non sostituisce davvero l'immagine del processo: avvia un processo nuovo e termina quello corrente, quindi il processo figlio sopravvive ma l'attività pianificata lo perde di vista. È una differenza da **annotare nel worklog**, non da risolvere in questo task: l'installazione di riferimento è il Raspberry.
- L'alternativa scartata era `sys.exit()` affidandosi al sorvegliante: su Windows l'attività pianificata è configurata con `-RestartCount 3` e riavvia solo in caso di fallimento, mentre `main.py` esce sempre con codice zero, quindi il bot resterebbe spento.

### Lavoro che il riavvio non deve troncare
1. **Download in corso.** `core/config.py:109` crea `download_semaphore = asyncio.Semaphore(CONCURRENT_DOWNLOAD_LIMIT)` e lo espone come `dp['download_semaphore']`. Il numero di permessi è `CONCURRENT_DOWNLOAD_LIMIT` (5 di default, letto dal `.env`).
2. **Comando post-salvataggio.** `core/services/post_save_command.py` esegue la riga configurata in `POST_SAVE_COMMAND` dopo ogni salvataggio su disco. Sul Raspberry dell'utente quella riga è un `rclone bisync` verso pcloud. Il modulo tiene l'attività in corso nella variabile di modulo `_runner_task` e usa `_rerun_requested` per il giro successivo. **Un `bisync` interrotto a metà può richiedere un `--resync` manuale per ripartire**: è il motivo per cui il riavvio deve attenderne la fine.

## File da toccare
- `core/services/restart.py` — nuovo
- `core/services/post_save_command.py` — sola aggiunta di una funzione di attesa
- `core/handlers/messages.py` — estrazione della parte riusabile di `message_handler` e chiamata al riavvio
- `main.py` — ripresa all'avvio
- `core/strings.py` — stringa della ripresa

**Non toccare**: `core/services/youtube.py`, `callbacks.py`, `config.py`, gli script in `INSTALL_BOT/`.

## Skill di codice da caricare
`coding-standard`.

## Sottoproblemi, nell'ordine

1. **Attesa del comando post-salvataggio.** In `post_save_command.py` aggiungere una funzione asincrona pubblica che attende la fine dell'attività in corso, con un limite di tempo passato dal chiamante. Se l'attività non esiste o è già finita ritorna subito. Se il limite scade, registra un `WARNING` e ritorna comunque, così un comando esterno bloccato non impedisce per sempre il riavvio. Non modificare la logica di raggruppamento e di rilancio già presente.

2. **Nuovo modulo `core/services/restart.py`**, con in testa il commento a blocco che spiega perché il riavvio esiste (yt-dlp già caricato in memoria, la versione nuova entra solo in un processo nuovo) e come funziona la ripresa. Espone:
   - il percorso del file di ripresa, dentro `data/`, in formato JSON;
   - **salvataggio della richiesta pendente**: scrive chat, utente, nome da mostrare come richiedente, testo cercato ed eventuale messaggio a cui rispondere. Sono esattamente i dati che servono a rieseguire la ricerca (vedi sottoproblema 4);
   - **lettura della richiesta pendente**: legge il file e lo **cancella subito**, prima ancora di restituirne il contenuto. La cancellazione immediata è obbligatoria: se la ricerca ripresa fallisse, un file rimasto sul disco farebbe ripartire la stessa ricerca a ogni avvio successivo. File assente, JSON non valido o campi mancanti → nessuna richiesta pendente, senza sollevare eccezioni;
   - **procedura di riavvio**: attende che tutti i permessi di `download_semaphore` siano liberi (acquisirli tutti è il modo di accertarsene) con un limite di tempo di circa due minuti, poi attende il comando post-salvataggio con un limite più largo perché una sincronizzazione può essere lunga; entrambi i limiti, se scadono, producono un `WARNING` e non impediscono il riavvio. Poi chiude la sessione HTTP del bot, svuota i buffer del log, e infine esegue `os.execv` con `sys.executable` e il percorso assoluto dello script di avvio.

3. **Chiamata dal `message_handler`.** Nel ramo in cui il task1 ha stabilito che una versione nuova è stata installata: salvare la richiesta pendente, poi avviare la procedura di riavvio. Il messaggio di stato mostrato all'utente resta in chat: sarà il processo nuovo a rispondere. Nessun `finally` di pulizia deve cancellarlo.

4. **Estrazione della parte riusabile di `message_handler`.** Oggi la ricerca, il download e l'invio stanno dentro l'handler e dipendono dall'oggetto messaggio di Telegram. Vanno spostati in una funzione asincrona a sé, nello stesso file, che riceve come parametri i dati oggi letti dal messaggio e il messaggio di stato già inviato:
   - `message.chat.id` (usato a riga 312 per `send_audio` e a riga 325 per `offer_disk_save`)
   - `message.from_user.id` (campo `requester` di `song_data`)
   - `message.from_user.full_name` (riga 286, usato per il testo del bottone)
   - la query
   - l'identificativo del messaggio a cui rispondere, oggi ricavato da `message.reply_to_message` a riga 314, che nella ripresa vale `None`
   L'ultima riga dell'handler, `await message.answer(msg_error)` (riga 370), diventa un invio diretto alla chat.
   **Il corpo non va riscritto**: si spostano le righe cambiando solo i riferimenti all'oggetto messaggio. Tutti i rami `except` e i loro messaggi restano identici, compresa la gestione di `LONG_AUDIO`, `TOO_LARGE`, `YT_DOWNLOAD_FAILED` e degli errori di Telegram: sono il comportamento già approvato e testato.
   `message_handler` continua a fare tutti i controlli d'accesso, l'antispam, la cancellazione del messaggio, il controllo dell'aggiornamento del task1 e la creazione del messaggio di stato, poi chiama la funzione estratta.

5. **Ripresa all'avvio, in `main.py`.** Dopo la registrazione dei router e prima di `dp.start_polling`, leggere la richiesta pendente. Se c'è:
   - inviare nella chat salvata una stringa nuova che dice che l'aggiornamento è stato completato e la ricerca riprende, con il testo cercato;
   - inviare il normale messaggio di stato e avviare la funzione estratta al sottoproblema 4 come attività separata con `asyncio.create_task`, **non** con `await`: attenderla qui ritarderebbe l'avvio del polling e il bot resterebbe muto per tutta la durata del download.
   - l'attività va avvolta in una gestione d'errore propria che registri l'eccezione con `logger.exception`: l'handler `@dp.error` introdotto dal task3 copre solo le eccezioni che nascono dagli aggiornamenti Telegram, non quelle di un'attività avviata a mano, che altrimenti resterebbero silenziose.

6. **Stringa nuova in `strings.py`** per l'annuncio della ripresa, in inglese e con emoji come le altre, con un segnaposto per il testo cercato.

7. **Verifica di sintassi** con `py_compile` su tutti i file toccati.

8. **Verifica funzionale del salvataggio e della rilettura**, in uno script temporaneo **nella cartella scratchpad indicata dall'orchestratore, mai dentro il progetto**: scrivere una richiesta pendente, rileggerla e controllare che i campi tornino identici e che il file sia sparito; rileggere una seconda volta e controllare che non risulti più nessuna richiesta. Non serve avviare il bot. Cancellare i file di prova al termine.

## Regole
- Commenti in italiano, presente indicativo in terza persona. I commenti esistenti si conservano.
- Nessuna nuova dipendenza: `json`, `os`, `sys` e `asyncio` bastano.
- Non modificare il comportamento del comando `music` nel caso normale, cioè quando nessun aggiornamento è disponibile: il percorso deve restare quello di oggi.
- Non introdurre un riavvio in nessun altro punto: l'unico motivo di riavvio è l'installazione di una versione nuova di yt-dlp.
- Se durante l'implementazione risulta che `os.execv` non è praticabile in questo contesto, **fermarsi e segnalarlo** invece di ripiegare su una soluzione diversa di propria iniziativa.

## Al termine
Aggiornare `aggiornamento-e-robustezza-task2-worklog.md`: spuntare l'avanzamento, annotare la differenza di comportamento di `os.execv` su Windows e aggiungere il tag `DA TESTARE`. Non scrivere nella sezione "Test".

# aggiornamento-e-robustezza — task1 — Aggiornamento di yt-dlp agganciato alla ricerca

## Prerequisiti bloccanti
Verificare che esistano e siano leggibili prima di toccare codice. Se uno manca, fermarsi e segnalarlo:
- `core/yt_dlp_update/yt_dlp_manager.py`, `core/handlers/messages.py`, `core/strings.py`, `main.py` — da modificare.
- `core/config.py` — solo da **leggere**.
- `data/` è **vietata**: contiene il `.env` con il token reale. Non leggerla e non modificarla. Il codice può comporre percorsi dentro `data/` senza aprirla.
- Version control: git in **sola lettura** (`git status`, `git diff`, `git log`, `git show`). Vietati commit, push, checkout, reset.
- Verifica: `.venv\Scripts\python.exe -m py_compile <file>`. Nessun target di compilazione, nessuna suite di test.
- Questo plan si legge **insieme** al task2 (`aggiornamento-e-robustezza-task2-plan.md`): il riavvio e la ripresa della ricerca sono descritti lì e i due task vanno implementati nella stessa sessione.

## Obiettivo
Oggi l'aggiornamento di yt-dlp gira **una sola volta, all'avvio del bot** (`main.py:32`). Il bot sul Raspberry resta acceso per settimane, quindi in pratica non si aggiorna mai, e quando YouTube cambia le sue difese i download falliscono con `HTTP Error 403: Forbidden` finché qualcuno non riavvia a mano.

L'aggiornamento va spostato **dentro il flusso del comando `music`**, mantenendo il limite di un controllo ogni 24 ore già presente, e non deve più bloccare l'avvio.

Comportamento voluto, deciso dall'utente:
- se il controllo delle 24 ore non è ancora scaduto → nessuna attesa aggiuntiva e nessun messaggio: l'utente vede `🔍 Searching...` esattamente come oggi;
- se è scaduto → messaggio che dice che si sta controllando, poi:
  - se yt-dlp era già aggiornato → il messaggio diventa `🔍 Searching...` e la ricerca prosegue normalmente;
  - se una versione nuova è stata installata → messaggio che segnala l'aggiornamento, e si passa al riavvio descritto nel task2.

## Fatti già verificati — non ri-esplorare

### Perché serve il riavvio (motivo del task2)
`main.py:14` importa `core.services.youtube`, che a sua volta importa `yt_dlp` a `youtube.py:10`. Quindi **yt-dlp è già caricato in memoria** prima che l'aggiornamento parta a `main.py:32`. pip scrive la versione nuova su disco, ma il processo in corso continua a usare quella vecchia: in Python un modulo già importato non si ricarica, e `importlib.reload` su yt-dlp non è affidabile perché la libreria ha decine di sottomoduli già caricati. L'unico modo perché la versione nuova entri in funzione è far ripartire il processo.

### Stato attuale di `core/yt_dlp_update/yt_dlp_manager.py`
- `EXPIRATION_SECONDS = 24 * 3600`, `LAST_UPDATE_TIMESTAMP_FILE = 'data/yt_dlp_last_update.txt'` (percorso relativo alla cartella di lavoro, che per systemd è la radice del progetto: vedi `WorkingDirectory` in `INSTALL_BOT/LINUX/musicbot.service`).
- `_summarize_pip_output(output)` — **aggiunta oggi dal task3**: scorre l'output di pip a ritroso e restituisce la riga `Successfully installed ...` se c'è, altrimenti la stringa `already up to date, nothing installed`. È la distinzione da cui capire se una versione nuova è stata davvero installata.
- `_update_yt_dlp_package()` — lancia `pip install --upgrade yt-dlp` con `sys.executable`, scrive il timestamp, ritorna `True`/`False` a seconda che pip sia andato a buon fine. **Non** distingue "aggiornato" da "era già aggiornato".
- `check_and_update_needed()` — legge il timestamp e dice se sono passate più di 24 ore. Se il file manca o è illeggibile ritorna `True`.
- `initialize()` — chiama l'aggiornamento se il controllo è scaduto, poi verifica che `import yt_dlp` funzioni; se l'import fallisce riprova a installare e, se ancora fallisce, solleva `RuntimeError`.

### Stato attuale di `message_handler` (`core/handlers/messages.py:219`)
Nell'ordine: scarta i messaggi anteriori all'avvio del bot (`BOT_START_TIME`, riga 226), controlla chat privata e gruppi ammessi, controlla gli utenti bloccati, riconosce il comando con `_split_command` e scarta ciò che non è `music` (riga 244), applica l'antispam (riga 247), risponde con le istruzioni d'uso se la query è vuota (riga 253), cancella il messaggio dell'utente (riga 258), invia `strings.STATUS_SEARCHING` salvandolo in `status` (riga 262), prende `dp['download_semaphore']` (riga 264) e dentro `async with semaphore` esegue ricerca e download.

## File da toccare
- `core/yt_dlp_update/yt_dlp_manager.py`
- `core/handlers/messages.py` — solo `message_handler`, nella parte che precede l'acquisizione del semaforo
- `core/strings.py` — stringhe nuove
- `main.py` — l'avvio non deve più aggiornare

**Non toccare**: `core/services/youtube.py`, `callbacks.py`, `config.py`, `log_reader.py`, gli script in `INSTALL_BOT/`.

## Skill di codice da caricare
`coding-standard`.

## Sottoproblemi, nell'ordine

1. **`_update_yt_dlp_package` deve dire cosa è successo, non solo se è riuscito.** Cambiarne il valore di ritorno in `Optional[str]`: il riepilogo prodotto da `_summarize_pip_output` quando pip è andato a buon fine, `None` quando è fallito. Chi chiama capisce che una versione nuova è entrata perché il riepilogo inizia con `Successfully installed`. I rami di errore già presenti (`CalledProcessError`, `FileNotFoundError`, eccezione generica) restano come sono, ritornando `None`.

2. **Il timestamp va scritto sempre che pip abbia girato**, anche quando non c'era nulla da aggiornare: è ciò che impedisce di ricontrollare a ogni ricerca. Questa parte esiste già dentro `_update_yt_dlp_package` e va conservata.
   **Punto critico**: se la scrittura del timestamp fallisce, `check_and_update_needed()` continuerà a rispondere `True` a ogni ricerca. Combinato col riavvio del task2 questo produce un **ciclo di riavvii infinito**. Quindi la funzione deve segnalare al chiamante se il timestamp è stato scritto davvero; il chiamante non deve chiedere il riavvio quando la scrittura è fallita (dettaglio nel sottoproblema 3).

3. **Nuova funzione asincrona `run_update()` in `yt_dlp_manager.py`**, che è il punto di ingresso usato dal comando `music`:
   - esegue `_update_yt_dlp_package` dentro `asyncio.to_thread`, perché `subprocess.run` è bloccante e fermerebbe l'intero bot per i secondi della richiesta a PyPI (il catalogo dei pacchetti Python da cui pip scarica);
   - ritorna `True` **solo** quando una versione nuova è stata installata **e** il timestamp è stato scritto correttamente, cioè solo quando il riavvio è sia utile sia sicuro;
   - quando pip fallisce, registra un `WARNING` con il motivo e ritorna `False`: la ricerca deve proseguire lo stesso con la versione di yt-dlp già presente, che funziona, semplicemente non è aggiornata. Il fallimento dell'aggiornamento non è un errore del comando dell'utente.
   Esporre anche `check_and_update_needed` come è, che il chiamante usa per sapere **senza rete** se il controllo serve.

4. **`initialize()` non aggiorna più all'avvio.** Deve limitarsi a garantire che yt-dlp sia importabile: se `import yt_dlp` riesce, non fa nulla; se fallisce, installa il pacchetto (è la prima installazione, non un aggiornamento) e riprova; se fallisce ancora, solleva `RuntimeError` come oggi. Questo toglie la finestra morta all'avvio, misurata sul Raspberry in 9-18 secondi durante i quali il bot non era ancora in ascolto.

5. **Aggancio nel `message_handler`.** Il blocco va inserito **prima** dell'acquisizione del semaforo dei download (riga 264 attuale), al posto della sola riga che invia `STATUS_SEARCHING`, con questa logica:
   - se `check_and_update_needed()` è falso → invio di `STATUS_SEARCHING` come oggi, niente altro;
   - se è vero → invio di una stringa nuova che dice che si sta controllando l'aggiornamento, poi `await run_update()`:
     - ritorno `False` → il messaggio di stato viene modificato in `STATUS_SEARCHING` e il flusso prosegue senza interruzioni;
     - ritorno `True` → il messaggio viene modificato in una stringa nuova che annuncia aggiornamento e riavvio, e si passa alla procedura del task2, dopo la quale il processo riparte.
   La decisione resta tutta nel `message_handler`, che è il metodo pilota del flusso: `run_update` esegue e basta.
   **Perché prima del semaforo**: il riavvio del task2 attende che tutti i permessi del semaforo siano liberi. Se il controllo avvenisse dopo `async with semaphore`, questo stesso comando ne terrebbe uno occupato e l'attesa non finirebbe mai.

6. **Stringhe nuove in `strings.py`**, in inglese e con emoji come le esistenti, vicino a `STATUS_SEARCHING`: una per il controllo dell'aggiornamento in corso, una per l'aggiornamento installato con riavvio in corso. Il testo deve dire all'utente che l'attesa è dovuta all'aggiornamento e che la ricerca riprende da sola.

7. **Verifica di sintassi** con `py_compile` su tutti i file toccati.

8. **Verifica funzionale possibile senza il bot in esecuzione**, da fare in uno script temporaneo **nella cartella scratchpad indicata dall'orchestratore, mai dentro il progetto**: chiamare `_summarize_pip_output` con un output di pip finto contenente `Successfully installed yt-dlp-2026.1.1` e con uno contenente solo `Requirement already satisfied`, e verificare che la distinzione funzioni. Non serve invocare pip davvero.

## Regole
- Commenti in italiano, presente indicativo in terza persona. I commenti esistenti si conservano dove restano corretti.
- Nessuna nuova dipendenza.
- Non cambiare `EXPIRATION_SECONDS` né il percorso del file di timestamp.
- Non toccare la gestione degli errori di download già presente nel `message_handler` (i rami `except` da riga 327 in poi).
- Non modificare `_build_log_chunks`, `_split_long_record` né l'handler `@dp.error`: sono il task3, già concluso.

## Al termine
Aggiornare `aggiornamento-e-robustezza-task1-worklog.md`: spuntare l'avanzamento, annotare le scelte fatte e aggiungere il tag `DA TESTARE`. Non scrivere nella sezione "Test".

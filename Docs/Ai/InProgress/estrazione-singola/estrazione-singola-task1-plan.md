# estrazione-singola — task1 — Una sola estrazione YouTube per download

## Prerequisiti bloccanti
Verificare che esistano e siano leggibili prima di toccare codice. Se uno manca o il percorso è ambiguo, fermarsi senza modificare nulla e segnalarlo:
- `core/services/youtube.py` — è l'unico file da modificare.
- `core/handlers/messages.py` — solo da **leggere**, per confermare come viene consumato il valore di ritorno di `download_by_url`.
- Questo plan e il worklog `estrazione-singola-task1-worklog.md`.
- `data/` è vietata: contiene il `.env` con il token reale. Non leggerla né modificarla.
- **Version control**: git in **sola lettura** (`git status`, `git diff`, `git log`, `git show`). Vietati commit, push, checkout, reset.
- **Build/verifica**: nessun target di compilazione. La verifica è `python -m py_compile` più la prova funzionale descritta nei sottoproblemi, da eseguire con il Python della venv: `.venv\Scripts\python.exe`.

## Obiettivo
`download_by_url` in `core/services/youtube.py` estrae le informazioni dello stesso video **due volte** da YouTube: una prima volta con `skip_download` per i controlli preventivi su durata e dimensione, una seconda volta per scaricare. Ogni estrazione è un giro completo di richieste verso YouTube.

Va ridotta a **una sola estrazione**: si estraggono le informazioni una volta, si eseguono i controlli preventivi su quelle informazioni, e se i controlli passano si procede al download **riusando le informazioni già ottenute**, senza interrogare di nuovo YouTube.

Il comportamento osservabile dall'esterno non deve cambiare in nulla: stessi controlli, stessi errori, stesso valore di ritorno.

## File da toccare
Uno solo:
- `core/services/youtube.py`, funzione `download_by_url` (attualmente righe 125-223)

**Non toccare** `messages.py`, `callbacks.py`, `config.py`, né qualunque altro file.

## Skill di codice da caricare
`coding-standard`.

## Fatti già verificati — non ri-esplorare

### Misure che motivano l'intervento
Misurato su Raspberry Pi 5 con un brano reale:
- estrazione + download senza conversione: **4,8s** totali, di cui solo 0,9s di CPU — il resto è attesa di rete verso YouTube
- il download del file in sé è istantaneo (3,26 MB a 21 MB/s)

L'estrazione doppia costa quindi circa **4,8 secondi sprecati** per ogni canzone. È tutto tempo di rete, non di calcolo.

### Struttura attuale di `download_by_url`
La funzione contiene la funzione interna `pre_check_and_download`, eseguita in un thread separato con `asyncio.to_thread`. Fa, nell'ordine:
1. Apre un primo `YoutubeDL` con `info_opts` (`skip_download: True`, nessun postprocessor) e chiama `extract_info(url, download=False)`.
2. Sulle informazioni ottenute controlla `duration` contro `MAX_SONG_DURATION_SEC` (solleva `Exception("LONG_AUDIO")`) e `filesize`/`filesize_approx` contro `MAX_FILE_SIZE_BYTES` (solleva `Exception("TOO_LARGE_PRECHECK")`).
3. Genera `unique_id` e apre un **secondo** `YoutubeDL` con `download_opts`, che ha `outtmpl` verso `TEMP_PATH`, `writethumbnail: True` e i quattro postprocessor ffmpeg.
4. Chiama `extract_info(url, download=True)` e ricava `base` da `prepare_filename(info)`.
5. Cerca il file audio prodotto tra le estensioni `mp3, m4a, webm, opus, ogg` e la copertina tra `jpg, jpeg, png, webp`.
6. Controlla la dimensione del file scaricato contro `MAX_FILE_SIZE_BYTES` (solleva `Exception("TOO_LARGE_POSTCHECK")` dopo aver ripulito).
7. Cancella i file temporanei diversi da audio e copertina.
8. Restituisce la tupla `(info, audio_file, thumb, base)`.

### Vincoli da preservare esattamente
- **Valore di ritorno**: la tupla `(info, audio_file, thumb, base)`. `messages.py:276` la scompatta come `info, file, thumb, base = await download_by_url(url)` e da `info` legge poi le chiavi `track`, `title`, `artist`, `uploader`, `duration`, `upload_date`, `view_count`, `like_count`, `id`. L'`info` restituito deve quindi essere quello **completo del brano**, con i metadati puliti di YouTube Music, non una versione ridotta.
- **Le eccezioni e i loro messaggi non cambiano**: `LONG_AUDIO`, `TOO_LARGE_PRECHECK`, `TOO_LARGE_POSTCHECK`, e il prefisso `YT_DOWNLOAD_FAILED: {e}` per i `DownloadError`. `messages.py:342-355` riconosce i primi due dal testo e spoglia il prefisso `YT_DOWNLOAD_FAILED:` per mostrare all'utente la descrizione dell'errore. Cambiare un messaggio romperebbe quella gestione.
- **I controlli preventivi restano preventivi**: durata e dimensione stimata vanno verificate **prima** che il file venga scaricato, altrimenti si scarica inutilmente un brano che verrà scartato. È il motivo per cui la doppia estrazione esisteva: va tolta la seconda estrazione, non l'anticipo dei controlli.
- **I postprocessor ffmpeg devono continuare a girare**: conversione in MP3 192k, tag, conversione della copertina in jpg e incorporamento. Il file finale deve restare un vero MP3 con copertina, e il file della copertina deve restare su disco (`already_have_thumbnail: True`) perché serve per l'invio separato a Telegram.
- Le opzioni `noplaylist`, `quiet`, `no_warnings`, `encoding: 'utf-8'`, `outtmpl` con `unique_id` e `writethumbnail` restano come sono.
- Non reintrodurre `extractor_args` con `client: android`: è stato rimosso oggi perché YouTube lo blocca e degradava la qualità audio.

### Punto tecnico su cui NON andare a memoria
Il modo di far scaricare a yt-dlp un video **partendo da informazioni già estratte**, senza rifare l'estrazione, è il cuore di questo task. L'API di `YoutubeDL` espone più metodi vicini (`extract_info`, `process_ie_result`, `process_video_result`, `download`) con comportamenti diversi riguardo a selezione dei formati e postprocessor.

**Non scegliere a memoria.** Verificare quale sia il metodo corretto leggendo il codice sorgente di yt-dlp installato nella venv, che è la fonte autorevole disponibile in locale:
`.venv\Lib\site-packages\yt_dlp\YoutubeDL.py`
Cercare le firme e i commenti dei metodi citati, e in particolare quale accetta un dizionario di informazioni già estratte insieme a un parametro che attiva il download.

Attenzione a due trappole:
- `extract_info(url, download=False)` restituisce informazioni **già elaborate** (formato selezionato). Ripassarle a un metodo che le rielabora potrebbe duplicare il lavoro o fallire: va verificato quale metodo accetta un dizionario in quello stato.
- I postprocessor vengono eseguiti nella fase di download. Con `download=False` non partono. Bisogna accertarsi che partano nella chiamata che scarica davvero, altrimenti il file resta in formato originale, senza MP3, tag e copertina.

Se dalla lettura del sorgente il metodo corretto non risulta univoco, **provare empiricamente** (vedi sottoproblema di verifica) e tenere la variante che produce l'MP3 con copertina. Se nessuna variante funziona, **fermarsi e segnalarlo** invece di lasciare il codice a metà: il comportamento attuale, per quanto lento, è corretto.

## Sottoproblemi, nell'ordine
1. **Unificare la configurazione**: un solo dizionario di opzioni, quello completo del download (`outtmpl`, `writethumbnail`, postprocessor), e una sola istanza di `YoutubeDL`. Il dizionario `info_opts` separato sparisce. `unique_id` va generato prima, perché serve a comporre `outtmpl`.
2. **Estrazione unica e controlli preventivi**: estrarre le informazioni una volta sola senza scaricare, e su quelle eseguire i controlli di durata e dimensione stimata già presenti, con le stesse eccezioni e gli stessi messaggi. Mantenere la gestione di `DownloadError` che rilancia con il prefisso `YT_DOWNLOAD_FAILED:`.
3. **Download riusando le informazioni**: far procedere il download a partire dalle informazioni già estratte, con il metodo individuato leggendo il sorgente di yt-dlp. Da qui devono ricavarsi `base` e l'`info` finale da restituire.
4. **Parte finale invariata**: individuazione del file audio e della copertina, controllo della dimensione a valle, pulizia dei file temporanei residui, valore di ritorno. Questa parte non va riscritta: va solo agganciata al nuovo flusso.
5. **Commenti**: spiegare in un commento sopra l'estrazione **perché** ora è unica, cioè che ogni estrazione è un giro di rete verso YouTube che costava circa 5 secondi a canzone, e che i controlli preventivi restano prima del download. Va spiegato anche il metodo scelto per scaricare dalle informazioni già estratte, perché non è ovvio a chi legge.
6. **Verifica di sintassi**: `.venv\Scripts\python.exe -m py_compile core/services/youtube.py`.
7. **Verifica funzionale**, obbligatoria — questa modifica tocca il percorso principale del bot e non basta compilarla. Scrivere uno script temporaneo **nella cartella scratchpad indicata dall'orchestratore, non dentro il progetto**, che importi `download_by_url` e la esegua su un video reale (`https://www.youtube.com/watch?v=w3iLsfsaWh4`), poi controllare che:
   - la chiamata restituisca quattro valori
   - il file audio esista, **abbia estensione `.mp3`** e dimensione plausibile (oltre 1 MB)
   - il file della copertina esista
   - `info` contenga le chiavi usate da `messages.py`: almeno `title`, `duration`, `id`
   - misurare il tempo totale con `time.perf_counter()` e confrontarlo con la stessa misura fatta **prima** della modifica (eseguire lo script sul codice attuale prima di toccarlo, oppure ricavare il tempo da una prova con `git stash` — no, git è in sola lettura: eseguire la misura di riferimento **prima** di applicare la modifica)
   - cancellare i file temporanei prodotti dalla prova
8. **Riportare i due tempi** (prima e dopo) nel worklog: servono a confermare che il risparmio previsto di circa 5 secondi si sia realizzato.

## Regole
- Commenti in italiano, presente indicativo in terza persona, secondo le regole di commento del progetto. Aggiungere i commenti nuovi senza riscrivere quelli esistenti, che vanno conservati dove restano corretti.
- Non cambiare la firma di `download_by_url` né il tipo del valore di ritorno.
- Non modificare `search_multiple` né altre funzioni del file.
- Non introdurre nuove dipendenze.
- Se la verifica funzionale fallisce, **non lasciare il codice modificato a metà**: segnalare il problema e riportare il file allo stato funzionante.
- Non scrivere file di prova dentro la cartella del progetto.

## Al termine
Aggiornare `estrazione-singola-task1-worklog.md`: spuntare i sottoproblemi nella sezione "Avanzamento", riportare i due tempi misurati e aggiungere il tag `DA TESTARE`. Non scrivere nella sezione "Test": la compila l'orchestratore dopo le prove dell'utente.

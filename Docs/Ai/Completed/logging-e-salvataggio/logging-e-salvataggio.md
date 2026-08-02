# Feature: Logging e Salvataggio

## Scopo
Implementare logging strutturato su file (livello INFO per storico leggibile), un comando di lettura log in Telegram (`/log`), e riordinamento dell'interfaccia di salvataggio con bottone "Save Srv" sul messaggio audio (senza mensaggi di conferma extra) + errori di download visibili all'utente.

## Modifiche per task

### Task 1 — Fix metadati MP3 (copertina, titolo, artista, album)
- **File toccato:** `core/services/youtube.py` (funzione `download_by_url`)
- **Cambiamenti:** 
  - Sostituzione postprocessors: `FFmpegExtractAudio` (produce vero MP3 a 192kbps), `FFmpegMetadata` (tag ID3), `FFmpegThumbnailsConvertor` (converti thumb a jpg), `EmbedThumbnail` (incorpora copertina con `already_have_thumbnail: True` per non eliminarla).
  - Rimosso hack di rinomina estensione (.webm → .mp3); lo scan del file audio mantiene, trova ora `.mp3` già vero.
- **Risultato:** File MP3 veri, leggibili dalle proprietà Windows con titolo/artista/album/copertina incorporati. Thumb file conservato per Telegram.

### Task 2 — Logging su file + logInfo operazioni
- **File toccati:** `core/config.py`, `core/services/music_library.py`, `core/handlers/callbacks.py`, `core/handlers/messages.py`
- **Cambiamenti:**
  - `config.py:35`: `file_handler.setLevel(logging.INFO)` (era ERROR); ora il file logga INFO per cronologia leggibile.
  - `music_library.py`: log INFO su `save_pending_to_folder`, `stage_pending_file`, `discard_pending`.
  - `callbacks.py`: log INFO nel flusso salvataggio (`offer_disk_save`, `save_to_directory` successo/skip, `_pending_cleanup_timeout`).
  - Console restante a INFO invariata.
- **Risultato:** `data/bot.log` contiene ora INFO, non solo ERROR. Operazioni di salvataggio tracciate.

### Task 3 — Comando `log` in chat privata
- **File creato:** `core/services/log_reader.py` (logica pura di lettura, parsing per record, filtri)
- **File toccati:** `core/handlers/messages.py`, `core/strings.py`
- **Cambiamenti:**
  - `log_reader.py`: lettura file log, parsing per record (riga iniziale matcha timestamp + livello; righe seguenti = traceback), filtri per livello (info/error/warning) e data (gg/mm/aa), restituzione ultimi N record (default 25). Legge anche backup ruotati se filtro data attivo.
  - `messages.py`: nuovo handler `/log [livello] [N] [gg/mm/aa]` solo chat privata. Parsing argomenti, chunking output sotto 4096 char Telegram.
  - `strings.py`: stringhe comando.
- **Risultato:** `/log` mostra ultimi 25 record o filtrati per livello/numero/data, in chat privata solo. Traceback completo e leggibile.

### Task 4 (RIVISTO) — Bottone "Save Srv" senza conferma, save per ultimo
- **File toccati:** `core/strings.py`, `core/handlers/callbacks.py`, `core/handlers/messages.py`, `core/services/music_library.py`, `core/config.py`, `main.py`
- **Cambiamenti:**
  - `strings.py`: rimossi SONG_CONFIRM_PROMPT, BUTTON_CONFIRM_YES/NO (piano primo rivisto); aggiunto BUTTON_SAVE_SRV.
  - `callbacks.py`: `offer_disk_save` ora fa solo stage + timer, nessun messaggio di conferma. Handler `save_srv` (bottone salvage) invia il picker. Rimosso handler confirm_song. Importato INFO_EXPIRATION_HOURS per timer.
  - `messages.py`: bottone Save Srv nella keyboard dell'audio; rimossa funzione `remove_not_right_button` e schedulazione (Not right? non sparisce più dopo 60s).
  - `music_library.py`: helper `pending_exists(key)` e `prune_orphan_pending(is_valid_key)`.
  - `main.py`: prune di temp/pending all'avvio dopo cleanup_expired_data, usando un predicato da storage.
  - `choose_song` (callback): bottone Save Srv nella keyboard dell'alternativa.
- **Risultato:** Bottone Save Srv sul messaggio audio (senza mensaggio extra). Click mostra picker, salva dopo scelta cartella. Not right? restante. Pending orfani puliti all'avvio.

### Task 5 — Errore di download visibile su Telegram
- **File toccati:** `core/services/youtube.py`, `core/handlers/messages.py`, `core/handlers/callbacks.py`
- **Cambiamenti:**
  - `youtube.py`: eccezioni DownloadError ora includono il vero errore: `raise Exception(f"YT_DOWNLOAD_FAILED: {e}")`.
  - `messages.py`: ramo else estrae e mostra la descrizione (senza prefisso sentinel), max 300 char, con `html.escape`.
  - `callbacks.py` choose_song: popup mostra descrizione, max ~190 char, testo semplice (no HTML).
- **Risultato:** Utente vede "HTTP Error 403: Forbidden" invece di "YT_DOWNLOAD_FAILED"; traceback completo nel log.

## Da tenere a mente

### Punti risolti (non riaprire)
1. **Metadati MP3 e rinomina estensione (Task 1):** Lo `FFmpegExtractAudio` del postprocessor produce .mp3 vero, non è un container rinominato. Lo scan trova `.mp3` già giusto. Non ritentare di rinominare estensioni.
2. **Livello file handler (Task 2):** È INFO, non ERROR. Se si vuole più verbosità in futuro, il file_handler.setLevel è il punto, non il root logger level.
3. **Timer salvataggio (Task 4):** `INFO_EXPIRATION_HOURS` da config governa sia la scadenza della preview che il garbage collect dei pending. Coerente in coppie di funzioni.
4. **Thumb file e EmbedThumbnail (Task 1):** `already_have_thumbnail: True` nel postprocessor: la thumb non viene cancellata, rimane disponibile per l'invio separato a Telegram. Non rimuovere.
5. **Priority rank nel dedup (future feature 3):** La cartella preferenziale per keep non è parametrizzata qui; sarà usata da dedup come "folder a priorità massima = keep". Per ora è irrilevante.

### Trappole note
1. **Logica di staging/discard_pending:** Un brano staginato rimane in `temp/pending/<key>.mp3` finché non salvo su folder o scade il timer. Se il timer è interferito da un riavvio, il file diventa orfano; per questo `prune_orphan_pending(is_valid_key)` all'avvio. Non manomettere il timing senza adeguare la prune.
2. **Formato log e parsing (Task 3):** Il file usa `[YYYY-MM-DD HH:MM:SS] [LEVEL] message`. Il parser regex assume questa forma esatta. Se il format della config cambia, adeguare `log_reader.py`.
3. **Conflitto tra comandi privati:** `/log`, `/priority`, `/delete` (feature successiva) registrati con filtri mutuamente esclusivi (prefisso nomi diversi). Se si aggiunge un nuovo comando privato, usare lo stesso pattern di `_is_*_command` per evitare falsi positivi.

### Scelte vincolanti per il futuro
1. **Album non riempito per YouTube semplice:** Se una query non va a YouTube Music (fallback), i campi `track`/`artist`/`album` restano None / uploader_name. Non è un bug, è il fallback atteso. L'arricchimento MusicBrainz è una fase futura (feature metadati-veri).
2. **Contenitori audio e re-encode:** Il re-encode a MP3 è lossy (decisione di progetto). Se in futuro si vuol mantenere la qualità, toccare il postprocessor FFmpegExtractAudio (usare codec diverso o skipcare il postprocessor, ma richiede gestire il .webm/opus).
3. **Timeout pending cancellazione file:** 10 ore (INFO_EXPIRATION_HOURS * 3600). Se file rimane in staging > 10h, viene scartato + il file temporaneo cancellato. Attenzione a sessioni lunghe.

## Esito test
Tutti i task marcati DA TESTARE; implementazione completa, compilazione ok. Test runtime delegato all'utente (metadati file, visibilità errori, log command in chat, etc.).

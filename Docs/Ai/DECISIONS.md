# Decisioni di progetto

Raccolta delle decisioni valide tra le sessioni. Aggiornare quando l'utente prende una scelta destinata a restare.

## Version control
- **Git consentito in sola lettura** per la verifica delle patch dopo Agent-Code (`git status`, `git diff`, `git show`, `git log`). Nessun commit/push senza richiesta esplicita dell'utente. (deciso 2026-07-05)

## Logging
- I `logger.info` devono finire sia su console (stdout) sia su file `data/bot.log`. Quindi `file_handler` a livello `INFO` (prima era `ERROR`). (deciso 2026-07-05)
- Comando `log` in chat per leggere `bot.log`: **abilitato solo in chat privata col bot**, indipendente da `ALLOW_PRIVATE_CHAT`. Motivo: i log contengono user id/query/errori, esporli in gruppo è una fuga di dati. (deciso 2026-07-05)

## Audio / salvataggio
- File audio salvati su disco in formato **MP3 riconvertito** (FFmpegExtractAudio 192k) con tag e copertina incorporati, non solo container rinominato. Re-encode lossy accettato per avere proprietà leggibili in Windows. (deciso 2026-07-05)
- ~~Conferma "È la canzone giusta? [Sì][No]" prima del salvataggio.~~ **Revocato**: nessun messaggio di conferma aggiuntivo. (revocato 2026-07-05)
- Salvataggio su PC tramite **bottone "💾 Save Srv"** aggiunto al messaggio audio esistente, accanto a `[🎵 info]` e `[🔎 Not the right song?]`. Cliccando la preview della canzone si salva sul telefono (nativo Telegram); "Save Srv" salva su PC/server. Il click su Save Srv mostra il picker delle cartelle. (deciso 2026-07-05)
- Il bottone "Not the right song?" **non deve più sparire dopo 60s**: rimosso il timer `remove_not_right_button` (era puramente cosmetico, nessun motivo di carico server; anzi toglierlo alleggerisce). "Not right?" resta finché i dati canzone non scadono. (deciso 2026-07-05)
- **Finestra di salvataggio T = `INFO_EXPIRATION_HOURS`** (default ~10h): vita del file in staging (`temp/pending/`). `PENDING_SAVE_TIMEOUT_SEC` passa da 300 a `INFO_EXPIRATION_HOURS*3600`. Motivo dello staging: il file temp del download viene ripulito dal `finally` di `message_handler`, la copia in `temp/pending` sopravvive per poter salvare dopo. Il timeout è la **garbage collection** dei file abbandonati (mai salvati/skippati) per non riempire il disco. (deciso 2026-07-05)
- `song_data` è persistito in SQLite (`songs_cache`), sopravvive al riavvio; `temp/pending/` no. Aggiungere all'avvio (`main.py`, dopo `cleanup_expired_data`) una **prune di `temp/pending`** che elimina i file il cui key non ha più un record in DB (orfani da riavvii). (deciso 2026-07-05)

## Errori di download
- Quando yt-dlp fallisce, mostrare su Telegram **la descrizione dell'errore** (es. "HTTP Error 403: Forbidden"), non il codice interno `YT_DOWNLOAD_FAILED`. Il traceback completo resta nel log. (deciso 2026-07-05)

## Feature futura — Priorità cartelle + dedup (via Telegram)
- File priorità: **`MUSIC_DIR/priority.txt`**, una cartella per riga, dall'alto = priorità massima.
  - Se il file **non esiste** → crearlo popolato con **tutte** le sottocartelle attuali (alfabetico). (deciso 2026-07-05)
  - Se il file **esiste** → è la **lista autoritativa**: le cartelle NON elencate sono **ignorate** dal dedup (non scansionate, mai cancellate). **Niente auto-add** delle cartelle nuove; per includerne una si aggiunge a mano al file. Le cartelle elencate ma non più esistenti su disco vengono filtrate in memoria (senza riscrivere il file). (deciso 2026-07-05, revoca il precedente "aggiunte automaticamente")
- Comandi testuali **solo in chat privata** (come `log`): `priority` (gestione ordine) e `dedup` (pulizia duplicati). (deciso 2026-07-05)
- Ordine modificabile con **bottoni inline ▲▼** (lista cartelle, su/giù), `priority.txt` aggiornato ad ogni spostamento. (deciso 2026-07-05)
- Criterio duplicato: **match fuzzy** (riusare `rapidfuzz`/`FUZZY_DUPLICATE_THRESHOLD` come l'inline DB). (deciso 2026-07-05)
- `dedup`: mostra i gruppi di duplicati con la copia da tenere (cartella a priorità più alta) già marcata e le altre come **bottoni deselezionabili** (☑/☐); "Conferma" cancella solo le selezionate. Operazione distruttiva. (deciso 2026-07-05)
- Si tiene la copia nella cartella a **priorità più alta tra quelle in cui la canzone esiste**; le altre si cancellano (nessuno spostamento). (deciso 2026-07-05)
- Ambito: **solo primo livello** di `MUSIC_DIR`; eventuali sottocartelle ricorsive ignorate. (deciso 2026-07-05)

## Feature futura — Metadati veri (titolo/artista)
- **Niente pulizia euristica del titolo** (troppe casistiche). (deciso 2026-07-05)
- Fonte primaria: **cercare su YouTube Music** (`https://music.youtube.com/search?q=...`). Verificato dal vivo: la ricerca flat dà `title` PULITO; l'`extract_info` completo del brano (già fatto in `download_by_url`) dà `track`/`artist`/`album`/`release_year` puliti → `FFmpegMetadata` (Task 1) li incorpora **senza API esterna**. (verificato 2026-07-05)
- Fallback ricerca: **YT Music prima, poi YouTube normale** se 0 risultati (metadati grezzi come oggi). (deciso 2026-07-05)
- **Shippare e testare prima YT Music**; solo se i metadati restano scarsi si aggiunge MusicBrainz. (deciso 2026-07-05)
- Fallback metadati esterni (per i casi da YouTube normale, opzionale/successivo): **MusicBrainz** primario (aiohttp diretto — la lib `musicbrainzngs` è sincrona; User-Agent con contatto obbligatorio; ~1 req/s; scegliere il match con `score >= 80`, preferire `status=Official`), **iTunes Search API** secondario (no key, `trackName`/`artistName`/`collectionName`). Sotto la soglia di confidenza → **mantenere i metadati grezzi** di YouTube. (deciso 2026-07-05, da ricerca online)
- Nome **file** salvato: **solo titolo pulito** (es. `Io sono.mp3`). Tag: title = titolo pulito, artist = artista vero. (deciso 2026-07-05)
- Ambito: applicare a **nome file + tag titolo + tag artista** e a title/performer inviati su Telegram. (deciso 2026-07-05)
- Rete: accettare **timeout** (3-5s). Errore di connessione → fallisce anche yt-dlp → mostrare errore. Errore di MusicBrainz/altro → continuare col fallback (metadati grezzi). (deciso 2026-07-05)

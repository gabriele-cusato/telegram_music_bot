# Feature: Metadati Veri (YouTube Music + Nome File Titolo-Only)

## Scopo
Integrare ricerca su YouTube Music per ottenere titolo/artista/album puliti (non grezzi), usarli per tag ID3 e display su Telegram, e salvare i file con nome = solo titolo (non "Artista - Titolo").

## Modifiche per task

### Task 1 — Ricerca YouTube Music + campi metadati puliti
- **File toccati:** `core/services/youtube.py`, `core/handlers/messages.py`, `core/handlers/callbacks.py`
- **Cambiamenti:**
  - `youtube.py search_multiple`: ricerca prima su YouTube Music flat (`music.youtube.com/search?q=...`), filtra entry valide (id + titolo), mantiene max 10. Se fallisce o nessuna entry, fallback a `ytsearch10:{query}` su YouTube normale. Log INFO della fonte usata ("YT Music" / "YouTube fallback").
  - `messages.py message_handler`: estrae campi puliti da `info` dopo download: `clean_title = info.get("track") or info.get("title")`, `clean_artist = info.get("artist") or info.get("uploader")`. Usati in `song_data` e `send_audio(title=..., performer=...)`.
  - `callbacks.py choose_song`: stessa logica per l'alternativa scelta (estrae track/artist puliti, popola `new_song_data` e `edit_message_media`).
- **Risultato:** Ricerca su YT Music porta titoli/artisti/album puliti; il fallback su YouTube normale mantiene il comportamento grezzo atteso. Tag ID3 e display Telegram ricevono i dati puliti quando disponibili.

### Task 2 — Nome file salvato = solo titolo
- **File toccato:** `core/handlers/callbacks.py` (funzione `save_to_directory`)
- **Cambiamenti:**
  - `save_to_directory` handler: `dest_basename = title or "audio"` (rimosso ramo `f"{artist} - {title}"`). Solo il titolo usato come nome file.
- **Risultato:** File salvato come `Io sono.mp3` (non `Annalisa - Io sono.mp3`). Tag ID3 restano completi (titolo, artista, album via FFmpegMetadata).

## Da tenere a mente

### Punti risolti (non riaprire)
1. **Fallback YouTube Music (Task 1):** Se YT Music fallisce, scattiamo a YouTube normale. Questo fallback NON è un errore; è il comportamento atteso per query che non sono brani musicali. Non forzare sempre YT Music.
2. **Campi puliti da `info` (Task 1):** I campi `track`/`artist`/`album` vengono solo se il brano è su YouTube Music o un brano ordinario di YouTube con metadata. Per video YouTube generici, restano None e ricadiamo su `title`/`uploader`. Normale, non un bug.
3. **Album e FFmpegMetadata (Task 1):** L'album scritto nei tag ID3 viene da `info.get("album")` (campo di yt-dlp), non è ricavato da noi. Se assente, FFmpegMetadata non lo scrive. Non mettere logica di arricchimento qui (MusicBrainz è futura).
4. **Collisioni nome file (Task 2):** Due brani con lo stesso titolo di artisti diversi nella stessa cartella si sovrascrivono. Accettato per scelta utente. Non aggiungere suffissi/contatori.

### Trappole note
1. **URL del brano da YT Music:** La ricerca piatta su `music.youtube.com/search?q=...` restituisce URL in forma `https://music.youtube.com/watch?v=ID`. Yt-dlp li riconosce e estrae i metadati completi (track, artist, album). Se la ricerca fallisce a fornire URL validi, il fallback a ytsearch10 recupera con YouTube normale. Verificare che il fallback non mascheri un errore di rete reale (il code loggava e ritornava [] nel caso base, la cascata non fa lo stesso).
2. **Feed flat di YT Music:** La modalità `extract_flat: True` su YT Music non fornisce campi artist/album a livello di entry di ricerca; li otteniamo solo dal full extract del brano specifico. Questo è normale e l'implementazione lo gestisce (extract_info completo nel download).

### Scelte vincolanti per il futuro
1. **Fallback a YouTube normale:** È permanente per query non-musicali. Se in futuro si vuol forzare YT Music per tutto, occorre refactoring della ricerca (ma si rischia di non trovare brani non pubblici su Music).
2. **Album e metadata tag:** L'album nei tag ID3 dipende da `info["album"]` di yt-dlp. Se mai arricchissimo con MusicBrainz, avremo due fonti di album (yt-dlp + MB). Scegliere quale prevalga (ora vince yt-dlp senza arricchimento).
3. **Nome file titolo-only:** Una volta scelto, cambiare indietro romperebbe la logica di dedup (feature 3, che cercerà match fuzzy su nome file). Mantenere.

## Esito test
Tutti i task marcati DA TESTARE. Implementazione completa, compilazione ok. Test runtime: verificare che ricerca porta titoli/artisti puliti, fallback funziona, file salvato con nome = titolo, tag ID3 corretti.

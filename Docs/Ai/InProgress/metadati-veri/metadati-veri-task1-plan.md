# Task 1 — Ricerca su YouTube Music + campi metadati puliti

## Obiettivo
Ottenere titolo pulito, artista vero e album usando **YouTube Music** come fonte di ricerca (con fallback a YouTube normale). I campi puliti (`track`/`artist`/`album`) arrivano da yt-dlp e devono essere usati per: dati canzone in cache, audio inviato su Telegram (titolo/performer) e tag del file (via `FFmpegMetadata`, già configurato).

## Contesto verificato dal vivo (2026-07-05)
- Ricerca `https://music.youtube.com/search?q=...` in modalità flat → entry con `title` PULITO (es. "Io sono") e `url`/`id` del brano (es. `https://music.youtube.com/watch?v=xinDhmKTE68`). In flat NON ci sono `artist`/`album`.
- `extract_info` COMPLETO del brano (già fatto in `download_by_url`) su `https://www.youtube.com/watch?v=xinDhmKTE68` → `track='Io sono'`, `artist='Annalisa'`, `artists=['Annalisa']`, `album='MA IO SONO FUOCO'`, `release_year=2025`, mentre `uploader`/`channel`='annalisaufficiale' (canale, NON artista).
- Su un video YouTube normale (non YT Music) `track`/`artist`/`album` restano None.
- Conseguenza: cercando su YT Music, l'`id`/`url` è quello del brano; sia il flusso principale (usa `url`) sia le alternative (`choose_song` costruisce `youtube.com/watch?v={id}`) ottengono i campi puliti al download.

## Prerequisiti bloccanti
- Devono esistere ed essere leggibili: `core/services/youtube.py`, `core/handlers/messages.py`, `core/handlers/callbacks.py`. Se manca uno, fermarsi.
- Non toccare file diversi. Il codice contiene già le feature precedenti (Task 1-5 di logging-e-salvataggio): NON rompere il comando `log`, il flusso Save Srv, i log.
- Version control: git in sola lettura lato orchestratore. Agent-Code NON committa/pusha.
- Verifica: `python -m py_compile` sui file toccati. Il test runtime lo fa l'utente.

## File da toccare
- `core/services/youtube.py` — `search_multiple`.
- `core/handlers/messages.py` — costruzione `song_data` e `send_audio` nel `message_handler`.
- `core/handlers/callbacks.py` — `choose_song`: `new_song_data` e `edit_message_media`.

## Fatti sul codice attuale
- `youtube.py search_multiple(query)`: usa `ydl.extract_info(f"ytsearch10:{query}", download=False)` con `ydl_opts` che hanno `extract_flat: True`, `extractor_args {'youtube': {'client': 'android'}}`, `postprocessors: []`. Ritorna `result.get("entries", [])`. C'è già un log INFO "Search started/completed".
- `messages.py message_handler`: `first = results[0]`; `url = first.get("url") or first.get("webpage_url")`; poi `info, file, thumb, base = await download_by_url(url)`. `song_data` usa `"title": info.get("title")`, `"artist": info.get("uploader")`. `send_audio(title=info.get("title"), performer=info.get("uploader"), ...)`.
- `callbacks.py choose_song`: costruisce `url = f"https://www.youtube.com/watch?v={video_id}"`; dopo il download `new_song_data` usa `"title": info.get("title")`, `"artist": info.get("uploader")`; `edit_message_media(InputMediaAudio(..., title=info.get("title"), performer=info.get("uploader"), ...))`.

## Sottoproblemi (in ordine)
1. `youtube.py search_multiple`: cercare prima su YouTube Music, con fallback a YouTube normale.
   - Costruire l'URL di ricerca YT Music: `from urllib.parse import quote_plus` → `f"https://music.youtube.com/search?q={quote_plus(query)}"`.
   - Eseguire `extract_info(url, download=False)` con gli stessi `ydl_opts` flat esistenti; prendere `result.get("entries", [])`.
   - **Filtrare** le entry valide: tenere solo quelle con un id/url di brano e un `title` (scartare eventuali voci di sezione senza id). Mantenere al massimo 10 entry.
   - Se le entry valide YT Music sono 0 (o l'estrazione solleva) → **fallback**: eseguire la ricerca attuale `ytsearch10:{query}` come prima. Loggare a INFO quale fonte è stata usata ("YT Music" / "YouTube fallback").
   - Ritornare le entry nello stesso formato di prima (lista di dict con `url`/`id`/`title`/`duration`), così il resto del flusso non cambia.
   - Mantenere la gestione errori esistente (`DownloadError` → log + lista vuota nel caso base). Il fallback non deve mascherare un errore reale di rete: se ANCHE il fallback fallisce, comportarsi come oggi.
2. `messages.py message_handler`: usare i campi puliti.
   - Titolo pulito: `clean_title = info.get("track") or info.get("title")`.
   - Artista vero: `clean_artist = info.get("artist") or info.get("uploader")`.
   - Usarli in `song_data` (`"title": clean_title, "artist": clean_artist`) e in `send_audio(title=clean_title, performer=clean_artist, ...)`.
   - Lasciare invariato il resto (thumb, durata, view/like, ecc.).
3. `callbacks.py choose_song`: stessa cosa.
   - `clean_title = info.get("track") or info.get("title")`, `clean_artist = info.get("artist") or info.get("uploader")`.
   - Usarli in `new_song_data` e in `edit_message_media(InputMediaAudio(..., title=clean_title, performer=clean_artist, ...))`.

## Note e limiti
- I tag del FILE (title/artist/album ID3) sono già scritti da `FFmpegMetadata` (configurato nel Task 1 di logging-e-salvataggio) leggendo `info`: con la fonte YT Music diventano puliti da soli, nessuna modifica ai postprocessor.
- Caso fallback (YouTube normale): titolo/artista restano grezzi come oggi — atteso; l'arricchimento MusicBrainz è una fase successiva, fuori da questo task.
- Album: usato per i tag del file via FFmpegMetadata; non è richiesto mostrarlo altrove in questo task.

## Skill di codice
Caricare `coding-standard`. Commenti in italiano forma infinito, stringhe in inglese.

## Verifica finale
- `python -m py_compile` sui 3 file.
- Aggiornare il worklog: spuntare i sottoproblemi, marcare `DA TESTARE`.

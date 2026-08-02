# Task 1 — Fix metadati MP3 (copertina, titolo, artista, album)

## Obiettivo
Il file audio scaricato/salvato su disco deve essere un vero MP3 con tag ID3 (titolo, artista, album se disponibile) e copertina incorporata, leggibili dalle proprietà file di Windows. Oggi il file è un container opus/webm rinominato `.mp3` senza copertina.

## Prerequisiti bloccanti
- Deve esistere ed essere leggibile `core/services/youtube.py`. Se manca, fermarsi senza modificare.
- `ffmpeg` deve essere disponibile a runtime (il progetto lo usa già via `ffmpeg-bin`/PATH in `start.sh`). Non è compito di questo task installarlo.
- Non toccare altri file oltre a `core/services/youtube.py`.
- Non leggere/modificare cartelle o file marcati sensibili (nessuno noto in questo task).
- Version control: git consentito in sola lettura per la verifica (lo usa l'orchestratore, non Agent-Code). Agent-Code NON esegue commit/push.
- Target di verifica: build/lint del modulo Python (import senza errori di sintassi). Il test runtime dei metadati lo fa l'utente.

## File da toccare
- `core/services/youtube.py` — SOLO la funzione `download_by_url`, blocco `download_opts` e blocco post-download.

## Fatti verificati (stato attuale del codice)
- `download_by_url` (righe ~97-195). `download_opts` attuale (righe ~132-144):
  ```python
  download_opts = {
      'format': 'bestaudio/best',
      'noplaylist': True,
      'quiet': True,
      'outtmpl': os.path.join(TEMP_PATH, f'{unique_id}.%(ext)s'),
      'writethumbnail': True,
      'extractor_args': {'youtube': {'client': 'android'}},
      'no_warnings': True,
      'encoding': 'utf-8',
      'postprocessors': [
          {'key': 'FFmpegMetadata'},
      ]
  }
  ```
- Dopo il download (righe ~156-168) c'è uno scan che trova il file audio tra estensioni `['mp3','m4a','webm','opus','ogg']` e, se non è `.mp3`, **rinomina** l'estensione a `.mp3` senza riconvertire (righe ~163-168). Questo è la causa del container sbagliato.
- Poi scan della thumb tra `['jpg','jpeg','png','webp']` (righe ~170-175).
- `writethumbnail: True` è già presente.
- La thumb file serve ancora dopo: viene ritornata (`thumb`) e inviata separatamente a Telegram dal chiamante. NON deve sparire dopo l'embed.

## Sottoproblemi (in ordine)
1. Sostituire i `postprocessors` di `download_opts` con la catena corretta:
   ```python
   'postprocessors': [
       {'key': 'FFmpegExtractAudio', 'preferredcodec': 'mp3', 'preferredquality': '192'},
       {'key': 'FFmpegMetadata', 'add_metadata': True},
       {'key': 'EmbedThumbnail', 'already_have_thumbnail': True},
   ],
   ```
   - `FFmpegExtractAudio` produce un vero `.mp3`.
   - `FFmpegMetadata` scrive i tag ID3 dai campi disponibili in `info` (title, artist/uploader, album se presente).
   - `EmbedThumbnail` incorpora la copertina nel mp3. `already_have_thumbnail: True` evita che la thumb file venga cancellata dopo l'embed (serve ancora a Telegram).
2. Compatibilità copertina su MP3: la thumb YouTube può essere `.webp`, che l'embed su mp3 non sempre accetta. Aggiungere il convertitore PRIMA di `EmbedThumbnail`:
   ```python
   {'key': 'FFmpegThumbnailsConvertor', 'format': 'jpg'},
   ```
   inserito tra `FFmpegMetadata` e `EmbedThumbnail`. Così lo scan thumb troverà `.jpg`.
3. Rimuovere l'hack di rinomina estensione (righe ~163-168): con `FFmpegExtractAudio` il file è già `.mp3`. Lo scan che individua `audio_file` tra le estensioni va **mantenuto** (troverà `.mp3`); rimuovere solo il blocco `if audio_file and not audio_file.endswith('.mp3'): ... os.rename(...)`.
4. Lasciare invariato tutto il resto: pre-check durata/dimensione, scan thumb, controllo `TOO_LARGE_POSTCHECK`, cleanup dei leftover, valori di ritorno `(info, audio_file, thumb, base)`.

## Note e limiti (da NON risolvere qui)
- Album e "artisti partecipanti" dipendono dai campi che YouTube espone in `info`. Su video YouTube normali spesso c'è solo `uploader` (niente `album`/`artist`/`track`): in quei casi il tag resta vuoto — non è un bug del codice. Nessuna forzatura verso YouTube Music in questo task.
- Il re-encode a mp3 è lossy e un po' più lento: accettato per decisione di progetto (vedi DECISIONS.md).

## Skill di codice
Caricare `coding-standard` (Python, nessuna skill più specifica per il progetto).

## Verifica finale del task
- Import/compile del modulo senza errori.
- Aggiornare il worklog: spuntare i sottoproblemi e marcare `DA TESTARE` (verifica metadati la fa l'utente a runtime).

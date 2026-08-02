# Task 2 — Nome file salvato = solo titolo

## Obiettivo
Il file salvato su disco deve avere come nome **solo il titolo pulito** della canzone (es. `Io sono.mp3`), non `Artista - Titolo`. I tag ID3 restano invariati (title = titolo pulito, artist = artista vero), già gestiti da FFmpegMetadata.

## Prerequisiti bloccanti
- Deve esistere ed essere leggibile: `core/handlers/callbacks.py`. Se manca, fermarsi.
- Eseguire DOPO il Task 1 di questa feature (i campi puliti popolano `title`).
- Non toccare file diversi da quelli elencati.
- Version control: git in sola lettura lato orchestratore. Agent-Code NON committa/pusha.
- Verifica: `python -m py_compile`.

## File da toccare
- `core/handlers/callbacks.py` — `save_to_directory`, costruzione di `dest_basename`.

## Fatti sul codice attuale
- In `save_to_directory` (handler `savedir_`):
  ```python
  entry = data_storage.get(f"info_{key}")
  title = entry.get("title") if entry else None
  artist = entry.get("artist") if entry else None
  if artist and title:
      dest_basename = f"{artist} - {title}"
  elif title:
      dest_basename = title
  else:
      dest_basename = "audio"
  ```
- `dest_basename` viene passato a `save_pending_to_folder(key, subfolder, dest_basename)` che salva come `<safe_basename>.mp3` (sanitizzazione già presente in `music_library._sanitize_filename`).

## Sottoproblemi
1. Cambiare la costruzione di `dest_basename` per usare **solo il titolo**:
   ```python
   dest_basename = title or "audio"
   ```
   Rimuovere il ramo `f"{artist} - {title}"`. `artist` non serve più qui (si può smettere di leggerlo se non usato altrove nella funzione — verificare che non sia usato oltre).
2. Non toccare `save_pending_to_folder` né la sanitizzazione (già gestiscono il nome file).

## Note
- Rischio collisione: due canzoni con lo stesso titolo di artisti diversi si sovrascrivono nella stessa cartella. Accettato per decisione dell'utente ("solo titolo e basta"). Non introdurre suffissi.
- I tag del file (title/artist/album) non dipendono dal nome file: restano quelli scritti da FFmpegMetadata.

## Skill di codice
Caricare `coding-standard`. Commenti in italiano forma infinito.

## Verifica finale
- `python -m py_compile core/handlers/callbacks.py`.
- Aggiornare il worklog: spuntare i sottoproblemi, marcare `DA TESTARE`.

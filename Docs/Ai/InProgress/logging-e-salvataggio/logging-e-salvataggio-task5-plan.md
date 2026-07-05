# Task 5 — Errore di download visibile su Telegram

## Obiettivo
Quando yt-dlp fallisce il download (es. `HTTP Error 403: Forbidden`), l'utente su Telegram deve vedere l'errore e la sua descrizione, non il codice interno `YT_DOWNLOAD_FAILED`. Il traceback completo resta nel log come ora.

## Prerequisiti bloccanti
- Devono esistere ed essere leggibili: `core/services/youtube.py`, `core/handlers/messages.py`, `core/handlers/callbacks.py`. Se manca uno, fermarsi.
- Non toccare file diversi. Mantenere i Task 1-4 già presenti.
- `html` è già importato in `messages.py` (Task 3). `callbacks.py` non serve html (i popup `cq.answer` sono testo semplice).
- Version control: git in sola lettura lato orchestratore. Agent-Code NON committa/pusha.
- Target verifica: `python -m py_compile` sui file toccati.

## Fatti verificati (stato attuale)
- `youtube.py` `download_by_url` → `pre_check_and_download`: due punti catturano `DownloadError` e fanno `raise Exception("YT_DOWNLOAD_FAILED")`, loggando il vero errore con `logger.error(f"... {e}")`:
  - pre-check `extract_info(url, download=False)` (~riga 116-118).
  - download `extract_info(url, download=True)` (~riga 150-152).
  - `e` è un `DownloadError`; `str(e)` = es. `ERROR: unable to download video data: HTTP Error 403: Forbidden`.
- `messages.py` `message_handler`, blocco finale `except Exception as e:`:
  ```python
  error_str = str(e)
  if "LONG_AUDIO" in error_str: ...ERROR_LONG_AUDIO
  elif "TOO_LARGE" in error_str: ...ERROR_TOO_LARGE
  else:
      logger.error(f"Download/Search Error: {error_str}", exc_info=True)
      msg_error = strings.ERROR_PREFIX + error_str
  ```
  `msg_error` va poi in `message.answer(msg_error)` con parse_mode HTML → serve escape sui contenuti dinamici.
- `callbacks.py` `choose_song`, blocco `except Exception as e:`:
  ```python
  if "TOO_LARGE" in error_str: cq.answer(ERROR_TOO_LARGE, show_alert=True)
  elif "LONG_AUDIO" in error_str: cq.answer(ERROR_LONG_AUDIO, show_alert=True)
  else:
      logger.error(f"Download Error for alternative: {error_str}", exc_info=True)
      cq.answer(f"Error: {error_str}", show_alert=True)
  ```
  `cq.answer(..., show_alert=True)` è un popup di testo semplice (no HTML), cap Telegram ~200 char.

## Sottoproblemi (in ordine)
1. `youtube.py` — entrambi i punti `DownloadError`: cambiare `raise Exception("YT_DOWNLOAD_FAILED")` in `raise Exception(f"YT_DOWNLOAD_FAILED: {e}")`. Lasciare invariato il `logger.error`. Non toccare gli altri sentinel (`LONG_AUDIO`, `TOO_LARGE_*`).
2. `messages.py` — ramo `else` del blocco `except Exception`:
   - Estrarre la descrizione: se `"YT_DOWNLOAD_FAILED"` è in `error_str`, prendere la parte dopo `"YT_DOWNLOAD_FAILED:"` (strip); altrimenti usare `error_str` intero.
   - `msg_error = strings.ERROR_PREFIX + html.escape(detail[:300])`.
   - Mantenere invariato `logger.error(..., exc_info=True)`.
3. `callbacks.py` `choose_song` — ramo `else`:
   - Stesso estratto della descrizione (togliere il prefisso `YT_DOWNLOAD_FAILED:` se presente).
   - `await cq.answer(f"Error: {detail[:190]}", show_alert=True)` (testo semplice, nessun html.escape).
4. Non modificare i rami `LONG_AUDIO`/`TOO_LARGE` né il blocco `except TelegramBadRequest`.

## Note
- Mostrare solo la descrizione concisa di yt-dlp, non il traceback (quello resta nel log e col comando `log` del Task 3).
- Il 403 in sé (causa a monte) non è oggetto di questo task: qui si rende solo visibile.

## Skill di codice
Caricare `coding-standard`. Commenti in italiano forma infinito.

## Verifica finale
- `python -m py_compile` su `youtube.py`, `messages.py`, `callbacks.py`.
- Aggiornare il worklog: spuntare i sottoproblemi, marcare `DA TESTARE`.

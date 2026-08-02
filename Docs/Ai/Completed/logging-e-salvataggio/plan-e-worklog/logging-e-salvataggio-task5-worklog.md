# Worklog Task 5 — Errore di download visibile su Telegram

## Avanzamento
- [x] youtube.py: i due `raise Exception("YT_DOWNLOAD_FAILED")` includono ora `{e}`
- [x] messages.py: ramo else mostra la descrizione (html.escape, cap 300), togliendo il prefisso sentinel
- [x] callbacks.py choose_song: popup mostra la descrizione (cap ~190), togliendo il prefisso sentinel
- [x] Non toccati i rami LONG_AUDIO/TOO_LARGE e except TelegramBadRequest
- [x] Verificato python -m py_compile sui 3 file

DA TESTARE: forzare un errore download e vedere descrizione su Telegram

## Test
<!-- Compilata dall'orchestratore dopo i test runtime dell'utente. -->

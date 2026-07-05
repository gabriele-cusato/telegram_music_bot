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

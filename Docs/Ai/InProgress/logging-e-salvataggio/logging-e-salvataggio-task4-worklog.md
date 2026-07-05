# Worklog Task 4 (RIVISTO) — Bottone "Save Srv", niente conferma

> Il worklog della prima versione (conferma Sì/No) è superato: quel lavoro va disfatto/riadattato secondo il plan rivisto.

## Avanzamento
- [x] strings.py: rimosse SONG_CONFIRM_PROMPT/BUTTON_CONFIRM_YES/NO; aggiunta BUTTON_SAVE_SRV (+ eventuale SAVE_EXPIRED)
- [x] callbacks.py: PENDING_SAVE_TIMEOUT_SEC = INFO_EXPIRATION_HOURS*3600 (import INFO_EXPIRATION_HOURS)
- [x] callbacks.py: `offer_disk_save` ora fa solo stage + timer, nessun messaggio (firma invariata)
- [x] callbacks.py: rimosso handler `confirm_song`; aggiunto handler `save_srv` (savesrv_) che invia il picker
- [x] messages.py: bottone Save Srv nella kb dell'audio; rimossa `remove_not_right_button` + schedulazione
- [x] callbacks.py: `choose_song` kb con bottone Save Srv
- [x] music_library.py: helper `pending_exists(key)` e `prune_orphan_pending(is_valid_key)`
- [x] main.py: prune di temp/pending all'avvio dopo cleanup_expired_data
- [x] Verificato che `savedir_` resta invariato e funziona sul messaggio del picker
- [x] Verificato `python -m py_compile` su tutti i file toccati
- [ ] DA TESTARE: flusso runtime Save Srv -> picker -> salvataggio; Not right? non sparisce; prune all'avvio

## Stato task
DA TESTARE

## Test
<!-- Compilata dall'orchestratore dopo i test runtime dell'utente. -->

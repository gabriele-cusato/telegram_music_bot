# Worklog Task 4 — Fix "message too long" nel delete + invariante sicurezza

## Avanzamento
- [x] build_dedup_session: doppio budget (testo < ~3500 char + max 60 candidati), costruzione incrementale, stop al primo limite
- [x] Invariante: session["candidates"] == candidati mostrati come bottoni; troncati mai in sessione (commentato nel codice)
- [x] Nota di troncamento nel testo quando si taglia
- [x] messages.py dedup_command_handler: try/except TelegramBadRequest sull'invio + fallback message + pop sessione se invio fallisce
- [x] (Difensivo) dd_ok: controllo path dentro MUSIC_DIR prima di os.remove
- [x] Verificato py_compile (venv) + prova scratchpad dell'invariante (molti gruppi, testo sotto limite, session == bottoni)
- [ ] DA TESTARE: /delete sulla cartella vera non dà più "message too long"; cancella solo i mostrati

DA TESTARE

## Test
<!-- Compilata dall'orchestratore dopo i test runtime dell'utente. -->

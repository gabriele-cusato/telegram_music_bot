# Worklog Task 1 — Modulo priorità cartelle

## Avanzamento
- [x] Creato core/services/library_priority.py con PRIORITY_FILE = MUSIC_DIR/priority.txt
- [x] _read_raw / _write robusti (utf-8, best-effort)
- [x] sync_priority: mantiene ordine esistente, aggiunge nuove in coda, scarta le rimosse, autocrea file
- [x] get_order, apply_move (su/giù), priority_rank
- [x] Robustezza MUSIC_DIR inesistente
- [x] Verificato py_compile + prova funzioni pure nello scratchpad

DA TESTARE

## Test
<!-- Compilata dall'orchestratore dopo i test runtime dell'utente. -->

# Worklog Task 3 — Comando dedup

## Avanzamento
- [x] Creato core/services/library_dedup.py: _collect_mp3 + find_duplicate_groups (clustering fuzzy cross-folder, keep = priorità più alta)
- [x] strings.py: DEDUP_* + bottoni conferma/annulla
- [x] callbacks.py: dedup_sessions store + rendering keyboard toggle
- [x] callbacks.py: handler dd_ (toggle / confirm-delete / cancel), cancellazione file selezionati con log
- [x] messages.py: _is_dedup_command + handler solo privata, find_duplicate_groups in thread, crea sessione
- [x] Cap numero candidati + avviso troncamento
- [x] Verificato py_compile + prova grouping nello scratchpad (no file reali)
- [x] DA TESTARE: dedup trova duplicati, deseleziona, conferma cancella solo i selezionati

## Stato
DA TESTARE (runtime bot). Logica pura verificata nello scratchpad; codice compilato senza errori.

## Test
<!-- Compilata dall'orchestratore dopo i test runtime dell'utente. -->

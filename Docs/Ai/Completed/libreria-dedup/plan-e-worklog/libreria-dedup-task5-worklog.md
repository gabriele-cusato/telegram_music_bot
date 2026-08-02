# Worklog Task 5 — priority.txt autoritativo, cartelle non elencate ignorate

## Avanzamento
- [x] sync_priority: se file manca -> seed con tutte; se esiste -> solo elencate esistenti, niente auto-add, niente rewrite
- [x] library_dedup._collect_mp3(order): itera i membri di priority invece di list_subfolders
- [x] find_duplicate_groups: calcola order una volta e lo passa a _collect_mp3
- [x] Verificato nessun altro chiamante di _collect_mp3 (Grep)
- [x] Verificato py_compile (venv) + prove scratchpad (seed, sottoinsieme, vuoto, stale, cartella ignorata dal dedup)

## DA TESTARE
- Cartella non in priority.txt ignorata dal /delete

## Test
<!-- Compilata dall'orchestratore dopo i test runtime dell'utente. -->

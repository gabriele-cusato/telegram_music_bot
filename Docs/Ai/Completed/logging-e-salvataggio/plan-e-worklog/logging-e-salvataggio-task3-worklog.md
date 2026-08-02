# Worklog Task 3 — Comando `log` in chat

Stato: DA TESTARE (implementazione completa, resta la verifica runtime su Telegram in chat privata)

## Avanzamento
- [x] Creato `core/services/log_reader.py` (lettura + parsing per record + filtri livello/data)
- [x] Helper conversione data gg/mm/aa -> YYYY-MM-DD
- [x] Lettura backup ruotati bot.log.1..3 quando c'è filtro data
- [x] Nuovo handler comando `log` in messages.py, gate solo chat privata
- [x] Parsing argomenti (livello / N default 25 / data), messaggio d'uso su token non validi
- [x] Output in <pre> con html.escape, chunking sotto 4096 char
- [x] Stringhe in strings.py
- [x] Verificato import/compile senza errori
- [x] DA TESTARE: comportamento runtime su Telegram (privata)

## Test
<!-- Compilata dall'orchestratore dopo i test runtime dell'utente. -->

# installer-guidato — task4 — Worklog

## Avanzamento
- [x] Modello `musicbot.service` con segnaposto, dipendenza dalla rete e riavvio automatico
- [x] Impianto comune: shebang, intestazioni, calcolo della radice, funzioni di stampa, nome del servizio condiviso
- [x] `RUN_BOT_STARTUP.sh`: verifica che l'installazione sia completa prima di installare qualcosa
- [x] `RUN_BOT_STARTUP.sh`: verifica della presenza di systemd e del file modello
- [x] `RUN_BOT_STARTUP.sh`: sostituzione dei segnaposto, installazione in `/etc/systemd/system/` e attivazione
- [x] `RUN_BOT_STARTUP.sh`: verifica finale dello stato, comando per i log e avviso sul polling singolo
- [x] `STOP_BOT_STARTUP.sh`: arresto, disattivazione, rimozione del file di unità e ricarica di systemd
- [x] `STOP_BOT_STARTUP.sh`: comportamento pulito quando non c'è nulla da rimuovere
- [x] Riepilogo conclusivo in entrambi gli script, con il comando per l'operazione inversa
- [x] Verifica di sintassi con `bash -n` su entrambi gli script, senza esecuzione

DA TESTARE

## Test
_Da compilare dopo i test dell'utente._

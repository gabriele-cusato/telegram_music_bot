# installer-guidato — task4 — Avvio automatico su Linux

## Prerequisiti bloccanti
Verificare che esistano e siano leggibili, prima di scrivere qualunque file. Se anche uno solo manca o il percorso è ambiguo, fermarsi senza creare né modificare nulla e segnalarlo:
- `main.py` nella radice del progetto (è il programma che il servizio deve avviare).
- `core/config.py` (conferma che i percorsi di lavoro sono relativi e quindi serve una `WorkingDirectory` corretta).
- Questo file di plan e il worklog `installer-guidato-task4-worklog.md`.
- Nessun file o cartella è dichiarato segreto o vietato in questa feature. Unica cartella da non leggere né modificare: `data/`, che contiene il `.env` reale con il token del bot.
- **Version control**: git è consentito in **sola lettura** (`git status`, `git diff`, `git log`, `git show`). Vietati commit, push, checkout, reset e qualunque comando che modifichi lo stato del repository.
- **Build/verifica**: non esiste un target di compilazione. La verifica consentita è il solo controllo di sintassi `bash -n` descritto nel sottoproblema finale.

## Obiettivo
Creare gli script che gestiscono l'avvio automatico del bot su Linux tramite systemd, senza che l'utente debba scrivere a mano un file di servizio:
- `RUN_BOT_STARTUP.sh` — genera il servizio con i percorsi reali della macchina, lo installa e lo avvia.
- `STOP_BOT_STARTUP.sh` — ferma il servizio, lo disattiva, **elimina il file dal sistema** e ricarica systemd, senza lasciare residui.
- `musicbot.service` — il modello del file di servizio, con segnaposto che `RUN_BOT_STARTUP.sh` sostituisce con i valori reali.

L'utente deve poter attivare e disattivare l'avvio automatico in qualsiasi momento, e la disattivazione deve riportare il sistema esattamente com'era prima.

## File da toccare
Tre, tutti nuovi:
- `INSTALL_BOT/LINUX/RUN_BOT_STARTUP.sh`
- `INSTALL_BOT/LINUX/STOP_BOT_STARTUP.sh`
- `INSTALL_BOT/LINUX/musicbot.service`

Creare le cartelle `INSTALL_BOT/` e `INSTALL_BOT/LINUX/` se non esistono. **Non toccare nessun altro file**, in particolare non `main.py`, non `core/`, non `INSTALL_BOT/INSTALL_BOT.LINUX.sh` (lo scrive un altro agente in parallelo), e non `start_bot.bat`/`stop_bot.bat`/`run_hidden.vbs`.

## Skill di codice da caricare
`coding-standard` (non esiste una skill specifica per bash o per i file di unità systemd).

## Fatti già verificati — non ri-esplorare
- **Radice del progetto**: la cartella che contiene `main.py`, `requirements.txt`, `core/`. Questi script stanno in `INSTALL_BOT/LINUX/`, quindi la radice è **due livelli sopra**: ricavarla dal percorso dello script (`cd "$(dirname "$0")/../.." && pwd`), **mai** da percorsi assoluti scritti a mano.
- **Percorsi relativi**: `core/config.py` definisce `DATA_PATH = "data"` e `TEMP_PATH = "temp"` come percorsi **relativi alla directory di lavoro**. Il servizio deve quindi impostare `WorkingDirectory` sulla radice del progetto, altrimenti il bot crea `data/` e `temp/` altrove e non trova il file `.env`.
- **Interprete da usare**: `.venv/bin/python` dentro la radice del progetto. Il servizio non deve usare il Python di sistema, perché `core/yt_dlp_update/yt_dlp_manager.py` riga 16 esegue a ogni avvio `pip install --upgrade yt-dlp` con `sys.executable`, e su Debian recenti il Python di sistema rifiuta le installazioni con pip.
- **Il servizio va eseguito come utente normale**, non come root: la venv, `data/` e `temp/` appartengono all'utente che ha fatto l'installazione, e il bot deve poterci scrivere. L'utente e il gruppo vanno ricavati da chi lancia lo script, non scritti a mano.
- **Attesa della rete**: il bot fa polling verso Telegram e all'avvio aggiorna yt-dlp, quindi senza rete fallisce. Il vecchio `start_bot.bat` risolveva il problema con un ciclo di ping a 8.8.8.8; su systemd lo stesso risultato si ottiene dichiarando la dipendenza dalla rete raggiungibile.
- **Riavvio automatico**: il servizio deve ripartire da solo se il processo termina, con una pausa tra i tentativi per non entrare in un ciclo stretto di riavvii.
- **File `.env`**: `core/config.py` lo carica da `data/.env`. Senza `BOT_TOKEN` valorizzato il bot esce subito, quindi il servizio partirebbe e morirebbe in continuazione.
- **Vincolo del polling**: un solo processo per volta può fare polling con lo stesso token del bot. Se ne girano due, Telegram alterna gli aggiornamenti tra i due e il bot sembra perdere messaggi.
- **Percorso dei file di unità systemd**: `/etc/systemd/system/`. Scriverci richiede privilegi di amministratore, quindi `sudo`.
- **Log**: con systemd l'output del bot finisce nel journal e si consulta con `journalctl -u <nome-servizio>`. È l'equivalente del vecchio `error_log.txt` prodotto dal `.bat` su Windows, e va indicato all'utente nel riepilogo.

## Scelte già decise dall'utente — rispettarle
- L'avvio automatico **non deve essere attivato dallo script di installazione**: si attiva solo qui, quando l'utente lo vuole esplicitamente.
- Deve esistere uno script di spegnimento che **rimuova completamente** il servizio dal sistema, per non lasciare configurazioni sporche.

## Sottoproblemi, nell'ordine
1. **Modello `musicbot.service`**: scrivere il file di unità con segnaposto riconoscibili al posto dei valori che dipendono dalla macchina, cioè utente, working directory e percorso dell'interprete. Deve dichiarare la dipendenza dalla rete raggiungibile, il riavvio automatico con pausa tra i tentativi, e l'attivazione all'avvio del sistema. Aggiungere un commento iniziale che spieghi che il file è un modello e che i segnaposto vengono sostituiti da `RUN_BOT_STARTUP.sh`.
2. **Impianto comune ai due script**: shebang, intestazione a blocco che spiega cosa fa lo script, cosa installa nel sistema e come si annulla; calcolo della radice del progetto risalendo di due livelli; funzioni di stampa degli esiti; nome del servizio definito una sola volta e identico nei due script.
3. **`RUN_BOT_STARTUP.sh` — verifica che l'installazione sia completa**: prima di installare qualcosa, controllare che esistano `main.py`, `.venv/bin/python` e `data/.env` con `BOT_TOKEN` valorizzato. Se manca qualcosa, non installare nulla e rimandare a `INSTALL_BOT/INSTALL_BOT.LINUX.sh`. Installare un servizio su un'installazione incompleta produrrebbe un processo che parte e muore a ripetizione.
4. **`RUN_BOT_STARTUP.sh` — verifica dell'ambiente**: controllare che `systemctl` esista, cioè che la distribuzione usi systemd; se non c'è, fermarsi spiegando che l'avvio automatico va configurato con lo strumento della distribuzione in uso. Controllare inoltre che il file modello `musicbot.service` sia presente accanto allo script.
5. **`RUN_BOT_STARTUP.sh` — generazione e installazione del servizio**: sostituire i segnaposto del modello con utente, radice del progetto e percorso dell'interprete reali, scrivere il risultato in `/etc/systemd/system/` con `sudo`, ricaricare la configurazione di systemd e attivare il servizio in modo che parta subito e anche ai riavvii successivi. Se un servizio con lo stesso nome esiste già, sostituirlo invece di duplicarlo.
6. **`RUN_BOT_STARTUP.sh` — verifica finale**: controllare che il servizio risulti attivo e dirlo all'utente; indicare il comando per leggere i log dal journal. Ricordare che un solo processo per volta può fare polling con lo stesso token, quindi va spenta l'eventuale istanza su un'altra macchina. Se il servizio non è partito, mostrare come consultare i log per capire il motivo.
7. **`STOP_BOT_STARTUP.sh` — arresto e rimozione completa**: fermare il servizio se attivo, disattivarne l'avvio automatico, eliminare il file di unità da `/etc/systemd/system/`, ricaricare systemd e ripulire lo stato dei servizi non più esistenti. Alla fine verificare che il servizio non risulti più né attivo né registrato, e dirlo esplicitamente.
8. **Comportamento quando non c'è nulla da rimuovere**: se il servizio non esiste, `STOP_BOT_STARTUP.sh` non deve fallire né allarmare: dichiara che non c'era nulla da rimuovere e termina con esito positivo.
9. **Riepilogo conclusivo** in entrambi gli script: cosa è stato fatto, cosa risulta attivo adesso, il comando per consultare i log e il comando dell'altro script per fare l'operazione inversa.
10. **Verifica di sintassi**: controllare entrambi gli script con `bash -n`, che ne verifica la sintassi **senza eseguirli**. **Non eseguirli**: modificherebbero la configurazione della macchina. Il file `.service` non è eseguibile e non richiede verifica.

## Regole
- Commenti e messaggi a video: i **commenti nel codice in italiano**, secondo le regole di commento del progetto. I **messaggi mostrati all'utente in italiano**, coerenti con il `README.INSTALL.md` della stessa cartella.
- Nessun percorso assoluto scritto a mano: tutto deve derivare dalla posizione dello script e dall'utente che lo lancia.
- Non toccare `data/.env`: contiene il token reale dell'utente. Va solo verificato che `BOT_TOKEN` sia presente e non vuoto.
- Usare `sudo` **solo** per i comandi che riguardano il file di unità e `systemctl`: nient'altro.
- Il servizio non deve girare come root.
- Ogni messaggio d'errore deve dire **cosa** è mancato e **quale comando** l'utente deve lanciare per rimediare.

## Al termine
Aggiornare `installer-guidato-task4-worklog.md`: spuntare i sottoproblemi completati nella sezione "Avanzamento" e aggiungere il tag `DA TESTARE` a fine task. Non scrivere nella sezione "Test": la compila l'orchestratore dopo le prove dell'utente.

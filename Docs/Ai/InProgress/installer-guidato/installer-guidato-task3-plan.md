# installer-guidato — task3 — Avvio automatico su Windows

## Prerequisiti bloccanti
Verificare che esistano e siano leggibili, prima di scrivere qualunque file. Se anche uno solo manca o il percorso è ambiguo, fermarsi senza creare né modificare nulla e segnalarlo:
- `main.py` nella radice del progetto (è il programma che l'attività pianificata deve avviare).
- `core/config.py` (conferma che i percorsi di lavoro sono relativi e quindi serve una working directory corretta).
- Questo file di plan e il worklog `installer-guidato-task3-worklog.md`.
- Nessun file o cartella è dichiarato segreto o vietato in questa feature. Unica cartella da non leggere né modificare: `data/`, che contiene il `.env` reale con il token del bot.
- **Version control**: git è consentito in **sola lettura** (`git status`, `git diff`, `git log`, `git show`). Vietati commit, push, checkout, reset e qualunque comando che modifichi lo stato del repository.
- **Build/verifica**: non esiste un target di compilazione. La verifica consentita è il solo controllo di sintassi PowerShell descritto nel sottoproblema finale.

## Obiettivo
Creare due script PowerShell che gestiscono l'avvio automatico del bot su Windows, senza che l'utente debba conoscere l'Utilità di pianificazione:
- `RUN_BOT_STARTUP.ps1` — registra e avvia l'attività pianificata che fa partire il bot da solo.
- `STOP_BOT_STARTUP.ps1` — ferma il bot, elimina l'attività pianificata e **non lascia nulla nel sistema**.

L'utente deve poter attivare e disattivare l'avvio automatico in qualsiasi momento, e la disattivazione deve riportare il sistema esattamente com'era prima.

## File da toccare
Due, entrambi nuovi:
- `INSTALL_BOT/WIN/RUN_BOT_STARTUP.ps1`
- `INSTALL_BOT/WIN/STOP_BOT_STARTUP.ps1`

Creare le cartelle `INSTALL_BOT/` e `INSTALL_BOT/WIN/` se non esistono. **Non toccare nessun altro file**, in particolare non `main.py`, non `core/`, non `INSTALL_BOT/INSTALL_BOT.WIN.ps1` (lo scrive un altro agente in parallelo), e non `start_bot.bat`/`stop_bot.bat`/`run_hidden.vbs`.

## Skill di codice da caricare
`coding-standard` (non esiste una skill specifica per PowerShell).

## Fatti già verificati — non ri-esplorare
- **Radice del progetto**: la cartella che contiene `main.py`, `requirements.txt`, `core/`. Questi script stanno in `INSTALL_BOT/WIN/`, quindi la radice è **due livelli sopra**: ricavarla da `$PSScriptRoot` risalendo di due cartelle, **mai** da percorsi assoluti scritti a mano.
- **Percorsi relativi**: `core/config.py` definisce `DATA_PATH = "data"` e `TEMP_PATH = "temp"` come percorsi **relativi alla directory di lavoro**. L'attività pianificata deve quindi avere la working directory impostata sulla radice del progetto, altrimenti il bot crea `data/` e `temp/` altrove e non trova il file `.env`.
- **Interprete da usare**: `.venv\Scripts\pythonw.exe`, non `python.exe`. `pythonw.exe` esegue senza aprire la finestra della console, ottenendo lo stesso risultato del vecchio `run_hidden.vbs` ma senza file di appoggio. Se `pythonw.exe` non esiste nella venv, ripiegare su `python.exe` segnalando che comparirà una finestra.
- **Gli script esistenti non sono riutilizzabili**: `start_bot.bat` e `run_hidden.vbs` contengono il percorso `C:\Projects\YtMusicDownload\telegram_music_bot` **scritto a mano**, quindi funzionano solo sulla macchina di sviluppo. I nuovi script non devono richiamarli né modificarli: restano nel progetto come storico.
- **Come `stop_bot.bat` ferma il bot oggi**: cerca i processi `python.exe` la cui riga di comando contiene `telegram_music_bot` e li termina. È il criterio di riconoscimento del processo da riusare, adattandolo alla radice reale del progetto invece del nome fisso, e considerando anche `pythonw.exe`.
- **File `.env`**: `core/config.py` lo carica da `data/.env`. Senza `BOT_TOKEN` valorizzato il bot esce subito, quindi l'attività pianificata partirebbe e morirebbe in continuazione.
- **Vincolo del polling**: un solo processo per volta può fare polling con lo stesso token del bot. Se ne girano due, Telegram alterna gli aggiornamenti tra i due e il bot sembra perdere messaggi.

## Scelte già decise dall'utente — rispettarle
- L'avvio automatico **non deve essere attivato dallo script di installazione**: si attiva solo qui, quando l'utente lo vuole esplicitamente.
- Deve esistere uno script di spegnimento che **rimuova completamente** ciò che è stato registrato, per non lasciare configurazioni sporche nel sistema.

## Sottoproblemi, nell'ordine
1. **Impianto comune ai due script**: intestazione a blocco che spiega cosa fa lo script, cosa registra nel sistema e come si annulla; calcolo della radice del progetto risalendo da `$PSScriptRoot`; funzioni di stampa degli esiti; scelta di un nome univoco e riconoscibile per l'attività pianificata, usato identico dai due script.
2. **Controllo dei privilegi**: registrare o rimuovere un'attività pianificata richiede una console PowerShell **come amministratore**. Verificarlo all'inizio di entrambi gli script e, se manca, fermarsi spiegando come riaprire il terminale con i privilegi necessari.
3. **`RUN_BOT_STARTUP.ps1` — verifica che l'installazione sia completa**: prima di registrare qualcosa, controllare che esistano `main.py`, la venv con il suo interprete, e `data/.env` con `BOT_TOKEN` valorizzato. Se manca qualcosa, non registrare nulla e rimandare a `INSTALL_BOT\INSTALL_BOT.WIN.ps1`. Registrare un avvio automatico su un'installazione incompleta produrrebbe un processo che parte e muore a ripetizione.
4. **`RUN_BOT_STARTUP.ps1` — registrazione dell'attività**: creare l'attività pianificata che al logon dell'utente corrente avvia l'interprete della venv su `main.py`, con working directory sulla radice del progetto. Se un'attività con lo stesso nome esiste già, sostituirla invece di duplicarla. Configurarla in modo che non venga interrotta dalle politiche di risparmio energetico e che riparta se l'avvio fallisce.
5. **`RUN_BOT_STARTUP.ps1` — avvio immediato e verifica**: far partire subito l'attività senza aspettare il riavvio, poi verificare che il processo del bot sia effettivamente attivo e dirlo all'utente. Ricordare che un solo processo per volta può fare polling con lo stesso token, quindi va spenta l'eventuale istanza su un'altra macchina.
6. **`STOP_BOT_STARTUP.ps1` — arresto e rimozione**: fermare l'attività pianificata se in esecuzione, eliminarla, poi terminare gli eventuali processi Python del bot rimasti, riconosciuti dalla riga di comando che contiene il percorso della radice del progetto. Alla fine verificare che non resti né l'attività né alcun processo, e dirlo esplicitamente.
7. **Comportamento quando non c'è nulla da rimuovere**: se l'attività non esiste, `STOP_BOT_STARTUP.ps1` non deve fallire né allarmare: dichiara che non c'era nulla da rimuovere e termina con esito positivo.
8. **Riepilogo conclusivo** in entrambi gli script: cosa è stato fatto, cosa risulta attivo adesso, e il comando dell'altro script per fare l'operazione inversa.
9. **Verifica di sintassi**: controllare che entrambi gli script siano sintatticamente validi senza eseguirli, con il parser di PowerShell (`[System.Management.Automation.PSParser]::Tokenize` oppure `[scriptblock]::Create` sul contenuto del file). **Non eseguirli**: modificherebbero la configurazione della macchina di sviluppo.

## Regole
- Commenti e messaggi a video: i **commenti nel codice in italiano**, secondo le regole di commento del progetto. I **messaggi mostrati all'utente in italiano**, coerenti con il `README.INSTALL.md` della stessa cartella.
- Nessun percorso assoluto scritto a mano: tutto deve derivare dalla posizione dello script.
- Non toccare `data/.env`: contiene il token reale dell'utente. Va solo verificato che `BOT_TOKEN` sia presente e non vuoto.
- La terminazione dei processi deve colpire **solo** i processi Python del progetto, riconosciuti dal percorso della radice nella riga di comando: mai terminare Python in modo indiscriminato.
- Ogni messaggio d'errore deve dire **cosa** è mancato e **quale comando** l'utente deve lanciare per rimediare.

## Al termine
Aggiornare `installer-guidato-task3-worklog.md`: spuntare i sottoproblemi completati nella sezione "Avanzamento" e aggiungere il tag `DA TESTARE` a fine task. Non scrivere nella sezione "Test": la compila l'orchestratore dopo le prove dell'utente.

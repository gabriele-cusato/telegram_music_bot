# installer-guidato — task2 — Script di installazione per Linux

## Prerequisiti bloccanti
Verificare che esistano e siano leggibili, prima di scrivere qualunque file. Se anche uno solo manca o il percorso è ambiguo, fermarsi senza creare né modificare nulla e segnalarlo:
- `requirements.txt` nella radice del progetto (serve a sapere cosa installa `pip`).
- `main.py` nella radice del progetto (è il punto di ingresso che lo script deve verificare).
- `core/config.py` (definisce i percorsi `data`/`temp` e le variabili d'ambiente attese).
- Questo file di plan e il worklog `installer-guidato-task2-worklog.md`.
- Nessun file o cartella è dichiarato segreto o vietato in questa feature. Unica cartella da non leggere né modificare: `data/`, che contiene il `.env` reale con il token del bot; lo script che scrivi la crea e la popola a runtime, ma tu non devi aprirla ora.
- **Version control**: git è consentito in **sola lettura** (`git status`, `git diff`, `git log`, `git show`). Vietati commit, push, checkout, reset e qualunque comando che modifichi lo stato del repository.
- **Build/verifica**: non esiste un target di compilazione. La verifica consentita è il solo controllo di sintassi `bash -n` descritto nel sottoproblema finale.

## Obiettivo
Creare `INSTALL_BOT/INSTALL_BOT.LINUX.sh`: uno script bash che installa e configura il bot su Linux (bersaglio principale: Raspberry Pi OS / Debian) in modo guidato, controllando ogni prerequisito e spiegando all'utente cosa fare per ciò che non può risolvere da solo.

Lo script deve essere **rieseguibile senza danni**: se una cosa è già a posto, la salta e lo dichiara, non la rifà e non sovrascrive nulla di esistente.

Il comportamento deve corrispondere a quello della versione Windows (`INSTALL_BOT.WIN.ps1`, scritto in parallelo da un altro agente): stessi controlli, stesso ordine, stessi messaggi finali. Non leggere quel file e non dipendere da esso: la sequenza da rispettare è quella descritta qui sotto.

## File da toccare
Uno solo, nuovo:
- `INSTALL_BOT/INSTALL_BOT.LINUX.sh`

Creare la cartella `INSTALL_BOT/` se non esiste. **Non toccare nessun altro file**, in particolare non `main.py`, non `core/`, non `requirements.txt`, non `.gitignore`, non `start_bot.bat`/`stop_bot.bat`/`run_hidden.vbs`.

## Skill di codice da caricare
`coding-standard` (non esiste una skill specifica per bash).

## Fatti già verificati — non ri-esplorare
- **Radice del progetto**: la cartella che contiene `main.py`, `requirements.txt`, `core/`. Lo script sta in `INSTALL_BOT/`, quindi la radice è la cartella padre dello script: ricavarla dal percorso dello script stesso (`cd "$(dirname "$0")/.." && pwd`), **mai** da percorsi assoluti scritti a mano.
- **Percorsi relativi**: `core/config.py` definisce `DATA_PATH = "data"` e `TEMP_PATH = "temp"` come percorsi **relativi alla directory di lavoro**. Il bot va quindi eseguito con working directory sulla radice del progetto, altrimenti crea `data/` e `temp/` nel posto sbagliato.
- **File `.env`**: `core/config.py` lo carica da `data/.env` (`load_dotenv(dotenv_path=os.path.join(DATA_PATH, ".env"))`). La cartella `data/` è in `.gitignore`, quindi dopo un `git clone` **non esiste** e va creata.
- **`.gitignore` contiene**: `__pycache__`, `data/`, `temp/`.
- **Versione Python minima**: `aiogram` dichiara `Requires-Python >=3.9`. Verificato sul pacchetto installato.
- **ffmpeg è obbligatorio**: `core/services/youtube.py` righe 172-176 usa i postprocessor `FFmpegExtractAudio`, `FFmpegMetadata`, `FFmpegThumbnailsConvertor`. Nel codice non è impostato `ffmpeg_location`, quindi yt-dlp cerca `ffmpeg` nel `PATH` di sistema. Senza ffmpeg ogni download fallisce.
- **La venv è obbligatoria su Debian/Raspberry Pi OS recenti**: `core/yt_dlp_update/yt_dlp_manager.py` riga 16 esegue all'avvio `pip install --upgrade yt-dlp` usando `sys.executable`. Su Debian Bookworm e successivi il Python di sistema è marcato "externally managed" e rifiuta le installazioni con pip, quindi senza venv quel comando fallisce a ogni avvio. La venv deve inoltre restare scrivibile dall'utente che esegue il bot.
- **Contenuto di `requirements.txt`**: `aiogram==3.22.0`, `aiohttp==3.12.15`, `python-dotenv==1.2.1`, `aiosqlite==0.21.0`, `RapidFuzz==3.14.1`, `text-unidecode==1.3`, `Unidecode==1.3.8`, `yt-dlp`, `requests`.
- **Variabili d'ambiente lette da `core/config.py`**, con i rispettivi default:
  - `BOT_TOKEN` — nessun default, **obbligatoria**; senza, `main.py` esce subito con un errore.
  - `MUSIC_DIR` — default `C:\Users\gabri\Music`, cioè un percorso Windows della macchina di sviluppo: su Linux va **sempre** impostato, altrimenti il salvataggio dei brani punta a un percorso inesistente.
  - `ALLOWED_CHAT_ID` — vuoto significa "tutte le chat di gruppo"; `false` significa nessuna; altrimenti lista di id separati da virgola.
  - `MUSIC_CHANNEL_ID`, `MUSIC_STORAGE_CHANNEL_ID` — vuoti valgono `-1`, cioè funzione disattivata.
  - `ALLOW_PRIVATE_CHAT` — default `false`, va messo a `true` per usare il bot in chat privata.
  - Opzionali con default già sensati: `FUZZY_DUPLICATE_THRESHOLD` (90), `MAX_FILE_SIZE_MB` (50), `MAX_SONG_DURATION_MIN` (15), `INFO_EXPIRATION_HOURS` (10), `ANTI_SPAM_INTERVAL` (15), `ANTI_SPAM_CALLBACK_INTERVAL` (1.0), `CONCURRENT_DOWNLOAD_LIMIT` (5), `DB_FILE` (`songs_cache.db`), `BLOCKED_USER_IDS` (vuoto).
- **Percorso del Python della venv su Linux**: `.venv/bin/python`.
- **Pacchetti di sistema necessari** su Debian/Raspberry Pi OS: `python3-venv` (senza, `python3 -m venv` fallisce anche se Python c'è), `python3-pip`, `ffmpeg`, `git`.
- Su Linux le librerie del progetto hanno wheel precompilate per **ARM 64 bit**; su un sistema a 32 bit `RapidFuzz` va compilato, il che richiede molto tempo e strumenti di build. È un'informazione da dare all'utente, non un errore bloccante.

## Scelte già decise dall'utente — rispettarle
- Lo script **installa davvero** i pacchetti mancanti, non si limita a segnalarli: usa `sudo apt install`. La password sudo verrà chiesta a terminale, ed è previsto. Se `apt` non è disponibile (distribuzione non Debian), non tentare altri gestori di pacchetti: stampare i nomi dei pacchetti necessari e fermarsi con esito negativo su quel controllo.
- Il file `data/.env`, se manca, va **chiesto a schermo** all'utente e scritto. Se esiste già, **non va sovrascritto**: si verifica soltanto che le variabili obbligatorie siano presenti e valorizzate.

## Sottoproblemi, nell'ordine
1. **Impianto dello script**: shebang `#!/usr/bin/env bash`; intestazione a blocco che spiega cosa fa lo script e a chi serve; `set -u` e gestione esplicita degli errori (evitare `set -e` secco, che impedirebbe di raccogliere più problemi in un unico riepilogo); calcolo della radice del progetto dal percorso dello script; funzioni di supporto per stampare gli esiti in modo uniforme (successo, avviso, errore) e un accumulatore dei problemi trovati, usato alla fine per il riepilogo.
2. **Controlli preliminari**: verificare che nella radice calcolata esistano `main.py`, `requirements.txt` e la cartella `core`. Se non ci sono, l'utente ha spostato lo script fuori dal progetto: fermarsi subito con un messaggio che spiega dove va posizionata la cartella `INSTALL_BOT`.
3. **Python**: verificare che esista `python3` e che la versione sia almeno 3.9. Verificare separatamente che il modulo `venv` sia disponibile, perché su Debian è in un pacchetto a parte: se manca, installare `python3-venv` con `apt`.
4. **Pacchetti di sistema**: verificare `ffmpeg` e `git`; installare con `sudo apt install -y` quelli mancanti, dopo un `sudo apt update`. Se `apt` non esiste, stampare l'elenco dei pacchetti necessari e registrare il problema.
5. **Ambiente virtuale**: creare `.venv` nella radice se assente, altrimenti riusarla dichiarandolo. Poi aggiornare `pip` e installare `requirements.txt` con il Python della venv. Segnalare che su sistemi a 32 bit l'installazione di `RapidFuzz` può richiedere una compilazione lunga.
6. **Cartelle di lavoro**: creare `data/` e `temp/` nella radice se mancano. Sono in `.gitignore` e dopo un clone non esistono.
7. **File `data/.env`**: se manca, chiedere a schermo i valori e scriverlo. `BOT_TOKEN` è obbligatorio e non deve essere accettato vuoto. `MUSIC_DIR` va proposto con un default ragionevole per Linux, ricavato dalla home dell'utente corrente, non un percorso fisso. Chiedere anche `ALLOW_PRIVATE_CHAT`, `ALLOWED_CHAT_ID`, `MUSIC_CHANNEL_ID`, `MUSIC_STORAGE_CHANNEL_ID`, spiegando in una riga a cosa serve ciascuno e cosa comporta lasciarlo vuoto. Impostare sul file permessi restrittivi (leggibile solo dal proprietario), perché contiene il token del bot. Se `data/.env` esiste già, **non riscriverlo**: leggerlo solo per controllare che `BOT_TOKEN` e `MUSIC_DIR` siano presenti e non vuoti, e segnalare quello che manca.
8. **Verifiche finali**: che la cartella indicata da `MUSIC_DIR` esista e sia scrivibile (se non esiste, proporre di crearla); che `ffmpeg -version` risponda; che il Python della venv riesca a importare `aiogram` e `yt_dlp`.
9. **Riepilogo conclusivo**: elencare ogni controllo con esito positivo o negativo, e in fondo i passi che restano all'utente. Se è tutto a posto, indicare il comando per avviare il bot a mano e ricordare che l'avvio automatico si attiva con lo script separato `INSTALL_BOT/LINUX/RUN_BOT_STARTUP.sh`. Avvisare che **un solo processo per volta** può fare polling con lo stesso token: se il bot gira già su un'altra macchina va spento, altrimenti i due si rubano i messaggi a vicenda. Terminare con codice di uscita diverso da zero se è rimasto un problema aperto.
10. **Verifica di sintassi**: controllare lo script con `bash -n` sul file, che ne verifica la sintassi **senza eseguirlo**. **Non eseguire lo script**: installerebbe pacchetti sulla macchina.

## Regole
- Commenti e messaggi a video: i **commenti nel codice in italiano**, secondo le regole di commento del progetto. I **messaggi mostrati all'utente in italiano**, coerenti con il `README.INSTALL.md` della stessa cartella.
- Lo script non deve mai scrivere fuori dalla radice del progetto, tranne l'installazione dei pacchetti tramite `apt`, che è di sistema.
- Non toccare `data/.env` se esiste: contiene il token reale dell'utente.
- Nessuna operazione distruttiva: niente rimozione di `.venv`, di `data/` o di file esistenti.
- Non eseguire mai `sudo` su comandi diversi da `apt update` e `apt install`.
- Ogni messaggio d'errore deve dire **cosa** è mancato e **quale comando** l'utente deve lanciare per rimediare.

## Al termine
Aggiornare `installer-guidato-task2-worklog.md`: spuntare i sottoproblemi completati nella sezione "Avanzamento" e aggiungere il tag `DA TESTARE` a fine task. Non scrivere nella sezione "Test": la compila l'orchestratore dopo le prove dell'utente.

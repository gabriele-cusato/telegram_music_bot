<#
    INSTALL_BOT.WIN.ps1

    Script di installazione guidata del bot Telegram su Windows.

    A chi serve: a chi ha appena clonato questo repository su una macchina Windows
    e vuole far girare il bot senza configurare a mano ogni prerequisito.

    Cosa fa, nell'ordine: verifica che lo script sia dentro la cartella giusta del
    progetto; controlla che Python (almeno versione 3.9) sia installato; controlla
    ffmpeg e lo installa con winget se manca; crea l'ambiente virtuale Python
    (venv) e vi installa le dipendenze di requirements.txt; crea le cartelle di
    lavoro "data" e "temp"; crea guidato il file di configurazione data\.env
    chiedendo i valori a schermo, oppure verifica quello esistente senza
    sovrascriverlo; infine ricontrolla che tutto risponda e stampa un riepilogo.

    Lo script è pensato per essere rieseguito più volte senza danni: ciò che
    trova già a posto lo dichiara e lo lascia invariato, non sovrascrive né
    cancella nulla di esistente (in particolare non tocca mai un data\.env già
    presente, perché conterrebbe il token reale del bot).

    Uso:
        powershell -ExecutionPolicy Bypass -File .\INSTALL_BOT.WIN.ps1
#>

#Requires -Version 5.1

# Un errore non gestito nei cmdlet (non nei programmi esterni, che vanno
# controllati a parte con $LASTEXITCODE) deve fermare lo script invece di
# passare inosservato: da qui in poi ogni operazione rischiosa è avvolta in
# un blocco try/catch che trasforma l'errore in un esito registrato.
$ErrorActionPreference = 'Stop'

try {
    # Su alcuni host di PowerShell la codifica di default della console non è
    # UTF-8: senza questa impostazione le lettere accentate dei messaggi in
    # italiano risulterebbero illeggibili. Non è un'operazione bloccante se
    # l'host non la supporta (es. alcune versioni della PowerShell ISE).
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {
    # Codifica console non modificabile su questo host: i messaggi restano comunque leggibili nella maggior parte dei terminali.
}

# La cartella principale del progetto è quella che contiene main.py,
# requirements.txt e core\: dato che questo script vive dentro INSTALL_BOT\,
# basta risalire di un livello dalla posizione dello script stesso. Usare
# $PSScriptRoot (mai un percorso scritto a mano) è ciò che permette allo
# script di funzionare su qualunque macchina, indipendentemente da dove è
# stato clonato il repository.
$ProjectRoot = Split-Path -Parent $PSScriptRoot

# Elenco di tutti i controlli eseguiti dallo script, usato per stampare il
# riepilogo finale e per decidere il codice di uscita: se resta anche un solo
# esito 'ERRORE' lo script segnala che l'installazione non è completa.
$script:Controlli = @()

function Show-Sezione {
    <#
        Stampa l'intestazione di una sezione dello script, per separare
        visivamente i gruppi di controlli nell'output a schermo.
    #>
    param([Parameter(Mandatory)][string]$Titolo)
    Write-Host ''
    Write-Host "=== $Titolo ===" -ForegroundColor Cyan
}

function Registra-Esito {
    <#
        Stampa un esito in modo uniforme (verde per successo, giallo per
        avviso, rosso per errore) e lo accumula in $script:Controlli, così
        il riepilogo finale può elencare ogni controllo eseguito e lo script
        può contare quanti problemi restano aperti.
    #>
    param(
        [Parameter(Mandatory)][string]$Nome,
        [Parameter(Mandatory)][ValidateSet('OK', 'AVVISO', 'ERRORE')][string]$Esito,
        [Parameter(Mandatory)][string]$Messaggio
    )
    $colore = switch ($Esito) {
        'OK' { 'Green' }
        'AVVISO' { 'Yellow' }
        'ERRORE' { 'Red' }
    }
    Write-Host "[$Esito] $Nome" -ForegroundColor $colore
    Write-Host "    $Messaggio"
    $script:Controlli += [PSCustomObject]@{ Nome = $Nome; Esito = $Esito; Messaggio = $Messaggio }
}

function Find-InterpretePython {
    <#
        Cerca un interprete Python utilizzabile, provando prima il comando
        "python" e poi il launcher "py" (installato di default da alcune
        distribuzioni di Python su Windows). Restituisce il percorso
        completo dell'eseguibile python.exe trovato, oppure $null se nessuno
        dei due candidati è disponibile o funzionante.
    #>
    foreach ($candidato in @('python', 'py')) {
        $comando = Get-Command $candidato -ErrorAction SilentlyContinue
        if ($null -eq $comando) { continue }
        try {
            # Il launcher "py" richiede l'opzione "-3" per selezionare Python 3
            # invece di un'eventuale installazione di Python 2 ancora presente.
            if ($candidato -eq 'py') {
                $percorsoEseguibile = & $candidato '-3' '-c' 'import sys; print(sys.executable)' 2>$null
            } else {
                $percorsoEseguibile = & $candidato '-c' 'import sys; print(sys.executable)' 2>$null
            }
            if ($LASTEXITCODE -eq 0 -and $percorsoEseguibile) {
                return $percorsoEseguibile.Trim()
            }
        } catch {
            continue
        }
    }
    return $null
}

function Get-VersionePython {
    <#
        Interroga l'interprete Python indicato e restituisce la sua versione
        come oggetto [version] (Major.Minor), per poterla confrontare con la
        versione minima richiesta. Restituisce $null se l'interprete non
        risponde correttamente.
    #>
    param([Parameter(Mandatory)][string]$PercorsoPython)
    try {
        $versione = & $PercorsoPython '-c' 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $versione) { return $null }
        return [version]$versione.Trim()
    } catch {
        return $null
    }
}

function Read-FileEnv {
    <#
        Legge un file .env e restituisce una tabella chiave/valore con le
        variabili trovate, ignorando righe vuote e righe di commento (che
        iniziano con #). Serve a verificare un data\.env già esistente senza
        doverlo riscrivere.
    #>
    param([Parameter(Mandatory)][string]$PercorsoFile)
    $valori = @{}
    foreach ($riga in Get-Content -Path $PercorsoFile -Encoding UTF8) {
        $rigaPulita = $riga.Trim()
        if ($rigaPulita -eq '' -or $rigaPulita.StartsWith('#')) { continue }
        $indiceUguale = $rigaPulita.IndexOf('=')
        if ($indiceUguale -lt 1) { continue }
        $chiave = $rigaPulita.Substring(0, $indiceUguale).Trim()
        $valore = $rigaPulita.Substring($indiceUguale + 1).Trim()
        $valori[$chiave] = $valore
    }
    return $valori
}

Write-Host 'Installazione guidata del bot Telegram (Windows)' -ForegroundColor Cyan
Write-Host "Cartella del progetto rilevata: $ProjectRoot"

# --- Controlli preliminari sulla struttura del progetto -------------------
# Se lo script è stato spostato fuori dalla cartella INSTALL_BOT del
# progetto (o il progetto è incompleto), nessuno dei passi successivi ha
# senso: si ferma subito con un messaggio che spiega dove va rimessa la
# cartella INSTALL_BOT.
Show-Sezione 'Controlli preliminari'
$fileMainPy = Join-Path $ProjectRoot 'main.py'
$fileRequirements = Join-Path $ProjectRoot 'requirements.txt'
$cartellaCore = Join-Path $ProjectRoot 'core'

if ((Test-Path $fileMainPy -PathType Leaf) -and (Test-Path $fileRequirements -PathType Leaf) -and (Test-Path $cartellaCore -PathType Container)) {
    Registra-Esito -Nome 'Struttura del progetto' -Esito 'OK' -Messaggio "Trovati main.py, requirements.txt e core\ in $ProjectRoot."
} else {
    Registra-Esito -Nome 'Struttura del progetto' -Esito 'ERRORE' -Messaggio "In $ProjectRoot mancano main.py, requirements.txt o la cartella core\."
    Write-Host ''
    Write-Host 'Impossibile proseguire: la cartella INSTALL_BOT deve restare dentro la cartella principale del progetto del bot (quella con main.py), non essere spostata altrove. Rimettila al suo posto e rilancia lo script.' -ForegroundColor Red
    exit 1
}

# --- Python -----------------------------------------------------------
# Senza un interprete Python funzionante non è possibile creare la venv né
# proseguire con nessuno dei passi successivi: è l'altro controllo che ferma
# subito lo script, con il comando pronto per installarlo.
Show-Sezione 'Controllo di Python'
$script:PythonExe = Find-InterpretePython
$versionePython = if ($script:PythonExe) { Get-VersionePython -PercorsoPython $script:PythonExe } else { $null }
$versioneMinima = [version]'3.9'

if ($script:PythonExe -and $versionePython -and $versionePython -ge $versioneMinima) {
    Registra-Esito -Nome 'Python' -Esito 'OK' -Messaggio "Trovato Python $versionePython in $($script:PythonExe)."
} else {
    Registra-Esito -Nome 'Python' -Esito 'ERRORE' -Messaggio 'Non è stato trovato un interprete Python funzionante di versione almeno 3.9 (richiesta da aiogram).'
    Write-Host ''
    Write-Host 'Installa Python con winget, poi riapri il terminale e rilancia questo script:' -ForegroundColor Red
    Write-Host '  winget install --id Python.Python.3.12 -e'
    Write-Host "In alternativa scarica l'installer da https://www.python.org/downloads/ e seleziona l'opzione 'Add python.exe to PATH' durante l'installazione." -ForegroundColor Red
    exit 1
}

# --- ffmpeg -------------------------------------------------------------
# yt-dlp usa ffmpeg per estrarre l'audio, incorporare i metadati e convertire
# le copertine: senza ffmpeg nel PATH ogni download del bot fallisce. Qui
# viene installato davvero (non solo segnalato) usando winget, se disponibile.
Show-Sezione 'Controllo di ffmpeg'
$ffmpegDisponibile = [bool](Get-Command ffmpeg -ErrorAction SilentlyContinue)

if ($ffmpegDisponibile) {
    Registra-Esito -Nome 'ffmpeg' -Esito 'OK' -Messaggio 'ffmpeg è già disponibile nel PATH di sistema.'
} else {
    $wingetDisponibile = [bool](Get-Command winget -ErrorAction SilentlyContinue)
    if ($wingetDisponibile) {
        Write-Host 'ffmpeg non è presente: avvio l''installazione con winget...' -ForegroundColor Yellow
        try {
            & winget install --id Gyan.FFmpeg -e
            if ($LASTEXITCODE -eq 0) {
                # Il PATH aggiornato da winget diventa visibile solo alle finestre di
                # terminale aperte DOPO l'installazione: la sessione corrente non lo vede.
                Registra-Esito -Nome 'ffmpeg' -Esito 'AVVISO' -Messaggio "ffmpeg è stato installato con winget, ma il PATH aggiornato è visibile solo in una NUOVA finestra di terminale: chiudi questa console, riaprila e rilancia lo script per completare la verifica."
            } else {
                Registra-Esito -Nome 'ffmpeg' -Esito 'ERRORE' -Messaggio "L'installazione di ffmpeg con winget è terminata con un errore (codice $LASTEXITCODE). Riprova a mano con: winget install --id Gyan.FFmpeg -e"
            }
        } catch {
            Registra-Esito -Nome 'ffmpeg' -Esito 'ERRORE' -Messaggio "Installazione di ffmpeg fallita: $($_.Exception.Message). Riprova a mano con: winget install --id Gyan.FFmpeg -e"
        }
    } else {
        Registra-Esito -Nome 'ffmpeg' -Esito 'ERRORE' -Messaggio "winget non è disponibile su questo sistema: installa ffmpeg manualmente scaricandolo da https://www.gyan.dev/ffmpeg/builds/ e aggiungi la cartella 'bin' dell'archivio estratto al PATH di sistema."
    }
}

# --- Ambiente virtuale (venv) e dipendenze --------------------------------
# La venv isola le dipendenze del bot dal Python di sistema e deve restare
# scrivibile: core/yt_dlp_update/yt_dlp_manager.py esegue "pip install
# --upgrade yt-dlp" dentro la venv a ogni avvio del bot.
Show-Sezione 'Ambiente virtuale Python (venv)'
$percorsoVenv = Join-Path $ProjectRoot '.venv'
$pythonVenv = Join-Path $percorsoVenv 'Scripts\python.exe'

if (Test-Path $pythonVenv -PathType Leaf) {
    Registra-Esito -Nome 'Ambiente virtuale' -Esito 'OK' -Messaggio "La venv esiste già in ${percorsoVenv}: viene riutilizzata."
} else {
    try {
        & $script:PythonExe -m venv $percorsoVenv
        if ($LASTEXITCODE -eq 0 -and (Test-Path $pythonVenv -PathType Leaf)) {
            Registra-Esito -Nome 'Ambiente virtuale' -Esito 'OK' -Messaggio "Creata la venv in $percorsoVenv."
        } else {
            Registra-Esito -Nome 'Ambiente virtuale' -Esito 'ERRORE' -Messaggio "Creazione della venv fallita. Riprova a mano con: `"$($script:PythonExe)`" -m venv `"$percorsoVenv`""
        }
    } catch {
        Registra-Esito -Nome 'Ambiente virtuale' -Esito 'ERRORE' -Messaggio "Creazione della venv fallita: $($_.Exception.Message)"
    }
}

if (Test-Path $pythonVenv -PathType Leaf) {
    $aggiornamentoPipOk = $true
    try {
        & $pythonVenv -m pip install --upgrade pip
        if ($LASTEXITCODE -ne 0) { $aggiornamentoPipOk = $false }
    } catch {
        $aggiornamentoPipOk = $false
    }
    if (-not $aggiornamentoPipOk) {
        Registra-Esito -Nome 'Aggiornamento pip' -Esito 'AVVISO' -Messaggio "L'aggiornamento di pip non è riuscito: si può proseguire comunque. Per aggiornarlo a mano: `"$pythonVenv`" -m pip install --upgrade pip"
    }

    try {
        & $pythonVenv -m pip install -r (Join-Path $ProjectRoot 'requirements.txt')
        if ($LASTEXITCODE -eq 0) {
            Registra-Esito -Nome 'Dipendenze Python' -Esito 'OK' -Messaggio 'Le dipendenze elencate in requirements.txt sono installate nella venv.'
        } else {
            Registra-Esito -Nome 'Dipendenze Python' -Esito 'ERRORE' -Messaggio "L'installazione delle dipendenze è terminata con un errore. Riprova a mano con: `"$pythonVenv`" -m pip install -r requirements.txt"
        }
    } catch {
        Registra-Esito -Nome 'Dipendenze Python' -Esito 'ERRORE' -Messaggio "Installazione delle dipendenze fallita: $($_.Exception.Message)"
    }
} else {
    Registra-Esito -Nome 'Dipendenze Python' -Esito 'ERRORE' -Messaggio 'Impossibile installare le dipendenze perché la venv non è disponibile.'
}

# --- Cartelle di lavoro (data e temp) -------------------------------------
# core/config.py usa questi due nomi come percorsi relativi alla directory
# di lavoro del bot. Sono elencati in .gitignore, quindi dopo un git clone
# non esistono: vanno create qui, senza mai cancellare eventuale contenuto
# già presente (ad esempio se lo script viene rilanciato).
Show-Sezione 'Cartelle di lavoro (data e temp)'
foreach ($nomeCartella in @('data', 'temp')) {
    $percorsoCartella = Join-Path $ProjectRoot $nomeCartella
    if (Test-Path $percorsoCartella -PathType Container) {
        Registra-Esito -Nome "Cartella $nomeCartella" -Esito 'OK' -Messaggio "$percorsoCartella esiste già."
    } else {
        try {
            New-Item -ItemType Directory -Path $percorsoCartella | Out-Null
            Registra-Esito -Nome "Cartella $nomeCartella" -Esito 'OK' -Messaggio "Creata $percorsoCartella."
        } catch {
            Registra-Esito -Nome "Cartella $nomeCartella" -Esito 'ERRORE' -Messaggio "Impossibile creare ${percorsoCartella}: $($_.Exception.Message)"
        }
    }
}

# --- File di configurazione data\.env -------------------------------------
# core/config.py carica le variabili d'ambiente da data\.env. Se il file
# esiste già non va mai riscritto (contiene il token reale dell'utente): si
# verifica solo che le variabili obbligatorie siano presenti. Se manca, i
# valori vengono chiesti a schermo e il file viene creato.
Show-Sezione 'File di configurazione data\.env'
$percorsoEnv = Join-Path (Join-Path $ProjectRoot 'data') '.env'
$valoriEnv = @{}

if (Test-Path $percorsoEnv -PathType Leaf) {
    $valoriEnv = Read-FileEnv -PercorsoFile $percorsoEnv
    $variabiliMancanti = @()
    if (-not $valoriEnv.ContainsKey('BOT_TOKEN') -or [string]::IsNullOrWhiteSpace($valoriEnv['BOT_TOKEN'])) { $variabiliMancanti += 'BOT_TOKEN' }
    if (-not $valoriEnv.ContainsKey('MUSIC_DIR') -or [string]::IsNullOrWhiteSpace($valoriEnv['MUSIC_DIR'])) { $variabiliMancanti += 'MUSIC_DIR' }

    if ($variabiliMancanti.Count -eq 0) {
        Registra-Esito -Nome 'File data\.env' -Esito 'OK' -Messaggio "$percorsoEnv esiste già e contiene BOT_TOKEN e MUSIC_DIR: non viene modificato."
    } else {
        Registra-Esito -Nome 'File data\.env' -Esito 'ERRORE' -Messaggio "$percorsoEnv esiste ma manca(no) la/e variabile/i: $($variabiliMancanti -join ', '). Aprilo con un editor di testo e aggiungile nel formato CHIAVE=valore, una per riga."
    }
} else {
    Write-Host "Il file data\.env non esiste: rispondi alle domande seguenti per crearlo." -ForegroundColor Cyan

    $botToken = ''
    while ([string]::IsNullOrWhiteSpace($botToken)) {
        $botToken = Read-Host 'Token del bot ottenuto da @BotFather su Telegram (obbligatorio, il bot non parte senza)'
    }

    # La cartella Musica dell'utente corrente, ricavata dall'ambiente Windows,
    # è proposta come default ragionevole al posto di un percorso fisso.
    $musicDirDefault = [Environment]::GetFolderPath('MyMusic')
    $musicDirInserito = Read-Host "Cartella dove il bot salva le canzoni scaricate [invio per usare: $musicDirDefault]"
    $musicDir = if ([string]::IsNullOrWhiteSpace($musicDirInserito)) { $musicDirDefault } else { $musicDirInserito }

    # L'uso in chat privata è il modo normale di usare questo bot, quindi la
    # risposta predefinita è "sì": serve una N esplicita per disattivarlo.
    $allowPrivateRisposta = Read-Host "Permettere l'uso del bot anche nelle chat private, non solo nei gruppi? (S/n)"
    $allowPrivateChat = if ($allowPrivateRisposta -match '^[nN]') { 'false' } else { 'true' }

    $allowedChatId = Read-Host "ID delle chat di gruppo autorizzate, separati da virgola [invio = tutte le chat di gruppo, scrivi 'false' per nessuna]"

    $musicChannelId = Read-Host 'ID del canale Telegram da cui importare le canzoni [invio = funzione disattivata]'

    $musicStorageChannelId = Read-Host 'ID del canale Telegram dove archiviare le canzoni scaricate [invio = funzione disattivata]'

    $righeEnv = @(
        "BOT_TOKEN=$botToken",
        "MUSIC_DIR=$musicDir",
        "ALLOW_PRIVATE_CHAT=$allowPrivateChat",
        "ALLOWED_CHAT_ID=$allowedChatId",
        "MUSIC_CHANNEL_ID=$musicChannelId",
        "MUSIC_STORAGE_CHANNEL_ID=$musicStorageChannelId"
    )

    try {
        # Scritto senza BOM (Byte Order Mark): python-dotenv leggerebbe il BOM
        # come parte del nome della prima chiave (BOT_TOKEN diventerebbe
        # illeggibile), impedendo al bot di trovare il token.
        $codificaUtf8SenzaBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllLines($percorsoEnv, $righeEnv, $codificaUtf8SenzaBom)
        Registra-Esito -Nome 'File data\.env' -Esito 'OK' -Messaggio "Creato $percorsoEnv con i valori inseriti."
        $valoriEnv = Read-FileEnv -PercorsoFile $percorsoEnv
    } catch {
        Registra-Esito -Nome 'File data\.env' -Esito 'ERRORE' -Messaggio "Scrittura di $percorsoEnv fallita: $($_.Exception.Message)"
    }
}

# --- Verifiche finali -------------------------------------------------
# Ultimo giro di controlli su ciò che deve funzionare davvero prima di poter
# avviare il bot: la cartella di destinazione delle canzoni, ffmpeg e i
# moduli Python installati nella venv.
Show-Sezione 'Verifiche finali'

if ($valoriEnv.ContainsKey('MUSIC_DIR') -and -not [string]::IsNullOrWhiteSpace($valoriEnv['MUSIC_DIR'])) {
    $musicDirFinale = $valoriEnv['MUSIC_DIR']
    if (Test-Path $musicDirFinale -PathType Container) {
        try {
            $fileProva = Join-Path $musicDirFinale ".scrivibile_$([guid]::NewGuid().ToString('N')).tmp"
            [System.IO.File]::WriteAllText($fileProva, '')
            Remove-Item $fileProva -Force
            Registra-Esito -Nome 'Cartella MUSIC_DIR' -Esito 'OK' -Messaggio "$musicDirFinale esiste ed è scrivibile."
        } catch {
            Registra-Esito -Nome 'Cartella MUSIC_DIR' -Esito 'ERRORE' -Messaggio "$musicDirFinale esiste ma non è scrivibile: $($_.Exception.Message)"
        }
    } else {
        $rispostaCrea = Read-Host "La cartella MUSIC_DIR ($musicDirFinale) non esiste. Crearla ora? (S/n)"
        if ($rispostaCrea -notmatch '^[nN]') {
            try {
                New-Item -ItemType Directory -Path $musicDirFinale | Out-Null
                Registra-Esito -Nome 'Cartella MUSIC_DIR' -Esito 'OK' -Messaggio "Creata $musicDirFinale."
            } catch {
                Registra-Esito -Nome 'Cartella MUSIC_DIR' -Esito 'ERRORE' -Messaggio "Impossibile creare ${musicDirFinale}: $($_.Exception.Message)"
            }
        } else {
            Registra-Esito -Nome 'Cartella MUSIC_DIR' -Esito 'ERRORE' -Messaggio "$musicDirFinale non esiste: creala manualmente prima di avviare il bot, oppure correggi MUSIC_DIR in data\.env."
        }
    }
} else {
    Registra-Esito -Nome 'Cartella MUSIC_DIR' -Esito 'ERRORE' -Messaggio "MUSIC_DIR non è definita (o è vuota) in data\.env: impossibile verificarla."
}

try {
    & ffmpeg -version 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Registra-Esito -Nome 'ffmpeg funzionante' -Esito 'OK' -Messaggio "Il comando 'ffmpeg -version' risponde correttamente."
    } else {
        Registra-Esito -Nome 'ffmpeg funzionante' -Esito 'ERRORE' -Messaggio "ffmpeg è nel PATH ma 'ffmpeg -version' ha restituito un errore."
    }
} catch {
    Registra-Esito -Nome 'ffmpeg funzionante' -Esito 'ERRORE' -Messaggio "ffmpeg non risponde: se è stato appena installato con winget, riapri il terminale (il PATH si aggiorna solo in una nuova finestra) e rilancia lo script."
}

if (Test-Path $pythonVenv -PathType Leaf) {
    try {
        & $pythonVenv -c 'import aiogram, yt_dlp' 2>$null
        if ($LASTEXITCODE -eq 0) {
            Registra-Esito -Nome 'Moduli Python' -Esito 'OK' -Messaggio 'aiogram e yt_dlp sono importabili dalla venv.'
        } else {
            Registra-Esito -Nome 'Moduli Python' -Esito 'ERRORE' -Messaggio "aiogram o yt_dlp non sono importabili dalla venv. Ripeti l'installazione con: `"$pythonVenv`" -m pip install -r requirements.txt"
        }
    } catch {
        Registra-Esito -Nome 'Moduli Python' -Esito 'ERRORE' -Messaggio "Verifica dei moduli fallita: $($_.Exception.Message)"
    }
} else {
    Registra-Esito -Nome 'Moduli Python' -Esito 'ERRORE' -Messaggio 'Impossibile verificare i moduli Python perché la venv non è disponibile.'
}

# --- Riepilogo conclusivo -----------------------------------------------
Show-Sezione 'Riepilogo'
foreach ($controllo in $script:Controlli) {
    $colore = switch ($controllo.Esito) {
        'OK' { 'Green' }
        'AVVISO' { 'Yellow' }
        'ERRORE' { 'Red' }
    }
    Write-Host "[$($controllo.Esito)] $($controllo.Nome): $($controllo.Messaggio)" -ForegroundColor $colore
}

$erroriRimasti = @($script:Controlli | Where-Object { $_.Esito -eq 'ERRORE' })

Write-Host ''
if ($erroriRimasti.Count -eq 0) {
    Write-Host 'Tutti i controlli sono a posto. Per avviare il bot a mano:' -ForegroundColor Green
    # Il bot va avviato con la cartella del progetto come directory di lavoro,
    # perché core/config.py calcola "data" e "temp" come percorsi relativi:
    # avviarlo da un'altra cartella creerebbe quelle cartelle nel posto sbagliato.
    Write-Host "  cd `"$ProjectRoot`""
    Write-Host '  .\.venv\Scripts\python.exe main.py'
    Write-Host ''
    Write-Host "Per l'avvio automatico all'accensione del PC usa lo script separato: INSTALL_BOT\WIN\RUN_BOT_STARTUP.ps1"
} else {
    Write-Host "Sono rimasti $($erroriRimasti.Count) problema/i da risolvere (vedi le righe [ERRORE] sopra). Risolvili e rilancia questo script." -ForegroundColor Red
}

Write-Host ''
Write-Host "ATTENZIONE: con lo stesso BOT_TOKEN può fare polling un solo processo alla volta. Se il bot è già in esecuzione su un'altra macchina con questo stesso token, spegnilo prima di avviarlo qui: due processi con lo stesso token si contendono i messaggi in arrivo di Telegram." -ForegroundColor Yellow

if ($erroriRimasti.Count -gt 0) {
    exit 1
} else {
    exit 0
}

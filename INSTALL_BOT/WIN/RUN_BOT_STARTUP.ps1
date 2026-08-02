<#
.SINOSSI
    Attiva l'avvio automatico del bot Telegram all'accesso a Windows.

.DESCRIZIONE
    Registra nell'Utilita di pianificazione di Windows un'attivita che, ad ogni
    accesso dell'utente corrente, avvia il bot leggendo l'interprete Python dalla
    venv del progetto e usando come cartella di lavoro la radice del progetto
    (i percorsi "data" e "temp" usati dal bot sono relativi a quella cartella).

    Cosa registra nel sistema:
    - Un'unica attivita pianificata, visibile in "Utilita di pianificazione" >
      "Libreria Utilita di pianificazione", con il nome indicato in $TaskName
      piu sotto in questo file.

    Come annullare:
    - Eseguire STOP_BOT_STARTUP.ps1 nella stessa cartella: ferma il bot, elimina
      l'attivita pianificata e non lascia nessuna configurazione residua.

    Questo script NON viene eseguito dall'installazione guidata: l'avvio
    automatico si attiva solo lanciando questo file esplicitamente, quando
    l'utente lo desidera.

    Richiede una console PowerShell avviata come amministratore, perche la
    creazione di attivita pianificate con questi privilegi lo richiede.
#>

# Nome dell'attivita pianificata: deve restare identico in RUN_BOT_STARTUP.ps1 e
# STOP_BOT_STARTUP.ps1, perche il secondo la individua cercando questo stesso nome.
$TaskName = "TelegramMusicBot - Avvio Automatico"

function Write-Informazione {
    param([string]$Messaggio)
    Write-Host $Messaggio -ForegroundColor Cyan
}

function Write-Successo {
    param([string]$Messaggio)
    Write-Host $Messaggio -ForegroundColor Green
}

function Write-Attenzione {
    param([string]$Messaggio)
    Write-Host $Messaggio -ForegroundColor Yellow
}

function Write-Errore {
    param([string]$Messaggio)
    Write-Host $Messaggio -ForegroundColor Red
}

# Verifica che la console sia stata avviata con privilegi di amministratore:
# senza di questi Register-ScheduledTask e Start-ScheduledTask falliscono.
function Test-EsecuzioneComeAmministratore {
    $utenteCorrente = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    return $utenteCorrente.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-EsecuzioneComeAmministratore)) {
    Write-Errore "Questo script richiede una console PowerShell avviata come amministratore."
    Write-Errore "Chiudi questa finestra, poi riapri PowerShell con 'Esegui come amministratore' (tasto destro sull'icona di PowerShell) e rilancia questo script."
    exit 1
}

# La cartella dello script e' INSTALL_BOT\WIN, quindi la radice del progetto si
# ottiene risalendo di due livelli. Non va mai scritta a mano: cosi lo script
# funziona indipendentemente da dove il progetto e' installato.
$ProjectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

Write-Informazione "Radice del progetto rilevata: $ProjectRoot"

# --- Verifica che l'installazione sia completa prima di registrare qualunque cosa ---
# Registrare l'avvio automatico su un'installazione incompleta produrrebbe un
# processo che parte e muore in continuazione ad ogni accesso.

$installazioneCompleta = $true

$percorsoMainPy = Join-Path $ProjectRoot "main.py"
if (-not (Test-Path $percorsoMainPy)) {
    Write-Errore "Non trovo '$percorsoMainPy'. L'installazione del bot non risulta completa."
    $installazioneCompleta = $false
}

# Preferisce pythonw.exe: esegue senza aprire la finestra della console, come
# faceva in passato run_hidden.vbs, ma senza bisogno di file di appoggio.
$percorsoPythonwVenv = Join-Path $ProjectRoot ".venv\Scripts\pythonw.exe"
$percorsoPythonVenv = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
$interpretePython = $null

if (Test-Path $percorsoPythonwVenv) {
    $interpretePython = $percorsoPythonwVenv
}
elseif (Test-Path $percorsoPythonVenv) {
    $interpretePython = $percorsoPythonVenv
    Write-Attenzione "Non trovo pythonw.exe nella venv: uso python.exe, quindi ad ogni accesso comparira' brevemente una finestra della console."
}
else {
    Write-Errore "Non trovo ne' pythonw.exe ne' python.exe in '$ProjectRoot\.venv\Scripts'. La venv del progetto non risulta creata."
    $installazioneCompleta = $false
}

# Verifica che il file .env esista e contenga un BOT_TOKEN valorizzato: senza
# token il bot esce subito all'avvio e l'attivita pianificata lo farebbe
# ripartire e morire di continuo.
$percorsoEnv = Join-Path $ProjectRoot "data\.env"
if (-not (Test-Path $percorsoEnv)) {
    Write-Errore "Non trovo '$percorsoEnv'. Manca il file con il token del bot."
    $installazioneCompleta = $false
}
else {
    $rigaBotToken = Get-Content $percorsoEnv | Where-Object { $_ -match '^\s*BOT_TOKEN\s*=' } | Select-Object -First 1
    $valoreBotToken = $null
    if ($rigaBotToken) {
        $valoreBotToken = ($rigaBotToken -split '=', 2)[1].Trim()
    }
    if ([string]::IsNullOrWhiteSpace($valoreBotToken)) {
        Write-Errore "Il file '$percorsoEnv' non contiene un BOT_TOKEN valorizzato."
        $installazioneCompleta = $false
    }
}

if (-not $installazioneCompleta) {
    Write-Errore ""
    Write-Errore "L'installazione non risulta completa: nessuna attivita pianificata verra' registrata."
    Write-Errore "Completa prima l'installazione eseguendo INSTALL_BOT\INSTALL_BOT.WIN.ps1, poi rilancia questo script."
    exit 1
}

Write-Successo "Installazione completa: procedo con la registrazione dell'avvio automatico."

# --- Registrazione dell'attivita pianificata ---

# Ricorda che un solo processo per volta puo' fare polling con lo stesso token
# del bot: se un'altra istanza sta gia' girando (su questo PC o su un altro),
# va fermata prima di attivare l'avvio automatico qui, altrimenti Telegram
# alterna gli aggiornamenti tra le due istanze e il bot sembra perdere messaggi.
Write-Attenzione "Attenzione: se il bot e' gia' in esecuzione altrove con lo stesso token, fermalo prima di continuare (un solo processo per volta puo' fare polling)."

$azione = New-ScheduledTaskAction -Execute $interpretePython -Argument '"main.py"' -WorkingDirectory $ProjectRoot
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$principale = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

# Le impostazioni evitano che le politiche di risparmio energetico interrompano
# il bot, tolgono il limite di durata massima (di default un'attivita verrebbe
# terminata dopo 3 giorni) e fanno ripartire l'attivita fino a 3 volte se
# l'avvio fallisce.
$impostazioni = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -DontStopOnIdleEnd `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)

$descrizione = "Avvia automaticamente il bot Telegram del progetto in '$ProjectRoot' all'accesso dell'utente. Registrata da RUN_BOT_STARTUP.ps1; per rimuoverla eseguire STOP_BOT_STARTUP.ps1."

# Register-ScheduledTask con -Force sostituisce l'attivita se una con lo
# stesso nome esiste gia', evitando di registrarne due copie.
try {
    Register-ScheduledTask -TaskName $TaskName -Action $azione -Trigger $trigger -Principal $principale -Settings $impostazioni -Description $descrizione -Force | Out-Null
}
catch {
    Write-Errore "Registrazione dell'attivita pianificata fallita: $($_.Exception.Message)"
    exit 1
}

Write-Successo "Attivita pianificata '$TaskName' registrata."

# --- Avvio immediato, senza aspettare il prossimo accesso ---

try {
    Start-ScheduledTask -TaskName $TaskName
}
catch {
    Write-Errore "L'attivita e' stata registrata ma non sono riuscito ad avviarla subito: $($_.Exception.Message)"
    Write-Errore "Riprova ad avviarla manualmente da Utilita di pianificazione, oppure disconnettiti e riaccedi a Windows."
    exit 1
}

# Concede al processo qualche istante per partire prima di controllarlo.
Start-Sleep -Seconds 3

# I caratteri jolly eventualmente presenti nel percorso della radice vengono
# neutralizzati, cosi il confronto con -like cerca il percorso letterale.
# Oltre alla radice del progetto la riga di comando deve contenere anche
# 'main.py': la sola radice non basta perche' altri programmi usano
# l'interprete della venv del progetto per scopi diversi dal bot (ad esempio
# i language server di VS Code), e verrebbero scambiati per il bot.
$radiceEscapata = [System.Management.Automation.WildcardPattern]::Escape($ProjectRoot)
$processoBot = Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe'" |
    Where-Object { $_.CommandLine -like "*$radiceEscapata*" -and $_.CommandLine -like '*main.py*' }

Write-Host ""
Write-Host "--- Riepilogo ---"
if ($processoBot) {
    Write-Successo "Il bot e' attivo: trovato il processo Python (PID $($processoBot.ProcessId -join ', ')) avviato dall'attivita pianificata."
}
else {
    Write-Attenzione "L'attivita pianificata e' stata avviata ma non trovo ancora un processo Python del bot in esecuzione."
    Write-Attenzione "Controlla il file '$(Join-Path $ProjectRoot 'data\bot.log')' per capire se il bot ha incontrato un errore all'avvio."
}
Write-Host "Attivita pianificata registrata: '$TaskName' (avvio automatico ad ogni accesso a Windows)."
Write-Host "Per disattivare l'avvio automatico e fermare il bot, esegui: INSTALL_BOT\WIN\STOP_BOT_STARTUP.ps1"

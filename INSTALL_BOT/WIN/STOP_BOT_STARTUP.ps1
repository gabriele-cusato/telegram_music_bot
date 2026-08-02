<#
.SINOSSI
    Disattiva l'avvio automatico del bot Telegram e ferma il bot.

.DESCRIZIONE
    Elimina dall'Utilita di pianificazione di Windows l'attivita registrata da
    RUN_BOT_STARTUP.ps1 e termina gli eventuali processi del bot rimasti
    attivi, in modo da riportare il sistema esattamente com'era prima che
    l'avvio automatico venisse attivato: nessuna configurazione residua.

    Se l'avvio automatico non risultava attivo, questo script non fa nulla di
    distruttivo: segnala che non c'era niente da rimuovere e termina con
    esito positivo, senza mostrare errori.

    Richiede una console PowerShell avviata come amministratore, perche la
    rimozione di attivita pianificate con questi privilegi lo richiede.
#>

# Deve restare identico al nome usato in RUN_BOT_STARTUP.ps1, perche' questo
# script individua l'attivita da rimuovere cercandola per nome.
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
# senza di questi Unregister-ScheduledTask fallisce.
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
# ottiene risalendo di due livelli, mai scritta a mano.
$ProjectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

Write-Informazione "Radice del progetto rilevata: $ProjectRoot"

# --- Arresto ed eliminazione dell'attivita pianificata ---

$attivitaEsistente = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

if (-not $attivitaEsistente) {
    Write-Successo "Non risulta nessuna attivita pianificata '$TaskName': l'avvio automatico non era attivo, niente da rimuovere."
}
else {
    try {
        if ($attivitaEsistente.State -eq 'Running') {
            Stop-ScheduledTask -TaskName $TaskName
        }
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Successo "Attivita pianificata '$TaskName' rimossa."
    }
    catch {
        Write-Errore "Rimozione dell'attivita pianificata fallita: $($_.Exception.Message)"
        exit 1
    }
}

# --- Terminazione degli eventuali processi del bot rimasti attivi ---

# Riconosce i processi da terminare dalla riga di comando che contiene il
# percorso della radice del progetto: e' lo stesso criterio gia' usato da
# stop_bot.bat (che cercava 'telegram_music_bot' scritto a mano), qui
# generalizzato alla radice reale e includendo anche pythonw.exe. Questo
# evita di terminare processi Python estranei al progetto.
$radiceEscapata = [System.Management.Automation.WildcardPattern]::Escape($ProjectRoot)
$processiBot = Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe'" |
    Where-Object { $_.CommandLine -like "*$radiceEscapata*" }

if ($processiBot) {
    foreach ($processo in $processiBot) {
        try {
            Stop-Process -Id $processo.ProcessId -Force
            Write-Successo "Terminato processo del bot (PID $($processo.ProcessId))."
        }
        catch {
            Write-Errore "Non sono riuscito a terminare il processo PID $($processo.ProcessId): $($_.Exception.Message)"
        }
    }
}
else {
    Write-Informazione "Nessun processo del bot risultava in esecuzione."
}

# --- Verifica finale: non deve restare ne' l'attivita ne' alcun processo ---

$attivitaResidua = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
$processiResidui = Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe'" |
    Where-Object { $_.CommandLine -like "*$radiceEscapata*" }

Write-Host ""
Write-Host "--- Riepilogo ---"
if (-not $attivitaResidua -and -not $processiResidui) {
    Write-Successo "Avvio automatico disattivato: nessuna attivita pianificata e nessun processo del bot restano attivi sul sistema."
}
else {
    if ($attivitaResidua) {
        Write-Errore "L'attivita pianificata '$TaskName' risulta ancora presente."
    }
    if ($processiResidui) {
        Write-Errore "Risultano ancora processi del bot in esecuzione (PID $($processiResidui.ProcessId -join ', '))."
    }
    Write-Attenzione "Riprova ad eseguire questo script; se il problema persiste, verifica manualmente da Utilita di pianificazione e dal Task Manager."
}
Write-Host "Per riattivare l'avvio automatico, esegui: INSTALL_BOT\WIN\RUN_BOT_STARTUP.ps1"

# Installazione del bot

Guida breve. Gli script fanno quasi tutto: qui c'è solo l'ordine dei passaggi e le poche cose che devi decidere tu.

## Prima di iniziare

- Serve il **token del bot**: su Telegram scrivi a `@BotFather`, comando `/newbot`, e conserva il token che ti dà.
- Serve una connessione a internet: gli script scaricano pacchetti.
- Il progetto va scaricato con `git clone`; la cartella `INSTALL_BOT` deve restare dentro la cartella del progetto, dove c'è `main.py`.
- **Un solo computer per volta** può far girare il bot con lo stesso token. Se lo attivi sul Raspberry, spegni quello sul PC.

## Installazione

Un solo script, che controlla tutto, installa quello che manca e ti chiede i dati mancanti.

### Windows
- Apri PowerShell **come amministratore** nella cartella del progetto.
- Esegui: `.\INSTALL_BOT\INSTALL_BOT.WIN.ps1`
- Se ti dice che l'esecuzione degli script è bloccata: `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` e rilancia.
- Se installa ffmpeg, **chiudi e riapri** il terminale e rilancia lo script: il percorso aggiornato è visibile solo alle finestre nuove.

### Linux e Raspberry Pi
- Apri il terminale nella cartella del progetto.
- Rendi eseguibili gli script: `chmod +x INSTALL_BOT/INSTALL_BOT.LINUX.sh INSTALL_BOT/LINUX/*.sh`
- Esegui: `./INSTALL_BOT/INSTALL_BOT.LINUX.sh`
- Ti verrà chiesta la password **sudo** per installare i pacchetti di sistema.

## Cosa ti viene chiesto

Solo la prima volta, se il file di configurazione non esiste ancora:

- **Token del bot** — obbligatorio, quello di `@BotFather`.
- **Cartella della musica** — dove salvare le canzoni. Premi invio per accettare quella proposta.
- **Chat private sì o no** — se il bot deve rispondere anche in privato, non solo nei gruppi.
- **Gruppi autorizzati** — invio lascia il bot libero in tutti i gruppi.
- **Canali Telegram** — due domande, invio le salta se non usi quelle funzioni.

Se il file esiste già non viene mai toccato: lo script controlla solo che i dati obbligatori ci siano.

## Avviare il bot

- Lo script, alla fine, ti stampa il comando esatto per avviarlo a mano.
- Va sempre lanciato **dalla cartella del progetto**, altrimenti non trova la sua configurazione.

## Avvio automatico all'accensione

Facoltativo, e separato apposta: si attiva solo se lo lanci tu.

### Windows
- Attivare: `.\INSTALL_BOT\WIN\RUN_BOT_STARTUP.ps1` (PowerShell come amministratore)
- Disattivare: `.\INSTALL_BOT\WIN\STOP_BOT_STARTUP.ps1`

### Linux e Raspberry Pi
- Attivare: `./INSTALL_BOT/LINUX/RUN_BOT_STARTUP.sh`
- Disattivare: `./INSTALL_BOT/LINUX/STOP_BOT_STARTUP.sh`

In entrambi i casi lo script di disattivazione rimuove tutto quello che era stato registrato: non resta niente nel sistema.

## Controllare che funzioni

- **Windows** — apri `data\bot.log` nella cartella del progetto.
- **Linux** — `journalctl -u musicbot -f` se hai attivato l'avvio automatico, altrimenti `data/bot.log`.
- Su Telegram, scrivi al bot `music` seguito dal nome di una canzone.

## Se qualcosa non va

- Rilancia lo script di installazione: è fatto per essere eseguito più volte, salta quello che è già a posto e ti dice cosa manca.
- Ogni messaggio di errore contiene già il comando da lanciare per rimediare.
- Se il bot sembra ignorare i messaggi, controlla che non stia girando **anche altrove** con lo stesso token.

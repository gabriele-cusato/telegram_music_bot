# comando-post-salvataggio

Comando shell arbitrario eseguito dopo il salvataggio di una canzone, usato per sincronizzare la cartella musicale con pcloud tramite rclone. Implementato e testato il 2026-08-03 (senza plan né worklog: modifica diretta su richiesta dell'utente).

## Cosa fa

Dopo ogni salvataggio riuscito su disco (bottone "💾 Save Srv"), il bot lancia in background la riga di comando scritta in `POST_SAVE_COMMAND`. Il comando è arbitrario ed eseguito dall'interprete di sistema: PowerShell su Windows, bash su Linux. Il bot non attende la fine: la risposta a Telegram parte subito.

## File toccati

- `core/config.py` — nuove impostazioni `POST_SAVE_COMMAND` (vuota = disattivato) e `POST_SAVE_COMMAND_DELAY` (default 10 secondi).
- `core/services/post_save_command.py` — nuovo modulo. Espone `schedule_post_save_command()`.
- `core/handlers/callbacks.py` — `save_to_directory` chiama `schedule_post_save_command()` dopo `discard_pending`.
- `data/env` — template aggiornato con le due impostazioni e un esempio rclone.

## Scelte di progetto

- **Attesa prima del lancio** (`POST_SAVE_COMMAND_DELAY`): raggruppa più salvataggi ravvicinati in una sola esecuzione invece di lanciare un processo per canzone.
- **Serializzazione**: se arrivano salvataggi mentre il comando gira, viene rilanciato **una** volta al termine. Nessun accumulo di processi e nessun file lasciato fuori dalla sincronizzazione.
- **Comando via shell e non lista di argomenti**: scelta esplicita dell'utente, per poter usare pipe, redirezioni e variabili con la sintassi nativa dell'interprete. Il valore arriva da `data/.env`, mai da Telegram.
- **Il comando non riceve il percorso del file salvato**: lavora sull'intera cartella musicale.
- Esito solo nel log (`data/bot.log`): `logger.info` se il codice di uscita è 0, `logger.error` con lo `stderr` altrimenti. Nulla viene mostrato su Telegram.

## Sincronizzazione bidirezionale (configurazione sul Raspberry, fuori dal repo)

Solo `POST_SAVE_COMMAND` copre la direzione locale→cloud. Per propagare anche cancellazioni e modifiche fatte sul cloud serve un'esecuzione periodica, decisa fuori dal progetto per non legare la sincronizzazione alla presenza del bot.

Configurazione scelta e verificata sul Raspberry:

- Comando usato sia nel post-save sia nel timer:
  `/usr/bin/rclone bisync /home/raspuser/Music pcloud:Music --create-empty-src-dirs --conflict-resolve newer --resilient --recover --max-lock 2m --transfers 4 --log-level NOTICE`
- Baseline iniziale a mano con `--resync` (obbligatoria, altrimenti ogni run fallisce).
- Unità systemd `musicbot-sync.service` (`Type=oneshot`) più `musicbot-sync.timer` con `OnCalendar=*:0/15` e `Persistent=true`, create a mano sul Raspberry: l'utente ha scelto di non versionarle in `INSTALL_BOT/LINUX/`.
- Soglia cancellazioni lasciata al default di rclone (`--max-delete` 50%), senza `--check-access`.
- Il lock file di rclone impedisce la sovrapposizione tra il run del timer e quello post-save.

## Test

- Salvataggio di una canzone: comando lanciato, `Post-save command completed successfully.` nel log.
- Cancellazione di una canzone su pcloud e sincronizzazione forzata con `sudo systemctl start musicbot-sync`: il file è sparito anche in locale. Verificato con `find /home/raspuser/Music -iname "*cheap*"` e `rclone lsf pcloud:Music -R | grep -i cheap`.

## Avvertenze note

- Con `bisync` la cancellazione di un file sul cloud lo cancella anche in locale, e il comando `/delete` (deduplica) propaga le sue cancellazioni al cloud. In entrambi i casi senza cestino.
- `bisync` richiede rclone 1.58 o superiore ed è un comando avanzato, non pienamente stabile. Se un run fallisce in modo sporco può servire un nuovo `--resync` manuale.
- Il servizio systemd gira come l'utente che ha installato il bot, quindi rclone legge la configurazione di quell'utente: un remote configurato come root non funziona.

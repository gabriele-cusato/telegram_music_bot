# Feature: Comandi con `/` e Menu Telegram

## Scopo
Aggiungere supporto per comandi con slash (`/log`, `/priority`, `/delete`, `/music`) retro-compatibili (funzionano ancora senza slash), registrare i comandi nel menu di Telegram per autocomplete e pulsante Menu, e migliorare UI del comando priority (bottone Confirm Order) e delete (elencare file eliminati).

## Modifiche per task

### Task 1 — Priority: bottone "Confirm Order"
- **File toccati:** `core/handlers/callbacks.py`, `core/strings.py`
- **Cambiamenti:**
  - `strings.py`: `BUTTON_PRIO_CONFIRM = "✅ Confirm Order"`, `PRIORITY_CONFIRMED = "📂 Priority order saved:\n{}"`.
  - `callbacks.py` `build_priority_kb`: aggiunta riga finale con bottone confirm (`prio_confirm`).
  - Handler `prio_`: nuovo ramo `prio_confirm` → cancella il messaggio interattivo, invia un nuovo messaggio con la lista numerata dell'ordine attuale.
- **Risultato:** Dopo riordinare le cartelle, utente clicca Confirm; la tastiera scompare e resta solo il messaggio testuale dell'ordine finale.

### Task 2 — Rinominare `dedup` → `delete` + elenco file eliminati
- **File toccati:** `core/strings.py`, `core/handlers/messages.py`, `core/handlers/callbacks.py`
- **Cambiamenti:**
  - `strings.py`: `DEDUP_COMMAND_PREFIX = "delete"` (era "dedup"); `DEDUP_DONE_HEADER = "✅ Deleted {} file(s):"`, corpo = lista file eliminati; `DEDUP_DONE_NONE` per nessuna cancellazione.
  - `messages.py`: `_is_dedup_command` matcha "delete" (non "dedup").
  - `callbacks.py` `dedup_callback` `dd_ok`: raccoglie le label dei candidati eliminati, compone messaggio con header + lista file (cap ~3800 char, tronca se eccede).
- **Risultato:** Comando rinominato in `/delete`. Dopo cancellazione, messaggio elenca esattamente quali file sono stati rimossi (cartella + nome).

### Task 3 — Comandi con `/` (retro-compatibili) + menu Telegram
- **File toccati:** `core/handlers/messages.py`, `main.py`, `core/strings.py`
- **Cambiamenti:**
  - `messages.py`: helper `_split_command(text)` che rimuove `/` iniziale e `@nomebot` (Telegram lo aggiunge nei gruppi), normalizza a lowercase, ritorna (name, args).
  - Aggiornamento filtri: `_is_log_command`, `_is_priority_command`, `_is_dedup_command` usano `_split_command`.
  - Estrazione argomenti: `log_command_handler` usa `_split_command` per ricavare args. `message_handler` (music) accetta sia `music query` sia `/music query`.
  - `main.py`: `set_my_commands()` registra comandi al startup:
    - Scope public (tutte le chat): `/music` ("Search & download a song").
    - Scope private: `/music`, `/log`, `/priority`, `/delete` (con descrizioni).
  - Try/except su `set_my_commands`; fallback con log warning se fallisce.
- **Risultato:** Comandi funzionano con `/` e senza, Telegram mostra autocomplete/Menu con i comandi registrati. Retro-compatibilità mantenuta.

## Da tenere a mente

### Punti risolti (non riaprire)
1. **Split comando e @nomebot (Task 3):** `_split_command` rimuove sia `/` sia `@nomebot` (che Telegram aggiunge nei gruppi). Questo permette che `/log@mio_bot` riconosca "log". Non ritentare di match il nome bot nella stringa.
2. **Menu Telegram scope privato vs pubblico (Task 3):** `/music` è registrato in ENTRAMBI gli scope (public default + private extra). La logica gate nei handler rimane: il comando privato per `/log` etc. è gated a `chat.type == 'private'` nel codice. Il scope del menu è solo cosmetico/di visibilità Telegram.
3. **COMMAND_PREFIX vecchio (Task 3):** `COMMAND_PREFIX = "music "` (con spazio) è ancora usato? Verificato con Grep che non è usato altrove (tranne storage di costante). Il match ora passa da `_split_command`, ma la costante rimane per retro-compatibilità config se letta altrove.
4. **Confirm order messaggio (Task 1):** Cancella il messaggio interattivo (con tastiera) e invia un nuovo messaggio testo. Non edita il messaggio vecchio perché Telegram non permette togliere inline_keyboard e rimpiazzare il testo in un'operazione.

### Trappole note
1. **@nomebot in privato vs gruppo (Task 3):** Nel comando di un gruppo, Telegram aggiunge `@nomebot` se il bot non è l'unico. In chat privata, non lo aggiunge. `_split_command` gestisce entrambi i casi (split su @ e prende il primo token). Non rompe.
2. **Ordine registrazione handler (Task 3):** `_is_log_command`, `_is_priority_command`, `_is_dedup_command` DEVONO essere registrati PRIMA del catch-all `message_handler`, altrimenti il catch-all intercetta tutto. Attualmente è così nel codice (comment nel plan confermava). Se si aggiunge un nuovo handler filtro, mantienere l'ordine.
3. **Set_my_commands idempotente ma ha rate limit (Task 3):** Telegr am lo permette ad ogni startup, ma se il bot si riavvia molte volte in breve tempo, potrebbe essere rate-limited. Non è un problema nel normal usage (startup è raro), ma testate con molti restart.
4. **Elenco file eliminati e lungghezza messaggio (Task 2):** La lista di file è cappata a ~3800 char. Se molti file hanno nomi lunghi, il cap si raggiunge prima di listare tutti. Il messaggio finale avrà "..." e avvisa. Corretto; Telegram non permette > 4096 char.

### Scelte vincolanti per il futuro
1. **Descrizioni comandi in inglese (Task 3):** Le descrizioni del menu sono in inglese, coerenti con le stringhe app. Se in futuro si aggiunge lingue, aggiornare BotCommand descriptions (richiede multi-scope se supportare più lingue).
2. **Comando `/delete` non è undo (Task 2):** Una volta cancellato un file, non c'è undo. Non aggiungere logica di recovery (backup) qui; è una scelta di UX.
3. **Priority.txt e lista numerata in confirm (Task 1):** La lista numerata è generata da `enumerate(order)` dal momento del click. Se l'ordine cambia velocemente (es. altro utente si connette), il confirm mostra lo stato attuale, non l'ordine "prima" del riordino. È intentato (semantica "salva l'ordine attuale").

## Esito test
Tutti i task marcati DA TESTARE. Implementazione completa, compilazione ok (venv + import reale BotCommand/scope). Test runtime: `/log`, `/priority`, `/delete`, `/music` funzionano con slash; menu compare digitando `/`; confirm order cancella tastiera; delete elenca file cancellati.

## Integrazione con feature precedenti
- Task 1 dipende da libreria-dedup Task 2 (comando priority preesistente).
- Task 2 dipende da libreria-dedup Task 3 (comando dedup/delete preesistente).
- Task 3 integra tutti i comandi precedenti (logging-e-salvataggio + metadati-veri + libreria-dedup) con slash support e menu.

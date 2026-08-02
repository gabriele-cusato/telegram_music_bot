# Feature: Libreria e Dedup (Priorità Cartelle + Rimozione Duplicati)

## Scopo
Gestire un ordine di priorità persistente per le sottocartelle della libreria musicale (`priority.txt`), fornire comandi per visualizzare e riordinare le cartelle, e implementare deduplica fuzzy cross-folder con conferma deselezionabile e eliminazione file.

## Modifiche per task

### Task 1 — Modulo priorità cartelle (priority.txt)
- **File creato:** `core/services/library_priority.py`
- **Cambiamenti:**
  - Modulo puro (no Telegram) che legge/scrive `MUSIC_DIR/priority.txt` (una cartella per riga).
  - API: `sync_priority()` (riconcilia file con cartelle reali, autocrea file), `get_order()` (ritorna ordine corrente), `apply_move(index, delta)` (sposta cartella su/giù), `priority_rank(folder, order)` (indice di priorità, 0 = massima).
  - Robusto: `MUSIC_DIR` inesistente → ritorna [], nessun errore.
- **Risultato:** Gestione persistente dell'ordine di priorità delle cartelle, usato poi da dedup per scegliere quale copia tenere.

### Task 2 — Comando `/priority` + riordino bottoni ▲▼
- **File toccati:** `core/handlers/messages.py`, `core/handlers/callbacks.py`, `core/strings.py`
- **Cambiamenti:**
  - `strings.py`: `PRIORITY_COMMAND_PREFIX`, `PRIORITY_PROMPT`, `PRIORITY_EMPTY`, bottoni `BUTTON_PRIO_UP`/`BUTTON_PRIO_DOWN`.
  - `messages.py`: handler `/priority` solo chat privata. `_is_priority_command` filtro (registrato prima del catch-all).
  - `callbacks.py`: `build_priority_kb(order)` helper. Handler `prio_` (noop / up / down) con `apply_move` e re-render keyboard.
- **Risultato:** Comando `/priority` mostra cartelle in ordine con bottoni ▲▼; ogni spostamento aggiorna `priority.txt` immediatamente.

### Task 3 — Comando `/delete` (dedup fuzzy, conferma deselezionabile)
- **File creato:** `core/services/library_dedup.py` (logica pura)
- **File toccati:** `core/handlers/messages.py`, `core/handlers/callbacks.py`, `core/strings.py`
- **Cambiamenti:**
  - `library_dedup.py`: `find_duplicate_groups()` scansiona file .mp3 nelle cartelle, clustering greedy fuzzy (WRatio ≥ 90%, case-insensitive), tiene copia con priorità massima, propone le altre per cancellazione. Ritorna gruppi con keep + candidati.
  - `strings.py`: `DEDUP_COMMAND_PREFIX`, `DEDUP_NONE`, `DEDUP_HEADER`, `DEDUP_CANCELLED`, `DEDUP_DONE`, bottoni confirm/cancel.
  - `messages.py`: handler `/delete` solo chat privata. Esegue `find_duplicate_groups` in thread, crea sessione con candidati.
  - `callbacks.py`: store effimero `dedup_sessions` (uuid per sessione). Handler `dd_` (toggle selected, confirm/cancel). Toggle ri-renderizza bottoni; confirm elimina file selected.
- **Risultato:** `/delete` trova duplicati cross-folder, mostra lista deselezionabile (☑/☐), utente toglie ciò che non vuol cancellare, conferma elimina solo i selected.

### Task 4 — Fix "message is too long" + invariante sicurezza
- **File toccati:** `core/handlers/callbacks.py`, `core/handlers/messages.py`, `core/strings.py`
- **Cambiamenti:**
  - `build_dedup_session`: doppio budget (testo < ~3500 char + max 60 candidati). Costruzione incrementale gruppo per gruppo; fermarsi al primo limite raggiunto. Nota di troncamento nel testo.
  - **Invariante critica:** `session["candidates"]` contiene SOLO i candidati mostrati come bottoni; i candidati oltre il taglio NON entrano nella sessione (quindi `dd_ok` non può cancellare ciò che non è mostrato).
  - `messages.py dedup_command_handler`: try/except su `message.answer`, fallback message su errore, pop sessione se invio fallisce.
  - (Difensivo) `dd_ok`: verifica path dentro MUSIC_DIR prima di `os.remove`.
- **Risultato:** Niente "message too long" anche con molti duplicati. Sicurezza garantita: cancella solo i file mostrati.

### Task 5 — priority.txt autoritativo; cartelle non elencate ignorate
- **File toccati:** `core/services/library_priority.py`, `core/services/library_dedup.py`
- **Cambiamenti:**
  - `library_priority.sync_priority()`: se file manca → crea con TUTTE le sottocartelle (primo avvio); se esiste → ritorna solo le elencate che ancora esistono, NIENTE auto-add di cartelle nuove, NON riscrive il file per cartelle stale (filtrate solo in memoria).
  - `library_dedup._collect_mp3(order)`: itera solo le cartelle in `order` (da `get_order()`), non tutte le sottocartelle.
  - `find_duplicate_groups`: calcola `order` una volta, passa a `_collect_mp3`, usa `order` anche per `priority_rank`.
- **Risultato:** Una volta creato `priority.txt`, il `/delete` guarda solo cartelle elencate. Cartelle nuove non vengono auto-aggiunte, rimangono invisibili al dedup finché non aggiunte manualmente via `/priority`.

## Da tenere a mente

### Punti risolti (non riaprire)
1. **Clustering fuzzy e copia keep (Task 3, Task 5):** Un gruppo di duplicati è ordinato per `priority_rank`: il primo (indice 0) è quello in cartella a priorità massima, è il "keep". Gli altri sono candidati. Il keep NON è mai un candidato per la cancellazione. Non invertire questa logica.
2. **Ordinamento cartelle (Task 1, Task 2):** `priority.txt` contiene un'ordine esplicito. `apply_move` scambia elementi adiacenti (-1 su, +1 giù). Se l'ordine viene corrotto (righe duplicate, ordine illogico), `sync_priority` lo ripara solo al riavvio/prima get_order. Nel dubbio, mandarsi un segnale di alert all'utente.
3. **Primo avvio priority.txt (Task 5):** Se il file non esiste, `sync_priority` lo crea con TUTTE le cartelle attuali in ordine alfabetico. Dopo quel momento, le cartelle nuove restano fuori finché non aggiunte via UI. È intentato.
4. **Budget testo nel dedup (Task 4):** ~3500 char per testo + header + nota troncamento. Se il numero di candidati è alto ma i nomi sono corti, il testo budget si raggiunge prima di 60 candidati. Se i nomi sono lunghi, il limite candidati si raggiunge prima di 3500 char. Entrambi sono "giusti" per il limite Telegram 4096.

### Trappole note
1. **File .mp3 in sottocartelle ricorsive (Task 3, Task 5):** `_collect_mp3` scannerizza solo il primo livello di cartelle. Eventuali `.mp3` dentro sottocartelle di secondo livello (ricorsive) vengono ignorate. Atteso; il dedup non è ricorsivo.
2. **priority.txt non in dedup (Task 3):** Il file `priority.txt` è in `MUSIC_DIR`, non dentro una sottocartella, quindi `_collect_mp3` che itera cartelle non lo tocca. Sicuro.
3. **Sessioni dedup effimere (Task 3, Task 4):** Lo store `dedup_sessions` è un dict in memoria; se il bot si riavvia, le sessioni attive spariscono. L'utente che ha la UI aperta riceverà "Session expired" se clicca un bottone dopo il riavvio. Atteso; le sessioni non sono persistenti.
4. **Fallimento `os.remove` in dedup (Task 3):** Se la cancellazione di un file fallisce (es. file in uso), il log registra un warning, ma la sessione continua e gli altri file vengono cancellati. Se vuoi che il primo errore interrompa, aggiungere un flag di uscita anticipata (non è così nel current design).

### Scelte vincolanti per il futuro
1. **Soglia match fuzzy (Task 3):** `FUZZY_DUPLICATE_THRESHOLD = 90` da config. Cambiare il valore cambierà i gruppi identificati (90 è conservativo, raggruppa solo nomi molto simili). Se la soglia scende, aumentano i falsi positivi (e il flag deselezionabile è la salvaguardia).
2. **Modalità dedup cartelle non-prioritizzate (Task 5):** Una volta scelto che `priority.txt` è autoritativo, non c'è modo di fare dedup su una cartella "nuova" che non è ancora nel file (senza che l'utente la aggiunga via `/priority`). È intentato, per non scansionare cartelle dimenticate. Se vuoi un comando "dedup questa cartella specifica", serve refactoring.
3. **Ordine alfabetico first-run (Task 5):** Primo avvio, le cartelle vanno alfabetiche lowercase. Non è l'ordine di creazione su disco. Se vuoi il filesystem order (che varia per OS), toccare `list_subfolders()` per non fare sort.

## Esito test
Tutti i task marcati DA TESTARE. Implementazione completa, compilazione ok (venv). Test runtime: `/priority` riordina e persiste, `/delete` trova duplicati (solo cartelle in priority.txt), deseleziona, conferma e cancella i file mostrati.

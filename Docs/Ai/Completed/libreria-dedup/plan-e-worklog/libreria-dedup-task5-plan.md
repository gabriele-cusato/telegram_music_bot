# Task 5 — priority.txt autoritativo: cartelle non elencate ignorate dal dedup

## Obiettivo
Cambiare la semantica della priorità:
- Se `priority.txt` NON esiste → crearlo con TUTTE le sottocartelle attuali (come oggi la prima volta).
- Se `priority.txt` ESISTE → è la lista autoritativa: le cartelle non elencate sono IGNORATE dal dedup (`/delete`), cioè non vengono scansionate né mai cancellate. Nessun auto-add di cartelle nuove.

## Prerequisiti bloccanti
- Devono esistere: `core/services/library_priority.py`, `core/services/library_dedup.py`, `core/config.py` (MUSIC_DIR), `core/services/music_library.py` (list_subfolders). Se manca, fermarsi.
- Non toccare file diversi da questi due moduli.
- Version control: git in sola lettura lato orchestratore. Agent-Code NON committa/pusha.
- Verifica: `.venv/Scripts/python.exe -m py_compile` + prova scratchpad.

## File da toccare
- `core/services/library_priority.py` — `sync_priority`.
- `core/services/library_dedup.py` — `_collect_mp3` e `find_duplicate_groups`.

## Comportamento attuale (da cambiare)
- `sync_priority()` attuale: mantiene le elencate esistenti, **aggiunge in coda le cartelle nuove** (auto-add), scarta le rimosse, e **riscrive** sempre il file. → va cambiato: niente auto-add quando il file esiste.
- `library_dedup._collect_mp3()` attuale: itera `list_subfolders()` (TUTTE le sottocartelle) → va cambiato: iterare solo i membri di priority (`get_order()`).

## Sottoproblemi (in ordine)
1. `library_priority.sync_priority()` — nuova logica:
   ```python
   def sync_priority() -> List[str]:
       existing_folders = list_subfolders()
       existing_set = set(existing_folders)

       if not os.path.exists(PRIORITY_FILE):
           # file assente: prima creazione, popola con TUTTE le sottocartelle (alfabetico)
           seeded = sorted(existing_folders, key=str.lower)
           _write(seeded)
           return seeded

       # file presente = lista autoritativa: NIENTE auto-add.
       # Ritorna solo le cartelle elencate che esistono ancora su disco, nell'ordine del file.
       # Non riscrive il file (le cartelle stale sono solo filtrate in memoria).
       raw_order = _read_raw()
       return [folder for folder in raw_order if folder in existing_set]
   ```
   - Aggiornare il docstring per riflettere la nuova semantica.
   - NB: file esistente ma VUOTO → `raw_order = []` → ritorna `[]` (tutte ignorate): è corretto, rispetta il contenuto del file.
   - `get_order`, `apply_move`, `priority_rank` restano invariati (usano `sync_priority`/`get_order`).
2. `library_dedup` — scansionare solo i membri di priority:
   - Cambiare `_collect_mp3()` in `_collect_mp3(order: List[str])`: iterare `for folder in order:` invece di `list_subfolders()`. Il resto invariato (scan `.mp3` di primo livello, skip non-file).
   - In `find_duplicate_groups`: calcolare `order = get_order()` PRIMA, poi `files = _collect_mp3(order)` (una sola chiamata a get_order, riusata anche per `priority_rank`).
   - Effetto: le cartelle non in `priority.txt` non vengono mai scansionate → ignorate dal dedup.
3. Verificare che nessun altro chiamante di `_collect_mp3` esista (Grep); se sì, adeguarlo.

## Cosa NON cambia
- Il picker "salva su cartella" (`_build_save_folder_kb` / `list_subfolders`) continua a mostrare TUTTE le sottocartelle: salvare un brano è indipendente dalla priorità. Non toccarlo.
- `apply_move`, `priority_rank`, il comando `/priority` e il bottone Confirm Order restano invariati (operano su `get_order()`, che ora riflette i soli membri).

## Verifica (scratchpad, obbligatoria)
- `sync_priority`:
  - file mancante → viene creato e ritorna TUTTE le sottocartelle (usare una dir temporanea nello scratchpad, monkeypatch di `PRIORITY_FILE` e `list_subfolders`).
  - file esistente con un sottoinsieme (manca una cartella presente su disco) → ritorna solo le elencate esistenti, la cartella non elencata NON compare; il file NON viene riscritto (mtime/contenuto invariato).
  - file esistente vuoto → ritorna `[]`.
  - cartella elencata ma non su disco → filtrata dal risultato.
- `_collect_mp3(order)` / `find_duplicate_groups`: con una struttura finta dove una cartella con duplicati NON è in `order`, quella cartella non compare in nessun gruppo (ignorata).

## Skill di codice
Caricare `coding-standard`. Commenti in italiano forma infinito.

## Verifica finale
- `.venv/Scripts/python.exe -m py_compile core/services/library_priority.py core/services/library_dedup.py`.
- Prove scratchpad sopra, senza toccare MUSIC_DIR reale.
- Aggiornare il worklog: spuntare i sottoproblemi, marcare `DA TESTARE`.

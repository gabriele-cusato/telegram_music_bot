# Task 3 — Comando `dedup` (duplicati fuzzy, conferma deselezionabile, cancellazione)

## Obiettivo
Comando `dedup` (solo chat privata) che trova canzoni duplicate presenti in più sottocartelle di `MUSIC_DIR` (match fuzzy sul nome file), tiene la copia nella cartella a priorità più alta e propone di cancellare le altre. Prima di cancellare mostra una lista **deselezionabile** (☑/☐): l'utente toglie dalla cancellazione ciò che vuole tenere, poi conferma. Operazione DISTRUTTIVA su file reali.

## Prerequisiti bloccanti
- Devono esistere: `core/handlers/messages.py`, `core/handlers/callbacks.py`, `core/strings.py`, `core/config.py` (per `MUSIC_DIR`, `FUZZY_DUPLICATE_THRESHOLD`), `core/services/music_library.py` (`list_subfolders`), `core/services/library_priority.py` (`get_order`, `priority_rank`). Se manca il modulo priorità, fermarsi.
- Eseguire DOPO i Task 1 e 2 di questa feature.
- Non toccare file diversi da quelli elencati.
- Version control: git in sola lettura lato orchestratore. Agent-Code NON committa/pusha.
- Verifica: `python -m py_compile` + prova della logica pura di grouping nello scratchpad (senza avviare il bot e senza cancellare file reali).

## File da toccare / creare
- CREARE `core/services/library_dedup.py` — logica pura: scan + raggruppamento fuzzy (no Telegram).
- `core/handlers/messages.py` — comando `dedup`.
- `core/handlers/callbacks.py` — UI stato (toggle/conferma/annulla) + cancellazione.
- `core/strings.py` — stringhe.

## Fatti verificati
- `FUZZY_DUPLICATE_THRESHOLD` in config (default 90). rapidfuzz già dipendenza: `from rapidfuzz import fuzz`, usare `fuzz.WRatio(a, b)` (0-100).
- I nomi file salvati ora sono "solo titolo" (feature metadati-veri), quindi il match fuzzy sui nomi file (senza estensione) è ragionevole per identificare la stessa canzone in cartelle diverse.
- `list_subfolders()` → sottocartelle di primo livello. `library_priority.priority_rank(folder, order)` → 0 = priorità massima.
- Pattern comandi privati: `_is_..._command` + `@dp.message(filtro)` registrato prima del catch-all, gate `chat.type == 'private'` (vedi comando `log`).

## `library_dedup.py` — logica pura
```python
import os
from typing import List, Dict, Any
from rapidfuzz import fuzz
from core.config import logger, MUSIC_DIR, FUZZY_DUPLICATE_THRESHOLD
from core.services.music_library import list_subfolders
from core.services.library_priority import get_order, priority_rank

def _collect_mp3() -> List[Dict[str, Any]]:
    # per ogni sottocartella di primo livello, ogni file .mp3:
    # {"folder": nome, "name": basename senza .mp3, "path": path assoluto}
    ...

def find_duplicate_groups(threshold: int = FUZZY_DUPLICATE_THRESHOLD) -> List[Dict[str, Any]]:
    # 1) raccoglie i file (solo primo livello; ignora eventuali ricorsioni)
    # 2) clustering greedy: per ogni file non ancora assegnato, forma un gruppo con
    #    tutti gli altri non assegnati il cui nome ha fuzz.WRatio(name_a, name_b) >= threshold
    #    (confronto case-insensitive, es. su name.lower().strip())
    # 3) tiene solo i gruppi con >= 2 file in >= 2 cartelle DISTINTE (duplicati cross-folder)
    # 4) ordina ogni gruppo per priority_rank(folder, order): il primo (rank minore) è la
    #    copia da TENERE; gli altri sono candidati alla cancellazione
    # ritorna: [{"keep": fileinfo, "candidates": [fileinfo, ...]}, ...]
    ...
```
Note logica:
- Un file per cartella nel gruppo (i nomi sono unici per cartella), quindi "≥2 cartelle distinte" ≡ "≥2 file".
- La copia da tenere non è mai tra i candidati.
- `get_order()` una sola volta e passarlo a `priority_rank` per coerenza.

## UI e stato (callbacks.py)
- Store effimero a livello modulo: `dedup_sessions: Dict[str, Dict[str, Any]] = {}`.
  - Alla creazione: `sid = uuid.uuid4().hex[:6]`; per ogni candidato un `cid` progressivo; `session = {"candidates": {cid: {"path":..., "label": f"{name} @ {folder}", "selected": True}}, "keep_labels": [...]}`.
  - Cap: limitare il numero totale di candidati mostrati (es. 60) per non superare i limiti bottoni/lunghezza Telegram; se eccede, troncare e avvisare.
- Rendering messaggio:
  - Testo: intestazione `DEDUP_HEADER` + per ogni gruppo una riga tipo `"🎵 {name} — keep in {folderKeep}"`.
  - Keyboard: per ogni candidato un bottone toggle su riga propria: testo `("☑️ " if selected else "☐ ") + label`, `callback_data=f"dd_tog_{sid}_{cid}"`. In fondo: `[✅ Confirm delete → dd_ok_{sid}]` e `[❌ Cancel → dd_no_{sid}]`.
- Handler `@dp.callback_query(F.data.startswith("dd_"))`:
  - Parsare `parts = cq.data.split("_")`: forma `dd_tog_{sid}_{cid}` / `dd_ok_{sid}` / `dd_no_{sid}`.
  - Sessione mancante (`sid` non in `dedup_sessions`) → `cq.answer("Session expired.", show_alert=True)`; return.
  - `dd_tog`: invertire `selected` del candidato; ri-renderizzare la keyboard via `edit_reply_markup`; `cq.answer()`.
  - `dd_no`: eliminare la sessione; `cq.message.edit_text(DEDUP_CANCELLED, reply_markup=None)`; `cq.answer()`.
  - `dd_ok`: raccogliere i candidati con `selected=True`; per ciascuno `os.remove(path)` in try/except (loggare ogni cancellazione a INFO, ogni errore a warning/exception); eliminare la sessione; `cq.message.edit_text(DEDUP_DONE.format(n), reply_markup=None)`; `cq.answer("Deleted")`. Non applicare `check_callback_spam`.
  - Robustezza edit con `try/except (TelegramBadRequest, AttributeError, TypeError)` + `logger.warning`.

## messages.py — comando dedup
- `_is_dedup_command(message)`: `text.lower() == "dedup"` (o startswith "dedup "). Evitare falsi positivi con altri comandi.
- Handler `@dp.message(_is_dedup_command)` registrato tra i filtri prima del catch-all; gate `chat.type == 'private'`; blocco `BLOCKED_USER_IDS`.
- Eseguire `find_duplicate_groups()` (in thread se pesante: `await asyncio.to_thread(find_duplicate_groups)` — lo scan del filesystem può essere lento). Se nessun gruppo → rispondere `DEDUP_NONE`.
- Creare la sessione e inviare il messaggio con la keyboard (helper di rendering in callbacks.py, riusato da toggle).

## strings.py
- `DEDUP_COMMAND_PREFIX = "dedup"`
- `DEDUP_NONE = "✅ No cross-folder duplicates found."`
- `DEDUP_HEADER = "🗑 Duplicates found. Uncheck what you want to KEEP, then confirm deletion:"`
- `DEDUP_CANCELLED = "Cancelled. Nothing deleted."`
- `DEDUP_DONE = "✅ Deleted {} file(s)."`
- `DEDUP_TRUNCATED = "⚠️ Too many duplicates: showing only the first ones."`
- `BUTTON_DEDUP_CONFIRM = "✅ Confirm delete"`, `BUTTON_DEDUP_CANCEL = "❌ Cancel"`.

## Note e sicurezza
- Operazione distruttiva su file reali in `MUSIC_DIR`: la cancellazione avviene SOLO su `dd_ok` e SOLO sui candidati con `selected=True`. La copia "keep" non è mai un candidato.
- Il match fuzzy può avere falsi positivi: la lista deselezionabile è la salvaguardia (l'utente toglie ciò che non è davvero un duplicato).
- Solo primo livello: eventuali sottocartelle ricorsive ignorate.
- Non cancellare `priority.txt` (è un file in `MUSIC_DIR`, non in una sottocartella; `_collect_mp3` guarda solo dentro le sottocartelle, quindi è escluso).

## Skill di codice
Caricare `coding-standard`. Stringhe in inglese, commenti in italiano forma infinito.

## Verifica finale
- `python -m py_compile` su library_dedup.py, messages.py, callbacks.py, strings.py.
- Prova `find_duplicate_groups`/grouping nello scratchpad con una struttura di cartelle finta (file .mp3 vuoti) puntando a una dir temporanea — SENZA toccare `MUSIC_DIR` reale (se non fattibile senza refactor, limitarsi al test della funzione di clustering su liste in memoria).
- Aggiornare il worklog: spuntare i sottoproblemi, marcare `DA TESTARE` il flusso runtime.

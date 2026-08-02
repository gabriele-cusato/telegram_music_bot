# Task 1 — Modulo priorità cartelle (priority.txt)

## Obiettivo
Modulo puro (no Telegram) per gestire l'ordine di priorità delle sottocartelle di `MUSIC_DIR`, persistito in `MUSIC_DIR/priority.txt` (una cartella per riga, dall'alto = priorità massima). Autocrea il file, aggiunge automaticamente le cartelle nuove, permette di riordinare, e fornisce il "rank" di una cartella per la dedup.

## Prerequisiti bloccanti
- Devono esistere ed essere leggibili: `core/config.py` (per `MUSIC_DIR`), `core/services/music_library.py` (per `list_subfolders`). Se mancano, fermarsi.
- Non toccare altri file (solo creare il nuovo modulo).
- Version control: git in sola lettura lato orchestratore. Agent-Code NON committa/pusha.
- Verifica: `python -m py_compile` + una prova rapida delle funzioni pure nello scratchpad (senza avviare il bot).

## File da creare
- `core/services/library_priority.py`.

## Fatti verificati
- `MUSIC_DIR` in `core/config.py` (default `C:\Users\gabri\Music`).
- `music_library.list_subfolders() -> List[str]`: sottocartelle di primo livello di `MUSIC_DIR`, ordinate case-insensitive. Ritorna [] se `MUSIC_DIR` non esiste.
- Nessun ciclo di import: `library_priority` importa `core.config` e `core.services.music_library`; `music_library` importa solo `core.config`.

## API del modulo (proposta)
```python
import os
from typing import List, Optional
from core.config import logger, MUSIC_DIR
from core.services.music_library import list_subfolders

PRIORITY_FILE = os.path.join(MUSIC_DIR, "priority.txt")

def _read_raw() -> List[str]:
    # legge le righe non vuote (nomi cartella), preservando l'ordine; file mancante -> []
    ...

def _write(order: List[str]) -> None:
    # scrive una cartella per riga (utf-8); best-effort, logga eccezioni
    ...

def sync_priority() -> List[str]:
    # riconcilia il file con le sottocartelle reali:
    #  - mantiene l'ordine esistente per le cartelle ancora presenti
    #  - aggiunge in coda le cartelle nuove (ordine alfabetico case-insensitive)
    #  - scarta dal file le cartelle non più esistenti
    # scrive il risultato e lo ritorna. Crea il file se manca.
    ...

def get_order() -> List[str]:
    # ritorna l'ordine corrente riconciliato (chiama sync_priority)
    ...

def apply_move(index: int, delta: int) -> List[str]:
    # carica l'ordine (sync), sposta l'elemento in `index` di `delta` (-1 su, +1 giù)
    # se lo scambio è valido; scrive e ritorna il nuovo ordine. Se index/scambio non
    # validi, ritorna l'ordine invariato.
    ...

def priority_rank(folder: str, order: Optional[List[str]] = None) -> int:
    # indice della cartella nell'ordine (0 = priorità massima). Se assente -> valore
    # grande (priorità minima). Se order è None, usa get_order().
    ...
```

## Sottoproblemi (in ordine)
1. `_read_raw` + `_write` (I/O robusto, encoding utf-8, best-effort con log su eccezione).
2. `sync_priority` con la logica di riconciliazione descritta. Attenzione: NON considerare `priority.txt` stesso come cartella (è un file, `list_subfolders` ritorna solo directory, quindi ok).
3. `get_order`, `apply_move`, `priority_rank`.
4. Robustezza: `MUSIC_DIR` inesistente → `list_subfolders` ritorna [] → `sync_priority` scrive/ritorna [] senza sollevare.

## Note
- Confronto nomi cartella: match esatto sul nome (case-sensitive come restituito da `list_subfolders`). Non normalizzare, per evitare ambiguità tra cartelle simili.
- Nessuna dipendenza da Telegram: il modulo resta testabile.

## Skill di codice
Caricare `coding-standard`. Commenti in italiano forma infinito.

## Verifica finale
- `python -m py_compile core/services/library_priority.py`.
- Prova nello scratchpad: creare una cartella finta con sottocartelle, puntare MUSIC_DIR? (Non modificabile a runtime facilmente). In alternativa testare `_read_raw`/`_write`/`apply_move`/`priority_rank` con liste in memoria e un file temporaneo nello scratchpad, senza dipendere da MUSIC_DIR reale.
- Aggiornare il worklog: spuntare i sottoproblemi.

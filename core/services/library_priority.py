# core\services\library_priority.py
# Gestisce l'ordine di priorità delle sottocartelle di MUSIC_DIR, persistito in
# MUSIC_DIR/priority.txt (una cartella per riga, dall'alto = priorità massima).
# Modulo puro: nessuna dipendenza da Telegram, per restare facilmente testabile.

import os
from typing import List, Optional

from core.config import logger, MUSIC_DIR
from core.services.music_library import list_subfolders

PRIORITY_FILE = os.path.join(MUSIC_DIR, "priority.txt")


def _read_raw() -> List[str]:
    """Legge le righe non vuote del file di priorità, preservando l'ordine. File mancante -> []."""
    if not os.path.exists(PRIORITY_FILE):
        return []

    try:
        with open(PRIORITY_FILE, "r", encoding="utf-8") as f:
            lines = [line.strip() for line in f.readlines()]
    except Exception:
        logger.exception(f"Failed to read priority file: {PRIORITY_FILE}")
        return []

    return [line for line in lines if line]


def _write(order: List[str]) -> None:
    """Scrive l'ordine, una cartella per riga (utf-8). Best-effort: logga senza sollevare."""
    try:
        with open(PRIORITY_FILE, "w", encoding="utf-8") as f:
            for folder in order:
                f.write(f"{folder}\n")
    except Exception:
        logger.exception(f"Failed to write priority file: {PRIORITY_FILE}")


def sync_priority() -> List[str]:
    """Ritorna l'ordine di priorità, creando il file solo alla prima esecuzione.

    Se `priority.txt` non esiste, viene creato con TUTTE le sottocartelle attuali
    (ordine alfabetico case-insensitive) e quell'elenco viene ritornato. Se il file
    esiste già è considerato autoritativo: le cartelle elencate ma non più presenti
    su disco vengono filtrate in memoria (senza riscrivere il file), mentre le
    sottocartelle non elencate sono ignorate (nessun auto-add). Se MUSIC_DIR non
    esiste, list_subfolders ritorna [] e il comportamento è coerente con un elenco vuoto.
    """
    existing_folders = list_subfolders()
    existing_set = set(existing_folders)

    if not os.path.exists(PRIORITY_FILE):
        # file assente: prima creazione, popola con tutte le sottocartelle attuali
        seeded = sorted(existing_folders, key=str.lower)
        _write(seeded)
        return seeded

    # file presente = lista autoritativa: nessun auto-add, nessuna riscrittura.
    # Ritorna solo le cartelle elencate che esistono ancora su disco, nell'ordine del file.
    raw_order = _read_raw()
    return [folder for folder in raw_order if folder in existing_set]


def get_order() -> List[str]:
    """Ritorna l'ordine corrente riconciliato con le sottocartelle reali."""
    return sync_priority()


def apply_move(index: int, delta: int) -> List[str]:
    """Sposta la cartella in `index` di `delta` posizioni (-1 su, +1 giù).

    Carica l'ordine riconciliato, esegue lo scambio se valido, scrive e ritorna il
    nuovo ordine. Se index o lo scambio risultante non sono validi, ritorna
    l'ordine invariato senza scrivere.
    """
    order = get_order()

    target_index = index + delta
    if index < 0 or index >= len(order) or target_index < 0 or target_index >= len(order):
        return order

    order[index], order[target_index] = order[target_index], order[index]
    _write(order)
    return order


def priority_rank(folder: str, order: Optional[List[str]] = None) -> int:
    """Ritorna l'indice di `folder` nell'ordine di priorità (0 = priorità massima).

    Se `folder` non è presente nell'ordine, ritorna un valore grande (priorità
    minima). Se `order` è None, usa get_order().
    """
    if order is None:
        order = get_order()

    try:
        return order.index(folder)
    except ValueError:
        return len(order)

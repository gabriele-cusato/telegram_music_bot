# core\services\library_dedup.py
# Trova canzoni duplicate presenti in più sottocartelle di MUSIC_DIR tramite match fuzzy
# sul nome file. Modulo puro: nessuna dipendenza da Telegram, per restare testabile.

import os
from typing import List, Dict, Any

from rapidfuzz import fuzz

from core.config import MUSIC_DIR, FUZZY_DUPLICATE_THRESHOLD
from core.services.library_priority import get_order, priority_rank


def _collect_mp3(order: List[str]) -> List[Dict[str, Any]]:
    """Raccoglie tutti i file .mp3 di primo livello nelle sottocartelle elencate in `order`.

    Scansiona solo le sottocartelle presenti nell'ordine di priorità: le cartelle non
    elencate in priority.txt sono ignorate dal dedup. Ignora eventuali sottocartelle
    annidate: guarda solo dentro le sottocartelle di primo livello di MUSIC_DIR, quindi
    non tocca mai file direttamente in MUSIC_DIR (es. priority.txt).
    """
    files: List[Dict[str, Any]] = []

    for folder in order:
        folder_path = os.path.join(MUSIC_DIR, folder)
        try:
            entries = os.listdir(folder_path)
        except Exception:
            continue

        for entry in entries:
            if not entry.lower().endswith(".mp3"):
                continue
            entry_path = os.path.join(folder_path, entry)
            if not os.path.isfile(entry_path):
                continue
            files.append({
                "folder": folder,
                "name": entry[:-len(".mp3")],
                "path": entry_path,
            })

    return files


def find_duplicate_groups(threshold: int = FUZZY_DUPLICATE_THRESHOLD) -> List[Dict[str, Any]]:
    """Raggruppa i file audio duplicati tra sottocartelle diverse, in base al nome file.

    Clustering greedy: per ogni file non ancora assegnato, forma un gruppo con tutti gli
    altri file non ancora assegnati il cui nome ha un match fuzzy (fuzz.WRatio) sopra
    threshold, confrontato case-insensitive. Un file per cartella nel gruppo (i nomi sono
    unici per cartella), quindi "gruppo con >= 2 file" equivale a ">= 2 cartelle distinte".

    Ritorna una lista di {"keep": fileinfo, "candidates": [fileinfo, ...]}: keep è la
    copia con priority_rank più basso (priorità più alta), candidates sono le altre copie,
    proposte per la cancellazione. keep non è mai incluso tra i candidati.
    """
    order = get_order()
    files = _collect_mp3(order)

    assigned = [False] * len(files)
    groups: List[Dict[str, Any]] = []

    for i, file_a in enumerate(files):
        if assigned[i]:
            continue

        cluster = [file_a]
        assigned[i] = True

        name_a = file_a["name"].lower().strip()
        for j in range(i + 1, len(files)):
            if assigned[j]:
                continue

            name_b = files[j]["name"].lower().strip()
            if fuzz.WRatio(name_a, name_b) >= threshold:
                cluster.append(files[j])
                assigned[j] = True

        if len(cluster) < 2:
            continue

        cluster.sort(key=lambda f: priority_rank(f["folder"], order))

        groups.append({
            "keep": cluster[0],
            "candidates": cluster[1:],
        })

    return groups

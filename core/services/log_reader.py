"""Logica pura di lettura, parsing e filtro del file di log per il comando `log`.

Nessun import Telegram: modulo testabile in isolamento.
"""

import os
import re
from datetime import date
from typing import List, Optional

from core.config import LOG_FILE

# inizio record: timestamp completo + livello, come scritto da file_handler in config.py
_RECORD_START_RE = re.compile(r'^\[(\d{4}-\d{2}-\d{2}) \d{2}:\d{2}:\d{2}\] \[(\w+)\] ')


def parse_ddmmyy_to_iso(date_str: str) -> Optional[str]:
    """Converte una data in formato gg/mm/aa in YYYY-MM-DD (anno = 2000+aa).

    Ritorna None se il formato o la data non sono validi.
    """
    match = re.fullmatch(r'(\d{2})/(\d{2})/(\d{2})', date_str)
    if not match:
        return None

    day_str, month_str, year_str = match.groups()
    full_year = 2000 + int(year_str)
    try:
        # usare date() per scartare date inesistenti (es. 31/02/26)
        date(full_year, int(month_str), int(day_str))
    except ValueError:
        return None

    return f"{full_year:04d}-{month_str}-{day_str}"


def _read_lines(path: str) -> List[str]:
    """Legge le righe di un file di log; file mancante o illeggibile -> lista vuota."""
    if not os.path.isfile(path):
        return []
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            return f.readlines()
    except OSError:
        return []


def _parse_records(lines: List[str]) -> List[dict]:
    """Divide le righe in record di log.

    Un record inizia con una riga che matcha il timestamp+livello; le righe
    successive senza questo prefisso (es. traceback di exc_info) vengono
    accodate al record precedente, così un'eccezione resta leggibile per intero.
    """
    records: List[dict] = []
    current: Optional[dict] = None

    for line in lines:
        match = _RECORD_START_RE.match(line)
        if match:
            if current is not None:
                records.append(current)
            current = {
                "date": match.group(1),
                "level": match.group(2),
                "text": line.rstrip("\n"),
            }
        elif current is not None:
            current["text"] += "\n" + line.rstrip("\n")

    if current is not None:
        records.append(current)

    return records


def read_log_records(level: Optional[str], limit: int, date_iso: Optional[str]) -> List[str]:
    """Legge il log e restituisce gli ultimi `limit` record che passano i filtri.

    - level: livello richiesto (case-insensitive), o None per tutti i livelli.
    - limit: numero massimo di record più recenti da restituire.
    - date_iso: data richiesta in formato YYYY-MM-DD, o None per nessun filtro data.

    Senza filtro data basta leggere il file corrente (più veloce); con filtro
    data si leggono anche i backup ruotati bot.log.1..3, dal più vecchio al più
    recente, prima del file corrente.

    Ritorno: lista di record (stringhe multi-riga) in ordine cronologico
    crescente. File mancante o non leggibile -> lista vuota, mai eccezioni.
    """
    if date_iso is None:
        lines = _read_lines(LOG_FILE)
    else:
        lines = []
        # backupCount=3: bot.log.3 è il più vecchio, bot.log.1 il più recente tra i backup
        for backup_index in (3, 2, 1):
            lines.extend(_read_lines(f"{LOG_FILE}.{backup_index}"))
        lines.extend(_read_lines(LOG_FILE))

    records = _parse_records(lines)

    if level is not None:
        level_upper = level.upper()
        records = [r for r in records if r["level"].upper() == level_upper]

    if date_iso is not None:
        records = [r for r in records if r["date"] == date_iso]

    if limit <= 0:
        return []

    selected = records[-limit:]
    return [r["text"] for r in selected]

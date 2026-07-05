# core\services\music_library.py
# Pure filesystem helpers for staging and saving downloaded songs into the local music library.
# No Telegram-related imports here to keep this module easily testable and free of circular imports.

import os
import shutil
from typing import Callable, List, Optional

from core.config import logger, MUSIC_DIR, PENDING_SAVE_PATH

# Characters not allowed in Windows file names.
_INVALID_FILENAME_CHARS = '\\/:*?"<>|'


def list_subfolders() -> List[str]:
    """Returns the first-level subfolder names of MUSIC_DIR, sorted alphabetically (case-insensitive)."""
    if not os.path.isdir(MUSIC_DIR):
        logger.warning(f"MUSIC_DIR does not exist or is not a directory: {MUSIC_DIR}")
        return []

    try:
        entries = os.listdir(MUSIC_DIR)
    except Exception:
        logger.exception(f"Failed to list subfolders of MUSIC_DIR: {MUSIC_DIR}")
        return []

    subfolders = [e for e in entries if os.path.isdir(os.path.join(MUSIC_DIR, e))]
    subfolders.sort(key=str.lower)
    return subfolders


def stage_pending_file(key: str, src_audio_path: str) -> Optional[str]:
    """Copies the downloaded audio file into the pending staging area so it survives temp cleanup."""
    if not src_audio_path or not os.path.exists(src_audio_path):
        logger.warning(f"Cannot stage pending file, source does not exist: {src_audio_path}")
        return None

    dest_path = os.path.join(PENDING_SAVE_PATH, f"{key}.mp3")
    try:
        shutil.copyfile(src_audio_path, dest_path)
    except Exception:
        logger.exception(f"Failed to stage pending file for key {key}")
        return None

    logger.info(f"Staged pending file for key {key}: {dest_path}")
    return dest_path


def _sanitize_filename(name: str) -> str:
    sanitized = name
    for ch in _INVALID_FILENAME_CHARS:
        sanitized = sanitized.replace(ch, "_")
    sanitized = sanitized.strip()
    return sanitized or "audio"


def save_pending_to_folder(key: str, subfolder: Optional[str], dest_basename: str) -> str:
    """Copies the staged pending file into the chosen music library subfolder as '<dest_basename>.mp3'."""
    pending_path = os.path.join(PENDING_SAVE_PATH, f"{key}.mp3")

    dest_dir = os.path.join(MUSIC_DIR, subfolder) if subfolder else MUSIC_DIR
    os.makedirs(dest_dir, exist_ok=True)

    safe_basename = _sanitize_filename(dest_basename)
    dest_path = os.path.join(dest_dir, f"{safe_basename}.mp3")

    shutil.copyfile(pending_path, dest_path)
    logger.info(f"Song saved to disk: {dest_path}")
    return dest_path


def discard_pending(key: str):
    """Removes the staged pending file for the given key, if present. Best-effort, never raises."""
    pending_path = os.path.join(PENDING_SAVE_PATH, f"{key}.mp3")
    try:
        if os.path.exists(pending_path):
            os.remove(pending_path)
            logger.info(f"Discarded pending file for key {key}")
    except Exception:
        logger.exception(f"Failed to discard pending file for key {key}")


def pending_exists(key: str) -> bool:
    """Checks whether a staged pending file still exists for the given key."""
    return os.path.exists(os.path.join(PENDING_SAVE_PATH, f"{key}.mp3"))


def prune_orphan_pending(is_valid_key: Callable[[str], bool]) -> int:
    """Removes pending files whose key no longer has valid song data (es. dopo un riavvio del bot).

    is_valid_key viene passato dal chiamante (main.py) invece di importare qui core.services.storage,
    per evitare di accoppiare questo modulo puramente filesystem al livello di persistenza.
    """
    removed = 0
    try:
        entries = os.listdir(PENDING_SAVE_PATH)
    except Exception:
        logger.exception(f"Failed to list PENDING_SAVE_PATH for orphan pruning: {PENDING_SAVE_PATH}")
        return removed

    for entry in entries:
        if not entry.endswith(".mp3"):
            continue
        key = entry[:-len(".mp3")]
        if is_valid_key(key):
            continue
        try:
            os.remove(os.path.join(PENDING_SAVE_PATH, entry))
            removed += 1
        except Exception:
            logger.exception(f"Failed to remove orphan pending file: {entry}")

    if removed > 0:
        logger.info(f"Pruned {removed} orphan pending file(s) from {PENDING_SAVE_PATH}")

    return removed

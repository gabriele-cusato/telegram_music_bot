import time
import asyncio
import os
import uuid
from typing import Dict, Any, List, Optional, Tuple
from aiogram import F, types
from aiogram.types import InlineKeyboardMarkup, InlineKeyboardButton, CallbackQuery, InputMediaAudio, BufferedInputFile
from aiogram.exceptions import TelegramBadRequest
from core import strings
from core.config import dp, bot, logger, MAX_SONG_DURATION_SEC, ANTI_SPAM_CALLBACK_INTERVAL, INFO_EXPIRATION_HOURS, MUSIC_DIR
from core.services.youtube import search_multiple, download_by_url, cleanup_temp_files, get_dislikes
from core.services.storage import (
  get_song_data,
  set_song_data,
  format_number_dot,
  user_last_request_time,
)
from core.services.music_library import (
  list_subfolders,
  stage_pending_file,
  save_pending_to_folder,
  discard_pending,
  pending_exists,
)
from core.services import library_priority

# Delay before an unclaimed pending file is discarded, allineato alla finestra di scadenza delle info in cache.
PENDING_SAVE_TIMEOUT_SEC = INFO_EXPIRATION_HOURS * 3600

# Telegram callback_data must stay well under 64 bytes; caps how many subfolder buttons we render.
MAX_SAVE_FOLDER_BUTTONS = 90

# Stesso cap del save picker: le righe di priorità usano callback_data basati su indice.
MAX_PRIORITY_BUTTONS = 90

# Cap sul numero di candidati alla cancellazione mostrati in un'unica sessione dedup, per
# restare sotto i limiti di Telegram su numero di bottoni e lunghezza del testo.
MAX_DEDUP_CANDIDATES = 60

# Budget di caratteri per il testo della lista dedup: Telegram limita i messaggi a 4096 char,
# si resta ben sotto (margine per header e nota di troncamento) per evitare "message is too long".
DEDUP_TEXT_CHAR_BUDGET = 3500

# Store effimero delle sessioni dedup in corso: sid -> {"candidates": {cid: {...}}}.
# In memoria di processo, non persistito: una sessione sopravvive fino a conferma/annullamento
# o al riavvio del bot.
dedup_sessions: Dict[str, Dict[str, Any]] = {}


async def _pending_cleanup_timeout(key: str):
  """Discards a staged pending file if the user never picks a save destination."""
  await asyncio.sleep(PENDING_SAVE_TIMEOUT_SEC)
  logger.info(f"Pending save timeout expired for key {key}, discarding")
  discard_pending(key)


def _build_save_folder_kb(key: str) -> InlineKeyboardMarkup:
  """Builds the folder picker keyboard (root + subfolders + don't save) for the given pending key."""
  subfolders = list_subfolders()
  if len(subfolders) > MAX_SAVE_FOLDER_BUTTONS:
    logger.warning(f"MUSIC_DIR has more than {MAX_SAVE_FOLDER_BUTTONS} subfolders, truncating save folder list.")
    subfolders = subfolders[:MAX_SAVE_FOLDER_BUTTONS]

  buttons = [[InlineKeyboardButton(text=strings.BUTTON_SAVE_ROOT, callback_data=f"savedir_{key}_root")]]
  for idx, name in enumerate(subfolders):
    buttons.append([InlineKeyboardButton(text=name, callback_data=f"savedir_{key}_{idx}")])
  buttons.append([InlineKeyboardButton(text=strings.BUTTON_DONT_SAVE, callback_data=f"savedir_{key}_skip")])

  return InlineKeyboardMarkup(inline_keyboard=buttons)


def build_priority_kb(order) -> InlineKeyboardMarkup:
  """Builds the priority reordering keyboard: one row per folder with a name button and ▲▼ buttons.

  callback_data usa l'indice della cartella nell'ordine (non il nome), per restare sotto il limite di
  64 byte imposto da Telegram.
  """
  if len(order) > MAX_PRIORITY_BUTTONS:
    logger.warning(f"Priority order has more than {MAX_PRIORITY_BUTTONS} folders, truncating priority list.")
    order = order[:MAX_PRIORITY_BUTTONS]

  buttons = []
  for idx, folder in enumerate(order):
    # una riga per cartella: nome + ▲ + ▼ affiancati
    buttons.append([
      InlineKeyboardButton(text=f"📁 {folder}", callback_data="prio_noop"),
      InlineKeyboardButton(text=strings.BUTTON_PRIO_UP, callback_data=f"prio_up_{idx}"),
      InlineKeyboardButton(text=strings.BUTTON_PRIO_DOWN, callback_data=f"prio_down_{idx}"),
    ])

  # riga finale con il bottone per confermare e chiudere l'ordine attuale
  buttons.append([
    InlineKeyboardButton(text=strings.BUTTON_PRIO_CONFIRM, callback_data="prio_confirm"),
  ])

  return InlineKeyboardMarkup(inline_keyboard=buttons)


def _build_dedup_kb(sid: str, session: Dict[str, Any]) -> InlineKeyboardMarkup:
  """Builds the dedup candidate keyboard: one toggle button per candidate, plus confirm/cancel."""
  buttons = []
  for cid, candidate in session["candidates"].items():
    mark = "☑️ " if candidate["selected"] else "☐ "
    buttons.append([InlineKeyboardButton(text=mark + candidate["label"], callback_data=f"dd_tog_{sid}_{cid}")])

  buttons.append([
    InlineKeyboardButton(text=strings.BUTTON_DEDUP_CONFIRM, callback_data=f"dd_ok_{sid}"),
    InlineKeyboardButton(text=strings.BUTTON_DEDUP_CANCEL, callback_data=f"dd_no_{sid}"),
  ])

  return InlineKeyboardMarkup(inline_keyboard=buttons)


def build_dedup_session(groups: List[Dict[str, Any]]) -> Tuple[str, str, InlineKeyboardMarkup]:
  """Creates a new dedup session from the duplicate groups and builds its text + keyboard.

  Ogni gruppo contribuisce una riga di testo (keep) e i suoi candidati alla cancellazione
  come bottoni toggle. Costruzione incrementale, gruppo per gruppo e candidato per candidato,
  con doppio budget: MAX_DEDUP_CANDIDATES sul numero di bottoni e DEDUP_TEXT_CHAR_BUDGET sulla
  lunghezza del testo. Al primo dei due limiti raggiunto si interrompe subito, avvisando con
  DEDUP_TRUNCATED.

  INVARIANTE DI SICUREZZA (critico, non rimuovere): `candidates` (e quindi la sessione salvata
  in dedup_sessions) contiene ESATTAMENTE i candidati che diventano bottoni nella keyboard
  costruita da _build_dedup_kb. Un candidato troncato dal budget non viene mai aggiunto a
  `candidates`, quindi non può mai comparire come bottone né essere cancellato da dd_ok, che
  itera solo su session["candidates"].
  """
  sid = uuid.uuid4().hex[:6]
  candidates: Dict[str, Dict[str, Any]] = {}
  text_lines = [strings.DEDUP_HEADER]
  current_len = len(strings.DEDUP_HEADER)
  cid_counter = 0
  truncated = False

  for group in groups:
    if truncated:
      break

    keep = group["keep"]
    keep_line = f"🎵 {keep['name']} — keep in {keep['folder']}"
    keep_line_added = False

    for candidate in group["candidates"]:
      if len(candidates) >= MAX_DEDUP_CANDIDATES:
        truncated = True
        break

      # la keep-line del gruppo pesa sul budget solo alla prima accettazione di un suo candidato:
      # se il gruppo non riesce ad aggiungere nemmeno un candidato, la riga non entra nel testo.
      pending_len = 0 if keep_line_added else len(keep_line) + 1
      if current_len + pending_len >= DEDUP_TEXT_CHAR_BUDGET:
        truncated = True
        break

      if not keep_line_added:
        text_lines.append(keep_line)
        current_len += pending_len
        keep_line_added = True

      cid = str(cid_counter)
      cid_counter += 1
      label = f"{candidate['name']} @ {candidate['folder']}"
      # aggiunto a `candidates` SOLO qui, dopo aver superato entrambi i controlli di budget: questo
      # è ciò che garantisce l'invariante di sicurezza descritta sopra.
      candidates[cid] = {"path": candidate["path"], "label": label, "selected": True}

  if truncated:
    text_lines.append(strings.DEDUP_TRUNCATED)

  session = {"candidates": candidates}
  dedup_sessions[sid] = session

  text = "\n".join(text_lines)
  # la kb va costruita DOPO aver finalizzato `candidates`, così i bottoni resi coincidono
  # esattamente con i candidati salvati nella sessione (nessun disallineamento possibile).
  kb = _build_dedup_kb(sid, session)
  return sid, text, kb


async def offer_disk_save(bot, chat_id: int, key: str, audio_file_path: str, reply_to_message_id: Optional[int]):
  """Stages the downloaded audio for a later save via the 'Save Srv' button, without sending any message.

  reply_to_message_id non è più usato (nessun messaggio da inviare): resta nella firma solo per non
  cambiare i chiamanti esistenti in messages.py e choose_song.
  """
  staged_path = stage_pending_file(key, audio_file_path)
  if not staged_path:
    return

  logger.info(f"Staged song for save, key {key} in chat {chat_id}")

  asyncio.create_task(_pending_cleanup_timeout(key))

def check_callback_spam(func):
  async def wrapper(cq: CallbackQuery):
    user_id = cq.from_user.id
    now = time.time()
    
    if now - user_last_request_time.get(user_id, 0) < ANTI_SPAM_CALLBACK_INTERVAL:
      
      user_last_request_time[user_id] = now
      
      return

    user_last_request_time[user_id] = now 
    
    await func(cq)

  return wrapper

def _check_access(cq: CallbackQuery, key: str) -> Optional[Tuple[Dict[str, Any], int]]:
  data_storage = get_song_data(key) 

  if not data_storage:
    asyncio.create_task(bot.answer_callback_query(
      callback_query_id=cq.id, 
      text=strings.INFO_EXPIRED, 
      show_alert=True
    ))
    return None
    
  entry: Optional[Dict[str, Any]] = data_storage.get(f"info_{key}")
  message_id: Optional[int] = data_storage.get(f"msg_{key}")
  if not isinstance(entry, dict) or not isinstance(message_id, int):
     asyncio.create_task(bot.answer_callback_query(
      callback_query_id=cq.id, 
      text=strings.INFO_EXPIRED, 
      show_alert=True
     ))
     return None     

  if cq.from_user.id != entry.get("requester"): 
    asyncio.create_task(bot.answer_callback_query(
      callback_query_id=cq.id, 
      text=strings.NOT_FOR_YOU, 
      show_alert=True
    ))
    return None

  return entry, message_id

@dp.callback_query(F.data.startswith("alt_"))
@check_callback_spam
async def show_alternatives(cq: CallbackQuery):
  key = cq.data[4:] # type: ignore 
  result = _check_access(cq, key)
  if not result:
    return
  entry, _ = result # type: ignore 

  query = entry.get("query", "")
  if not query:
    await cq.answer("Error: Query not found in cache.", show_alert=True)
    return

  results = await search_multiple(query)
  btns = []
  count = 0

  for r in results:
    duration = r.get("duration", 0)
    if duration and duration > MAX_SONG_DURATION_SEC:
      continue

    video_id = r.get('id')
    if not video_id:
      continue

    title_short = (r.get("title") or strings.UNTITLED_SONG)[:40]
    btns.append([InlineKeyboardButton(text=title_short, callback_data=f"choose_{key}_{video_id}")])
    count += 1
    if count >= 10:
      break

  if not btns:
    await cq.answer("No suitable alternatives found.", show_alert=True)
    return

  btns.append([InlineKeyboardButton(text=strings.BUTTON_CANCEL, callback_data=f"cancel_{key}")])
  try:
    if cq.message:
      await cq.message.edit_reply_markup(reply_markup=InlineKeyboardMarkup(inline_keyboard=btns)) # type: ignore 
  except (TelegramBadRequest, AttributeError, TypeError) as e:
    logger.warning(f"Failed to edit alt menu for {key}: {e}")
    pass
  await cq.answer()


@dp.callback_query(F.data.startswith("cancel_"))
@check_callback_spam
async def cancel_alt(cq: CallbackQuery):
  key = cq.data[7:] # type: ignore 
  result = _check_access(cq, key)
  if not result:
    return
  entry, _ = result # type: ignore 

  sender_name = cq.from_user.full_name
  btn_text = strings.BUTTON_REQUESTER.format(sender_name)

  kb = InlineKeyboardMarkup(inline_keyboard=[
    [InlineKeyboardButton(text=btn_text, callback_data=f"info_{key}"),
      InlineKeyboardButton(text=strings.BUTTON_NOT_RIGHT, callback_data=f"alt_{key}")]
  ])

  try:
    if cq.message:
      await cq.message.edit_reply_markup(reply_markup=kb) # type: ignore 
  except (TelegramBadRequest, AttributeError, TypeError) as e:
    logger.warning(f"Failed to restore markup in cancel_alt for {key}: {e}")
    pass
  await cq.answer()


@dp.callback_query(F.data.startswith("choose_"))
@check_callback_spam
async def choose_song(cq: CallbackQuery):
  parts = cq.data.split("_", 2) # type: ignore 
  key = parts[1]
  video_id = parts[2]
  
  result = _check_access(cq, key)
  if not result:
    return
  entry, message_id = result # type: ignore 

  base = None
  
  base_old = entry.get("base")
  if base_old:
    cleanup_temp_files(base_old)

  try:
    if cq.message:
      await cq.message.edit_reply_markup(reply_markup=None) # type: ignore 
  except (TelegramBadRequest, AttributeError, TypeError) as e:
    logger.warning(f"Failed to remove markup in choose_song start for {key}: {e}")
    pass


  url = f"https://www.youtube.com/watch?v={video_id}"
  semaphore = dp['download_semaphore']

  try:
    async with semaphore:
      info, file, thumb, base = await download_by_url(url)
  except Exception as e:
    error_str = str(e)
    if "TOO_LARGE" in error_str: await cq.answer(strings.ERROR_TOO_LARGE, show_alert=True)
    elif "LONG_AUDIO" in error_str: await cq.answer(strings.ERROR_LONG_AUDIO, show_alert=True)
    else:
      logger.error(f"Download Error for alternative: {error_str}", exc_info=True)
      # Estrae la descrizione concisa di yt-dlp, togliendo il prefisso sentinel interno
      if "YT_DOWNLOAD_FAILED" in error_str:
        detail = error_str.split("YT_DOWNLOAD_FAILED:", 1)[-1].strip()
      else:
        detail = error_str
      await cq.answer(f"Error: {detail[:190]}", show_alert=True)
    
    sender_name = cq.from_user.full_name
    btn_text = strings.BUTTON_REQUESTER.format(sender_name)
    kb = InlineKeyboardMarkup(inline_keyboard=[
      [InlineKeyboardButton(text=btn_text, callback_data=f"info_{key}"),
        InlineKeyboardButton(text=strings.BUTTON_NOT_RIGHT, callback_data=f"alt_{key}")]
    ])
    try: 
      if cq.message:
        await cq.message.edit_reply_markup(reply_markup=kb) # type: ignore 
    except (TelegramBadRequest, AttributeError, TypeError) as edit_e: 
      logger.warning(f"Failed to restore markup in choose_song error block for {key}: {edit_e}")
      pass
    return

  if not file:
    cleanup_temp_files(base)
    await cq.answer("Error during download. No audio file found.", show_alert=True)
    return

  with open(file, "rb") as f:
    audio = BufferedInputFile(f.read(), filename=os.path.basename(file))

  thumbnail = None
  if thumb:
    with open(thumb, "rb") as t:
      thumbnail = BufferedInputFile(t.read(), filename=os.path.basename(thumb))

  sender_name = cq.from_user.full_name
  btn_text = strings.BUTTON_REQUESTER.format(sender_name)
  kb = InlineKeyboardMarkup(inline_keyboard=[
    [InlineKeyboardButton(text=btn_text, callback_data=f"info_{key}")],
    [InlineKeyboardButton(text=strings.BUTTON_SAVE_SRV, callback_data=f"savesrv_{key}")],
  ])

  # Titolo/artista puliti quando la fonte è YT Music (track/artist); fallback a title/uploader
  clean_title = info.get("track") or info.get("title")
  clean_artist = info.get("artist") or info.get("uploader")

  try:
    if cq.message and cq.message.chat:
      await bot.edit_message_media( # type: ignore
        media=InputMediaAudio(media=audio, title=clean_title, performer=clean_artist, thumbnail=thumbnail),
        chat_id=cq.message.chat.id,
        message_id=message_id,
        reply_markup=kb
)
    else:
        raise TelegramBadRequest("Message or chat is inaccessible/None.") # type: ignore

  except TelegramBadRequest as e:
    cleanup_temp_files(base)
    logger.error(f"TelegramBadRequest when updating media: {e}")
    await cq.answer(strings.FAILED_TO_UPDATE.format(str(e)), show_alert=True)
    return

  new_song_data = {
    **entry,
    "title": clean_title, "artist": clean_artist, "thumb": thumb,
    "file": file, "base": base, "url": url, "requester": cq.from_user.id,
    "duration": info.get("duration"), "upload_date": info.get("upload_date"),
    "view_count": info.get("view_count") or 0, 
    "like_count": info.get("like_count") or 0,
    "dislike_count": await get_dislikes(info.get("id")), "timestamp": time.time(),
  }
  set_song_data(key, message_id, new_song_data)

  if cq.message and cq.message.chat:
    await offer_disk_save(bot, cq.message.chat.id, key, file, message_id)

  cleanup_temp_files(base)
  await cq.answer(strings.SONG_UPDATED)


@dp.callback_query(F.data.startswith("info_"))
@check_callback_spam
async def show_song_info(cq: CallbackQuery):
  key = cq.data[5:] # type: ignore
  data_storage = get_song_data(key)

  if not data_storage:
    await cq.answer(strings.INFO_EXPIRED, show_alert=True)
    return
    
  data: Optional[Dict[str, Any]] = data_storage.get(cq.data) # type: ignore 
  if not isinstance(data, dict):
    await cq.answer(strings.INFO_EXPIRED, show_alert=True)
    logger.warning(f"Info data is missing or invalid for key: {key}")
    return

  views = format_number_dot(data.get("view_count") or 0)
  likes = format_number_dot(data.get("like_count") or 0)
  dislikes = format_number_dot(data.get("dislike_count") or 0)

  msg = strings.get_song_info_message(data, views, likes, dislikes)

  MAX_ALERT_LENGTH = 200
  if len(msg) > MAX_ALERT_LENGTH:
    msg = msg[:MAX_ALERT_LENGTH - 3] + "..."

  await cq.answer(msg, show_alert=True)


@dp.callback_query(F.data.startswith("savesrv_"))
async def save_srv(cq: CallbackQuery):
  # Not decorated with check_callback_spam: la richiesta di salvataggio non deve essere silenziosamente scartata.
  key = cq.data[len("savesrv_"):] # type: ignore

  data_storage = get_song_data(key)
  if not data_storage:
    await cq.answer(strings.INFO_EXPIRED, show_alert=True)
    discard_pending(key)
    return

  if not pending_exists(key):
    await cq.answer(strings.SAVE_EXPIRED, show_alert=True)
    return

  try:
    if cq.message:
      await bot.send_message(
        chat_id=cq.message.chat.id,
        text=strings.SAVE_PROMPT,
        reply_markup=_build_save_folder_kb(key),
        reply_to_message_id=cq.message.message_id,
      )
  except (TelegramBadRequest, AttributeError, TypeError) as e:
    logger.warning(f"Failed to send save folder picker for {key}: {e}")

  logger.info(f"Save folder picker offered for key {key}")
  await cq.answer()


@dp.callback_query(F.data.startswith("savedir_"))
async def save_to_directory(cq: CallbackQuery):
  # Not decorated with check_callback_spam: the folder choice must not be silently dropped.
  raw = cq.data[len("savedir_"):] # type: ignore
  key, _, sel = raw.partition("_")

  if sel == "skip":
    logger.info(f"User skipped saving for key {key}")
    discard_pending(key)
    try:
      if cq.message:
        await cq.message.edit_text(strings.NOT_SAVED, reply_markup=None) # type: ignore
    except (TelegramBadRequest, AttributeError, TypeError) as e:
      logger.warning(f"Failed to edit message after skipping save for {key}: {e}")
    await cq.answer()
    return

  data_storage = get_song_data(key)
  if not data_storage:
    await cq.answer(strings.INFO_EXPIRED, show_alert=True)
    discard_pending(key)
    return

  entry: Optional[Dict[str, Any]] = data_storage.get(f"info_{key}")
  title = entry.get("title") if entry else None

  # Il nome del file salvato è solo il titolo pulito (i tag ID3 restano invariati).
  dest_basename = title or "audio"

  if sel == "root":
    subfolder = None
  else:
    try:
      idx = int(sel)
    except ValueError:
      logger.warning(f"Invalid save folder selector in callback data: {cq.data}")
      await cq.answer("Invalid selection.", show_alert=True)
      return

    subs = list_subfolders()
    if idx < 0 or idx >= len(subs):
      await cq.answer("Folder no longer available.", show_alert=True)
      return
    subfolder = subs[idx]

  try:
    save_pending_to_folder(key, subfolder, dest_basename)
  except Exception as e:
    logger.exception("Failed to save song to disk")
    await cq.answer(strings.SAVE_FAILED.format(str(e)), show_alert=True)
    return

  logger.info(f"Song saved for key {key} to folder: {subfolder or 'MUSIC_DIR'}")
  discard_pending(key)
  try:
    if cq.message:
      await cq.message.edit_text(strings.SAVED_TO.format(subfolder or "MUSIC_DIR"), reply_markup=None) # type: ignore
  except (TelegramBadRequest, AttributeError, TypeError) as e:
    logger.warning(f"Failed to edit message after saving song for {key}: {e}")
  await cq.answer("Saved")


@dp.callback_query(F.data.startswith("prio_"))
async def priority_reorder(cq: CallbackQuery):
  # Not decorated with check_callback_spam: il riordino non deve essere silenziosamente scartato.
  action = cq.data[len("prio_"):] # type: ignore

  if action == "noop":
    await cq.answer()
    return

  if action == "confirm":
    order = library_priority.get_order()
    ordered_list = "\n".join(f"{i + 1}. {folder}" for i, folder in enumerate(order))
    try:
      if cq.message:
        await cq.message.delete()
        await bot.send_message(chat_id=cq.message.chat.id, text=strings.PRIORITY_CONFIRMED.format(ordered_list))
    except (TelegramBadRequest, AttributeError, TypeError) as e:
      logger.warning(f"Failed to delete/send message on priority confirm: {e}")
    await cq.answer()
    return

  if action.startswith("up_"):
    delta = -1
    idx_text = action[len("up_"):]
  elif action.startswith("down_"):
    delta = 1
    idx_text = action[len("down_"):]
  else:
    logger.warning(f"Unrecognized priority callback data: {cq.data}")
    await cq.answer()
    return

  try:
    idx = int(idx_text)
  except ValueError:
    logger.warning(f"Invalid priority index in callback data: {cq.data}")
    await cq.answer()
    return

  new_order = library_priority.apply_move(idx, delta)

  try:
    if cq.message:
      await cq.message.edit_reply_markup(reply_markup=build_priority_kb(new_order)) # type: ignore
  except (TelegramBadRequest, AttributeError, TypeError) as e:
    if "message is not modified" not in str(e):
      logger.warning(f"Failed to re-render priority keyboard: {e}")

  await cq.answer()


@dp.callback_query(F.data.startswith("dd_"))
async def dedup_callback(cq: CallbackQuery):
  # Not decorated with check_callback_spam: l'operazione è distruttiva, il toggle/conferma/annulla
  # non deve essere silenziosamente scartato.
  parts = cq.data.split("_") # type: ignore

  if len(parts) < 3:
    logger.warning(f"Unrecognized dedup callback data: {cq.data}")
    await cq.answer()
    return

  action = parts[1]
  sid = parts[2]

  session = dedup_sessions.get(sid)
  if session is None:
    await cq.answer("Session expired.", show_alert=True)
    return

  if action == "tog":
    if len(parts) < 4:
      logger.warning(f"Unrecognized dedup toggle callback data: {cq.data}")
      await cq.answer()
      return

    cid = parts[3]
    candidate = session["candidates"].get(cid)
    if candidate is None:
      await cq.answer()
      return

    candidate["selected"] = not candidate["selected"]
    try:
      if cq.message:
        await cq.message.edit_reply_markup(reply_markup=_build_dedup_kb(sid, session)) # type: ignore
    except (TelegramBadRequest, AttributeError, TypeError) as e:
      logger.warning(f"Failed to re-render dedup keyboard for session {sid}: {e}")
    await cq.answer()
    return

  if action == "no":
    del dedup_sessions[sid]
    try:
      if cq.message:
        await cq.message.edit_text(strings.DEDUP_CANCELLED, reply_markup=None) # type: ignore
    except (TelegramBadRequest, AttributeError, TypeError) as e:
      logger.warning(f"Failed to edit message on dedup cancel for session {sid}: {e}")
    await cq.answer()
    return

  if action == "ok":
    deleted_labels = []
    for candidate in session["candidates"].values():
      if not candidate["selected"]:
        continue
      path = candidate["path"]
      # controllo difensivo: cancella solo se il path esiste ed è effettivamente dentro MUSIC_DIR,
      # a protezione da eventuali path malformati.
      real_path = os.path.realpath(path)
      real_music_dir = os.path.realpath(MUSIC_DIR)
      if not os.path.exists(real_path) or os.path.commonpath([real_path, real_music_dir]) != real_music_dir:
        logger.warning(f"Skipped deletion of path outside MUSIC_DIR or missing: {path}")
        continue

      try:
        os.remove(path)
        deleted_labels.append(candidate["label"])
        logger.info(f"Deleted duplicate file: {path}")
      except Exception:
        logger.exception(f"Failed to delete duplicate file: {path}")

    del dedup_sessions[sid]

    if deleted_labels:
      lines = [strings.DEDUP_DONE_HEADER.format(len(deleted_labels))]
      lines.extend(f"🗑 {label}" for label in deleted_labels)
      result_text = "\n".join(lines)
      # limite di sicurezza sulla lunghezza del messaggio (limite Telegram ~4096 char): tronca e segnala
      if len(result_text) > 3800:
        result_text = result_text[:3800] + "\n..."
    else:
      result_text = strings.DEDUP_DONE_NONE

    try:
      if cq.message:
        await cq.message.edit_text(result_text, reply_markup=None) # type: ignore
    except (TelegramBadRequest, AttributeError, TypeError) as e:
      logger.warning(f"Failed to edit message on dedup confirm for session {sid}: {e}")
    await cq.answer("Deleted")
    return

  logger.warning(f"Unrecognized dedup action in callback data: {cq.data}")
  await cq.answer()
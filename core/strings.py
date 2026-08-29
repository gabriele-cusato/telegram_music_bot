import random

COMMAND_PREFIX = "music "
LOG_COMMAND_PREFIX = "log"
PRIORITY_COMMAND_PREFIX = "priority"
DEDUP_COMMAND_PREFIX = "delete"

# Il bot invia i messaggi con parse_mode HTML, quindi i segnaposto tra parentesi angolari
# vanno scritti con le entità &lt; e &gt;: scritti come tag veri Telegram rifiuterebbe il messaggio.
MUSIC_USAGE = "To search for music write music &lt;song_name&gt;, Es: music &lt;Esibizionista&gt;"

LOG_USAGE = "⚠️ Usage: log [info|error|warning] [N] [gg/mm/aa]"
LOG_NO_RESULTS = "No matching log entries."
LOG_TRUNCATED = "⚠️ Output truncated: showing only the most recent messages."

PRIORITY_PROMPT = "📂 Folder priority (top = highest). Use ▲▼ to reorder:"
PRIORITY_EMPTY = "No subfolders in the music library yet."
BUTTON_PRIO_UP = "▲"
BUTTON_PRIO_DOWN = "▼"
BUTTON_PRIO_CONFIRM = "✅ Confirm Order"
PRIORITY_CONFIRMED = "📂 Priority order saved:\n{}"

DEDUP_NONE = "✅ No cross-folder duplicates found."
DEDUP_HEADER = "🗑 Duplicates found. Uncheck what you want to KEEP, then confirm deletion:"
DEDUP_CANCELLED = "Cancelled. Nothing deleted."
DEDUP_DONE_HEADER = "✅ Deleted {} file(s):"
DEDUP_DONE_NONE = "No files deleted."
DEDUP_TRUNCATED = "⚠️ Too many duplicates: showing only the first ones."
DEDUP_SEND_FAILED = "⚠️ Could not show the duplicates list (it was too long to send). Please try again."
BUTTON_DEDUP_CONFIRM = "✅ Confirm delete"
BUTTON_DEDUP_CANCEL = "❌ Cancel"

STATUS_SEARCHING = "🔍 Searching..."
STATUS_CHECKING_UPDATE = "🔄 Checking for a yt-dlp update, the search will start right after..."
STATUS_UPDATE_RESTARTING = "🔄 A yt-dlp update was installed. Restarting to load it, your search will resume automatically..."
STATUS_RESUME_AFTER_UPDATE = "✅ Update completed, resuming your search for \"{}\"..."
ERROR_PREFIX = "❌ Error: "
ERROR_LONG_AUDIO = "Track is longer than 15 minutes."
ERROR_TOO_LARGE = "File is larger than {} MB.".format(50)
ERROR_NO_RESULTS = "No results found."
# Mostrato quando un comando fallisce per un'eccezione non prevista dal comando stesso: il dettaglio
# completo, con il traceback, resta nel log del server e si legge con `/log error`.
ERROR_UNEXPECTED = "❌ Command failed unexpectedly. Full details are in the log: /log error"

TOO_FAST_CALLBACK = ""

BUTTON_REQUESTER = "🎵{}" 
BUTTON_NOT_RIGHT = "🔎 Not the right song?"
BUTTON_CANCEL = "❌ Cancel"
UNTITLED_SONG = "Untitled Song"
UNKNOWN_VALUE = "unknown"
NOT_FOR_YOU = "❌ This button is not for you 💅"
SONG_UPDATED = "Song updated."
INFO_EXPIRED = "Information expired."
FAILED_TO_UPDATE = "Failed to update message: {}"

SAVE_PROMPT = "💾 Save this song to a folder?"
BUTTON_DONT_SAVE = "❌ Don't save"
BUTTON_SAVE_ROOT = "📁 (main folder)"
BUTTON_SAVE_SRV = "💾 Save Srv"
SAVED_TO = "✅ Saved to: {}"
NOT_SAVED = "Not saved."
SAVE_FAILED = "⚠️ Save failed: {}"
SAVE_EXPIRED = "⌛ This song can no longer be saved."


def get_song_info_message(data, views, likes, dislikes):
    """Generates the formatted song information message."""
    
    tagline = random.choice([
        "The oldest song found is a 3400-year-old hymn from Ugarit.",
        "A 40,000-year-old bird bone flute is considered the first instrument."
    ])
    
    year = data.get("upload_date", "")
    year = year[:4] if year else UNKNOWN_VALUE
    
    return (
        f"👤 Artist: {data.get('artist', UNKNOWN_VALUE)}\n"
        f"📅 Year: {year}\n"
        f"──────────────────\n"
        f"📈 Views: {views}\n"
        f" \n"
        f"👍 {likes}  👎 {dislikes}\n"
        f"──────────────────\n"
        f"{tagline}"
    )

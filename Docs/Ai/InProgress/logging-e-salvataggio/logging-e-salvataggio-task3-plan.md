# Task 3 — Comando `log` in chat (solo privata)

## Obiettivo
Un comando testuale `log` usabile SOLO in chat privata col bot, che legge `data/bot.log` e mostra su Telegram gli ultimi N record di log, con filtro opzionale per livello e per data.

## Prerequisiti bloccanti
- Devono esistere ed essere leggibili: `core/handlers/messages.py`, `core/strings.py`, `core/config.py`. Se manca uno, fermarsi.
- **Dipende da Task 2**: `file_handler` deve già essere a livello INFO, altrimenti `log info` dal file sarebbe vuoto. Eseguire Task 3 dopo Task 2.
- Non toccare file diversi da quelli elencati.
- Version control: git in sola lettura lato orchestratore. Agent-Code NON committa/pusha.
- Target di verifica: import/compile dei moduli senza errori.

## File da toccare / creare
- CREARE `core/services/log_reader.py` — logica pura di lettura/parsing/filtri del file di log (nessun import Telegram, testabile).
- `core/handlers/messages.py` — nuovo handler del comando `log` (solo chat privata).
- `core/strings.py` — eventuali stringhe (prefisso comando, messaggi "log vuoto", "solo in privato"…).

## Fatti verificati (stato attuale)
- Formato riga del file (`config.py:31-34`): `'[%(asctime)s] [%(levelname)s] %(message)s'` con `datefmt='%Y-%m-%d %H:%M:%S'`. Esempio: `[2026-06-23 14:05:01] [INFO] Query received from user 123: ...`. NB: il console_handler usa datefmt `%H:%M:%S`, ma sul FILE la data è completa `%Y-%m-%d`.
- File log: `LOG_FILE = data/bot.log` (config `LOG_FILE`). Backup ruotati: `bot.log.1`, `bot.log.2`, `bot.log.3`.
- Comando canzoni esistente: prefisso `strings.COMMAND_PREFIX = "music "`, handler `@dp.message()` in `messages.py:59` che filtra `text.lower().startswith(COMMAND_PREFIX)`. Il nuovo handler deve NON entrare in conflitto: il `message_handler` esistente ritorna presto se il testo non inizia con "music ", quindi va bene aggiungere un handler separato che gestisce il prefisso "log". Attenzione all'ordine di registrazione degli handler aiogram: entrambi sono `@dp.message()`; il primo che matcha e non ritorna vince. Rendere i gate mutuamente esclusivi sul prefisso testo così non si calpestano.
- `message.chat.type == 'private'` identifica la chat privata (già usato in `messages.py:68`).
- parse_mode di default = HTML (`config.py:95`), quindi l'output va passato in `<pre>...</pre>` con `html.escape` sul contenuto.

## Grammatica comando
`log [livello] [N] [gg/mm/aa]` — token dopo il prefisso `log`, separati da spazi, in qualunque ordine tra loro entro i tipi:
- livello ∈ {`info`, `error`, `warning`} (case-insensitive); assente = tutti i livelli.
- N = intero; assente = **25** (default).
- data = formato `gg/mm/aa` (es. `23/06/26` → 2026-06-23); assente = nessun filtro data.
- Semantica N: **ultimi N record più recenti** (dalla fine del file). In tutti i casi.

Esempi:
- `log` → ultimi 25 record di ogni livello.
- `log error` → ultimi 25 record ERROR.
- `log error 30` → ultimi 30 record ERROR.
- `log error 30 23/06/26` → ultimi 30 record ERROR del 2026-06-23.
- `log 30 23/06/26` → ultimi 30 record di ogni livello del 2026-06-23.

## `log_reader.py` — API pura
Funzione principale, es:
```python
def read_log_records(level: Optional[str], limit: int, date_iso: Optional[str]) -> list[str]:
    ...
```
- Legge `data/bot.log` (path dalla config: importare `LOG_FILE` o ricostruire da `DATA_PATH`). Per il filtro data, leggere anche i backup ruotati `bot.log.1..3` se esistono (concatenare in ordine cronologico: i backup sono più vecchi del file corrente). Se NESSUN filtro data, basta il file corrente per gli ultimi N (più veloce).
- Parsing per **record**: un record inizia con una riga che matcha `^\[(\d{4}-\d{2}-\d{2}) \d{2}:\d{2}:\d{2}\] \[(\w+)\] `. Le righe successive senza questo prefisso (es. traceback di `exc_info`) appartengono al record precedente. Così N conta i record, non le righe fisiche, e le eccezioni restano leggibili con il loro traceback.
- Filtri: per livello (match sul gruppo livello, case-insensitive) e per data (match sul gruppo data == date_iso).
- Ritorno: lista degli ultimi `limit` record (stringhe multi-riga), in ordine cronologico crescente (dal più vecchio al più recente tra quelli selezionati).
- Robustezza: file mancante → lista vuota; mai sollevare per parsing.

Helper per convertire `gg/mm/aa` → `YYYY-MM-DD` (anno = 2000+aa). Se la data non è valida, il chiamante mostra un errore d'uso.

## Handler in `messages.py`
- Nuovo `@dp.message()` (o filtro `F.text`) che gestisce il prefisso `log`.
- Gate: SOLO `message.chat.type == 'private'` (indipendente da `ALLOW_PRIVATE_CHAT`, da `ALLOWED_CHAT_IDS`, da `BLOCKED_USER_IDS`? — mantenere comunque il blocco utenti bloccati). Se non è privata: ritornare senza rispondere (non rivelare l'esistenza del comando in gruppo).
- Riconoscere il comando: `text.strip().lower() == 'log'` oppure `text.lower().startswith('log ')`. Evitare falsi positivi con "music ...".
- Parsing argomenti: separare i token, classificarli (livello / intero N / data gg/mm/aa). Token non riconosciuto → messaggio d'uso breve.
- Chiamare `read_log_records(...)`, comporre l'output:
  - Se vuoto → messaggio "no matching log entries".
  - Altrimenti unire i record con `\n`, `html.escape`, avvolgere in `<pre>`.
  - **Limite Telegram 4096 char**: se l'output supera ~3800 char, spezzarlo in più messaggi (`<pre>` per ciascun blocco), massimo un numero ragionevole di messaggi (es. 6); se ancora eccede, troncare i record più vecchi e avvisare.
- Anti-spam: riusare `user_last_request_time` come per gli altri comandi se opportuno (facoltativo, non critico in privato).

## Note e limiti
- N conta i record (voce di log + eventuale traceback), non le righe fisiche: scelta per leggibilità delle eccezioni. Se l'utente si aspetta righe fisiche, è un adattamento futuro.
- Con filtro data si leggono anche i backup ruotati; senza filtro data solo il file corrente (sufficiente per gli ultimi N).

## Skill di codice
Caricare `coding-standard`.

## Verifica finale del task
- Import/compile dei moduli senza errori.
- (Se semplice) una prova di parsing su un `bot.log` di esempio nello scratchpad, senza avviare il bot.
- Aggiornare il worklog: spuntare i sottoproblemi, marcare `DA TESTARE` il comportamento runtime su Telegram.

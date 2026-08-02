# Task 1 — Priority: bottone "Confirm Order"

## Obiettivo
Nella keyboard del comando `priority` aggiungere in fondo un bottone `✅ Confirm Order`. Al click: il messaggio interattivo sparisce (viene cancellato) e il bot invia un nuovo messaggio con l'ordine attuale delle cartelle (dopo le modifiche), come lista numerata.

## Prerequisiti bloccanti
- Devono esistere: `core/handlers/callbacks.py` (con `build_priority_kb`, handler `prio_`), `core/strings.py`, `core/services/library_priority.py` (`get_order`). Se manca, fermarsi.
- Non toccare file diversi.
- Version control: git in sola lettura lato orchestratore. Agent-Code NON committa/pusha.
- Verifica: `python -m py_compile` con `.venv/Scripts/python.exe` (il python di sistema non ha python-dotenv).

## File da toccare
- `core/handlers/callbacks.py` — `build_priority_kb`, handler `prio_`.
- `core/strings.py` — stringhe.

## Fatti verificati
- `build_priority_kb(order)`: costruisce una riga per cartella `[📁 nome][▲ prio_up_{idx}][▼ prio_down_{idx}]`. `prio_noop` per il nome.
- Handler `@dp.callback_query(F.data.startswith("prio_"))`: gestisce `prio_noop`, `prio_up_{idx}`, `prio_down_{idx}` con `apply_move` + `edit_reply_markup`.
- `library_priority.get_order()` → lista cartelle in ordine di priorità.

## Sottoproblemi (in ordine)
1. `strings.py`: aggiungere
   - `BUTTON_PRIO_CONFIRM = "✅ Confirm Order"`
   - `PRIORITY_CONFIRMED = "📂 Priority order saved:\n{}"` (il placeholder riceverà la lista numerata).
2. `build_priority_kb`: dopo le righe delle cartelle, aggiungere una riga finale con `[BUTTON_PRIO_CONFIRM → "prio_confirm"]`.
3. Handler `prio_`: gestire il nuovo caso `prio_confirm`:
   - Comporre la lista numerata dell'ordine corrente: `order = library_priority.get_order()`; testo tipo `"\n".join(f"{i+1}. {folder}" for i, folder in enumerate(order))`.
   - Cancellare il messaggio interattivo: `await cq.message.delete()` (in try/except).
   - Inviare un nuovo messaggio con `PRIORITY_CONFIRMED.format(lista)`: `await bot.send_message(chat_id=cq.message.chat.id, text=...)`.
   - `await cq.answer()`.
   - Robustezza: se `cq.message` è None o delete/send falliscono → `try/except (TelegramBadRequest, AttributeError, TypeError)` + `logger.warning`.
   - Attenzione all'ordine dei rami: `prio_confirm` NON deve essere intercettato dal parsing di `prio_up_`/`prio_down_` (usare confronto esatto `cq.data == "prio_confirm"` o `cq.data.startswith("prio_up_")` ecc., in modo mutuamente esclusivo).

## Note
- Dopo il confirm la conversazione resta con il solo messaggio testuale dell'ordine finale; la tastiera interattiva sparisce come richiesto.

## Skill di codice
Caricare `coding-standard`. Stringhe in inglese, commenti in italiano forma infinito.

## Verifica finale
- `.venv/Scripts/python.exe -m py_compile` su callbacks.py e strings.py.
- Aggiornare il worklog: spuntare i sottoproblemi, marcare `DA TESTARE`.

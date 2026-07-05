# Worklog Task 3 — Comandi con / + menu Telegram — DA TESTARE

## Avanzamento
- [x] messages.py: helper _split_command (toglie '/' e '@bot', ritorna name+args)
- [x] _is_log_command / _is_priority_command / _is_dedup_command usano _split_command
- [x] log_command_handler: args da _split_command
- [x] message_handler (music): accetta music e /music via _split_command, controlli iniziali invariati
- [x] main.py: set_my_commands (default: music; private: music/log/priority/delete) con try/except
- [x] Verificato py_compile + import reale via venv (BotCommand/scope)
- [ ] DA TESTARE: /log /priority /delete /music funzionano come i vecchi; menu compare digitando /

## Test
<!-- Compilata dall'orchestratore dopo i test runtime dell'utente. -->

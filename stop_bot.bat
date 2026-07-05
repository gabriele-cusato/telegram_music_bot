@echo off
powershell -Command "Get-CimInstance Win32_Process -Filter \"Name='python.exe'\" | Where-Object { $_.CommandLine -like '*telegram_music_bot*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"
echo Bot fermato.
pause
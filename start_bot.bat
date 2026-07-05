@echo off
:: Attende la connessione a internet
:loop
ping -n 1 8.8.8.8 >nul
if errorlevel 1 (
    timeout /t 2 >nul
    goto loop
) else (
    :: Si sposta nella cartella del progetto
    cd /d C:\Projects\YtMusicDownload\telegram_music_bot\
    
    :: Esegue lo script usando il percorso corretto del venv
    "C:\Projects\YtMusicDownload\telegram_music_bot\.venv\Scripts\python.exe" main.py > error_log.txt 2>&1
    
    exit
)
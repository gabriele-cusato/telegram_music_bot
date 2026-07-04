#!/bin/sh
export PATH="$PWD/ffmpeg-bin:$PATH"
# Output non bufferizzato: su Render lo stdout è una pipe e Python bufferizza,
# così i log (info/errori) non compaiono live in console. -u / PYTHONUNBUFFERED lo forzano.
export PYTHONUNBUFFERED=1

# Node per il PO token provider (bgutil): binario scaricato nella build command.
export PATH="$PWD/node-v20.18.0-linux-x64/bin:$PATH"
# Server PO token su porta 4416: serve a yt-dlp per ottenere i formati da IP datacenter.
node bgutil-ytdlp-pot-provider/server/build/main.js &
sleep 2

# Health server per il bind del $PORT richiesto da Render: silenziato, altrimenti
# logga ogni ping di health-check e seppellisce/tronca i log del bot in console.
python -m http.server $PORT >/dev/null 2>&1 &
python -u main.py
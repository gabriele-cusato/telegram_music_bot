#!/bin/sh
export PATH="$PWD/ffmpeg-bin:$PATH"
# Output non bufferizzato: su Render lo stdout è una pipe e Python bufferizza,
# così i log (info/errori) non compaiono live in console. -u / PYTHONUNBUFFERED lo forzano.
export PYTHONUNBUFFERED=1
python -m http.server $PORT &
python -u main.py
#!/bin/sh
export PATH="$PWD/ffmpeg-bin:$PATH"
python -m http.server $PORT &
python main.py
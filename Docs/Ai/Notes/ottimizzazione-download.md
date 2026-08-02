# Ottimizzazione del tempo di attesa "Searching..."

Annotazione del 2026-08-02. Strada individuata ma **non intrapresa**: qui restano il ragionamento e le misure, per non doverli rifare.

## Da dove nasce l'attesa

Il messaggio "Searching..." resta in chat finché non sono finiti download **e** conversione: viene cancellato in `core/handlers/messages.py` subito prima dell'invio dell'audio, quindi copre tutte le fasi.

Misure su PC fisso (Windows, brano di prova di 3,26 MB):

| Fase | Tempo |
|---|---|
| Ricerca su YouTube Music | ~1,3 s |
| Download (chiamate API, firme JavaScript, trasferimento) | ~1,9 s |
| Conversione MP3 a 192k | ~1,5 s |
| Tag, conversione copertina, incorporamento | dentro il rumore di misura |

Il trasferimento del file dura meno di un secondo: quei 1,9 s sono quasi tutti chiamate all'API di YouTube e risoluzione delle firme JavaScript.

Sul Raspberry Pi 5 la parte di conversione pesa di più, perché l'encoder `libmp3lame` è monothread e conta solo la velocità del singolo core.

## Strada B — sovrapporre download e conversione

Oggi il bot scarica l'intero file e **solo dopo** lo converte: due fasi in sequenza, ~1,9 s + ~1,5 s. Facendo scorrere il flusso scaricato direttamente dentro ffmpeg, le due cose avverrebbero insieme e il totale scenderebbe quasi al tempo della fase più lunga: **fino a ~1,5 s risparmiati**, circa il doppio di quanto ha reso l'estrazione unica.

Costo: si rinuncia alla catena di postprocessor di yt-dlp (`FFmpegExtractAudio`, `FFmpegMetadata`, `FFmpegThumbnailsConvertor`, `EmbedThumbnail`) e si invoca ffmpeg direttamente, rifacendo a mano tag ID3 e copertina incorporata. È una riscrittura del percorso di download in `core/services/youtube.py`, con rischio concreto di regressioni proprio sui metadati, che sono un requisito esplicito (vedi `DECISIONS.md`: i file devono avere proprietà leggibili in Windows).

Va affrontata solo se il tempo di attesa torna a essere un problema, e con una verifica funzionale seria sui metadati del file prodotto.

## Strada A — encoder MP3 più veloce, mai misurata

`libmp3lame` espone `-compression_level` (0 = lento e accurato, 9 = veloce), che regola quanto lavora l'algoritmo **a parità di bitrate**. Oggi non è impostato e si usa il default. Alzarlo potrebbe ridurre quei ~1,5 s con perdita di qualità minima a 192k. Si passa a yt-dlp con `postprocessor_args`, senza toccare la struttura del codice: rischio quasi nullo, reversibile.

È l'esperimento da fare **per primo** se si riprende in mano l'argomento, prima di considerare la strada B.

## Strade già scartate, non riproporle

- **Download a frammenti paralleli**: inutile, il trasferimento non è il collo di bottiglia.
- **Riusare il `file_id` Telegram dei brani già scaricati**: scartato dall'utente, che lo considera una scorciatoia che falsa il funzionamento del bot.
- **Non riconvertire in MP3, o abbassare il bitrate**: scartato dall'utente, i metadati devono restare leggibili.
- **Accorpare i passaggi ffmpeg**: misurato, non conviene. Oltre alla conversione MP3, gli altri passaggi stanno dentro il rumore di misura (±0,6 s): non c'è nulla di significativo da recuperare.

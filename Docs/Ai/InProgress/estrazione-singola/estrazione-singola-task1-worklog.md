# estrazione-singola — task1 — Worklog

DA TESTARE

## Avanzamento
- [x] Misura di riferimento dei tempi **prima** della modifica
- [x] Lettura del sorgente di yt-dlp per individuare il metodo che scarica da informazioni già estratte
- [x] Unificazione delle opzioni in un solo dizionario e una sola istanza di `YoutubeDL`
- [x] Estrazione unica con i controlli preventivi di durata e dimensione, eccezioni e messaggi invariati
- [x] Download riusando le informazioni già estratte, con `base` e `info` finali corretti
- [x] Parte finale invariata: ricerca di audio e copertina, controllo dimensione, pulizia, valore di ritorno
- [x] Commenti che spiegano il motivo dell'estrazione unica e il metodo scelto per il download
- [x] Verifica di sintassi con `py_compile`
- [x] Verifica funzionale su video reale: mp3 prodotto, copertina presente, chiavi di `info` corrette
- [x] Tempi prima/dopo riportati qui sotto

## Tempi misurati
Misure fatte sul video di prova `https://www.youtube.com/watch?v=w3iLsfsaWh4` (brano "Esibizionista", 3,26 MB, 207s di durata), con lo script temporaneo nella cartella scratchpad che chiama `download_by_url` e cronometra con `time.perf_counter()`.

- **Prima** della modifica (doppia estrazione): **5,03 s** totali.
- **Dopo** la modifica (estrazione unica + `process_ie_result` per il download): **3,69 s** totali.
- Risparmio misurato: **~1,34 s** (circa il 27%) sulla singola prova. È inferiore ai circa 5 secondi di risparmio teorico stimati nel plan (che confrontavano un'estrazione isolata "a vuoto" con `skip_download`): qui la seconda estrazione eliminata era comunque seguita, nel giro rimosso, dallo stesso download e dagli stessi postprocessor ffmpeg che restano nel tempo "dopo", quindi il confronto reale include codice non risparmiabile (download del file, conversione mp3, tag, copertina). Il risparmio osservato corrisponde comunque a un intero giro di rete verso YouTube (l'estrazione di metadati) rimosso dal percorso, coerente con l'obiettivo del task.

## Test
_Da compilare dopo i test dell'utente._

# Worklog Task 1 — Fix metadati MP3 — DA TESTARE

## Avanzamento
- [x] Sostituiti i postprocessors di `download_opts` con FFmpegExtractAudio + FFmpegMetadata + EmbedThumbnail
- [x] Aggiunto FFmpegThumbnailsConvertor (jpg) prima di EmbedThumbnail
- [x] Rimosso l'hack di rinomina estensione (righe ~163-168), mantenuto lo scan del file audio
- [x] Verificato import/compile del modulo senza errori

## Test
<!-- Compilata dall'orchestratore dopo i test runtime dell'utente. -->

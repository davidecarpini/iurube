# iurub 1.3 — In corso, ripresa e riassunti

1 novembre 2026 · progetto `/Users/davidecarpini/apps/iurub` · versione **1.3.0, build 4**.

## Modifiche consegnate

- **In corso** è la prima tab, a sinistra di **Salvati**. Aprire un video lo porta nel player dedicato, conservando la pagina da cui proviene.
- Posizione conservata separatamente per video, anche dopo cambio di tab e riavvio. All’avvio si apre l’ultimo video incompleto; altrimenti Salvati. Premi Play quando richiesto da YouTube.
- Aprire un altro video non cancella il punto del precedente. Un secondo tocco su In corso non azzera la riproduzione; sulle altre tab torna alla pagina iniziale.
- **Indietro** mantiene la cronologia WebKit anche nel player, senza aggiungere nuovamente la pagina di destinazione.
- Conservate **Salvati, Iscrizioni, Cronologia, Esplora**, login condiviso, refresh, Tu in alto e webview fino al bordo inferiore.
- **Riassunto** apre una modale chat con Gemini 2.5 Flash via OpenRouter/Google AI Studio. Domande e approfondimenti conservano il video nel contesto; ogni video mantiene la propria conversazione locale. Cache, interruzione e retry esplicito.
- Chiave configurata nel **Portachiavi** di simulatore e iPhone. Nessuna chiave nei sorgenti, conversazioni, screenshot o ZIP. File temporanei di importazione eliminati.
- **Segnalibro compatto** nella riga dettagli/avatar/menu e **cestino** nella colonna azioni dei salvati, senza righe aggiuntive sotto i video. Aree toccabili da 44 punti.
- Salvati mostra direttamente la lista, senza la copertina grande. Nascondimento limitato alla playlist Guarda più tardi, inclusa la variante autenticata del sito.
- Rimosse dalle impostazioni **Account YouTube** e **Archivio locale**; conservati dati precedenti e toggle Shorts.

## Esiti effettivi

Ambiente: **Xcode 27.2 · iPhone Air · iOS 27.2**.

| Verifica | Esito finale | Copertura |
|---|---|---|
| Swift Testing, macOS e simulatore | **32/32** | URL, preferenze, persistenza, richieste Gemini, cache/errori/cancellazione; checkpoint per video, riavvio, completamento/replay, timestamp ed eventi tardivi |
| XCUITest con fixture | **6/6** | Cinque tab/toolbar, salva/rimuovi/Annulla, Shorts, chat/retry, In corso, cambio tab/video, riavvio e completamento |
| XCUITest YouTube reale | **1/1** | Playlist autenticata, menu ufficiale, lista compatta, sezioni, Tu → Indietro e impostazioni |
| XCUITest Gemini reale | **1/1** | Chat riaperta e nuova domanda sul video pubblico “Me at the zoo”; risposta sugli elefanti. Riassunto iniziale reale già verificato nella stessa sessione |
| XCUITest ripresa reale | **1/1 dopo correzione dell’attesa del test** | Nuova posizione reale dopo riavvio, poi Tu → Indietro senza duplicare la cronologia |
| JavaScript/jsdom | **39/39** | Playlist, Shorts, layout, navigazione verso player, timestamp, seek confermato, annunci, eventi tardivi, bfcache e Trusted Types |
| Build Debug simulatore | **Superata** | Firma ad hoc per il Portachiavi; app riavviata normalmente senza fixture |
| Build Release iPhone | **Superata** | Apple Development, Personal Team configurato |
| Installazione iPhone fisico | **Superata** | iPhone di Davide, iPhone 16 Pro Max, iOS 26.6.1; versione **1.3.0 (4)** sopra l’app esistente |

**41 test iOS distinti superati come esito finale**, più **39 test JavaScript**. Le ripetizioni non sono sommate due volte.

Il player reale ha confermato **8,000 secondi prima e dopo il riavvio**, durata **19,0135 secondi**, con un nuovo aggiornamento del media dopo la riapertura. Il secondo avvio legge il checkpoint persistito, senza impostare nuovamente il tempo. Il probe Debug mette in pausa solo dopo la conferma del media; non simula tempo o durata.

Nella sessione live combinata playlist e Gemini sono passati; la ripresa ha incontrato il pulsante Play esposto da YouTube prima che il player fosse pronto. Il filmato mostrava ancora la schermata iniziale di caricamento. Corretto il test consentendo un nuovo tocco sul controllo visibile, la ripetizione mirata ha superato ripresa e cronologia. Il JSON originale conserva quel timeout, risolto nel risultato mirato allegato.

L’installazione fisica è riuscita. **L’apertura automatica è stata rifiutata perché l’iPhone era bloccato**: apri iurub dopo averlo sbloccato. Nessun aggiramento, disinstallazione o cancellazione di cookie, playlist, dati e credenziali. Il precedente avvio fisico e l’importazione della chiave erano riusciti.

## Evidenze

- `build/Tests-20261101-194303.xcresult`: **38 pass**, nessun errore o test saltato.
- `build/Tests-20261101-194658.xcresult`: **2 pass**, timeout della prima prova di ripresa descritto sopra.
- `build/Playback-Final-Live.xcresult`: **1 pass**, nessun errore o test saltato; ripresa e Indietro finali.
- `work/playback-final-js.log`: **39 pass**. `work/playback-core-final.log`: **32 pass**.
- Build/installazione fisica: `work/playback-final-iphone-build.log`, `work/playback-final-iphone-install.json`.
- Apertura rifiutata per blocco: `work/playback-final-iphone-launch.json`.
- `iurub-ripresa-reale.json` negli outputs conserva checkpoint e timestamp reali. Screenshot di lista, player e chat ispezionati visivamente.

## Isolamento e limiti

Aggiunta/rimozione usano fixture e una playlist di prova. I controlli sul sito reale non aggiungono né rimuovono video dalla playlist dell’utente. La prova del player usa un archivio di checkpoint separato da quello normale. La prova Gemini usa un video pubblico di circa 19 secondi, senza coprire sistematicamente durate, lingue o tipi di video.

I checkpoint sono locali, fino a 100 video, salvati circa ogni cinque secondi e su pausa, seek, cambio sezione e background. Una chiusura improvvisa può perdere gli ultimissimi secondi. Annunci e media senza durata valida non sovrascrivono il punto del contenuto. Caricamento e disponibilità dipendono da YouTube; i video non vengono scaricati.

Gemini analizza il contenuto audiovisivo accessibile, senza simulare una trascrizione completa. Video privati o con restrizioni possono non essere analizzabili. Le risposte possono contenere errori. URL del video e conversazione vengono inviati a OpenRouter/Google, usando il credito dell’account.

La suite funzionale è eseguita nel simulatore; sul telefono è verificata l’installazione, con il limite dell’ultimo avvio bloccato. Fullscreen, PiP, AirPlay, rotazione, iOS 17 e VoiceOver completo non sono stati ricollaudati in questo aggiornamento. I cambiamenti del sito possono richiedere manutenzione.

## Ripetere

```sh
cd /Users/davidecarpini/apps/iurub
./scripts/test-core.sh
npm test
./scripts/simulator.sh test
./scripts/simulator.sh live
TEST_RUNNER_IURUB_PLAYBACK_LIVE=1 ./scripts/simulator.sh live
TEST_RUNNER_IURUB_SUMMARY_LIVE=1 ./scripts/simulator.sh live
```

Il normale `live` richiede il login YouTube e salta le due prove opt-in. Il flag playback abilita il player reale; summary abilita richieste reali OpenRouter con la chiave configurata. L’avvio normale usa sito e dati reali, senza fixture.

## Deliverable

- `iurub-sorgenti.zip`: progetto completo, test, script e documentazione, senza credenziali.
- `iurub-in-corso.png`, `iurub-player-indietro.png`: player reale e ripresa.
- `iurub-salvati-compatti.png`, `iurub-iscrizioni.png`, `iurub-esplora.png`: sito reale con cinque tab e controlli compatti.
- `iurub-riassunto-chat.png`: riepilogo e prima domanda Gemini reale; `iurub-riassunto-test-live.png`: ulteriore domanda del collaudo finale.
- `iurub-impostazioni.png`: sezioni aggiornate e OpenRouter configurato, senza chiave visibile.
- `iurub-ripresa-fixture.png`: prova deterministica a 42 secondi con media simulato.
- `iurub-test-ios.json`, `iurub-test-live.json`, `iurub-test-ripresa.json`, `iurub-test-javascript.txt`: esiti originali, incluso il timeout live poi risolto.
- `LEGGIMI.txt`, `Avvia-iurub.command`: istruzioni e avvio del simulatore.

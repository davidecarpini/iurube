# iurub 1.6.0 · build 9

La barra del player riprende la proposta [In linea in Figma](https://www.figma.com/design/Z5jYRiRSVP4Gt8CERP4nFi/Untitled?node-id=7-422). Salva, Finestra, i pulsanti − e + con il valore della velocità e Riassunto sono accessibili con un tocco. Il segnalibro diventa pieno dopo la conferma del salvataggio e torna vuoto dopo la rimozione. In **Salvati** iurub ricarica la playlist a ogni ingresso. Se una modifica si conclude dopo il cambio di tab, iurub aggiorna la lista già aperta.

Le notifiche di conferma della playlist vengono sostituite da un solo messaggio nativo, **Salvato** o **Rimosso**. Le altre notifiche e gli errori del sito restano disponibili.

**Riproduzione fuori dall’app.** Quando il player in primo piano perde il focus, iurub chiede a WebKit di aprire Picture in Picture per il video già in riproduzione e conserva il punto di visione. L’apertura dipende dalle capacità del dispositivo e del sito. Nel simulatore iPhone Air, che non offre la finestra di sistema, sia la clip con traccia audio sia il video YouTube pubblico hanno subito una sospensione durante il cambio di app. La clip ha mantenuto la posizione e ha ripreso a scorrere al rientro. La continuità automatica in una finestra di sistema resta da verificare in TestFlight.

**Verifiche.** Superati 54 test JavaScript e 48 test Swift. Sul simulatore sono inoltre passati sei test di interfaccia distinti, inclusa la prova della velocità sul video YouTube reale. Il test della riproduzione continua di YouTube è stato registrato come saltato dopo aver misurato la sospensione sul simulatore senza PiP. I cambi alla playlist sono stati provati con un account simulato. La larghezza del valore «1,25×», i limiti della velocità e la ripresa della clip sono stati riverificati sulla versione definitiva. Esiti in `build/InlinePlayer-Final-160.xcresult` e `build/InlinePlayer-Release-160.xcresult`.

**TestFlight.** Apple ha ricevuto iurub 1.6.0 (9) il 2 novembre 2026 alle 16:21, ora italiana. App Store Connect conferma la disponibilità della build 9 per il gruppo interno **Internals**, con un invito. [Dettagli della build](https://appstoreconnect.apple.com/apps/6829671295/testflight/ios/76572cfa-7e32-46fc-afb0-c3707a54fe86). Archivio firmato `build/Distribution/iurub-1.6.0-9-final.xcarchive`, sorgenti `0b4eb28`.

---

# iurub 1.5.0 · build 8

2 novembre 2026. Nella barra di **In corso**, il pulsante Picture in Picture apre la finestra di sistema durante la riproduzione. I pulsanti **−** e **+** regolano la velocità da 0,5× a 2× a passi di 0,25×. L’indicatore legge la velocità effettiva del player.

**Prove sul simulatore.** Nella verifica finale sono passati 48 test Swift e 3 XCUITest per velocità, ripresa tra tab e riavvio, e riassunti manuali (`build/PlayerControls-Final-150.xcresult`). Su iPhone Air una clip H.264 locale ha verificato il cambiamento della velocità effettiva, entrambi i limiti e il relativo blocco dei pulsanti. Un secondo test su YouTube, con “Me at the zoo”, ha cambiato la velocità del player e ripristinato il valore iniziale. I 51 test JavaScript sono passati, inclusi i casi di transizione PiP, pausa e limiti imposti dal sito. Il simulatore non supporta la finestra PiP di sistema: in quell’ambiente è verificato il messaggio di indisponibilità.

**Prova PiP precedente alla scelta di usare solo il simulatore.** Con una clip di test su iPhone 16 Pro Max, il video è passato da 3 a 10 secondi mentre era aperta un’altra app ed è tornato nel player al rientro. Prova su copia isolata, rimossa assieme al runner. Per le verifiche future si usa solo il simulatore.

**Distribuzione.** Archivio definitivo: `build/Distribution/iurub-1.5.0-8-final.xcarchive`. Firma verificata; nessuna chiave OpenRouter o clip di test nel pacchetto. Commit dei sorgenti: `5df6945`. Apple ha ricevuto la build alle 14:29, ora italiana. TestFlight conferma la versione 1.5.0 (8) assegnata al gruppo interno **Internals** (1 invito). [Apri la build](https://appstoreconnect.apple.com/apps/6829671295/testflight/ios/81052e6d-89cc-428d-b527-d0e5e859fc50).

---

# iurub 1.4.1 · build 7

2 novembre 2026. In **Impostazioni → Riassunti con Gemini** il toggle **Riassunto automatico nei Salvati** è spento per impostazione iniziale, anche aggiornando dalla versione precedente. In modalità manuale, un video salvato o aperto attende il tocco su **Riassunto**. Attivando il toggle, i nuovi salvataggi confermati da YouTube avviano il riassunto. La preferenza viene conservata al riavvio. Disattivarla rimuove le richieste automatiche ancora in coda e lascia terminare quelle già avviate.

**Verifica.** Superati 48 test Swift e 3 XCUITest su iPhone Air. La prova manuale salva il video, lo riapre da Salvati, verifica lo stato “Da preparare” e ottiene il testo dopo il tocco su Riassunto. La prova automatica verifica che la risposta sia pronta prima di aprire la chat. Sono stati verificati anche la persistenza della preferenza, il cambio di modello e lo svuotamento della coda. Le prove hanno usato risposte simulate. Risultati in `build/AutoSummary-141.xcresult`.

**Distribuzione.** Archivio Release firmato e verificato in `build/Distribution/iurub-1.4.1-7.xcarchive`. Xcode ha completato il caricamento il 2 novembre alle 14:08 (ora italiana). App Store Connect conferma la build 7 disponibile per il gruppo interno Internals (1 invito). Dettaglio: https://appstoreconnect.apple.com/apps/6829671295/testflight/ios/a9a357ed-662b-4489-8a91-f3e0e9d1246e

---

# iurub 1.4.0 · build 6

2 novembre 2026. In Impostazioni → Modello e costi si sceglie tra Gemini 2.5 Flash-Lite, 3.1 Flash-Lite, 2.5 Flash e 3.8 Flash. La preferenza viene conservata. Le richieste in partenza usano il modello scelto e le risposte riportano il modello e, quando fornito da OpenRouter, il costo. Le vecchie conversazioni rimangono leggibili.

Il confronto in USD usa le tariffe standard di Google AI Studio su OpenRouter, comprese le componenti audio e di risposta. La durata del video e il numero di domande modificano la stima per 1 e 30 video. Il calcolo, le ipotesi e la data del listino di riserva sono visibili nell’app.

**Verifica.** Sono passati 46 test Swift e la prova nel simulatore della selezione persistente, del riassunto anticipato e di una domanda con un modello diverso nella stessa chat. Due test distinti hanno verificato sul video pubblico di 19 secondi “Me at the zoo” che ciascun Flash-Lite genera un riassunto e restituisce un costo effettivo. Nel primo tentativo 2.5 Flash-Lite aveva ricevuto un limite di richieste. I test successivi sono passati per entrambi. Per 3.8 Flash sono stati verificati catalogo, tariffe e costruzione della richiesta.

**Distribuzione.** Xcode ha firmato e caricato la build 6 di `it.davidecarpini.iurub`. Apple ha confermato la ricezione alle 10:16. In App Store Connect la versione 1.4.0 appare nell’elenco di TestFlight con la build 6 assegnata al gruppo interno **Internals** e un invito registrato. [Dettaglio build](https://appstoreconnect.apple.com/apps/6829671295/testflight/ios/d8d66bc0-82be-4542-92fa-4a8069a09035)

Gli esiti sono in `build/ModelCosts-140-Validation.xcresult` e `build/ModelCosts-140-Live.xcresult`. L’archivio distribuito è `build/Distribution/iurub-1.4.0-6.xcarchive`.

---

# iurub 1.3.1 — Commenti, segnalibri e riassunti anticipati

2 novembre 2026 · versione **1.3.1, build 5** · progetto `/Users/davidecarpini/apps/iurub`.

## Modifiche

- Nella pagina video sono nascosti i suggerimenti. Player, titolo, azioni e riquadro Commenti restano visibili; il riquadro apre il pannello ufficiale di YouTube. Esplora, Iscrizioni e le playlist mantengono le loro liste.
- Il segnalibro diventa pieno quando l’app conosce l’appartenenza a Guarda più tardi. Un secondo tocco rimuove il video. Lista e player condividono lo stato verificato; il menu ufficiale e Annulla rimangono disponibili.
- Il riassunto parte dopo un nuovo salvataggio confermato da YouTube. La coda evita duplicati e avvia una sola richiesta automatica alla volta. Aprire la chat usa la risposta pronta o la richiesta in corso; un video ancora in coda prende priorità. La chat conserva domande e risposte esistenti.
- Errori, chiave mancante e interruzioni non producono tentativi automatici ripetuti. L’indicatore accanto a Riassunto segnala la preparazione. Le impostazioni descrivono questo comportamento e l’uso del credito OpenRouter.
- Gli stati della playlist restano in memoria durante la sessione. Aprendo i controlli dell’account vengono invalidati e la lista viene riletta al ritorno. Un video non ancora verificato viene esposto all’accessibilità come “da verificare”, senza dichiararlo assente.

## Verifiche effettive

Ambiente: **Xcode 27.2 · iPhone Air · iOS 27.2**.

| Verifica | Esito |
|---|---|
| Swift, modelli | **41/41**, anche nel simulatore |
| XCUITest con fixture | **9/9** come esito finale |
| XCUITest commenti YouTube reale | **1/1** |
| JavaScript/jsdom | **49/49** |
| Build Debug simulatore | Superata |
| Archivio Release 1.3.1 (5) | Superato; firma verificata |
| Installazione iPhone di Davide | Superata, sopra l’app esistente |
| Apertura automatica su iPhone | Rifiutata: dispositivo bloccato |

**51 test iOS distinti superati**, più **49 test JavaScript**. Le ripetizioni non sono sommate.

La prima suite iOS ha prodotto 47 pass e 3 errori nei selettori dei test: con `aria-pressed`, WebKit espone il segnalibro come **Switch**, mentre i test cercavano un **Button**. La gerarchia accessibile esportata conferma la causa. Corretto solo il selettore, i tre test ripetuti sono passati conservando tutte le verifiche di salvataggio, rimozione, riavvio e prefetch. Gli esiti originali sono conservati.

La prova del riassunto anticipato verifica che la risposta esista **prima di aprire la modale**, e che riaprirla non aggiunga una seconda risposta. I test dei modelli coprono richieste duplicate, cache persistita, una sola richiesta automatica attiva, priorità manuale, errori, chiave assente, cancellazione e risposte tardive.

Sul sito reale è stato aperto il video pubblico “Me at the zoo”. Il controllo strutturale conferma suggerimenti nascosti e commenti visibili. XCUITest apre e chiude il pannello ufficiale dei commenti; gli screenshot sono stati ispezionati. Nessun commento è stato pubblicato e la playlist reale non è stata modificata.

## Evidenze

- `build/Tests-20261102-002417.xcresult`: 47 pass, 3 errori di selezione descritti sopra.
- `build/Changes131-Bookmark-Retry.xcresult`: 3 pass, nessun errore.
- `build/Changes131-Comments-Live.xcresult`: 1 pass, nessun errore.
- `work/membership-watch-bridge-tests.log`: 49 pass.
- `work/changes-131-archive.log`: ARCHIVE SUCCEEDED.
- `work/changes-131-iphone-install.json`: installazione riuscita; `work/changes-131-iphone-launch.json`: Locked.
- Archivio: `build/Distribution/iurub-1.3.1-5.xcarchive`. Il bridge archiviato coincide con il sorgente finale. Nessuna chiave OpenRouter incorporata nell’app.

## Distribuzione e limiti

Apple ha ricevuto iurub 1.3.1 (5) il 2 novembre 2026 alle 09:45, ora italiana. Xcode ha confermato il caricamento e l’avvio dell’elaborazione per TestFlight. [Apri TestFlight](https://appstoreconnect.apple.com/apps/6829671295/testflight/ios)

L’iPhone era bloccato durante il tentativo di apertura automatica: l’utente può aprire iurub dopo lo sblocco. Non sono stati cancellati cookie, credenziali, playlist o dati precedenti.

Il salvataggio e la rimozione remoti sono verificati tramite i controlli di YouTube, quindi dipendono dal suo DOM. Una lista caricata solo in parte non dimostra l’assenza degli altri video; lo stato ignoto viene verificato dal menu quando si agisce. I cambiamenti effettuati fuori dall’app richiedono una rilettura o verifica del menu.

La coda dei riassunti non è persistita dopo la chiusura e iOS può sospendere l’elaborazione in background. Le richieste automatiche consumano il credito OpenRouter già autorizzato. In questo aggiornamento il prefetch è stato provato con risposte simulate; **nessuna nuova richiesta reale a Gemini** è stata effettuata. L’integrazione reale Gemini e la ripresa della riproduzione erano state verificate nella versione 1.3.0, documentata nello storico.

## Deliverable

Negli outputs: sorgenti aggiornati, rapporto, conteggio finale `iurub-test-ios.json`, tre rapporti originali separati, esito JavaScript e `iurub-layout-video-reale.json`.

`iurub-video-commenti.png` e `iurub-commenti-aperti.png` mostrano il sito reale. `iurub-segnalibro-fixture.png` e `iurub-riassunto-anticipato-fixture.png` sono prove esplicitamente simulate. I risultati precedenti sono conservati in `storico/`.

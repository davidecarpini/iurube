# iurub 1.11.0 · build 17

**Riassunto in Cronologia.** Il pulsante con le scintille accanto al segnalibro apre la chat del video selezionato. Si può richiedere un riassunto senza avviare il player o salvare il video. Chiudendo la chat si torna alla stessa tab. Le conversazioni esistenti sono condivise con le altre sezioni.

**Verifica.** Sul sito mobile di YouTube nel simulatore iPhone Air con iOS 27.2, XCUITest ha verificato la posizione del pulsante accanto al segnalibro, il titolo del video nella chat, la risposta e il ritorno a Cronologia. La prova ha usato una risposta di test senza chiamate a pagamento. Superati 48 test Swift, 65 test JavaScript e due prove di interfaccia; la prova con fixture sul simulatore iPhone 18 Pro ha verificato il riutilizzo della chat senza aprire il player o cambiare il salvataggio. Le prove iniziali sull’iPhone Air hanno subito interferenze da un’altra app aperta in primo piano.

**TestFlight.** Apple ha ricevuto la build alle 12:58 e TestFlight ne ha confermato la disponibilità per il tester interno alle 13:01 del 04/11/2026 (ora italiana). [App Store Connect](https://appstoreconnect.apple.com/apps/6829671295/testflight/ios) · [Sorgenti della build](https://github.com/davidecarpini/iurube/commit/ac1257a72c56b1903580015f12e32eb1b0594af0).

---

# iurub 1.10.1 · build 16

**Chat e tastiera.** Aprire il campo per una domanda non riposiziona la conversazione. Anche quando la tastiera riduce lo spazio o la bozza va a capo, il paragrafo in lettura resta fermo. Inviare una domanda continua a portare al nuovo scambio.

**Verifica del 4 novembre 2026.** Sul simulatore iPhone Air (iOS 27.2) la build precedente spostava il testo di circa 222 punti all’apertura della tastiera. Con un riassunto di 30 paragrafi la posizione relativa del testo è rimasta entro 3 punti dal riferimento prima e dopo la comparsa della tastiera, durante la digitazione e tornando a un passaggio precedente in una chat con più messaggi. Superati 48 test Swift e le due prove d’interfaccia della chat, compresa la riapertura dopo il riavvio. I dati di queste prove sono simulati e non hanno richiesto chiamate a OpenRouter. Risultati locali: `build/KeyboardRelease16.xcresult`.

**TestFlight.** Apple ha ricevuto la build alle 00:23; alle 00:25 TestFlight ne ha confermato la disponibilità per il tester interno (ora italiana del 04/11/2026). [App Store Connect](https://appstoreconnect.apple.com/apps/6829671295/testflight/ios) · [Sorgenti della build](https://github.com/davidecarpini/iurube/commit/8dc1767e0dff79e7d801f98eb5393fb4a72e987e).

---

# iurub 1.10.0 · build 15

**Riassunto dalle anteprime.** In Salvati, Esplora e Iscrizioni le scintille accanto al segnalibro aprono la chat del video senza avviarlo o cambiare la playlist. La prova ha aperto la conversazione da Salvati, fatto una domanda e ritrovato entrambe le risposte nel player dello stesso video. Un altro video ha aperto una conversazione distinta. Chiudere la chat ha lasciato selezionata la sezione di partenza.

**Freccia e spazio per i titoli.** Il simulatore ha verificato sul sito mobile di YouTube l’assenza della freccia accanto al titolo nelle pagine iniziali di Guarda più tardi e Cronologia. La ricerca, il menu del sito e la navigazione di iurub sono rimasti disponibili. In una riga compatta di prova larga 390 punti, il titolo è passato da 58 a 125 punti di larghezza, mantenendo aree distinte per menu, segnalibro e Riassunto.

**Verifica del 3 novembre 2026.** Superati 65 test JavaScript, 48 test Swift del progetto e quattro prove di interfaccia nel simulatore iPhone Air con iOS 27.2. Sul sito reale sono state verificate le tre anteprime, l’apertura della chat per il titolo selezionato e il ritorno alla lista. Le risposte per queste prove provenivano dal servizio di test, senza addebiti OpenRouter o modifiche alla playlist reale. Risultati locali: `build/PreviewFinal1100.xcresult`.

**Disponibilità della build 15.** Il 03/11/2026, Apple ha ricevuto l’archivio alle 18:35 e TestFlight ha confermato alle 18:38 (ora italiana) che il tester interno poteva installarlo. [App Store Connect](https://appstoreconnect.apple.com/apps/6829671295/testflight/ios) · [Sorgenti fc5d046](https://github.com/davidecarpini/iurube/commit/fc5d046e7fbb26506f06813123c730cdcb0ec387).

---

# iurub 1.9.0 · build 14

**In corso.** La × in alto a sinistra chiude il video. Sul simulatore iPhone Air il video non si è riaperto dopo un riavvio e, scegliendolo nuovamente da Salvati, è ripartito da 42 secondi. Il marchio animato rimane all’avvio; durante la navigazione si vede solo il caricamento del sito.

**Finestra.** La richiesta esplicita avvia il player, aspetta i primi fotogrammi e chiede il PiP di sistema. Se il sistema non lo offre, torna alla tab precedente con il video in miniatura. La prova con una clip H.264 in pausa e quella con “Big Buck Bunny” su YouTube hanno verificato che basta toccare Finestra e che la riproduzione prosegue. Il simulatore non supportava il PiP di sistema: la finestra fuori dall’app non è stata verificata su questa build.

**OpenRouter.** La chiave deve essere inserita dall’utente in Impostazioni. Il vecchio import da file è stato rimosso e le vecchie credenziali non vengono riutilizzate. La guida apre le pagine ufficiali delle chiavi e dei crediti. Una prova con una chiave fittizia, senza richieste a pagamento, ha verificato il rifiuto di un formato errato, il salvataggio, la persistenza dopo il riavvio e la rimozione.

**Verifica del 3 novembre 2026.** Superati 63 test JavaScript, 48 test Swift e 7 prove di interfaccia sul simulatore iPhone Air, iOS 27.2.

**Disponibilità della build 14.** Il 03/11/2026, Apple ha ricevuto l’archivio alle 18:12 e TestFlight ha confermato alle 18:14 (ora italiana) che il tester interno poteva installarlo. [App Store Connect](https://appstoreconnect.apple.com/apps/6829671295/testflight/ios) · [Sorgenti 7955f5d](https://github.com/davidecarpini/iurube/commit/7955f5dee782f35ff1db5f6dc650ff6f4040d61b).

---

# iurub 1.8.1 · build 13

**Accesso YouTube.** Se l’ultima pagina di Google non riesce a tornare al client, iurub controlla la sessione YouTube senza chiudere il modulo. Un account confermato apre Salvati automaticamente. Se serve riprovare, il pulsante verifica prima la sessione e riapre il modulo nell’app soltanto se necessario. L’opzione per continuare nel browser è stata rimossa.

**TestFlight.** Il 3 novembre 2026 Apple ha ricevuto la build alle 15:51 tramite Xcode Organizer. App Store Connect ha confermato la fine dell’elaborazione e TestFlight la disponibilità per il tester interno alle 15:54, ora italiana. [iurub in App Store Connect](https://appstoreconnect.apple.com/apps/6829671295/testflight/ios). Sorgenti della build: [e2034a0](https://github.com/davidecarpini/iurube/commit/e2034a0051eb132bbabbf9be09a4964de1879fff).

---

# iurub 1.8.0 · build 12

**Ingresso.** Una sessione YouTube già autenticata apre i suoi contenuti. Un ospite vede «Accedi a YouTube» e «Esplora senza accedere». La seconda scelta viene ricordata; da Salvati, Iscrizioni, Cronologia e Tu si può avviare l’accesso in seguito. La finestra di accesso mostra il dominio e si chiude quando YouTube conferma la sessione. Un eventuale accesso nel browser esterno resta separato dall’app.

La splash mostra il marchio di iurub all’avvio. Durante il caricamento l’anello resta al centro e rispetta l’impostazione Riduci movimento. Il rapporto dettagliato e le schermate per questa versione sono negli output locali, in `iurub-verifica.md`.

**TestFlight.** Il 3 novembre 2026 Apple ha ricevuto la build alle 13:24, ha confermato la fine dell’elaborazione alle 13:25 e la disponibilità per il tester interno alle 13:26, ora italiana. [iurub in App Store Connect](https://appstoreconnect.apple.com/apps/6829671295/testflight/ios). Sorgenti della build: [6ae494f](https://github.com/davidecarpini/iurube/commit/6ae494f28d03c352427ed4a148fcba959be09638).

---

# iurub 1.7.0 · build 11

**Esplora e Salvati.** Il menu originale e il segnalibro condividono la riga del titolo. Il segnalibro occupa un proprio spazio a destra dei tre puntini. In Esplora, sul sito YouTube in italiano, il simulatore ha verificato che entrambi fossero toccabili, allineati e senza sovrapposizioni. Il salvataggio e la rimozione sono stati provati con la playlist di test.

**In corso.** Il titolo resta visibile al ritorno da Salvati. La miniatura usa lo stesso player alla stessa larghezza di pagina. Nella prova con “Big Buck Bunny” la riproduzione è passata da 40,46 a 50,48 secondi durante l’uso di Esplora. Rientrando dalla miniatura, la prova ha verificato che il titolo fosse visibile sotto il video.

**Commenti.** Con “Me at the zoo”, il simulatore ha aperto automaticamente la conversazione ufficiale sotto il titolo. Il test ha rilevato almeno tre commenti caricati e verificato che uno swipe mostrasse commenti successivi. La prova copre anche il ritorno da Salvati con il video in pausa. Una prova separata controlla che, dopo la chiusura manuale, l’elenco si riapra automaticamente soltanto passando a un altro video.

**Verifica del 2 novembre 2026.** Superati 60 test JavaScript, 48 test Swift e 6 prove di interfaccia nel simulatore iPhone Air con iOS 27.2. Risultati in `build/WatchRelease-170.xcresult` e `work/watch-170/bridge-final.log`.

**TestFlight.** Apple ha ricevuto la build alle 17:43. TestFlight ha confermato la disponibilità per il tester alle 17:45 del 2 novembre 2026, ora italiana. Archivio firmato `build/Distribution/iurub-1.7.0-11.xcarchive`, sorgenti `f55370c`. [Build iOS di iurub](https://appstoreconnect.apple.com/apps/6829671295/testflight/ios).

---

# iurub 1.6.1 · build 10

Il sito presenta la propria conferma di salvataggio o rimozione e il suo comando Annulla. Il segnalibro riconosce anche il messaggio con miniatura «Salvato in Guarda più tardi» in un normale elemento della pagina, con testo suddiviso in più parti o apparso in ritardo. Un timeout dell’interfaccia avvia un controllo della playlist. Il solo invio di un comando non avvia un riassunto a pagamento.

Il player conserva la stessa webview cambiando tab. Se la finestra di sistema è disponibile, iurub richiede il PiP prima del cambio. Altrimenti continua a mostrare il video in una miniatura in alto a destra. Toccare la miniatura riapre In corso, la × ferma il video. Nel passaggio alla Home, iurub mantiene la finestra di sistema e tenta una sola ripresa se WebKit ha messo in pausa il video durante la transizione.

**Verifiche del 2 novembre 2026.** Sul simulatore iPhone Air, “Big Buck Bunny” su YouTube è rimasto visibile e in riproduzione durante l’uso di Esplora, passando da 40,47 a 50,49 secondi. Una clip locale è passata da 1 a 14 secondi tra cambio di tab e ritorno al player. I test di salvataggio utilizzano una playlist di prova. Sono stati verificati la conferma originale ritardata, l’icona piena e vuota, Annulla e la lista aggiornata. Sono passati 48 test Swift e 58 test JavaScript. Esiti in `build/FloatingPlayer-161-release.xcresult` e `work/floating-161/bridge-release.log`.

**Limite della prova Home.** Il simulatore non supporta la finestra PiP di sistema e WebKit vi ha sospeso il video pubblico quando un’altra app era in primo piano. Il test di continuità fuori dall’app è registrato come saltato. Le prove del comportamento durante l’ingresso in PiP coprono anche la sequenza pausa/finestra con eventi simulati. La continuità della nuova build sulla Home dell’iPhone resta da verificare in TestFlight.

**TestFlight.** Apple ha ricevuto iurub 1.6.1 (10) il 2 novembre 2026 alle 16:59, ora italiana. La build 10 è disponibile per il gruppo interno **Internals**, con un invito. [Dettagli della build](https://appstoreconnect.apple.com/apps/6829671295/testflight/ios/0d8897fb-68ea-4646-a9f6-5b0ed8ea1daa). Archivio firmato `build/Distribution/iurub-1.6.1-10.xcarchive`, sorgenti `88ec1fd`. Il video pubblico in miniatura e la conferma di salvataggio ritardata sono stati riverificati con gli stessi sorgenti in `build/FloatingPlayer-161-signed-source.xcresult`.

---

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

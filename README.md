# iurub

Versione **1.3.0**. Client personale per iPhone, SwiftUI + WKWebView, iOS 17+. Nessun backend da configurare. I riassunti usano Gemini tramite la tua chiave OpenRouter, custodita nel Portachiavi.

## Navigazione

La barra inferiore ha cinque tab, in questo ordine:

- **In corso**: il video aperto, con il punto di riproduzione conservato. La tab è sempre presente; senza un video mostra un invito ad aprire Salvati.
- **Salvati**: Guarda più tardi del tuo account YouTube, aperto all’avvio quando non c’è un video incompleto da riprendere.
- **Iscrizioni**: i video dei canali a cui sei iscritto.
- **Cronologia**: la cronologia YouTube dell’account.
- **Esplora**: la normale Home di YouTube, con un segnalibro compatto nella riga dei dettagli del video.

La barra inferiore del sito (Home, Iscrizioni, Tu) è nascosta. La webview si estende fino al bordo inferiore, dietro la barra dell’app. In alto trovi **Indietro e Ricarica pagina** a sinistra, **Impostazioni e Tu** a destra. Tu apre la pagina personale nella sezione corrente; Indietro torna alla pagina precedente. Ricarica aggiorna la pagina che stai guardando.

Un secondo tocco sulla tab già selezionata riporta alla pagina iniziale della sezione. Su **In corso** torna al video attivo senza azzerarne la posizione.

Aprendo un video da una delle altre sezioni, iurub passa automaticamente a **In corso**. Le pagine di provenienza restano separate dal player: tornando dal video ritrovi la pagina e lo scorrimento precedenti. Se hai salvato il video dal player, **Salvati** viene aggiornato al ritorno per mostrare la modifica alla playlist.

Salvati mostra direttamente la lista, senza la grande copertina della playlist. Ogni video ha un piccolo **cestino** nella colonna delle azioni, senza aggiungere spazio tra le righe. La rimozione viene eseguita da YouTube; il suo comando **Annulla**, quando disponibile, rimane utilizzabile. Nelle impostazioni puoi abilitare gli Shorts, nascosti inizialmente, per tutte le sezioni.

Tutte le sezioni condividono lo stesso archivio WebKit di cookie e sessione. Accedendo a YouTube nell’app, anche le altre pagine usano quell’account. Le modifiche alla playlist compaiono sugli altri dispositivi collegati allo stesso account. Se non hai effettuato l’accesso, YouTube mostra la sua schermata di login.

Le sezioni informative Account YouTube e Archivio locale sono state rimosse dalle impostazioni. I precedenti dati locali non vengono cancellati dall’aggiornamento.

## Riprendere un video

La posizione è conservata per ciascun video sul dispositivo. Puoi cambiare sezione, aprire un altro video o chiudere l’app: riaprendo lo stesso video riparti dal punto salvato, premendo Play quando richiesto dal player. Il rientro nella tab **In corso** riutilizza il player già aperto, senza ricaricarlo inutilmente. Un link con un tempo iniziale esplicito usa quel punto.

All’avvio, un video incompleto viene riaperto in **In corso**; se non ce n’è uno, l’app mostra **Salvati**. Un video terminato non viene riaperto automaticamente. Aprendolo di nuovo dalla lista, ricomincia dall’inizio. Se il video in corso è uno Short e disattivi gli Shorts, il punto salvato resta conservato: la tab indica come riabilitarli per continuare.

Il progresso viene registrato circa ogni cinque secondi durante la riproduzione, oltre che in occasione di pausa, spostamento del cursore, cambio di sezione e passaggio in background. Dopo una chiusura forzata si riparte dall’ultimo aggiornamento effettivamente salvato: gli ultimissimi secondi potrebbero non essere stati registrati. La ripresa dipende dal caricamento e dalla disponibilità del player YouTube; questi segnalibri sono locali e non sincronizzano la posizione con altri dispositivi.

## Riassunto e chat sul video

Apri un video e, in **In corso**, tocca **Riassunto**: una modale genera il riepilogo e permette domande, esempi e approfondimenti. Ogni video conserva la propria conversazione sul dispositivo; riaprirla non rigenera il riassunto. Una richiesta in corso continua mentre la modale è chiusa. Puoi interromperla o riprovare esplicitamente dopo un errore. Nessuna richiesta parte soltanto perché guardi un video.

Il modello è `google/gemini-2.5-flash`, instradato su Google AI Studio, che supporta i link YouTube come input video. Ogni domanda mantiene il video originale nel contesto, il riassunto e gli ultimi scambi. Non viene simulato il recupero di una trascrizione: Gemini analizza il contenuto audiovisivo disponibile. I video privati o con restrizioni possono non essere accessibili. Le risposte possono contenere errori; le istruzioni distinguono il contenuto del video dagli esempi aggiuntivi.

La chiave si imposta in **Impostazioni → Riassunti con Gemini → Chiave OpenRouter**. È salvata nel Portachiavi, separata dai sorgenti, dall’app e dalle conversazioni. Le richieste inviano URL del video e conversazione a OpenRouter/Google e usano il credito dell’account. Il codice gestisce chiave non valida, credito esaurito, limiti di richieste, problemi di rete e risposte incomplete senza registrare credenziali.

Documentazione di riferimento: [OpenRouter video inputs](https://openrouter.ai/docs/guides/overview/multimodal/videos), [Gemini video understanding](https://ai.google.dev/gemini-api/docs/video-understanding).

## Avvio

Apri `iurub.xcodeproj` in Xcode, scegli lo schema **iurub** e un simulatore iPhone, poi Run. Il progetto è già generato e non occorrono dipendenze esterne per compilare l’app.

```sh
cd /Users/davidecarpini/apps/iurub
./scripts/simulator.sh run
```

Lo script usa `DEVELOPER_DIR`, oppure `/Applications/Xcode.app`, e installa il runtime iOS se manca. Non cambia `xcode-select` globalmente. Su questo Mac è configurato il Personal Team di Davide Carpini e l’app è installata su iPhone di Davide. Per installarla da Xcode scegli il dispositivo collegato e Run. Su un altro account imposta il tuo team in Signing & Capabilities.

## Test

```sh
./scripts/test-core.sh
npm ci --ignore-scripts
npm test
./scripts/simulator.sh test
./scripts/simulator.sh live
TEST_RUNNER_IURUB_PLAYBACK_LIVE=1 ./scripts/simulator.sh live
TEST_RUNNER_IURUB_SUMMARY_LIVE=1 ./scripts/simulator.sh live
```

La suite ripetibile usa fixture, una lista locale di prova e un archivio WebKit non persistente: non legge né modifica l’account Google reale. Simula una playlist già popolata, salvataggio nel conto di prova, riavvio, rimozione, annullamento, toggle Shorts e le cinque tab. Verifica anche ordine e posizione dei controlli, refresh, ritorno alla radice al secondo tocco, dimensioni della webview e chat con risposte simulate (persistenza, domanda, errore e retry). La fixture del player copre ripresa tra tab e riavvii, posizioni distinte per video e comportamento dopo il completamento.

Il comando `live` richiede una sessione YouTube già autenticata. È una verifica in sola lettura della playlist, della presenza dei controlli, delle sezioni YouTube e del percorso Tu → Indietro; non cancella o aggiunge video reali. I risultati e le immagini sono allegati ai file `build/*.xcresult`. Il rapporto riporta separatamente gli esiti delle fixture, del sito reale e delle richieste Gemini.

`IURUB_PLAYBACK_LIVE` aggiunge una prova di ripresa del video pubblico “Me at the zoo”, con archivio dei progressi separato da quello normale. Il test verifica posizione e durata riportate dal media reale dopo un riavvio, poi Tu → Indietro. `IURUB_SUMMARY_LIVE` abilita le richieste reali a Gemini con la chiave configurata e consuma credito OpenRouter. Le variabili sono passate a XCTest con il prefisso `TEST_RUNNER_`, come negli esempi.

Le fixture sono disponibili solo nelle build Debug con argomenti espliciti. L’avvio normale mostra il sito reale. `scripts/test-webkit.sh` conserva i controlli precedenti del bridge locale su macOS.

## Comportamento del sito

L’app usa i controlli visibili di YouTube, senza leggere password o token e senza chiamare API private. Se il sito cambia un menu o richiede il login, iurub lascia disponibile il menu originale e indica come completare l’azione; non dichiara un salvataggio locale come salvataggio nell’account.

Connessione, consenso, pubblicità, disponibilità dei video e login sono gestiti da YouTube. I filtri e i pulsanti dipendono dal DOM e possono richiedere manutenzione se Google lo cambia. I video non vengono scaricati. Nessun servizio di analytics è incluso.

Sorgenti in `iurub/`, test in `iurubTests/`, `iurubUITests/` e `scripts/tests/`. Piano e risultati effettivi in `docs/PLAN.md` e `docs/TEST-REPORT.md`.

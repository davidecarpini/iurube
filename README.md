# iurub

Versione **1.11.0**. Client personale per iPhone, SwiftUI + WKWebView, iOS 17+. Nessun backend da configurare. I riassunti usano Gemini tramite la tua chiave OpenRouter, custodita nel Portachiavi.

## Primo accesso

Se YouTube ti riconosce, iurub apre la tua lista o il video da riprendere. Se sei ospite, tocca **Accedi a YouTube**. L’accesso avviene sulla pagina di Google e iurub apre **Salvati** quando YouTube conferma la sessione.

Puoi anche scegliere **Esplora senza accedere**. Iurub ricorda la scelta e puoi collegare l’account in seguito da **Tu** o da una delle sezioni personali. Se il ritorno da Google si interrompe, iurub verifica prima se la sessione YouTube è già attiva. Anche **Riprova** controlla la sessione prima di riaprire il modulo. L’intero percorso resta nell’app.

## Navigazione

La barra inferiore ha cinque tab, in questo ordine:

- **In corso**: il video aperto, con il punto di riproduzione conservato. La × in alto a sinistra chiude il video e conserva il punto di riproduzione. La tab è sempre presente; senza un video mostra un invito ad aprire Salvati.
- **Salvati**: Guarda più tardi del tuo account YouTube, aperto all’avvio quando non c’è un video incompleto da riprendere.
- **Iscrizioni**: i video dei canali a cui sei iscritto.
- **Cronologia**: la cronologia YouTube dell’account.
- **Esplora**: la normale Home di YouTube, con il segnalibro a destra dei tre puntini nella riga del titolo.

Quando apri un video, iurub mostra i commenti disponibili sotto il titolo. Scorri la conversazione per leggere altri commenti e aprire le risposte. Puoi chiuderla con la × e riaprirla dall’anteprima di YouTube. Tornando da Salvati a In corso ritrovi il titolo e la posizione di riproduzione. Tocca il titolo o **altro** per aprire la descrizione originale di YouTube e leggere il titolo completo, anche mentre i commenti sono aperti.

La barra inferiore del sito (Home, Iscrizioni, Tu) è nascosta. La webview si estende fino al bordo inferiore, dietro la barra dell’app. In alto trovi **Indietro e Ricarica pagina** a sinistra, **Impostazioni e Tu** a destra. Tu apre la pagina personale nella sezione corrente; Indietro torna alla pagina precedente. Ricarica aggiorna la pagina che stai guardando.

Un secondo tocco sulla tab già selezionata riporta alla pagina iniziale della sezione. Su **In corso** torna al video attivo senza azzerarne la posizione.

Aprendo un video da una delle altre sezioni, iurub passa automaticamente a **In corso**. Le pagine di provenienza restano separate dal player: tornando dal video ritrovi la pagina e lo scorrimento precedenti. Aprendo **Salvati**, iurub rilegge la playlist di YouTube e mostra le aggiunte e le rimozioni.

Il segnalibro diventa pieno quando iurub verifica che il video è in Guarda più tardi. Toccandolo di nuovo rimuovi il video dalla playlist; lo stato viene condiviso tra le tab e con il player. Iurub usa i controlli e le conferme di YouTube: un comando non confermato non viene mostrato come riuscito. La lista Salvati viene letta anche quando all’avvio si riprende un video.

In **Salvati** ogni riga ha un segnalibro pieno che puoi toccare per rimuovere il video. YouTube mostra la propria conferma, anche con miniatura e pulsante **Annulla**. Il segnalibro segue la conferma del sito anche se arriva in ritardo. Nelle impostazioni puoi abilitare gli Shorts, nascosti inizialmente, per tutte le sezioni.

Tutte le sezioni condividono lo stesso archivio WebKit di cookie e sessione. Accedendo a YouTube nell’app, anche le altre pagine usano quell’account. Le modifiche alla playlist compaiono sugli altri dispositivi collegati allo stesso account. Se non hai effettuato l’accesso, iurub presenta il benvenuto.

Le sezioni informative Account YouTube e Archivio locale sono state rimosse dalle impostazioni. I precedenti dati locali non vengono cancellati dall’aggiornamento.

## Riprendere un video

La posizione è conservata per ciascun video sul dispositivo. Puoi cambiare sezione, aprire un altro video o chiudere l’app: riaprendo lo stesso video riparti dal punto salvato, premendo Play quando richiesto dal player. Il rientro nella tab **In corso** riutilizza il player già aperto, senza ricaricarlo inutilmente. Un link con un tempo iniziale esplicito usa quel punto.

All’avvio, un video incompleto viene riaperto in **In corso**; se non ce n’è uno, l’app mostra **Salvati**. Un video terminato non viene riaperto automaticamente. Aprendolo di nuovo dalla lista, ricomincia dall’inizio. Se il video in corso è uno Short e disattivi gli Shorts, il punto salvato resta conservato: la tab indica come riabilitarli per continuare.

Il progresso viene registrato circa ogni cinque secondi durante la riproduzione, oltre che in occasione di pausa, spostamento del cursore, cambio di sezione e passaggio in background. Dopo una chiusura forzata si riparte dall’ultimo aggiornamento effettivamente salvato: gli ultimissimi secondi potrebbero non essere stati registrati. La ripresa dipende dal caricamento e dalla disponibilità del player YouTube; questi segnalibri sono locali e non sincronizzano la posizione con altri dispositivi.

## Finestra video e velocità

La barra **In linea** tiene a portata di mano **Salva**, **Finestra**, i controlli di velocità e **Riassunto**. Tocca **Finestra** anche a video fermo: iurub avvia il player e chiede la finestra di sistema; se il sistema non la offre, apre una miniatura nella tab precedente. Cambiando tab durante la riproduzione, il video resta in finestra. Se il PiP di sistema non è disponibile, iurub mostra lo stesso player in miniatura sopra la tab aperta. Tocca la miniatura per espanderla o la × per fermarla.

Quando lasci iurub per la Home, l’app chiede la finestra di sistema per il video già avviato. Se WebKit sospende il video mentre entra in PiP, iurub chiede una sola ripresa collegata a quel passaggio. La finestra di sistema dipende dal dispositivo e dal sito. Puoi rientrare nel player da **In corso**. Una chiusura forzata termina la riproduzione.

Usa **−** e **+** accanto alla velocità per passare da **0,5× a 2×** a passi di 0,25×. Il numero al centro mostra la velocità effettiva, anche se la cambi dal menu YouTube.

## Riassunto e chat sul video

Tocca le scintille **Riassunto** accanto al segnalibro nelle anteprime di **Salvati**, **Iscrizioni**, **Cronologia** o **Esplora** per aprire la chat senza avviare il video. Se lo stai guardando, in **In corso** tocca **Riassunto**: una modale genera il riepilogo e permette domande, esempi e approfondimenti. Ogni video conserva la propria conversazione sul dispositivo; riaprirla non rigenera il riassunto. Una richiesta in corso continua mentre la modale è chiusa. Puoi interromperla o riprovare esplicitamente dopo un errore. Di default un nuovo video viene riassunto solo quando tocchi **Riassunto**. Se attivi **Impostazioni → Riassunto automatico nei Salvati**, ogni nuovo salvataggio confermato da YouTube avvia la preparazione. Disattivando il toggle si svuota la coda automatica. Le richieste già avviate possono terminare. Più salvataggi vengono accodati, con una sola richiesta automatica alla volta. Aprire la chat riusa la risposta pronta o la richiesta già in corso; se il video è ancora in coda, gli dà priorità. Un indicatore sul pulsante Riassunto segnala la preparazione. Leggere la playlist o aprire un video non genera automaticamente riassunti per tutti i video esistenti. Errori e interruzioni richiedono un nuovo tentativo esplicito; non scattano retry automatici. La coda non è conservata dopo la chiusura dell’app e iOS può sospendere le richieste quando l’app passa in background.

In **Impostazioni → Modello e costi** puoi scegliere Gemini 2.5 Flash-Lite, 3.1 Flash-Lite, 2.5 Flash o 3.8 Flash. La scelta iniziale è 2.5 Flash. Ogni nuova richiesta usa il modello selezionato al momento della partenza e passa il link YouTube a Google AI Studio tramite OpenRouter. Le risposte già salvate conservano il modello originale. La schermata confronta i costi stimati in USD per durata e numero di domande, con tariffe lette dal catalogo pubblico di OpenRouter o il listino datato disponibile offline. Sotto le nuove risposte appare il costo restituito da OpenRouter quando disponibile. Ogni domanda mantiene il video originale nel contesto, il riassunto e gli ultimi scambi. Non viene simulato il recupero di una trascrizione: Gemini analizza il contenuto audiovisivo disponibile. I video privati o con restrizioni possono non essere accessibili. Le risposte possono contenere errori; le istruzioni distinguono il contenuto del video dagli esempi aggiuntivi.

La chiave si imposta in **Impostazioni → Riassunti con Gemini → OpenRouter**. La guida nella stessa schermata apre la [pagina ufficiale delle chiavi](https://openrouter.ai/settings/keys), spiega come impostare un limite di spesa e dove incollare il valore. Dalla versione 1.9.0 serve inserirla personalmente, anche dopo un aggiornamento: iurub non importa chiavi preconfigurate. È possibile sostituirla o rimuoverla dal dispositivo in qualsiasi momento. È salvata nel Portachiavi, separata dai sorgenti, dall’app e dalle conversazioni. Le richieste, comprese quelle avviate automaticamente dopo un salvataggio confermato, inviano URL del video e conversazione a OpenRouter/Google e usano il credito dell’account. Il codice gestisce chiave non valida, credito esaurito, limiti di richieste, problemi di rete e risposte incomplete senza registrare credenziali.

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
TEST_RUNNER_IURUB_LAYOUT_LIVE=1 ./scripts/simulator.sh live
```

La suite ripetibile usa fixture, una lista locale di prova e un archivio WebKit non persistente: non legge né modifica l’account Google reale. Simula una playlist già popolata, salvataggio nel conto di prova, riavvio, rimozione, aggiornamento al rientro in Salvati, toggle Shorts e le cinque tab. Verifica anche ordine e posizione dei controlli, refresh, ritorno alla radice al secondo tocco, dimensioni della webview e chat con risposte simulate (persistenza, domanda, errore e retry). La fixture del player copre ripresa tra tab e riavvii, posizioni distinte per video e comportamento dopo il completamento.

Il comando `live` richiede una sessione YouTube già autenticata. È una verifica in sola lettura della playlist, della presenza dei controlli, delle sezioni YouTube e del percorso Tu → Indietro; non cancella o aggiunge video reali. I risultati e le immagini sono allegati ai file `build/*.xcresult`. Il rapporto riporta separatamente gli esiti delle fixture, del sito reale e delle richieste Gemini.

`IURUB_PLAYBACK_LIVE` aggiunge una prova di ripresa del video pubblico “Me at the zoo”, con archivio dei progressi separato da quello normale. Il test verifica posizione e durata riportate dal media reale dopo un riavvio, poi Tu → Indietro. `IURUB_SUMMARY_LIVE` abilita le richieste reali a Gemini con la chiave configurata e consuma credito OpenRouter. Le variabili sono passate a XCTest con il prefisso `TEST_RUNNER_`, come negli esempi.

`IURUB_LAYOUT_LIVE` verifica sul sito reale lo scorrimento dei commenti, il titolo al ritorno tra tab e l’apertura della descrizione toccando sia **altro** sia un titolo lungo. Controlla anche che il titolo completo sia visibile su più righe e che la pagina torni interattiva alla chiusura della descrizione. Non modifica la playlist né pubblica commenti.

Le fixture sono disponibili solo nelle build Debug con argomenti espliciti. L’avvio normale mostra il sito reale. `scripts/test-webkit.sh` conserva i controlli precedenti del bridge locale su macOS.

## Comportamento del sito

L’app usa i controlli visibili di YouTube, senza leggere password o token e senza chiamare API private. Se il sito cambia un menu o richiede il login, iurub lascia disponibile il menu originale e indica come completare l’azione; non dichiara un salvataggio locale come salvataggio nell’account.

Connessione, consenso, pubblicità, disponibilità dei video e login sono gestiti da YouTube. I filtri e i pulsanti dipendono dal DOM e possono richiedere manutenzione se Google lo cambia. I video non vengono scaricati. Nessun servizio di analytics è incluso.

Sorgenti in `iurub/`, test in `iurubTests/`, `iurubUITests/` e `scripts/tests/`. Piano e risultati effettivi in `docs/PLAN.md` e `docs/TEST-REPORT.md`.

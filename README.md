# iurub

Client personale per iPhone, SwiftUI + WKWebView, iOS 17+. Nessun backend e nessuna chiave API.

## Navigazione

La barra inferiore ha quattro tab, in questo ordine:

- **Salvati**: Guarda più tardi del tuo account YouTube, aperto all’avvio e aggiornato quando torni alla tab.
- **Iscrizioni**: i video dei canali a cui sei iscritto.
- **Cronologia**: la cronologia YouTube dell’account, aggiornata quando riapri la tab.
- **Esplora**: la normale Home di YouTube, con **+ Guarda più tardi** sulle schede.

La barra inferiore del sito (Home, Iscrizioni, Tu) è nascosta. La webview si estende fino al bordo inferiore, dietro la barra dell’app. In alto trovi **Indietro e Ricarica pagina** a sinistra, **Impostazioni e Tu** a destra. Tu apre la pagina personale nella sezione corrente; Indietro torna alla pagina precedente. Ricarica aggiorna la pagina che stai guardando.

Ogni video nella playlist ha **Rimuovi**. La rimozione viene eseguita da YouTube; il suo comando **Annulla**, quando disponibile, rimane utilizzabile. Nelle impostazioni puoi abilitare gli Shorts, nascosti inizialmente, per tutte le sezioni.

Tutte le sezioni condividono lo stesso archivio WebKit di cookie e sessione. Accedendo a YouTube nell’app, anche le altre pagine usano quell’account. Le modifiche alla playlist compaiono sugli altri dispositivi collegati allo stesso account. Se non hai effettuato l’accesso, YouTube mostra la sua schermata di login.

L’**archivio locale della versione precedente** è conservato in Impostazioni → Salvati sul dispositivo. Puoi ancora aggiungere link, cercare, riprodurre e rimuovere con annullamento. Questi link restano separati dalla playlist YouTube e non vengono trasferiti automaticamente.

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
```

La suite ripetibile usa fixture, una lista locale di prova e un archivio WebKit non persistente: non legge né modifica l’account Google reale. Simula una playlist già popolata, salvataggio nel conto di prova, riavvio, rimozione, annullamento, toggle Shorts e le quattro sezioni. Verifica anche ordine e posizione dei controlli, refresh e dimensioni della webview.

Il comando `live` richiede una sessione YouTube già autenticata. È una verifica in sola lettura della playlist, della presenza dei controlli, delle quattro sezioni e del percorso Tu → Indietro; non cancella o aggiunge video reali. I risultati e le immagini sono allegati ai file `build/*.xcresult`.

Le fixture sono disponibili solo nelle build Debug con argomenti espliciti. L’avvio normale mostra il sito reale. `scripts/test-webkit.sh` conserva i controlli precedenti del bridge locale su macOS.

## Comportamento del sito

L’app usa i controlli visibili di YouTube, senza leggere password o token e senza chiamare API private. Se il sito cambia un menu o richiede il login, iurub lascia disponibile il menu originale e indica come completare l’azione; non dichiara un salvataggio locale come salvataggio nell’account.

Connessione, consenso, pubblicità, disponibilità dei video e login sono gestiti da YouTube. I filtri e i pulsanti dipendono dal DOM e possono richiedere manutenzione se Google lo cambia. I video non vengono scaricati. Nessun servizio di analytics è incluso.

Sorgenti in `iurub/`, test in `iurubTests/`, `iurubUITests/` e `scripts/tests/`. Piano e risultati effettivi in `docs/PLAN.md` e `docs/TEST-REPORT.md`.

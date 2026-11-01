# iurub

Client personale per iPhone, SwiftUI + WKWebView, iOS 17+. Nessun backend e nessuna chiave API.

## Le due tab

- **Guarda più tardi**, a sinistra e all’avvio: la vera playlist privata dell’account YouTube con cui hai effettuato l’accesso. Si aggiorna quando torni dalla Home; il pulsante segnalibro in alto permette di ricaricarla.
- **Home**, a destra: sito mobile YouTube, con pulsante **+ Guarda più tardi** sulle schede. Il pulsante richiama il menu di YouTube e la playlist dell’account.
- Ogni video nella playlist ha un pulsante **Rimuovi**. La rimozione viene eseguita da YouTube; il suo comando **Annulla**, quando disponibile, rimane utilizzabile.
- Nelle **Impostazioni** puoi abilitare gli Shorts, nascosti inizialmente. La preferenza è persistente e si applica a entrambe le tab.

Home e playlist condividono lo stesso archivio WebKit di cookie e sessione. Accedendo a YouTube nell’app, anche la prima tab usa quell’account. Le modifiche riguardano la playlist YouTube, visibile anche sugli altri dispositivi dello stesso account. Se non hai effettuato l’accesso, YouTube mostra la sua schermata di login.

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

La suite ripetibile usa fixture, una lista locale di prova e un archivio WebKit non persistente: non legge né modifica l’account Google reale. Simula una playlist già popolata, salvataggio nel conto di prova, riavvio, rimozione, annullamento e toggle Shorts.

Il comando `live` richiede una sessione YouTube già autenticata. È una verifica in sola lettura della playlist, della presenza dei controlli e della navigazione fra le tab; non cancella o aggiunge video reali. I risultati e le immagini sono allegati ai file `build/*.xcresult`.

Le fixture sono disponibili solo nelle build Debug con argomenti espliciti. L’avvio normale mostra il sito reale. `scripts/test-webkit.sh` conserva i controlli precedenti del bridge locale su macOS.

## Comportamento del sito

L’app usa i controlli visibili di YouTube, senza leggere password o token e senza chiamare API private. Se il sito cambia un menu o richiede il login, iurub lascia disponibile il menu originale e indica come completare l’azione; non dichiara un salvataggio locale come salvataggio nell’account.

Connessione, consenso, pubblicità, disponibilità dei video e login sono gestiti da YouTube. I filtri e i pulsanti dipendono dal DOM e possono richiedere manutenzione se Google lo cambia. I video non vengono scaricati. Nessun servizio di analytics è incluso.

Sorgenti in `iurub/`, test in `iurubTests/`, `iurubUITests/` e `scripts/tests/`. Piano e risultati effettivi in `docs/PLAN.md` e `docs/TEST-REPORT.md`.

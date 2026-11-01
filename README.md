# iurub

Un’app personale per iPhone: scegli i video su YouTube, salvali e guardali quando vuoi. SwiftUI + WKWebView, iOS 17+, nessun backend e nessuna chiave API.

## Cosa fa

- **Guarda più tardi**, prima tab a sinistra: lista locale persistente, ricerca per titolo/canale, ordinamento, riproduzione, condivisione link, rimozione e annullamento.
- **Home**, seconda tab a destra: sito mobile originale di YouTube, con pulsante **+ Guarda più tardi** sulle schede video. Un pulsante nativo salva anche il video attualmente aperto.
- **Impostazioni**, pulsante in alto: toggle **Abilita Shorts**, spento inizialmente. La scelta resta salvata dopo il riavvio.
- Aggiunta tramite link con il pulsante **+**, anche senza visitare la Home.
- Shorts nascosti da home, ricerche, canali e navigazione. Il toggle ripristina gli elementi; il filtro usa il DOM di YouTube e potrebbe richiedere manutenzione quando Google lo cambia.
- La riproduzione viene messa in pausa passando alla lista, chiudendo il player o mandando l’app in background.

**La lista di iurub è locale e non sincronizza la playlist “Guarda più tardi” del tuo account YouTube.** Non occorre il login Google per salvare video. Il login nel sito incorporato può essere rifiutato da Google. Pubblicità, consenso, eventuali restrizioni di riproduzione e disponibilità dei contenuti restano quelli di YouTube. I video non vengono scaricati.

## Aprire e provare

1. Installa **Xcode completo** dall’App Store; aprilo una volta e completa la configurazione iniziale. Installa il runtime iOS quando richiesto.
2. Apri `iurub.xcodeproj`.
3. Seleziona lo schema **iurub**, un simulatore iPhone e premi **Run**.
4. Per installare sul tuo iPhone, scegli il tuo team in **Signing & Capabilities**, collega il dispositivo e selezionalo come destinazione.

Il progetto Xcode è già generato. Non è necessario installare XcodeGen, Node o altre dipendenze per compilare l’app. `project.yml` permette di rigenerarlo con XcodeGen se si cambia la struttura.

Per eseguire test e avviare l’app nel simulatore:

```sh
cd /Users/davidecarpini/apps/iurub
./scripts/simulator.sh test
```

Solo compilazione e avvio:

```sh
./scripts/simulator.sh run
```

Lo script usa `DEVELOPER_DIR` se impostato, altrimenti `/Applications/Xcode.app`. Se manca un runtime iOS ne avvia il download tramite Xcode. Non inserisce credenziali e non modifica la configurazione globale di `xcode-select`.

## Test

```sh
./scripts/test-core.sh       # Modelli Swift: URL, persistenza, duplicati, errori, impostazioni
npm ci --ignore-scripts
npm test                     # Bridge JS, Shorts, schede dinamiche, metadati e sicurezza URL
./scripts/test-webkit.sh     # Integrazione reale Swift ↔ WebKit su macOS
./scripts/simulator.sh test  # Swift Testing + XCUITest nel simulatore iOS
./scripts/simulator.sh live  # Test opzionale sul sito YouTube reale (richiede rete)
```

I test UI usano `--ui-testing --reset-state --fixture` e una lista separata. Le fixture sono attivate soltanto in build Debug con questi argomenti; l’avvio normale mostra YouTube reale e una lista vuota. Nessuna fixture o credenziale viene inserita nella lista personale.

Il test `live` usa una lista di prova separata ma il sito YouTube reale: cerca un video, lo salva, verifica la persistenza dopo il riavvio e controlla l’avanzamento del player. Può cambiare esito se YouTube modifica l’interfaccia o limita l’accesso; non effettua il login. Gli screenshot sono allegati ai risultati `.xcresult` in `build/`.

Per testare un link in simulatore:

```sh
xcrun simctl openurl booted 'iurub://open?url=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3DM7lc1UVf-VE'
```

## Struttura

- `iurub/Models`: validazione URL, metadati, storage atomico, preferenze.
- `iurub/Web`: sessione WebKit, policy di navigazione, bridge con verifica dell’origine.
- `iurub/Resources/YouTubeBridge.js`: filtri, pulsanti sulle schede, osservazione delle modifiche DOM.
- `iurub/Views`: lista, Home, player e impostazioni SwiftUI.
- `iurubTests` / `iurubUITests`: test dei modelli e flussi di interfaccia.
- `docs/PLAN.md`, `docs/TEST-REPORT.md`: piano e verifiche effettivamente eseguite.

I dati vengono scritti nella cartella Application Support del contenitore dell’app, in `iurub/saved-videos.json`. Una scrittura fallita non mostra il video come salvato. Un file corrotto viene conservato e segnalato, invece di essere sovrascritto. Nessun servizio di analytics è incluso.

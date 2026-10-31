# iurub — rapporto di verifica

31 ottobre 2026 · progetto: `/Users/davidecarpini/apps/iurub`

## Stato

Implementazione completata nel progetto Xcode. Xcode 27.2 (27B52) è ora installato. **Compilazione iOS e test nel simulatore non eseguiti**: il primo avvio è bloccato dalla licenza Xcode/Apple SDK non ancora accettata. Il progetto non va descritto come già collaudato su iPhone.

## Implementato

- Tab sinistra **Guarda più tardi**, prima schermata all’avvio: lista locale persistente, ricerca, ordinamento, apertura player, rimozione e annullamento.
- Tab destra **Home**: sito YouTube mobile originale. Pulsante aggiunto alle schede video e pulsante nativo sul video aperto.
- Impostazioni con toggle **Abilita Shorts**, spento inizialmente e persistente.
- Filtri per scaffali, schede e tab Shorts; blocco URL e navigazioni SPA. Riabilitazione senza cancellare la lista.
- Aggiunta di link, condivisione, gestione errori, pausa della riproduzione quando si lascia il contenuto.
- Icona originale, progetto generato, test e script di avvio.

La lista è **locale a iurub** e non sincronizza la playlist del proprio account Google. Il login non è necessario per salvare. L’accesso Google e la riproduzione sono soggetti al comportamento del sito nella WKWebView.

## Verifiche eseguite

| Verifica | Risultato | Ambito reale |
|---|---|---|
| Modelli Swift | **10 test passati** | Codice di produzione, eseguito su macOS con Swift Testing |
| Bridge JavaScript | **9 test passati** | DOM controllato con jsdom, incluse schede riciclate e navigazione dinamica |
| Swift ↔ WebKit | **17 verifiche passate** | WKWebView reale su macOS; fixture e sito YouTube live |
| Interfaccia condivisa | **Compilata** | Sorgenti SwiftUI compilati con SDK macOS 26.5 |
| Rami UIKit/iOS | **Typecheck passato** | Target Mac Catalyst iOS 17, usando il supporto UIKit del SDK macOS; non build iPhone |
| Rendering SwiftUI | **Eseguito** | Schermata vuota nativa macOS; non screenshot iPhone |
| Progetto e plist | **Validi** | XcodeGen 2.46.0, `plutil`, controllo sintassi degli script |
| Test UI iPhone | **Non eseguiti** | Suite XCUITest pronta nel progetto |
| Riproduzione video completa, fullscreen, rotazione | **Da verificare su iOS** | Non dichiarati come test superati |
| Login Google | **Non verificato** | Nessuna credenziale utilizzata |

### Dettagli dei test

I test Swift coprono URL validi e ostili, canonicalizzazione, duplicati, persistenza fra istanze, rimozione/annullamento, ordinamento, file corrotti, scritture fallite e impostazioni.

I test JavaScript verificano un solo pulsante per scheda, metadati corretti, conferma del salvataggio ricevuta da Swift, filtri ripristinabili, contenuti aggiunti o riciclati, assenza di loop del MutationObserver, blocco dei link Shorts e mancata iniezione nelle pagine di login.

Nel test WebKit live:

- Il sito YouTube è stato caricato e il bridge inizializzato.
- La voce Shorts della barra inferiore, che non usa un link, è stata individuata e correttamente nascosta.
- I pulsanti sono comparsi nei risultati reali di una ricerca.
- Un video reale è stato passato al codice Swift, salvato in una lista temporanea e riletto da disco.
- Il dialogo di consenso di YouTube è rimasto visibile: il test ha verificato programmaticamente i pulsanti aggiunti e il bridge, **non l’interazione manuale completa né la riproduzione**.
- I messaggi di salvataggio provenienti da un’origine diversa da YouTube sono stati rifiutati.

Le fixture non inseriscono dati nella lista personale. Screenshot e log di sviluppo sono sotto `work/`, esclusi da Git.

## Blocco attuale del simulatore

Controllo automatico del 31 ottobre 2026, ore 15:16 (Europe/Rome):

- Xcode 27.2, build 27B52, è installato in /Applications/Xcode.app.
- xcodebuild -checkFirstLaunchStatus termina con codice 69.
- xcodebuild -runFirstLaunch termina con codice 77: «You have not agreed to the Xcode license agreements».
- Occorre aprire Xcode, esaminare e accettare la licenza e completare l’installazione iniziale dei componenti. Questo passaggio richiede l’intervento dell’utente.
- Nessuna licenza è stata accettata automaticamente. Nessun test nel simulatore è stato avviato in questo controllo.
- Il monitor del download è stato rimosso dopo questa notifica, perché il download è terminato e ora serve un’azione dell’utente.

Il precedente impedimento al download è superato: l’utente ha installato Xcode tramite App Store.

## Completare la verifica iPhone

Aprire Xcode già installato e completare il primo avvio (licenza e componenti). Poi:

```sh
cd /Users/davidecarpini/apps/iurub
./scripts/simulator.sh test
```

Lo script installa il runtime iOS se necessario, seleziona o crea un simulatore iPhone, esegue i test, compila, installa e avvia l’app reale. I risultati XCUITest sono salvati in `build/*.xcresult`.

Per il collaudo manuale finale: completare il consenso YouTube, cercare un video, salvarlo, ritrovarlo dopo il riavvio, riprodurlo, verificare fullscreen/rotazione e provare il toggle Shorts. Il login Google va valutato separatamente, senza darlo per funzionante.

## Riferimenti

- [Download e risorse Xcode, Apple](https://developer.apple.com/xcode/resources/)
- [Componenti e runtime aggiuntivi, Apple](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components)
- [Google: OAuth nei browser incorporati](https://developers.googleblog.com/en/upcoming-security-changes-to-googles-oauth-20-authorization-endpoint-in-embedded-webviews/)

# iurub — rapporto di verifica

31 ottobre 2026 · progetto: `/Users/davidecarpini/apps/iurub`

## Stato

Implementazione completata nel progetto Xcode. **Compilazione iOS e test nel simulatore non eseguiti**, perché manca Xcode completo e non è stato possibile installarlo con le autorizzazioni disponibili. Il progetto non va descritto come già collaudato su iPhone.

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

## Blocco del simulatore

- `xcode-select -p` restituisce `/Library/Developer/CommandLineTools`.
- `xcodebuild` richiede Xcode completo; `simctl` non è disponibile.
- Il download diretto ufficiale di Xcode reindirizza alla pagina Apple di accesso non autorizzato.
- L’installazione tramite il client App Store richiede privilegi amministratore; `sudo -n` segnala che serve la password.
- Computer Use non è stato autorizzato a usare App Store. L’apertura del sito Apple nel browser è stata negata dal controllo di autorizzazione. Non sono stati aggirati questi blocchi e non sono state cercate o usate credenziali.

## Completare la verifica iPhone

Installare Xcode dall’App Store e completare il primo avvio. Poi:

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

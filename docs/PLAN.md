# Piano di sviluppo di iurub

1. Preparare progetto SwiftUI iOS 17+, senza dipendenze runtime o chiavi API.
2. Modellare una lista locale «Guarda più tardi», persistita atomicamente, senza duplicati. Chiarire che non sincronizza la playlist Google.
3. Prima tab: lista salvata, ricerca, apertura player, rimozione con annullamento e aggiunta tramite URL.
4. Seconda tab: YouTube mobile reale in WKWebView, ricerca originale e pulsanti aggiunti alle schede per salvare in un tocco. Pulsante nativo sul video aperto come alternativa.
5. Impostazioni: toggle Shorts, disattivato per default e persistente. Nascondere scaffali/link, bloccare le navigazioni native e SPA; ripristinare senza ricaricare quando abilitato.
6. Proteggere il bridge WebKit con verifica di origine e validazione dei video. Gestire errori/retry, consenso YouTube, navigazione esterna e cambi di tab senza audio nascosto.
7. Testare modello e bridge su contenuti dinamici, salvare/rimuovere/riaprire, toggle e navigazione. Fornire test XCTest/XCUITest e comando riproducibile per simulatore.
8. Compilare e avviare nel simulatore se Xcode e runtime sono disponibili. Non rappresentare test macOS, fixture o parser come esecuzioni iOS.

## Decisioni

- La lista è locale: nessun requisito di login e nessuna finta sincronizzazione con YouTube.
- Non si eludono i blocchi Google della WKWebView. Il sito resta quello originale, inclusi pubblicità e consenso.
- L'app funziona senza backend; connessione richiesta per vedere YouTube e caricare miniature.
- Gli Shorts salvati quando abilitati restano nella lista, ma non si aprono finché il toggle non viene riattivato.
- Nessun dato dimostrativo nella modalità normale. Fixture disponibili solo nelle build Debug con argomenti espliciti di test.

## Esito

- [x] Progetto e interfaccia implementati.
- [x] Persistenza, validazione URL, bridge e filtri implementati.
- [x] Test Swift e JavaScript eseguiti con esito positivo.
- [x] Integrazione WKWebView su macOS e salvataggio da YouTube reale verificati.
- [x] Typecheck dei rami UIKit tramite Mac Catalyst e compilazione dei rami macOS.
- [x] Progetto Xcode, test UI e script per il simulatore preparati.
- [x] Xcode 27.2 e runtime iOS 27.2 configurati; build Debug simulatore e Release iPhone riuscite.
- [x] XCUITest su iPhone Air: tab, salvataggio da Home e URL, persistenza, rimozione/annullamento e toggle Shorts.
- [x] YouTube reale: ricerca, salvataggio, riavvio, apertura e avanzamento del video nel simulatore.
- [ ] Login Google, dispositivo fisico, PiP/AirPlay: richiedono verifiche separate; nessuna credenziale o firma personale utilizzata.

Il blocco iniziale di Xcode è superato. Esiti, screenshot e limiti del collaudo sono in `TEST-REPORT.md`.

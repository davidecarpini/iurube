# iurub — rapporto di verifica

1 novembre 2026 · progetto: `/Users/davidecarpini/apps/iurub`

## Stato

App implementata, compilata e avviata nel simulatore **iPhone Air con iOS 27.2 (24B8117)**, usando **Xcode 27.2 (27B52)**. Il precedente blocco del primo avvio di Xcode è superato. Il monitor automatico è stato rimosso.

La suite iOS finale ha concluso con **13 test superati, 0 fallimenti, 0 test saltati**: 10 test Swift e 3 test XCUITest. Risultati in `build/Tests-20261101-153540.xcresult`.

Anche il test live finale è **superato**: 1 scenario end-to-end, 0 fallimenti, con avanzamento del player rilevato da 1 a 2 secondi e ritorno alla lista dopo la chiusura. Risultati in `build/Tests-20261101-154434.xcresult`. Complessivamente: **14 test iOS superati nelle due esecuzioni finali**.

## Funzioni verificate

- **Guarda più tardi** è la tab sinistra e la schermata iniziale.
- **Home** apre il sito mobile YouTube originale. Il pulsante **+ Guarda più tardi** compare sulle schede video reali; il video aperto ha anche un pulsante nativo di salvataggio.
- Salvataggio dalla Home e da URL, validazione dei link, deduplicazione e persistenza dopo la chiusura e il riavvio dell’app.
- Rimozione dalla lista e annullamento.
- Toggle **Abilita Shorts** spento inizialmente; contenuti nascosti, ripristinati quando abilitati, preferenza conservata dopo il riavvio e nuovo blocco quando disabilitati.
- Ricerca di un video sul sito reale, salvataggio con titolo e miniatura, riapertura dalla lista dopo il riavvio e avvio della riproduzione. Nel collaudo del player è stato osservato un avanzamento fino a 25 secondi.

**La lista è locale a iurub: non sincronizza la playlist del tuo account Google.** Non occorre il login per salvare video. I test utilizzano una lista separata; l’avvio normale non contiene i video dimostrativi.

## Risultati

| Verifica | Esito | Ambito |
|---|---|---|
| Build Debug iOS Simulator | Superata | App nativa arm64 |
| Build Release iPhone | Superata | SDK iPhoneOS; compilazione senza firma personale |
| Swift Testing | 10/10 superati | Eseguiti anche nel simulatore iOS |
| XCUITest | 3/3 superati | Tab, URL, Home, persistenza, rimozione/annullamento, toggle Shorts |
| Bridge JavaScript | 9/9 superati | jsdom, esecuzione precedente sul medesimo bridge |
| Integrazione Swift/WebKit | 17/17 superate | WKWebView macOS, fixture e YouTube live; verifiche precedenti |
| XCUITest YouTube live | 1/1 superato | Ricerca, salvataggio, riavvio, avanzamento del player e chiusura |
| Login Google | Non verificato | Nessuna credenziale utilizzata |
| iPhone fisico, fullscreen/rotazione, PiP/AirPlay | Non verificati | Non inclusi negli esiti superati |

I test Swift coprono URL validi e ostili, canonicalizzazione, metadati, duplicati, persistenza, ordine, rimozione/annullamento, file corrotti, scritture fallite e impostazioni. Il bridge verifica origine, conferma del salvataggio nativo, filtri ripristinabili e schede aggiunte o riciclate.

Nel collaudo è stato corretto il gesto XCUITest sul toggle: SwiftUI espone l’intera riga come interruttore, ma occorre toccare il controllo sul bordo destro. Il controllo del player è stato aggiornato per misurare l’avanzamento temporale, perché YouTube nasconde automaticamente i pulsanti di riproduzione. Lo script del simulatore seleziona ora dispositivi compatibili con il runtime e avvia i test UI senza parallelismo. Termina inoltre l’app prima del collaudo, per consentire a XCTest un avvio pulito. Durante le prove una sessione di Xcode aveva dato un timeout di lancio: riavviato il simulatore, la suite completa e il test live finale sono terminati correttamente.

## Ripetere i controlli

```sh
cd /Users/davidecarpini/apps/iurub
./scripts/simulator.sh test
./scripts/simulator.sh live
./scripts/simulator.sh run
```

`test` esegue la suite ripetibile con fixture locali. `live` esegue il percorso sul sito reale e richiede Internet; l’esito dipende anche dall’interfaccia e dalla disponibilità di YouTube. Entrambi mantengono separata la lista di prova. I risultati e gli screenshot allegati vengono salvati in `build/*.xcresult`.

`run` compila, installa e avvia l’app normale. Il progetto `iurub.xcodeproj` è già generato e non richiede dipendenze esterne per la build. Per installare su un iPhone fisico occorre impostare il proprio team Apple in Signing & Capabilities.

## Screenshot e consegna

Gli screenshot allegati sono acquisizioni originali del simulatore, senza ricostruzioni grafiche:

- `iurub-guarda-piu-tardi.png`: video reale salvato nella lista di prova.
- `iurub-youtube.png`: ricerca YouTube reale e pulsante aggiunto alle schede.
- `iurub-impostazioni.png`: impostazioni native con Shorts abilitati nel test.
- `iurub-riproduzione.png`: fotogramma del video durante la riproduzione reale.
- `iurub-avvio.png`: avvio normale, lista personale vuota e tab sinistra selezionata.
- `iurub-test-ios.json`: riepilogo originale esportato da Xcode dei 13 test superati.
- `iurub-test-live.json`: riepilogo originale del test live finale superato.

`iurub-sorgenti.zip` contiene sorgenti, progetto Xcode, piano, test, script e documentazione. `Avvia-iurub.command` avvia il progetto già presente su questo Mac; `LEGGIMI.txt` contiene le istruzioni brevi.

## Limiti

L’app usa il sito e il player originali: rete, pubblicità, consenso e disponibilità dei contenuti rimangono gestiti da YouTube. I filtri e i pulsanti dipendono dal DOM del sito e possono richiedere aggiornamenti se Google lo modifica. L’accesso Google nella WKWebView non è garantito e non è stato collaudato. Non è stata effettuata una pubblicazione su App Store né un’installazione firmata su un iPhone fisico.

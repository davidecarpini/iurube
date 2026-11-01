# iurub 1.1 — navigazione e verifica

1 novembre 2026 · progetto `/Users/davidecarpini/apps/iurub` · versione **1.1.0, build 2**.

## Modifiche consegnate

- Barra inferiore nativa con **Salvati, Iscrizioni, Cronologia, Esplora**, in quest’ordine.
- La navigazione inferiore interna di YouTube (Home, Iscrizioni, Tu) è nascosta, anche quando gli Shorts vengono abilitati o il sito aggiorna le schede.
- **Indietro e Ricarica pagina** in alto a sinistra; **Impostazioni e Tu** in alto a destra. Rimossa l’icona segnalibro/Home accanto alle impostazioni.
- **Tu** apre la pagina personale YouTube nella sezione corrente. Il percorso mobile è `/feed/library`; Indietro torna alla pagina precedente.
- La webview raggiunge il bordo inferiore dello schermo, dietro la barra nativa. Le acquisizioni reali mostrano il contenuto sotto la barra flottante.
- Tutte le sezioni condividono lo stesso login. Salvati e Cronologia si aggiornano al ritorno nella rispettiva tab. Il refresh ricarica la pagina corrente.
- Conservati salvataggio nell’account, Rimuovi, eventuale Annulla di YouTube, toggle Shorts e archivio locale precedente nelle impostazioni.

## Esiti finali

Ambiente simulatore: **Xcode 27.2, iPhone Air, iOS 27.2**.

| Verifica | Esito | Copertura |
|---|---|---|
| Swift Testing | **10/10** | URL, modello, persistenza, errori e preferenze |
| XCUITest con fixture | **4/4** | Quattro tab, ordine, toolbar, refresh, Tu, frame webview, salvataggio/riavvio, rimozione/annullamento, archivio locale, Shorts |
| XCUITest YouTube reale | **1/1** | Playlist autenticata, menu, Tu → Indietro, Iscrizioni, Cronologia, Esplora, ritorno a Salvati |
| JavaScript/jsdom | **21/21** | Bridge, menu account, rimozione, filtri e assenza della barra YouTube dopo aggiornamenti dinamici |
| Build Debug simulatore | **Superata** | App aggiornata installata e avviata |
| Build Release firmata iPhone | **Superata** | Apple Development, team personale configurato |
| Installazione e avvio iPhone fisico | **Superati** | iPhone di Davide, iPhone 16 Pro Max, iOS 26.6.1; inventario conferma 1.1.0 (2) |

Totale iOS: **15 test superati, 0 fallimenti, 0 saltati** nelle esecuzioni finali. La verifica della geometria controlla che il bordo inferiore della WKWebView coincida con quello dello schermo. Gli screenshot confermano la rimozione della seconda barra e la disposizione dei nuovi controlli.

Risultati:

- Suite iOS: `build/Tests-20261101-181020.xcresult`.
- Test live: `build/Tests-20261101-180850.xcresult`.
- JavaScript: `work/navigation-js.log`.
- Build firmata: `work/navigation-iphone-build.log`.
- Installazione, avvio e versione fisica: `work/navigation-iphone-install.json`, `work/navigation-iphone-launch.json`, `work/navigation-iphone-app.json`.

## Isolamento dei test e limiti

I test che aggiungono o rimuovono video usano una playlist simulata e un archivio WebKit non persistente. La verifica live apre pagine e menu, senza aggiungere o togliere video dall’account. Il percorso Indietro dopo Tu è verificato sul sito reale, perché le pagine HTML iniettate della fixture non riproducono la cronologia nativa di navigazione di WKWebView.

L’aggiornamento sull’iPhone è stato installato sopra la versione esistente, senza disinstallazione o cancellazione dei dati. La sessione del simulatore rimane separata da quella del telefono. È stata verificata l’installazione e l’apertura fisica; la suite funzionale completa è stata eseguita nel simulatore.

Il player reale era stato verificato in precedenza; la riproduzione non è stata ricollaudata in questo aggiornamento di navigazione. Fullscreen, rotazione, PiP e AirPlay restano fuori dal collaudo. Menu, conferme, disponibilità di Annulla e filtri dipendono dal sito YouTube. Nessuna pubblicazione su App Store.

## Ripetere i controlli

```sh
cd /Users/davidecarpini/apps/iurub
npm ci --ignore-scripts
npm test
./scripts/simulator.sh test
./scripts/simulator.sh live
./scripts/simulator.sh run
```

`live` richiede la sessione YouTube già autenticata, una playlist popolata e il sito in italiano. Per aggiornare l’iPhone collegato, selezionalo come destinazione in Xcode e premi Run.

## Deliverable

- `iurub-sorgenti.zip`: sorgenti, progetto Xcode, test, script e documentazione aggiornati.
- `iurub-navigazione.png`: Salvati con le quattro tab e la pagina dietro la barra.
- `iurub-tu.png`, `iurub-iscrizioni.png`, `iurub-cronologia.png`, `iurub-esplora.png`: le nuove sezioni sul sito reale.
- `iurub-impostazioni.png`: impostazioni aggiornate, Shorts abilitati nella fixture.
- `iurub-avvio.png`, `iurub-guarda-piu-tardi.png`, `iurub-rimozione-rapida.png`: aggiornati alla nuova navigazione.
- `iurub-test-ios.json`, `iurub-test-live.json`, `iurub-test-javascript.txt`: esiti originali dei controlli.
- `Avvia-iurub.command` e `LEGGIMI.txt`: avvio locale e istruzioni.
- `storico/`: immagini del precedente collaudo della riproduzione.

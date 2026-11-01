# iurub — verifica playlist account e rimozione rapida

1 novembre 2026 · progetto `/Users/davidecarpini/apps/iurub`

## Correzione consegnata

La prima tab mostra ora **Guarda più tardi dell’account YouTube** già autenticato nell’app. Home e playlist condividono la sessione WebKit; tornando dalla Home la playlist si aggiorna. La lista locale della versione precedente è conservata in **Impostazioni → Salvati sul dispositivo**.

Il pulsante **+ Guarda più tardi** della Home usa i menu del sito e seleziona la playlist dell’account. Gestisce sia i checkbox sia le voci selezionabili attualmente usate da YouTube mobile, senza deselezionare un video già presente. Se il menu non è riconosciuto, lascia disponibile il comando originale e indica come procedere.

Ogni riga della playlist ha un pulsante **Rimuovi**: un tocco richiama il comando di YouTube per quel video. Non viene rimossa una riga solo graficamente in anticipo. L’eventuale comando **Annulla** del sito rimane utilizzabile.

## Risultati finali

Ambiente: **Xcode 27.2 (27B52), iPhone Air, iOS 27.2 (24B8117)**.

| Verifica | Esito | Ambito |
|---|---|---|
| Debug iOS Simulator | Superata | Compilazione, installazione e avvio della versione aggiornata |
| Release iPhone | Superata | Compilazione per iPhoneOS senza firma personale |
| Swift Testing | **10/10** | Modello, URL, persistenza locale, errori e preferenze |
| XCUITest con fixture | **3/3** | Playlist account iniziale, salvataggio, riavvio, rimozione/annullamento, archivio locale, Shorts |
| JavaScript/jsdom | **20/20** | Menu reali riprodotti, selezione corretta, rimozione della riga corretta, fallback, schede dinamiche e filtri |
| XCUITest YouTube live | **1/1** | Sessione già autenticata, playlist reale, pulsanti, menu e selezione esistente, passaggio fra le tab |

Totale delle due esecuzioni iOS: **14 test superati, 0 fallimenti, 0 saltati**. Nessun runtime warning segnalato nei riepiloghi Xcode.

- Suite iOS: `build/Tests-20261101-160425.xcresult`.
- Test live: `build/Tests-20261101-160613.xcresult`.
- Log JavaScript: `work/account-bridge-final.log`.
- Build Release: `work/account-release-final.log`.

## Cosa è stato verificato

La suite ripetibile parte da una playlist account simulata già popolata. Aggiunge un secondo video dalla Home, verifica che sia presente dopo il riavvio, lo rimuove con il nuovo pulsante, controlla che l’altro video rimanga e usa **Annulla** per ripristinarlo. Verifica anche che i salvataggi account non finiscano silenziosamente nell’archivio locale.

Il toggle Shorts è stato verificato spento inizialmente, abilitato, conservato dopo il riavvio e nuovamente disabilitato. L’archivio locale conserva aggiunta tramite link, validazione, rimozione e annullamento.

Sul sito reale è stata verificata la playlist dell’account presente nel simulatore. Sono stati aperti il menu originale della prima riga e il selettore delle playlist, senza attivare le opzioni di aggiunta o rimozione. I controlli osservati sono stati usati per aggiornare i selettori del bridge. **La cancellazione e l’annullamento completi sono stati collaudati sulla fixture, non sui video personali.**

Le fixture usano un archivio WebKit non persistente e dati di prova separati. La sessione personale è stata mantenuta durante gli aggiornamenti dell’app. I controlli diagnostici temporanei sono stati rimossi dai sorgenti finali.

## Ripetere i controlli

```sh
cd /Users/davidecarpini/apps/iurub
npm ci --ignore-scripts
npm test
./scripts/simulator.sh test
./scripts/simulator.sh live
./scripts/simulator.sh run
```

`test` usa fixture isolate. `live` richiede una sessione YouTube autenticata e la playlist popolata, ed esegue il controllo dei menu in italiano in sola lettura. `run` compila, installa e apre l’app normale. I risultati Xcode includono allegati acquisiti dal simulatore.

## Deliverable

- `iurub-sorgenti.zip`: sorgenti aggiornati, progetto Xcode, test, script e documentazione.
- `Avvia-iurub.command` e `LEGGIMI.txt`: avvio sul Mac e istruzioni.
- `iurub-rimozione-rapida.png`, `iurub-guarda-piu-tardi.png`, `iurub-avvio.png`: app aggiornata, vera playlist e pulsante Rimuovi.
- `iurub-impostazioni.png`: impostazioni attuali, Shorts abilitati nella fixture di test.
- `iurub-test-ios.json`, `iurub-test-live.json`: riepiloghi originali esportati da Xcode.
- `iurub-test-javascript.txt`: output dei 20 test JavaScript.
- `storico/iurub-youtube.png` e `storico/iurub-riproduzione.png`: acquisizioni del collaudo precedente, conservate come riferimento.

## Limiti della verifica

Il player reale aveva superato il collaudo precedente con avanzamento della riproduzione; quel test non è stato ripetuto in questa correzione. Il login è stato effettuato dall’utente: è stato verificato il riuso della sessione, non il flusso di autenticazione con credenziali.

Menu, filtri, conferme e disponibilità di Annulla dipendono dal sito YouTube e possono richiedere manutenzione quando cambia. Non sono stati verificati iPhone fisico, firma personale, fullscreen/rotazione o PiP/AirPlay. Nessuna pubblicazione su App Store è stata effettuata.

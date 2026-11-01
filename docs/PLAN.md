# Piano di sviluppo di iurub

Aggiornato il 1 novembre 2026 dopo la verifica con l’account YouTube dell’utente.

1. Conservare il progetto SwiftUI iOS 17+ e la sessione Google già presente nella WKWebView.
2. Collegare la prima tab alla vera playlist `https://m.youtube.com/playlist?list=WL`, usando lo stesso archivio WebKit della Home. Ricaricarla al ritorno dalla seconda tab.
3. Usare i menu visibili di YouTube per il pulsante **+ Guarda più tardi** sulle schede e il salvataggio del video aperto. Verificare la selezione della playlist corretta, evitando di deselezionarla quando è già selezionata.
4. Aggiungere **Rimuovi** alle righe della playlist: un tocco richiama il comando YouTube della stessa riga. Lasciare disponibile l’eventuale **Annulla** del sito.
5. Conservare i vecchi link locali in **Impostazioni → Salvati sul dispositivo**, senza presentarli come playlist Google o trasferirli automaticamente.
6. Mantenere Shorts disattivati inizialmente, toggle persistente, filtri ripristinabili, validazione dei link e pausa audio quando si cambia tab.
7. Testare le modifiche con fixture isolate dall’account reale: playlist preesistente, aggiunta, persistenza, rimozione della riga corretta, annullamento, archivio locale e Shorts.
8. Verificare sul simulatore la vera playlist dell’account e i menu correnti di YouTube in sola lettura. Aggiornare sorgenti, rapporto e screenshot con gli esiti effettivi.

## Decisioni

- La prima tab è la playlist YouTube dell’account: il login effettuato nella Home vale anche qui.
- L’archivio locale precedente rimane accessibile e distinto.
- Nessun backend, password o token letti dall’app, nessuna API privata. Le operazioni usano i controlli del sito originale.
- Se un menu non è riconosciuto, il sito resta utilizzabile e viene indicato come completare l’operazione. Nessun successo fittizio o rimozione grafica anticipata.
- Le cancellazioni di collaudo avvengono soltanto nella playlist simulata. La verifica live non aggiunge né rimuove video dall’account dell’utente.
- Fixture disponibili solo in Debug con argomenti espliciti; archivio WebKit non persistente e dati di test separati.

Esiti effettivi e limiti in `TEST-REPORT.md`.

## Aggiornamento navigazione — 1 novembre 2026

1. Sostituire le due tab con Salvati, Iscrizioni, Cronologia, Esplora, conservando sessioni separate e lo stesso login WebKit.
2. Nascondere la navigazione inferiore interna di YouTube, anche dopo aggiornamenti dinamici o abilitazione degli Shorts.
3. Togliere il segnalibro/Home dalla barra superiore; aggiungere refresh vicino a Indietro e Tu a destra delle impostazioni.
4. Estendere la webview dietro la barra inferiore nativa, fino al bordo dello schermo.
5. Verificare geometria e navigazione con fixture isolate e con il sito reale; aggiornare simulatore e iPhone collegato.

# Piano di sviluppo di iurub

Aggiornato il 1 novembre 2026 per **iurub 1.3.0**. Il piano include la nuova tab In corso e conserva le funzionalità della versione 1.2. Gli esiti effettivi delle verifiche sono riportati in `TEST-REPORT.md`.

1. Conservare il progetto SwiftUI iOS 17+ e la sessione Google già presente nella WKWebView.
2. Collegare **Salvati** alla vera playlist `https://m.youtube.com/playlist?list=WL`, usando lo stesso archivio WebKit delle altre sezioni. Conservare la pagina al rientro dal player; aggiornarla quando un salvataggio richiede di mostrare la playlist modificata.
3. Usare i menu visibili di YouTube per il segnalibro compatto sulle schede e il salvataggio del video aperto. Verificare la selezione della playlist corretta, evitando di deselezionarla quando è già selezionata.
4. Inserire un cestino compatto nelle righe della playlist: un tocco richiama il comando **Rimuovi** di YouTube della stessa riga, senza aggiungere una riga sotto il video. Lasciare disponibile l’eventuale **Annulla** del sito.
5. Conservare i vecchi dati locali senza presentarli come playlist Google o trasferirli automaticamente. La sezione nelle impostazioni è stata poi rimossa su richiesta.
6. Mantenere Shorts disattivati inizialmente, toggle persistente, filtri ripristinabili, validazione dei link e pausa audio quando si cambia tab.
7. Testare le modifiche con fixture isolate dall’account reale: playlist preesistente, aggiunta, persistenza, rimozione della riga corretta, annullamento, archivio locale e Shorts.
8. Verificare sul simulatore la vera playlist dell’account e i menu correnti di YouTube in sola lettura. Aggiornare sorgenti, rapporto e screenshot con gli esiti effettivi.

## Decisioni

- Le cinque tab sono **In corso, Salvati, Iscrizioni, Cronologia, Esplora**. La prima ospita il player dedicato; le altre conservano la navigazione YouTube. Tutte condividono lo stesso login.
- All’avvio si riprende l’ultimo video incompleto; in sua assenza si apre Salvati. Un video completato non viene riaperto automaticamente.
- Le posizioni di riproduzione e le chat sono conservate per video sul dispositivo, separate dalla playlist YouTube dell’account.
- I dati locali precedenti rimangono distinti; la voce delle impostazioni è stata rimossa.
- Nessun backend, password o token YouTube letti dall’app, nessuna API YouTube privata. Le operazioni della playlist usano i controlli del sito originale. I riassunti usano la chiave OpenRouter fornita dall’utente, nel Portachiavi.
- Se un menu non è riconosciuto, il sito resta utilizzabile e viene indicato come completare l’operazione. Nessun successo fittizio o rimozione grafica anticipata.
- Le cancellazioni di collaudo avvengono soltanto nella playlist simulata. La verifica live non aggiunge né rimuove video dall’account dell’utente.
- Fixture disponibili solo in Debug con argomenti espliciti; archivio WebKit non persistente e dati di test separati.

Esiti effettivi e limiti in `TEST-REPORT.md`.

## Navigazione introdotta nella versione 1.2

1. Conservare le quattro sezioni Salvati, Iscrizioni, Cronologia, Esplora con sessioni separate e lo stesso login WebKit; nella versione 1.3 sono affiancate dalla prima tab In corso.
2. Nascondere la navigazione inferiore interna di YouTube, anche dopo aggiornamenti dinamici o abilitazione degli Shorts.
3. Togliere il segnalibro/Home dalla barra superiore; aggiungere refresh vicino a Indietro e Tu a destra delle impostazioni.
4. Estendere la webview dietro la barra inferiore nativa, fino al bordo dello schermo.
5. Verificare geometria e navigazione con fixture isolate e con il sito reale; aggiornare simulatore e iPhone collegato.

## Riassunti e lista compatta della versione 1.2

1. Leggere la chat sui riassunti e verificare una richiesta reale Gemini/OpenRouter con input video YouTube.
2. Implementare in parallelo: servizio e Portachiavi; modale chat e impostazioni; pulsanti compatti e lista senza copertina; test.
3. Conservare una chat per video, mantenere il video originale nelle domande successive, gestire errori/interruzione senza retry automatici o duplicati.
4. Ridurre salva/rimuovi a icone da 44 punti nella riga dei dettagli; verificare il DOM reale e la compatibilità con Trusted Types.
5. Eliminare Account YouTube e Archivio locale dalle impostazioni; il secondo tocco sulle tab di navigazione torna alla radice.
6. Collaudare con fixture isolate, poi con YouTube e Gemini reali; aggiornare simulatore e iPhone senza cancellare dati o login.
7. Consegnare sorgenti senza chiave, rapporto con esiti reali e screenshot aggiornati.

## In corso — versione 1.3.0

1. Aggiungere **In corso** come prima tab, sempre visibile. Senza un video, mostrare “Un video alla volta” con accesso a Salvati.
2. Aprire i video in un player dedicato e selezionare automaticamente In corso, mantenendo la pagina e lo scorrimento delle sezioni di provenienza. Conservare nel player i comandi di salvataggio e Riassunto.
3. Salvare una posizione distinta per ogni video. Prima di passare a un altro, acquisire il progresso del precedente; gli eventi arrivati in ritardo non devono cambiare il video selezionato o sovrascrivere il suo punto di ripresa.
4. All’avvio riaprire il video incompleto dal punto salvato. Se manca un video da riprendere, o l’ultimo è terminato, aprire Salvati. Una nuova apertura esplicita di un video completato riparte dall’inizio.
5. Tornando a In corso, riutilizzare il player già aperto. Anche un secondo tocco sulla tab conserva la posizione; un link con tempo esplicito può scegliere un punto diverso. Le altre tab mantengono il ritorno alla radice al secondo tocco.
6. Al ritorno dal player conservare le pagine di navigazione; dopo un salvataggio nel player aggiornare Salvati per mostrare il cambiamento nell’account.
7. Registrare il progresso circa ogni cinque secondi durante la riproduzione e anche su pausa, spostamento del cursore, cambio di sezione e passaggio in background. Dopo una chiusura forzata vale l’ultimo aggiornamento salvato: non promettere una ripresa precisa al fotogramma o la sincronizzazione del punto con altri dispositivi.
8. Conservare il progresso di uno Short anche quando il toggle viene disabilitato; mostrare come riabilitarlo senza cancellare il video in corso.
9. Verificare con fixture separate apertura del player, ripresa tra tab, secondo tocco, riavvio, cambio di video e completamento. Affiancare una verifica sul player YouTube reale, riportando eventuali limiti del sito e distinguendola dalle simulazioni.
10. Aggiornare l’app sul simulatore e sull’iPhone senza cancellare dati o accesso Google; consegnare sorgenti, rapporto e screenshot della versione finale.

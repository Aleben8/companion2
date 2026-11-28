# Companion (ricostruito)

Companion app multigiocatore per un gioco di ruolo "alla Pokémon", scritta in Flutter
(web + mobile) con Firebase Firestore come backend.

Il codice è stato **ricostruito dalla build compilata** (`main.dart.js`) del repository
`Aleben8/companion2`: la logica di gioco, i nomi delle collezioni/campi Firestore e i testi
sono quelli dell'originale; il layout è ricreato dagli screenshot.

## Installazione (la prima volta)

Questa cartella è già il progetto completo, pronta da usare come repository (`web/`, `.github/`, `assets/`, `lib/` inclusi).
Mancano solo `android/` e `ios/`, che si generano con Flutter:

```bash
sh setup.sh              # genera android/ios, scarica le dipendenze
flutter run -d chrome    # prova in locale
```

Se hai già un progetto con `android/` e `ios/` generati, copia sopra `lib/`, `assets/`, `web/`, `.github/`,
`pubspec.yaml` e `analysis_options.yaml`, poi `flutter pub get`.

## Due modalità: Tavolo e Dal vivo (le sceglie il Master)

Un'unica app e un unico deploy. La modalità è una proprietà del **party**: il Master la sceglie in
*Impostazioni > Gestione Party > Modalità di gioco* (`Party/{codice}.mode` = `tavolo` | `live`) e la app di tutti i
giocatori del party passa subito all'altra modalità. Si può cambiare **anche a partita in corso**: la partita si adatta
(verso il live l'orologio riparte dal giro corrente e trappole/azioni perse diventano attese; verso il tavolo si crea
l'ordine dei turni e chi non è in una zona torna all'Hub).

Finché il Master non sceglie, vale la modalità predefinita della build:

```bash
flutter run -d chrome                                  # predefinita: TAVOLO
flutter run -d chrome --dart-define=MODE=live          # predefinita: DAL VIVO
flutter build web --release --base-href /companion2/   # build del deploy.yml
```

### Firestore (uno solo)
Entrambe le modalità usano lo stesso progetto Firebase (`lib/firebase_options.dart`), quindi non c'è nulla da configurare.
- I dati della partita stanno tutti sotto `Party/{codice}/...`: per giocare in parallelo un tavolo e un gioco dal vivo
  usa due party diversi (per esempio `TAVOLO1` e `SecretBB`).
- I giocatori (`Users/...`) e le loro mosse sono in comune. Il tavolo aggiunge ai giocatori i campi `pos`, `trappedSkip` e `actionPenalty`.
  All'avvio di una partita gli effetti temporanei vengono azzerati.
- Chi avvia la partita ha `isMaster: true` in `Party/{codice}/players/{nome}` (si imposta dalla console). Poi gioca come tutti.
- La collezione `Tipi` esiste già; se mancasse, la app la crea all'avvio della partita.

### Come funziona il tavolo
- **Fasi del giorno (niente turni).** Chiunque agisce quando vuole. Ogni giocatore ha **N azioni per fase** (le sceglie il
  Master a "Nuova partita", di base `kDefaultActionsPerPlayer` = 2) e la fase passa alla successiva quando **tutti** le hanno
  usate: 🌅 Mattina → ☀️ Pomeriggio → 🌇 Sera → 🌙 Notte → mattina del giorno dopo. Il "giro" del resto del regolamento **è la
  fase**: gli eventi si annunciano per fase ("nel pomeriggio", "fino a stasera") e al cambio di fase avanzano gli eventi e chi
  è in un rifugio recupera PS. Le **azioni perse** (Trappola: 2; eruzione: 1; Spavento: 1) contano come usate: prima quelle che
  restano nella fase, poi quelle della fase dopo (la Fune di fuga contro la Trappola te le restituisce). Chi non vuole fare
  nulla **sta fermo**: è un'azione e recupera `kWaitHp` (3) PS e `kWaitEnergy` (2) energie. Regole per agire
  (`lib/table/phases.dart`, `actBlock`):
  1. **mai due volte di fila**: dopo una tua azione deve agire qualcun altro, se qualcun altro ha ancora azioni in questa fase;
  2. **mai due azioni uguali di fila** (es. "cerca" dopo "cerca"); gli **spostamenti tra settori della stessa zona** e lo
     **stare fermo** sono liberi;
  3. **cambi di zona**: al massimo 2 al giorno e distanziati: se cambi zona la sera, la notte e la mattina dopo no, dal
     pomeriggio sì (`kZoneMovesPerDay`, `kZoneMoveGap`);
  4. le azioni costano quello che costano (settore impervio, eventi): servono abbastanza azioni rimaste nella fase.
  Eludere chi ti ha notato è una reazione: se non hai più azioni, la perdi nella fase dopo. La **Clessidra** ti fa agire
  subito una volta, anche di fila. La scheda in cima alla tab Tavolo dice giorno, fase, le tue azioni (in rosso quelle perse),
  chi deve ancora agire e se puoi agire (e perché no).
  Stato: `state.actionsPerPlayer`, `used` e `lost` (per giocatore, questa fase), `actions` (contatore del gruppo), `lastUid`;
  per giocatore `lastKind`, `zoneMoves`, `freeAction`, `priority`.
- **Per tornare ai turni** basta mettere `kTableTurns = true` in `lib/table/phases.dart`: ordine casuale, 2 azioni a turno con
  un numero DISPARI di giocatori e 3 con un numero PARI (`kActionsOdd`/`kActionsEven`), "Fine turno", il giro avanza quando
  tutti hanno giocato.
- **Posizione.** Dopo aver mosso la pedina sul tabellone, il giocatore la sposta anche sulla **mappa** della tab
  **Tavolo**: tocca la zona, sceglie il settore nel pannello che compare sotto e conferma con un solo bottone
  ("Vai: zona, settore N · costo"). Ogni spostamento costa 1 azione (`kMoveActionCost`). Le posizioni sono private: le altre
  si scoprono con il Radar. Al tavolo si gioca **al massimo in 9** (`kMaxTablePlayers`).
- **Schermata del Tavolo**, dall'alto: giorno e fase (o il turno, con i turni); le cose da risolvere subito (ti hanno notato,
  incontro selvatico, messaggio dei locali, avvistamenti; per il Master le richieste ai locali); **La tua posizione** (zona,
  settore attuale con le sue regole, eventi della zona con "Prendi uno strumento" / "Sfida il leggendario"); poi **tre
  pulsanti** che aprono un pannello dal basso (`lib/screens/table_sheets.dart`):
  - **Movimento**: i settori della tua zona, ognuno con tipo, costo e stato (bloccato, leggendario, avvistamenti, dove hai
    già cercato, la tua traccia, i tuoi indizi, Trappola/Allarme), e sotto le **altre zone** (mappa a pulsanti). Dopo lo
    spostamento il pannello si chiude.
  - **Strumenti**: la Borsa, con in cima l'Emporio se sei in un settore cittadino.
  - **Esplorazione**: **Cerca indizi** (1 azione), **Cerca tracce** (1 azione: chi è passato dal tuo settore di recente, da
    dove è arrivato, dove è andato e chi ci ha cercato; la Lente vede di più), **Parla con i locali** (1 azione, vedi sotto).
  Se un'azione non si può fare il bottone è grigio e dice perché. In fondo gli strumenti del Master (comprimibili).
  Icone dei tre pulsanti provvisorie (Strumenti usa già `assets/images/borsa.png`).
- **Mappa.** Un pulsante per ogni zona in gioco, con le miniature dei suoi settori (icona del tipo e numero; settori
  bloccati barrati, ⚡ dove c'è il leggendario, bordo sul settore dove sei) e, sotto il nome, gli eventi della zona
  ("⚠️ Frana nel Canyon · ancora 2 giri", "🔜 In arrivo: …"). Sono **colorate** le zone dove puoi andare adesso
  (è il tuo turno, hai le azioni e, per Biglietto/treno/traghetto, sei nel settore di passaggio), **grigie** e non
  selezionabili le altre. Sul pulsante: "Tu", il costo in azioni oppure "Biglietto" / "Treno/traghetto", e un'icona per gli
  eventi in corso. Codice: `lib/screens/table_map.dart`, regola in `TableService.canReach`.
- **Minuti -> giri.** Repellente 2 giri, recupero dopo la sconfitta 1 giro, divieto di riaffrontarsi dopo una fuga 2 giri,
  Trappola = fermo finché gli altri non fanno 2 azioni (con i turni: si salta il turno successivo) (valori in `lib/items.dart`).
- **Strumenti.** Radar mostra zona e settore degli altri, Calmanella rivela la tua zona, Trappola si piazza nel tuo settore e scatta
  quando qualcuno ci entra, Fune di fuga la annulla.
- **Eventi di zona** (`lib/table/events.dart`). All'avvio ne vengono estratti 5 più un leggendario e sono pianificati dal giro 3, uno ogni
  2 giri, in ordine casuale. Ogni evento è **annunciato un giro prima**, poi è **in corso** per qualche giro e infine termina. La app dice
  cosa mettere sul tabellone. Effetti: Vulcano (entrata +1 azione, Fuoco +1 danno, chi è lì perde 1 azione), Canyon (2 settori bloccati),
  Giungla (nebbia: invisibili al Radar), Regione innevata (entrata +1 azione), Isola (2 settori sommersi), Colline (Elettro +2, Volante +1),
  Hub e Campi (una volta sola si prende uno strumento a caso). **Il leggendario** compare in un **settore impervio** di una zona
  in gioco (che ne abbia uno) con un Pokémon più forte dei capi: per sfidarlo bisogna essere in quel settore; il primo che lo
  batte vince 2 strumenti.
- **Battaglie.** Funzionano come prima (codice da condividere). Gli eventi attivi nella zona di chi crea la battaglia danno il bonus di danno.
- Le palestre GPS di Varese esistono solo nella modalità dal vivo.

### Eventi di zona: automatici o manuali

Nel riquadro Master della tab Tavolo c'è l'interruttore **Eventi di zona manuali** (si sceglie prima dell'avvio e si può cambiare durante la partita).
- **Automatici**: la app pianifica e fa partire gli eventi (come prima). Passando ad automatico a partita in corso, i nuovi eventi vengono pianificati dal giro corrente.
- **Manuali**: la app non pianifica nulla. Dopo aver pescato la carta, il Master tocca *Inserisci evento*, sceglie l'evento (e la zona per il leggendario) e decide se **annunciarlo** (poi lo fa partire con *Attiva*) o **attivarlo subito**. *Termina* chiude un evento in corso, *Annulla* ritira uno annunciato. Effetti e durata in giri restano quelli di `lib/table/events.dart`; il Radar meteo in manuale vede solo gli eventi già annunciati con una data.

### Collegamenti tra zone e viaggi speciali

Non tutte le zone confinano: a piedi ci si sposta (di settore o di zona) solo tra zone **collegate**, scegliendo liberamente il settore di arrivo. Il Master decide i collegamenti dal riquadro Master della tab Tavolo, bottone **Collegamenti tra zone** (spunta le coppie; "Proposta" ripristina la bozza letta dalla mappa, `kDefaultLinks` in `lib/table/zones.dart`). Le scelte restano salvate nel party e valgono dalla partita successiva e, se la partita è in corso, subito. Sulla mappa le zone raggiungibili sono colorate.

Per andare in una zona **non collegata** (es. Neve → Canyon) non si va a piedi:
- **Biglietto** (strumento solo tavolo) o **eventi di passaggio**: *Treno straordinario* (Hub) e *Traghetto dei relitti* (Isola); finché sono attivi, chi è in quella zona raggiunge qualsiasi zona senza Biglietto.
- In tutti e tre i casi si parte **solo da un settore di passaggio** e si arriva **nel settore di passaggio** della zona di destinazione (il settore non si sceglie). Il costo in azioni è quello normale.
- **Ritorno gratis**: chi arriva in una zona con il Biglietto può tornare alla zona di partenza senza un altro Biglietto
  (paga solo le azioni), finché resta nella zona d'arrivo; se ne esce in un altro modo il ritorno gratis si perde
  (`Users/{uid}.ticketReturn`). Sulla mappa il pulsante della zona di partenza dice "Ritorno gratis".

### Biomi in gioco

A **Nuova partita** il Master vede i biomi estratti: l'Hub c'è sempre, poi **giocatori + 1** biomi a caso tra gli altri 7 (al massimo tutti). Può cambiarli con le spunte (o "Riestrai") prima di avviare. Se con i collegamenti l'Hub non raggiunge a piedi uno dei biomi scelti, la app lo avvisa (si può avviare lo stesso). La scelta sta in `state.biomes`: mappa, collegamenti, Biglietto, eventi (anche il leggendario), indizi ed emporio usano solo i biomi in gioco. Dal vivo i biomi non ci sono.

### Settori e loro tipo

Ogni settore ha un tipo (`SectorType` in `lib/table/zones.dart`, regole e costanti in `lib/table/sectors.dart`). Il Master cambia tipo e numero dei settori dal riquadro Master, bottone **Settori delle zone** ("Proposta" torna alla disposizione di partenza); si salva in `Party/{codice}.sectorTypes` e viene copiato in `state.sectors` all'avvio. Se a partita in corso una zona perde settori, giocatori, tracce, indizi nascosti, trappole, allarmi e settori bloccati che stavano nei settori spariti finiscono nell'ultimo rimasto.

Distribuzione di partenza (30 settori):

| Zona | Settori | Cittadino | Rifugio | Passaggio | Selvaggio | Impervio |
|---|---|---|---|---|---|---|
| Hub | 5 | 3 | 1 | 1 | 0 | 0 |
| Giungla | 4 | 1 | 1 | 1 | 1 | 0 |
| Canyon | 4 | 1 | 1 | 1 | 0 | 1 |
| Regione innevata | 4 | 1 | 1 | 1 | 0 | 1 |
| Vulcano | 4 | 1 | 1 | 1 | 0 | 1 |
| Campi | 3 | 1 | 1 | 1 | 0 | 0 |
| Colline | 3 | 1 | 1 | 1 | 0 | 0 |
| Isola dei relitti | 3 | 1 | 1 | 1 | 0 | 0 |

| Tipo | Effetti |
|---|---|
| **Cittadino** | Qui c'è l'emporio (l'Emporio si apre solo in un settore cittadino). Nessun incontro selvatico. Locali: CD −2. Tracce: forza −1 (minimo 1). |
| **Selvaggio** | Entrando, 25% di incontrare un Pokémon selvatico del tipo della zona (forza simile alla tua, NPC come nelle palestre). Si sceglie: affrontarlo (vittoria: `kCoinsWild` monete e 25% di uno strumento) o fuggire (1 azione; se non ne hai, la perdi al turno dopo). Finché non scegli non puoi muoverti né cercare. |
| **Impervio** | Entrare nel settore costa +1 azione. Tracce: forza +1. *Cerca* trova uno strumento al 30% invece del 15%. Qui compare il leggendario. Locali: CD +2. |
| **Rifugio** | A ogni nuova fase del giorno chi è qui recupera 5 PS e 2 energie. Nessuno può sfidarlo a battaglia (né lui può combattere contro altri giocatori da qui); il Radar lo vede comunque. Locali: CD −1. |
| **Passaggio** | Da qui partono e qui arrivano Biglietto, treno e traghetto. Tracce: forza +1. |

### Capipalestra del tavolo

Uno per zona in gioco, del tipo della zona, nel suo punto più caratteristico (`kZoneGyms` in `lib/table/zones.dart`). Il nome
del punto diventa il titolo di quel settore nei testi ("Ash è passato da Bordo del cratere"):

| Zona | Tipo | Settore | Punto |
|---|---|---|---|
| Hub centrale | Normale | Cittadino 1 | Piazza centrale |
| Canyon | Roccia | Impervio 4 | Gola del canyon |
| Giungla | Erba | Selvaggio 4 | Albero millenario |
| Regione innevata | Ghiaccio | Impervio 4 | Ghiacciaio |
| Vulcano | Fuoco | Impervio 4 | Bordo del cratere |
| Campi e fattoria | Normale | Cittadino 1 | La fattoria |
| Isola dei relitti | Acqua | Passaggio 3 | Relitto del porto |
| Colline ventose | Volante | Passaggio 3 | Picco dei venti |

(Se il Master cambia i settori si usa il primo del tipo indicato, altrimenti il settore 1.) A ogni "Nuova partita" i
capipalestra vengono generati di nuovo (Pokémon, allenatore e mosse casuali del tipo), in `Party/{codice}/zoneGyms`.
**Si sfidano solo dal loro settore e dopo essere rimasti nella zona per una fase intera**: bisogna esserci già all'inizio della
fase in corso (`Users/{uid}.zoneSince`, aggiornato a ogni cambio di zona); chi arriva al pomeriggio lo sfida dalla sera.
Il bottone "Sfida il capopalestra" sta nella scheda "La tua posizione". Vittoria: monete e medaglia della palestra
(`badges.zona-<zona>`, la prima volta), come dal vivo. Sfidarlo non costa azioni (come il leggendario).

### Azioni di settore (Esplorazione)

Come "Parla con i locali": costano **1 azione**, il giocatore tira il dado al tavolo e il Master (in cima alla sua tab Tavolo,
"Prove da approvare") vede **la CD completa** e risponde "Sì" o "No"; se è sì la app applica l'effetto. L'esito lo vede solo il
giocatore, in una scheda con il titolo dell'azione. Se la prova fallisce si perde solo l'azione. Una prova alla volta.

| Azione | Settore | CD | Se riesce |
|---|---|---|---|
| **Contrattare** | cittadino | 12 | Per il resto della fase ogni acquisto all'emporio costa 1 moneta in meno (minimo 1). |
| **Seguire le tracce** | selvaggio | max(8, 16 − 2 × forza totale delle tracce visibili nel settore) | Leggi la traccia più forte di chi è già **ripartito** da qui: debole = "qualcuno è passato", chiara = anche dove è andato, evidente = anche chi era e da dove veniva. |
| **Cancellare le tracce** | tutti tranne cittadino | 12 | La traccia che hai lasciato entrando nel settore torna a forza 1. |
| **Scalare** | impervio | 13 | Il prossimo spostamento costa 1 azione in meno (anche 0): `Users/{uid}.moveDiscount`, consumato da `moveTo`. |
| **Riposare** | rifugio | nessuna prova | Subito: +10 PS, +3 energie e via gli status alterati. |

Costanti e testi in `lib/table/sectors.dart` (`SectorAction`, `kMinDc`, `followCd`…); codice in
`TableService.sectorAction` e `answerCheck` (richieste in `Party/{codice}/localsRequests` con `kind` e `cd`).

### PS, energie e status restano tra uno scontro e l'altro

Alla fine di ogni battaglia (o fuggendo) il Pokémon si porta dietro **PS**, **energie** e l'eventuale **status alterato**
con i turni rimasti (`currentHp`, `currentEnergy`, `currentStatus` sul documento del Pokémon). Dopo una sconfitta, finito il
recupero, riparte pieno e senza status. In Home, accanto ai PS, ci sono le energie (⚡) e lo status. Pozione e Super Pozione
(PS), **Elisir** (energie) e **Antidoto** (status) si usano anche dalla Borsa; il rifugio ricarica PS ed energie a ogni fase;
Riposare fa di più. Capipalestra, selvatici e leggendari partono sempre pieni.

### Furtività: entrare in un settore dove c'è qualcuno

Quando ti sposti in un settore dove ci sono altri giocatori la app tira **d20 + destrezza** contro una CD:

- **destrezza** = Velocità del tuo Pokémon attivo × 0,5 (per ora; poi potrà essere una statistica dedicata);
- **CD** = 10 + modificatore del settore + **percezione** del più attento nel settore (Difesa Speciale × 0,5, per ora);
- modificatori del settore: cittadino −2 (folla), selvaggio −1 e impervio −1 (ripari), rifugio +2, passaggio +1.

Se riesci non succede nulla (e non sai se c'era qualcuno: non arriva nessun avviso). Se fallisci, chi è nel settore riceve
l'avviso "Hai notato X entrare nel tuo settore" e a te si apre il popup **"Ti hanno notato!"** (anche come scheda nella tab
Tavolo): non puoi muoverti né cercare finché non decidi. **Decidi tu per primo**:
- **Eludi** (1 azione; con i turni, se non ne hai, la perdi al turno dopo): resti nel settore ma ti nascondi, e chi ti ha
  notato perde l'occasione;
- **Fune di fuga**: scappi in un altro settore libero della zona, a scelta (nessuno vede dove);
- **Resta allo scoperto**: chi ti ha notato ottiene la **priorità** e gli si apre il popup "Hai notato X!": può sfidarti
  (lotta obbligata, 1 azione), usare un'abilità o uno strumento, anche se ha appena agito, oppure lasciar stare. La priorità
  scade dopo `kPriorityActions` (2) azioni del gruppo (`Users/{uid}.priority`, regola in `actBlock`). Con il Passo felpato attivo nessuno ti nota. Solo al tavolo. Costanti in `lib/table/sectors.dart` (`kStealthBaseCd`, `kDexterityMultiplier`,
`kPerceptionMultiplier`, `kEludeCost`), codice in `TableService._checkSpotted` / `elude`.

### Tracce e informazioni dai locali

- **Forza delle tracce.** Ogni spostamento e ogni ricerca lascia una traccia di forza 1–3: base 1, **+1 con la spunta "Lascia una traccia ben visibile"** (nel pannello di spostamento), più il modificatore del settore. La Lente vede una traccia per *forza × 2* giri e ne dice la forza (debole, chiara, evidente). Costanti in `lib/table/sectors.dart`.
- **Parla con i locali** (Esplorazione, 1 azione, in **qualsiasi** settore). La richiesta arriva al Master in cima alla sua tab
  Tavolo ("Richieste ai locali") con il settore del giocatore e solo il **modificatore di CD** (cittadino −2, rifugio −1,
  selvaggio 0, impervio +2, passaggio 0). Il tiro si fa al tavolo e il Master risponde "Sì" o "No" a "ha superato la CD?".
  Il racconto dei locali (chi è passato nella zona di recente con la forza della traccia, gli eventi in arrivo, se qualcuno ha
  nascosto indizi lì) lo vede **solo il giocatore**, in una scheda nella sua tab Tavolo: il Master, che gioca, non lo legge.
  Codice: `TableService.requestLocals`, `answerLocals` (richieste in `Party/{codice}/localsRequests`, risposta su
  `Users/{uid}.localsInfo`).

### Proposta per il futuro (non fatta): una mappa con più settori

Oggi le zone hanno 3–5 settori e la mappa è un disegno semplice. Per le versioni successive:
1. **Settori come caselle sulla mappa.** Ogni settore diventa una casella con le sue coordinate (`kSectorMapPos`), e i collegamenti si definiscono anche *tra settori* (non solo tra zone): ci si sposta da un settore a uno adiacente, anche di un'altra zona, se confinano.
2. **Più settori per zona** (es. 6–9), con un costo di movimento per casella invece che per zona, così le distanze contano davvero.
3. **Immagine del tabellone** come sfondo, con le caselle sovrapposte e un editor del Master per trascinarle al punto giusto.
4. I tipi di settore restano gli stessi: aumentando i settori si possono aggiungere più selvaggi e impervi senza togliere città e rifugi.
5. Dati: `sectorTypes` diventa una lista di oggetti `{type, x, y, links[]}`; serve una migrazione che converta le partite in corso.

Tutti gli eventi di zona ora durano 2 giri.

## Il tavolo dal vivo

Tutto quello che c'è al tavolo (zone, settori, eventi di zona, empori di zona, protezioni di bioma, Radar meteo,
Chiave, leggendario, fascia eventi in cima alla home) funziona anche dal vivo. Cambia solo come si traducono
posizione, tempo e azioni. Codice: `lib/services/live_service.dart`, regole in fondo a `lib/mode.dart`.

- **Zone = cerchi sulla mappa.** Il Master le posiziona dalla tab **Mappa**: tiene premuto sulla mappa e sceglie
  zona e raggio, oppure va sul posto e preme **Qui** nel riquadro Master. Il raggio si cambia da lì (predefinito 80 m).
  Dati: `Party/{codice}.liveZones`. Per avviare la partita servono tutte le 8 zone.
- **Settori = 4 spicchi** del cerchio: 1 Nord, 2 Est, 3 Sud, 4 Ovest. Zona e settore li ricava il GPS e li scrive
  in `Users/{uid}.pos`, lo stesso campo del tavolo (fuori dai cerchi `pos` non c'è).
- **Giri = minuti.** Il giro avanza da solo ogni N minuti (`roundMinutes`, il Master sceglie 5–30, predefinito 10).
  Lo fa avanzare il primo telefono aperto che si accorge della scadenza (transazione: uno solo). Se nessuno ha la app
  aperta l'orologio si ferma e alla riapertura recupera i giri persi. Gli effetti "in giri" valgono in entrambe le modalità.
- **Niente turni, le azioni diventano attese** (`busyUntil`, `searchReadyAt` su `Users/{uid}`):
  - *Cerca indizi*: una volta ogni `kLiveSearchCooldownMinutes` (2) minuti; non si cerca in un settore bloccato.
  - *Entrare* in una zona con bufera/eruzione: `kLiveEnterWaitMinutes` (1) minuto di attesa per ogni azione extra.
  - *Azioni perse* (eruzione con te nella zona): `kLivePenaltyMinutes` (2) minuti per azione.
  - Durante un'attesa non si cerca, non si compra e non si prendono gli strumenti degli eventi. La **Clessidra** le azzera.
- **Collegamenti tra zone, Biglietto, Treno e Traghetto non esistono dal vivo** (ci si sposta a piedi).
- **Emporio**: dentro una zona è quello della zona (Hub = mercato centrale), fuori dalle zone resta quello delle palestre.
- **Nebbia**: il Radar non vede chi è (secondo il GPS) nella Giungla con la nebbia.

## Abilità dei Pokémon

Progetto completo (regole, tabella delle 54 abilità, note di bilanciamento) in [`abilita.md`](abilita.md). Le regole valgono
identiche al tavolo e dal vivo: l'unità è il **giro** (al tavolo una fase del giorno, dal vivo `roundMinutes` minuti), lo
stesso contatore (`state.round`) degli eventi di zona. Definizioni e regole in `lib/abilities.dart`, Firestore in
`lib/services/ability_service.dart`, interfaccia in `lib/widgets/abilities_card.dart`.

- **Ogni tipo ha 3 abilità**: 2 attive e 1 passiva (`kAbilities`, chiavi dei tipi come in `kTypes`, `Tipi` e
  `PkmTypePrim`/`PkmTypeSec`). **Riserva** (`abilityPool`): tipo singolo = le 3 del suo tipo; tipo doppio = le 6 dei due tipi.
  **Kit completo**: al massimo `kMaxActives` (2) attive e `kMaxPassives` (1) passiva.
- **Sblocco con i badge della partita.** A ogni palestra vinta per la prima volta **in questa partita** (capopalestra di zona
  al tavolo, palestra GPS dal vivo) la app estrae `kAbilityChoices` (2) abilità tra quelle ancora sbloccabili (rispettando il
  kit massimo) e il giocatore ne sceglie una; se ne resta una sola si sblocca subito. Il **tipo singolo** sceglie tra 2 al 1º
  badge e al 2º riceve insieme le due rimaste (`kMonoTypeFullKitBadges`); il tipo doppio completa il kit in 3 badge. Appena arriva
  il badge (anche alla fine della lotta col capopalestra) si apre il popup **Nuova abilità** (o **Hai sbloccato…**); se lo
  chiudi, la scheda resta in cima alla Home e alla tab Tavolo finché non scegli.
- **Badge della partita**: `Users/{uid}.gameBadges` (lista delle palestre vinte in questa partita), aggiornato alla vittoria su
  un capopalestra di zona o una palestra GPS. Si azzera a ogni avvio della partita (al tavolo "Nuova partita", dal vivo
  "Avvia/Riavvia la partita"), insieme a monete, tracce e stato delle abilità. `Users/{uid}.badges` resta lo storico.
- **Stato sul documento del Pokémon**: `abilities` (sbloccate), `abilityOffer` (le 2 in attesa di scelta), `abilityNotice`
  ("Hai sbloccato…"), `abilityOfferNext` (badge vinti con una scelta già in sospeso), `abilityUsedRound` (chiave → giro
  dell'ultimo uso), `abilityActiveUntil` / `abilityActiveKey` (effetto in corso).
- **Uso delle attive**: al tavolo costa 1 azione (passa da `actBlock` come le altre azioni, tipo `ability`), dal vivo un'attesa
  di `kLiveAbilityWaitMinutes` (1) minuto; quelle "di reazione" non costano nulla. Non si può usare se è in ricarica (giro
  attuale − ultimo uso < ricarica: 2, 4 o 8 giri), se un'altra attiva è ancora in corso o se ne hai già usata una in questo
  giro (`abilityBlock`).
- **Dove**: nella Home (tab Statistiche, subito sotto PS ed energie) la scheda **Abilità** con i bottoni delle attive (grigi
  con il motivo: "Pronta tra 2 giri", "Un'altra abilità è in corso"), le passive con il loro testo e gli slot vuoti
  ("Si sblocca con il prossimo badge"); al tavolo gli stessi bottoni anche nella scheda "La tua posizione". Icone provvisorie:
  quelle dei tipi.
- **Effetti delle abilità sulla mappa**: `Party/{codice}/sectorEffects/{id}` → `{kind, zone, sector, owner, untilRound,
  active}` (Gelata, Esca tossica, Rovi, Barricata, Sismo e gli altri effetti che gli altri devono "vedere"); si leggono negli
  stessi punti di trappole, allarmi e settori bloccati e si cancellano a ogni nuova partita.

### Abilità fuori dalla lotta (dove agiscono)

Gli effetti sono raggruppati per punto del codice. Chi usa l'abilità ne è sempre escluso; tutte rispettano rifugi e Repellente.
Al tavolo "+1 azione" si paga nello spostamento, dal vivo diventa `kLiveEnterWaitMinutes` minuti di attesa (`updateLivePos`).

| Dove | Abilità |
|---|---|
| **Spostamenti e ingressi** (`moveCost`, `blockedSectors`, `canReach`, `moveTo`, `updateLivePos`; regole in `Mobility`, `lib/abilities.dart`; cosa succede entrando in `AbilityService.onEnter`) | **Fiammata** (zona rovente: +1 azione entrando, non con la Tuta ignifuga), **Gelata** (+1 azione nel settore e avviso segreto al proprietario), **Barricata** e **Sismo** (settore bloccato per 1 giro; dal vivo lì non si cerca), **Rovi** (−2 PS, minimo 1, e traccia evidente), **Esca tossica** (il primo che entra è avvelenato: `currentStatus`), **Passo sicuro** (niente costo extra degli impervi), **Nuotatore** (settori sommersi), **Corazza** (frana e Sismo). Le passive **Sangue caldo** (Vulcano), **Nuotatore** (Isola), **Pelle spessa** (Neve), **Statico** e **Correnti ascensionali** (Colline), **Corazza** (Canyon) e **Fotosintesi** (nebbia della Giungla) valgono come una protezione di bioma permanente (`kPassiveImmuneZone`): costo di ingresso, settori bloccati, azioni perse, bonus di tipo, nebbia per il tuo Radar. |
| **Radar, Calmanella, Lente, Sensore** (`ItemService.radarScan`, `useBell`, `useLens`, `useSensor`, `weatherRows`) | **Impulso** (Radar sulla tua zona, senza strumento), **Svanire** (invisibile al Radar), **Depistaggio** (chi ti trova vede una zona a caso; dal vivo un punto falso a 100–400 m), **Sciame** (nella zona nessun altro usa Radar, Lente, Sensore, Impulso, Fiuto), **Ombra** (gli altri vedono solo la tua zona), **Mente lucida** (avviso segreto quando un Radar ti vede), **Fiuto** (Lente sul tuo settore, senza strumento), **Preveggenza** (Radar meteo senza strumento), **Ricognizione** (eventi e numero di giocatori per zona, senza nomi), **Vedetta** (avviso con il nome quando qualcuno entra nella tua zona). |
| **Tracce** (`ItemService.addTrace`, `moveTo`) | **Pioggia** (tracce della zona a forza 1 e per 1 giro niente bonus Fuoco degli eventi; dal vivo le tracce di ricerca ora hanno anche la zona), **Svanire** (nessuna traccia), **Correnti ascensionali** (il primo ingresso in una zona a ogni giro non lascia traccia: `Users/{uid}.updraftRound`), **Rovi** (traccia di forza 3, anche con il Passo felpato). |
| **Ricerca, strumenti, emporio, monete** | **Racimolare** (+3 monete), **Scavo** (50% di uno strumento, non è un "Cerca"), **Distrazione** (per 1 giro nel tuo settore gli altri non cercano indizi), **Forgia** (una ricetta con 1 solo ingrediente; per Pozione + Elisir scegli quale dare), **Fortuna** (25% di un secondo strumento uguale: Cerca, Scavo, indizio dichiarato, PvP, selvatici, eventi, leggendario, palestre; mai la MT; `ItemService.luckyDrops`), **Cliente abituale** (−1 moneta a ogni acquisto, si somma a Contrattare, minimo 1: `priceFor`), **Lega** (borsa da 14: `ItemService.bagLimit`), **Borseggio** (uno strumento a caso, MT esclusa, da un giocatore a caso nel tuo settore), **Benedizione** (+10 PS e niente status a te e a chi è nel tuo settore), **Idratazione**, **Sintesi**, **Fotosintesi** (+2 PS a ogni nuovo giro, tavolo e dal vivo). |
| **Trappole e Allarmi** | **Attraversamuri** (non scattano su di te, tavolo e dal vivo), **Sonda** (disattiva nel tuo settore Trappole, Allarmi, Gelata ed Esca tossica degli altri e dice di chi erano; dal vivo usa il settore GPS di ogni trappola). |
| **Sfide tra giocatori** | **Sfida** (lotta obbligata con un giocatore del tuo settore: `BattleService.createForcedBattle`, al bersaglio si apre il popup "Sei stato sfidato!"), **Imboscata** (chi entra nel tuo settore fa aprire il popup **Imboscata** con il bottone *Sfida*: non costa azioni, +2 al dado nel primo turno; `Users/{uid}.ambush`), **Ibernazione** (per 1 giro nessuna lotta tra giocatori per te, +5 PS), **Spavento** (il bersaglio perde 1 azione; dal vivo 2 minuti). |
| **Selvatici** | **Nido** (fuga gratis, 50% di strumento vincendo). |

Gli avvisi segreti (Gelata, Vedetta, Mente lucida, Imboscata, Borseggio, Spavento, Benedizione, Sfida) sono eventi
`Party/{codice}/events` con `type: 'notice'` e `to: [uid]`: compaiono a comparsa solo a chi sono destinati (`GameWatcher`).
Le schermate di movimento (pannello Movimento, mappa) usano la stessa `Mobility` dei servizi, così costi e settori bloccati
mostrati sono quelli veri; nei tuoi settori compare anche "✨ La tua Gelata è qui".

### Abilità in lotta

Quando la lotta parte davvero (`createGymBattle`, `joinBattle`, `createForcedBattle` in `battle_service.dart`) per ogni
giocatore si salvano sul combattente i **modificatori attivi** (`mods`, da `AbilityService.battleMods`): le passive che contano
in lotta, **Ardore** se è in corso e l'effetto "per la prossima lotta entro 2 giri", che lì **si consuma** (oppure scade dopo
2 giri). **Aura del drago** vale solo contro un altro giocatore: contro capipalestra, selvatici e leggendario non si consuma.
Il motore dei turni (`computeTurn`) li applica così (costanti in fondo a `lib/abilities.dart`):

| Abilità | In lotta |
|---|---|
| **Statico** (passiva) e **Aura del drago** | l'avversario parte con −2 energie (`applyStartMods`) |
| **Danza del drago** | +1 al dado per tutto lo scontro |
| **Sangue antico** (passiva) | +2 al dado contro il leggendario; +2 monete a ogni vittoria su un capopalestra |
| **Pugno di ferro** | il primo attacco andato a segno (Debole o Medio) conta come Forte |
| **Ardore** | per 2 giri le mosse Fuoco fanno +1 danno (in tutte le lotte) |
| **Riflessi** | la prima Schiva riesce anche contro un attacco imbloccabile |
| **Rinforzo** | il primo colpo subito è dimezzato anche senza Difesa |
| **Secrezione** | il primo attacco a segno avvelena sempre (Danno nel tempo) |
| **Incanto** | il primo status alterato che ricevi torna all'avversario |
| **Sangue caldo** (passiva) | il tuo Danno nel tempo dura 1 turno in più |
| **Immunità**, **Pelle spessa**, **Lega** (passive) | niente Danno nel tempo / Rallentamento / Debuff (anche quello portato da uno scontro precedente) |
| **Corazza** (passiva) | Difesa dà +2 energie in più (+5 invece di +3) |
| **Tenacia** (passiva) | dopo una sconfitta niente recupero: riparti subito con metà PS |
| **Imboscata** | chi tende l'imboscata ha +2 al dado nel primo turno (`firstTurnDice`) |

Gli effetti "la prima volta" segnano sul combattente `used_pugno`, `used_riflessi`, `used_secrezione`, `used_rinforzo`,
`used_incanto`. Tutto finisce nel resoconto del turno. Test: `test/battle_abilities_test.dart`.

### Abilità: scelte di implementazione (da confermare dopo le prime partite)

Dove `abilita.md` lasciava spazio a interpretazioni:
- chi usa un'abilità di settore o di zona non ne subisce gli effetti (Gelata, Fiammata, Barricata, Sismo, Rovi, Esca, Distrazione, Sciame);
- **Corazza** passa anche il **Sismo** ("bloccato come per la frana"); la **Chiave** non sblocca Barricata e Sismo;
- **Sciame** blocca anche **Impulso** e **Fiuto** (sono un Radar e una Lente senza strumento);
- **Distrazione** blocca solo "Cerca indizi": lo **Scavo** non è un "Cerca" e resta permesso;
- **Rovi** lascia la traccia evidente anche a chi ha il Passo felpato e non porta mai sotto 1 PS;
- **Esca tossica** non scatta su chi ha **Immunità** (resta per il prossimo);
- **Spavento** al tavolo ferma il bersaglio finché il gruppo non fa un'altra azione (con i turni: un'azione in meno al prossimo);
- **Rinforzo** dimezza il primo colpo anche se è imbloccabile; la **Schiva** continua a evitare sempre lo status, come prima;
- **Tenacia** dopo la sconfitta toglie anche lo status alterato;
- nessuna attiva ha il flag "di reazione": la reazione gratuita è il bottone *Sfida* dell'**Imboscata**;
- la **MT** resta legata al primo badge "storico" di quella palestra (`badges`, come lo strumento di oggi), lo sblocco delle
  abilità ai badge della partita (`gameBadges`);
- lo stato delle abilità si azzera con "Nuova partita" / "Avvia o Riavvia la partita" (anche dal vivo); "Rigenera
  capipalestra" nella schermata Palestre non lo tocca.

## Indizi sulla mappa (live e tavolo)

Tab **Party**, scheda "Indizi sulla mappa" (piazzamento, indizi trovati e dichiarati). La **ricerca** sta nella sezione dei movimenti:
tab **Tavolo > Mappa** (tavolo) oppure tab **Mappa** (dal vivo). Funziona uguale nelle due modalità; cambia solo il modo di indicare il luogo.

1. **Apertura (Master).** Chi ha `isMaster: true` preme "Apri il piazzamento degli indizi": a ogni giocatore viene assegnato a caso un
   **simbolo** (▲ ● ■ ◆ ★ ✚ ☾ ❖ ♥ ♣) e gli eventuali indizi precedenti vengono cancellati. Lo stesso succede da solo quando il
   Master **riavvia la partita**: tutti ridispongono i loro indizi e la ricerca riparte quando il Master chiude il piazzamento.
   Al primo avvio al tavolo deve rifarli solo chi li aveva messi in un bioma rimasto fuori dalla partita.
2. **Piazzamento.** Ogni giocatore sceglie a chi assegnare i suoi **3 indizi**, scrive il testo di ciascuno (max 90 caratteri) e
   li nasconde: al tavolo scegliendo zona e settore, dal vivo premendo "Piazza qui (GPS)" nel punto in cui si trova.
   Finché il piazzamento è aperto può modificarli ("Modifica" riparte da quelli già messi). Durante tutta la partita la scheda
   mostra a chi li ha piazzati testo, destinatario e **dove** li ha nascosti (zona e settore, o coordinate dal vivo). Gli indizi sono identificati da simbolo + numero (▲1, ▲2, ▲3), come le carte sul tavolo.
3. **Chiusura (Master).** "Chiudi il piazzamento e inizia" (avvisa se non tutti sono pronti).
4. **Ricerca.** "Cerca indizi qui": al tavolo cerca nel tuo settore e **costa 1 azione** (anche se non trovi nulla, e solo nel tuo turno),
   dal vivo entro **10 m** (`kClueRadiusMeters` in `lib/services/clue_service.dart`: il GPS sbaglia di qualche metro, se la ricerca
   fallisce spesso alzalo). Si trovano gli indizi di chiunque tranne i propri, non solo quelli destinati a te. Il testo lo vede solo chi trova.
5. **Dichiarazione e bonus.** Chi ha trovato un indizio può "dichiararlo" (al tavolo: dopo aver preso la carta). **Se l'indizio non era destinato a lui,
   riceve uno strumento a caso come bonus** (è il premio per il rischio di diventare un bersaglio). Gli indizi dichiarati compaiono a tutti
   come "Giocatore · ▲2", senza testo. Chi ha piazzato un indizio vede solo se è "Nascosto" o "Trovato", non da chi.

Limite: i testi degli indizi stanno nel database e la app li nasconde, ma un giocatore esperto potrebbe leggerli dalla console.
Per un gioco tra amici va bene.

Il vecchio sistema (numero del giocatore, numero assegnato, indovinello da sbloccare vincendo) è stato **rimosso**.

Dati: `Party/{codice}.cluePhase`, `Party/{codice}/clues/{id}`, `Party/{codice}/players/{uid}.symbol` e `.cluesReady`.

## Pubblicazione su GitHub Pages (come l'originale)

Il file `.github/workflows/deploy.yml` è già incluso: a ogni `git push` su `main` GitHub ricompila e pubblica il sito
(in Settings > Pages imposta Source = GitHub Actions). In alternativa, a mano:

```bash
flutter build web --release --base-href /companion2/
# copia il contenuto di build/web nella radice del repo companion2 (branch main) e fai push
```

## Struttura

```
lib/
  main.dart                       avvio Firebase + routing login/home
  firebase_options.dart           config web (progetto pokemoncompanion-cc8dc)
  constants.dart                  costanti di gioco, colori dei tipi, costi energia
  services/
    session.dart                  utente + Pokémon attivo
    party_service.dart            party, numeri, indizi, ricompensa
    battle_service.dart           creazione/ingresso battaglia + motore dei turni
    item_service.dart             inventario, effetti, trappole, Radar, Calmanella
    location_service.dart         posizione GPS
    gym_service.dart              generazione capipalestra, avvio, calibrazione, badge
  screens/
    login_screen.dart             Nome Utente + Pokémon
    create_character_screen.dart  crea giocatore e Pokémon (30 punti stat)
    moves_screen.dart             configurazione delle 2 mosse
    home_screen.dart              arco con le 3 tab + statistiche
    party_tab.dart                numero, assegna numero & indizio, indizi del party
    battle_tab.dart               lobby, attesa, arena
    settings_screen.dart          Gestione Party (Master), cambio party, colore
    inventory_screen.dart         zaino con gli 8 strumenti
    gyms_screen.dart              mappa, lista palestre, avvio gioco e calibrazione (Master)
  widgets/common.dart             icone tipo, immagini Pokémon, snackbar
  widgets/drop.dart               componenti grafici a goccia (DropCard, DropButton, HpBar...)
  theme.dart                      palette e tema chiaro
  widgets/game_status.dart        effetti attivi, osservatore trappole/Calmanella
  items.dart                      definizione e regole degli strumenti
  gyms.dart                       palestre, profili dei tipi, parametri
  widgets/badge_row.dart          badge delle palestre
  mode.dart                       modalità (tavolo/live), regole del tavolo e del live
  services/mode_service.dart      segue la modalità scelta dal Master per il party
  services/live_service.dart      zone GPS, settori, attese del live
  table/                          zone, settori e loro tipi (sectors.dart), eventi di zona, tabella dei tipi
  screens/table_map.dart          mappa a pulsanti del Tavolo e pannello dei settori
  services/table_service.dart     turni, spostamenti, eventi, leggendario
  services/clue_service.dart      indizi: piazzamento, ricerca, dichiarazione
  abilities.dart                  abilità dei Pokémon: le 54 definizioni e le regole (riserva, sblocco, ricariche)
  services/ability_service.dart   abilità: sblocco con i badge, scelta, uso, effetti di settore
  widgets/abilities_card.dart     finestra "Nuova abilità" e bottoni delle abilità
  widgets/game_popups.dart        popup di gioco (avvistamenti, priorità, sfide, cambio di fase, esito della lotta), fissabili
  widgets/clues_card.dart         scheda "Indizi sulla mappa" (tab Party)
  screens/table_tab.dart          tab Tavolo, barra dei turni, osservatore
  geo.dart                        distanza e direzione
assets/images/...                 sprite e icone originali
```

## Modello dati Firestore (invariato rispetto all'originale)

- `Users/{UserName}` → `{UserName, actualParty, parties[]}`
  - `Pokemon/{PokemonDocumentID}` → `PkmName, PkmTypePrim, PkmTypeSec, Atk, AtkSpec, Def, DefSpec, Vel, PkmLv, PkmExp, PkmInitialLife, PkmLife, Resistenze[], Debolezze[], Color`
    - `MoveSet/{MoveName}` → `MoveName, MoveType, MoveTypo (Fisico|Speciale), Dmg, Description, AltEffect (Rallentamento|Danno|Debuff), targetStat, AltDmg, AltStatusPerc, altStatus, altStatusName`
- `Tipi/{Tipo}` → `Resistenze[], Debolezze[], altStatus, altStatusName`
- `Party/{codice}` → `{riddleView}`; `players/{userId}` → `{userId, number, joinedAt, numberVisibility, assignedNumber, riddle, isMaster}`
- `Battles/{utente-xxx-HHmm}` → `status (pending|in_progress|playerA_win|playerB_win|draw), turn_number, playerA, playerB, last_turn_log, winnerUid, processing, rewardUnlocked`

## Regole di battaglia (come nel codice originale)

- PS: massimo 40. **I PS restano tra uno scontro e l'altro** (`currentHp` sul documento del Pokémon): si entra in
  battaglia con i PS con cui si è finito lo scontro precedente (anche dopo una fuga). Dopo una sconfitta il Pokémon è
  esausto a 0 PS e, finito il recupero (o con un Revitalizzante), riparte pieno. Pozione e Super Pozione curano anche
  fuori dalla battaglia, dalla Borsa. La home mostra i PS attuali. Capipalestra e leggendari partono sempre pieni.
- Partenza: 15 energie. Tiro d20 per ogni attacco; la statistica (Atk o AtkSpec) × 0,3
  abbassa le soglie: 1 = Nullo, poi Debole (+0), Medio (+2), Forte (+3), Forte e Imbloccabile (+3, ignora difesa/schivata).
- Danno = Dmg mossa + bonus categoria + modificatore elementale (+categoria se debolezza, −categoria se resistenza).
- Costo energia per Dmg 1..7: 1, 2, 4, 7, 9, 10, 11. Difesa: danno dimezzato e +3 energie. Schiva: evita i colpi non imbloccabili.
- Effetti (probabilità per Dmg ≤1: 0,8 · 2: 0,5 · 3: 0,35 · 4: 0,2 · ≥5: 0): Danno nel tempo, Rallentamento (Vel −2), Debuff (−1 a una stat).



## Grafica

Stile ispirato alle schede degli strumenti: sfondo chiaro, schede bianche con bordo sfumato, etichetta verticale a sinistra,
foglia/goccia all'angolo e pulsanti "a foglia" (angoli opposti arrotondati). Colori e font in `lib/theme.dart`;
componenti riutilizzabili in `lib/widgets/drop.dart` (`DropCard`, `DropButton`, `HpBar`, `EnergyDrops`, `InfoChip`, `SectionTitle`).
Per cambiare lo stile dell'intera app basta toccare questi due file.

**Etichette delle schede.** Nella home (Statistiche, Debolezze, Resistenze, Badge) l'etichetta sta in alto sopra il contenuto
(`DropCard(labelOnTop: true)`); nelle altre schermate resta verticale a sinistra (`labelOnTop: false`, il valore predefinito).

**Battaglia: come si capisce chi ha cliccato.** Ogni turno ha tre fasi sempre visibili:
1. *Scegli*: tocchi un'azione (mossa, Difesa, Schiva, Pozione). La scheda si evidenzia (bordo spesso, alone, spunta) e **sotto di
   essa si apre una piccola sezione con il pulsante "Conferma"**. Un secondo tocco sulla scheda la deseleziona. Non succede nulla
   finché non premi Conferma.
2. *Attesa*: dopo la conferma le altre opzioni si sbiadiscono, la tua resta evidenziata e la sezione sotto mostra "Scelta inviata"
   e se l'avversario ha già scelto. In alto due indicatori mostrano chi ha scelto.
3. *Risoluzione*: quando entrambi sono pronti compare "Risoluzione del turno…", poi il resoconto e le barre PS si animano.
Le mosse senza energia sono sbiadite con il motivo scritto.

**Battaglia: strisce in alto.** A inizio turno si vedono le schede grandi dei due combattenti; mentre scegli le mosse si
rimpiccioliscono e l'avversario diventa una **striscia fissata in alto** (resta visibile scorrendo: `BattleStripsHeader`,
`CombatantStrip` in `screens/battle_tab.dart`) con PS e l'effetto attivo (icona `assets/images/icons/buff.png` /
`debuff.png`). Il tuo Pokémon non ha una striscia: la barra in alto della Home diventa più spessa (`BattleSelfBar`) e mostra
PS, le tue energie e sotto il buff/debuff attivo. A fine lotta si apre il popup di **vittoria** o **sconfitta**. Caramella Rara e Fune di fuga restano a uso immediato.
La selezione non sposta le schede: il bordo ha spessore fisso e l'evidenziazione è un anello esterno (ombra), che non occupa spazio.

**Energia.** Ogni punto di energia è il glifo angolare `assets/images/energy_full.png` (pieno) o `energy_empty.png` (vuoto),
tinto del colore del tipo. Per cambiarlo basta sostituire quei due PNG (sfondo trasparente, forma nera); il widget è `EnergyPips` in `widgets/drop.dart`.

**Popup di gioco.** Gli eventi che chiedono una scelta o vanno notati si aprono come popup (`widgets/game_popups.dart`,
`GamePopupsWatcher`): "Ti hanno notato!" (Eludi / Fune di fuga / Resta allo scoperto), "Hai notato X!" (la priorità:
sfida, abilità, strumenti, lascia stare), "Sei stato sfidato!", Imboscata, cambio di fase del giorno (con gli eventi della
fase), vittoria o sconfitta, nuova abilità. Ogni popup ha **📌 Fissa sullo schermo**: resta come scheda in cima alla Home finché non la
togli (solo per questa sessione); "Chiudi" lo chiude e non si riapre. Al cambio di fase la scheda della fase precedente si
toglie da sola.

**Home.** Cinque pulsanti: Statistiche, Party, Battaglia, Borsa, Mappa.

## Strumenti (zaino)

Ogni giocatore parte con **tutti e 8 gli strumenti, 1 copia ciascuno** (`kStartingInventory` in `lib/items.dart`).
Gli utenti già esistenti ricevono la dotazione al primo accesso. La borsa è il tab **Borsa** della home.
Tutte le durate e i valori sono costanti in `lib/items.dart`.

| Strumento | Dove si usa | Effetto nella app |
|---|---|---|
| Repellente | zaino | per 10 min sei nascosto al Radar e non puoi creare/unirti a scontri né essere sfidato |
| Caramella Rara | battaglia, prima del 1º turno | +4 al dado del giocatore per tutto lo scontro (un 1 naturale resta "Nullo") |
| Fune di fuga | battaglia / quando sei in trappola | in battaglia: scontro chiuso subito, direzione casuale, le due squadre non possono riaffrontarsi per 10 min. In trappola: annulla il blocco |
| Trappola | zaino | piazzata nella tua posizione GPS; il primo altro giocatore entro 30 m viene bloccato 5 min (salvo Fune di fuga) |
| Pozione | battaglia | cura 10 PS al posto della mossa di quel turno (cura prima dei danni) |
| Calmanella | zaino | avvisa tutti i giocatori del party con distanza e direzione |
| Revitalizzante | zaino | annulla subito il recupero di 5 min dopo una sconfitta |
| Radar | zaino | elenca gli altri giocatori con distanza, direzione e "aggiornato X fa" (esclusi quelli con Repellente) |
| MT | borsa, fuori dalla lotta | sovrascrive una delle 2 mosse con una nuova (qualsiasi tipo, stesse regole della creazione); costa 1 azione al tavolo, dal vivo 1 minuto di attesa; si consuma solo al salvataggio. Solo come premio della prima vittoria su un capopalestra, massimo 1 in borsa, non si compra né si scambia |

Nuove regole introdotte per far funzionare gli strumenti:
- **Ogni giocatore è un "party"** (la squadra della scheda coincide con l'account).
- **Sconfitta = Pokémon esausto per 5 minuti** (non può combattere); il Revitalizzante lo cura subito.
- Il Radar mostra la posizione **al momento dell'uso**, non in tempo reale.

## Strumenti, monete ed Emporio (v8)

Tutte le regole numeriche sono in `lib/items.dart` (costanti `k...`).

**Borsa**: massimo `kBagLimit` (12) oggetti. Si parte con i primi 8 strumenti e `kStartingCoins` (5) monete. Se la borsa è piena un premio va perso (la app lo segnala).

| Categoria | Strumenti |
|---|---|
| Base | Repellente, Caramella Rara, Fune di fuga, Trappola, Pozione, Calmanella, Revitalizzante, Radar |
| Esplorazione | **Lente** (tracce: zone già battute e direzioni degli altri), **Sensore** (quanti indizi nascosti qui), **Allarme** (come la Trappola ma avvisa in segreto, non blocca), **Radar meteo** (eventi dei prossimi 2 giri), **Passo felpato** (ignora Trappole/Allarmi, nessuna traccia, invisibile al Radar), **Clessidra** (al tavolo agisci subito una volta, anche di fila; dal vivo azzera le attese), **Chiave** (sblocca un settore chiuso da frana/marea) |
| Battaglia | **Elisir** (+5 energie), **Super Pozione** (+20 PS), **Antidoto** (toglie DOT e malus), **Amuleto** (blocca il primo status, da dichiarare prima del 1º turno), **Guanto** (+2 danno per uno scontro, da dichiarare prima del 1º turno) |
| Mosse | **MT** (sovrascrive una mossa; solo premio dei capipalestra, vedi sotto) |
| Protezioni di bioma | Corda da scalata (Canyon), Bussola (Giungla), Tuta da neve (Regione innevata), Tuta ignifuga (Vulcano), Zattera (Isola), Parafulmine (Colline): per 2 giri annullano gli effetti dell'evento di quella zona (costo extra, settori bloccati, azioni perse, nebbia per il tuo Radar, bonus di tipo) |

Il Radar meteo sostituisce il Telescopio.

**Emporio** (al tavolo: bottone nella scheda "La tua posizione" della tab Tavolo; dal vivo: bottone nella Borsa)
- Tavolo: ogni zona ha il suo emporio (Pozione, Fune, Antidoto, Elisir, Sensore, **Biglietto** + la protezione del suo bioma); l'Hub è il mercato centrale con tutti gli strumenti. È aperto solo in un **settore cittadino**: fuori il bottone è grigio e dice in quale settore andare. Nella Borsa al tavolo resta solo il **Crafting**.
- Dal vivo: dentro una zona come al tavolo; fuori dalle zone si compra entro `kGymRadiusMeters` da una palestra (tutti gli strumenti tranne il Biglietto).
- Prezzi: `price` di ogni `ItemDef`.

**Come si ottengono**
- *Cerca* senza indizi: `kSearchItemChance` (15%) di trovare uno strumento.
- Dichiarare un indizio non tuo: strumento bonus + monete (`kCoinsDeclare`).
- Vittoria PvP: `kCoinsPvpWin` monete e `kPvpDropChance` di uno strumento. Primo badge di una palestra (capopalestra di zona o palestra GPS): `kCoinsGymWin` monete + la **MT** (se ne hai già una, uno strumento a caso come prima). Leggendario: 2 strumenti + `kCoinsLegendary`.
- Eventi Mercato/Raccolto (già presenti).
- **MT** (`ItemId.mt`, sprite `assets/images/items/mt.png`, icona Material finché manca): `ItemDef` senza prezzo con i flag
  `buyable: false` (niente emporio), `random: false` (esclusa da Cerca, Scavo, premi PvP, selvatici, eventi, leggendario,
  crafting e Fortuna), `tradable: false` (niente Scambia) e `maxInBag: 1`. Dalla Borsa apre `moves_screen.dart` in modalità
  "sostituisci una mossa": scegli quale delle 2 sovrascrivere e la ricrei; la MT (e l'azione) si consumano solo al salvataggio
  (`ItemService.replaceMoveWithTm`).
- **Scambi** tra giocatori dalla Borsa ("Scambia"): proposta con o senza richiesta in cambio; al tavolo bisogna essere nella stessa zona.
- **Crafting** (nell'Emporio, e al tavolo dal bottone Crafting della Borsa): 2 Pozioni → Super Pozione; 2 Caramelle → Guanto; Pozione + Elisir → Revitalizzante (`kRecipes`).
- Nuove partite al tavolo azzerano monete, protezioni e tracce.

**Tracce (per la Lente)**: ogni spostamento e ogni ricerca scrive un documento in `Party/{codice}/traces` (non lo fa chi ha il Passo felpato). Gli Allarmi stanno in `Party/{codice}/alarms`, gli scambi in `Party/{codice}/trades`.
Gli strumenti nuovi usano le icone Material finché non aggiungi gli sprite in `assets/images/items/<chiave>.png` (chiavi: lente, sensore, allarme, meteo, passoFelpato, clessidra, chiave, elisir, superPozione, antidoto, amuleto, guanto, corda, bussola, tutaNeve, tutaIgnifuga, zattera, parafulmine).

## Posizione (GPS)

Usata da Radar, Calmanella e Trappola. Funziona solo con l'app aperta in primo piano e viene salvata
su `Users/{uid}.location` ogni ~20 secondi.

- **Web:** serve HTTPS (GitHub Pages lo è); il browser chiede il permesso.
- **Android:** in `android/app/src/main/AndroidManifest.xml` aggiungi
  `<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>` e `ACCESS_COARSE_LOCATION`.
- **iOS:** in `ios/Runner/Info.plist` aggiungi `NSLocationWhenInUseUsageDescription` con un testo che spieghi l'uso.

## Regole Firestore da controllare

Le nuove funzioni scrivono in `Users/{uid}` (`inventory`, `location`, `repellentUntil`, `koUntil`, `trappedUntil`, `fleeBlocks`)
e nelle sotto-collezioni `Party/{codice}/traps` e `Party/{codice}/events`. Se le tue regole sono restrittive, vanno aperte
in lettura/scrittura per gli utenti del gioco, altrimenti vedrai errori di permessi.


## Palestre e capipalestra

Sei palestre (`kGyms` in `lib/gyms.dart`): Biblioteca (Normale), Giardini Estensi (Erba), Piazza Montegrappa (Acqua),
Piazza della Motta (Fuoco), Battistero (Volante), Tribunale (Roccia). Si trovano nel tab **Mappa** della home.

**Avvio del gioco.** Chi ha il ruolo di Master (`isMaster: true` sul suo documento in `Party/{codice}/players/`) vede nella
schermata Palestre la sezione "Avvio e calibrazione" e preme **Avvia il gioco**: per ogni palestra viene creato un capopalestra
casuale ma coerente con il tipo. Dopo l'avvio il Master gioca come tutti gli altri: non governa nulla.
Il pulsante diventa "Rigenera capipalestra" (nuovi Pokémon e mosse; posizioni calibrate e badge restano).

**Cosa viene generato** (profili in `kTypeProfiles`):
- allenatore e Pokémon pescati da liste del tipo (es. Roccia: Onix, Golem, Tyranitar...);
- 30 punti statistica distribuiti con pesi del tipo (Roccia = molta Difesa, Volante = molta Velocità, Fuoco = Attacco Speciale...);
- 2 mosse del tipo, una leggera (Dmg 1-3) e una forte (Dmg 3-5), con effetto alterato coerente (Fuoco = Danno nel tempo,
  Acqua/Volante = Rallentamento, Roccia/Erba = Debuff...);
- debolezze e resistenze dalla collezione `Tipi` (con valori di riserva per i 6 tipi).

**Come combatte.** Il capopalestra sceglie a ogni turno in modo casuale ma "in carattere": Volante schiva spesso, Roccia si
difende, Fuoco attacca quasi sempre. Se non ha energia per nessuna mossa si difende per recuperarla. Usa le stesse regole dei giocatori.

**Sfida.** Serve essere entro 50 m (`kGymRadiusMeters`). La vittoria dà il **badge** della palestra (una sola volta); la sconfitta
mette il Pokémon in recupero per 5 minuti come in ogni battaglia. Gli oggetti (Pozione, Caramella, Fune di fuga) valgono anche qui.

**Coordinate: da calibrare.** Non ho trovato coordinate affidabili online, quindi quelle in `kGyms` sono provvisorie.
Due modi per sistemarle: (1) sul posto, il Master preme **Imposta qui** accanto a ogni palestra; (2) sostituire i valori in
`kGyms` con quelli di Google Maps (tasto destro sul punto > coordinate). Le palestre non calibrate mostrano "Posizione provvisoria".
Nota: la Biblioteca (Via Sacco 9) è dentro Palazzo Estense, accanto ai Giardini Estensi: calibra i due punti ben distinti
(raggio 50 m ciascuno) oppure sposta la palestra Erba più in fondo al giardino.

**Prove da casa.** Imposta `kGymTestMode = true` in `lib/gyms.dart` per sfidare le palestre senza essere sul posto
(poi rimettilo a `false`).

**Mappa.** Usa OpenStreetMap (gratis) con il pacchetto `flutter_map`. I server delle tile pubblici di OSM vanno bene per un
gruppo di amici; per un uso più intenso la loro politica richiede un fornitore di tile dedicato.

Dati Firestore aggiunti: `Party/{codice}/gyms/{gymId}` (palestra + capopalestra), `Party/{codice}.gameStarted`,
`Users/{uid}.badges` (storico) e `Users/{uid}.gameBadges` (palestre vinte nella partita in corso, per le abilità), e nelle battaglie `npc`, `gymId`, `badgeEarned`.

## Differenze volute rispetto all'originale

- Un attacco con energia insufficiente ora **non** infligge danno (nell'originale veniva solo scritto nel log).
- Un tiro di 1 (Nullo) fa davvero 0 danni.
- Il numero del turno nel log parte da 1.

> Nota: il codice passa `flutter analyze` e `flutter build web`; il calcolo di zona e settore dal GPS ha un test
> (`flutter test`). Il gioco dal vivo va ancora provato sul campo.

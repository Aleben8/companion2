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
- **Turni.** All'avvio l'ordine è casuale. Ogni turno dà **2 azioni con un numero DISPARI di giocatori, 3 con un numero PARI**
  (`kActionsOdd`/`kActionsEven` in `lib/mode.dart`). Chi gioca usa "Ho usato un'azione" per le azioni fatte al tavolo e
  "Fine turno" per passare. Quando tutti hanno giocato il **giro** avanza. La barra in alto mostra giro, chi gioca e le azioni rimaste.
- **Posizione.** Dopo aver mosso la pedina sul tabellone, il giocatore la sposta anche sulla **mappa** della tab
  **Tavolo**: tocca la zona, sceglie il settore nel pannello che compare sotto e conferma con un solo bottone
  ("Vai: zona, settore N · costo"). Ogni spostamento costa 1 azione (`kMoveActionCost`). Le posizioni sono private: le altre
  si scoprono con il Radar. Al tavolo si gioca **al massimo in 9** (`kMaxTablePlayers`).
- **Schermata del Tavolo**, dall'alto: turno (azioni, "Fine turno"); le cose da risolvere subito (ti hanno notato, incontro
  selvatico, messaggio dei locali, avvistamenti); **La tua posizione**: zona e settore, gli eventi della tua zona (con "Prendi
  uno strumento" / "Sfida il leggendario"), poi **tutti i settori della zona**, ognuno con tipo, costo per andarci e stato
  (bloccato da un evento, leggendario, chi hai avvistato lì, dove hai già cercato, la tua traccia, i tuoi indizi, la tua
  Trappola o il tuo Allarme); toccandone uno ci vai ("Vai al settore N"). Sotto, cosa puoi fare nel tuo settore (Cerca
  indizi, Emporio se è cittadino). Poi **Altre zone** (la mappa a pulsanti) e in fondo gli strumenti del Master.
  Codice: `lib/screens/here_sectors.dart`.
- **Mappa.** Un pulsante per ogni zona in gioco, con le miniature dei suoi settori (icona del tipo e numero; settori
  bloccati barrati, ⚡ dove c'è il leggendario, bordo sul settore dove sei) e, sotto il nome, gli eventi della zona
  ("⚠️ Frana nel Canyon · ancora 2 giri", "🔜 In arrivo: …"). Sono **colorate** le zone dove puoi andare adesso
  (è il tuo turno, hai le azioni e, per Biglietto/treno/traghetto, sei nel settore di passaggio), **grigie** e non
  selezionabili le altre. Sul pulsante: "Tu", il costo in azioni oppure "Biglietto" / "Treno/traghetto", e un'icona per gli
  eventi in corso. Codice: `lib/screens/table_map.dart`, regola in `TableService.canReach`.
- **Minuti -> giri.** Repellente 2 giri, recupero dopo la sconfitta 1 giro, divieto di riaffrontarsi dopo una fuga 2 giri,
  Trappola = si salta il turno successivo (valori in `lib/items.dart`).
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
| **Rifugio** | A inizio turno chi è qui recupera 5 PS. Nessuno può sfidarlo a battaglia (né lui può combattere contro altri giocatori da qui); il Radar lo vede comunque. Locali: CD −1. |
| **Passaggio** | Da qui partono e qui arrivano Biglietto, treno e traghetto. Tracce: forza +1. |

### Furtività: entrare in un settore dove c'è qualcuno

Quando ti sposti in un settore dove ci sono altri giocatori la app tira **d20 + destrezza** contro una CD:

- **destrezza** = Velocità del tuo Pokémon attivo × 0,5 (per ora; poi potrà essere una statistica dedicata);
- **CD** = 10 + modificatore del settore + **percezione** del più attento nel settore (Difesa Speciale × 0,5, per ora);
- modificatori del settore: cittadino −2 (folla), selvaggio −1 e impervio −1 (ripari), rifugio +2, passaggio +1.

Se riesci non succede nulla (e non sai se c'era qualcuno). Se fallisci, chi è nel settore riceve **subito** l'avviso
"Hai notato X entrare nel tuo settore" (a comparsa e nella scheda **Avvistamenti** della tab Tavolo, che mostra questo giro e
il precedente), e a te compare la scheda **"Ti hanno notato!"**: non puoi muoverti né cercare finché non eludi, con **1 azione**
(se non ne hai, la perdi al turno dopo) o con una **Fune di fuga**. Con il Passo felpato attivo nessuno ti nota. Solo al tavolo. Costanti in `lib/table/sectors.dart` (`kStealthBaseCd`, `kDexterityMultiplier`,
`kPerceptionMultiplier`, `kEludeCost`), codice in `TableService._checkSpotted` / `elude`.

### Tracce e informazioni dai locali

- **Forza delle tracce.** Ogni spostamento e ogni ricerca lascia una traccia di forza 1–3: base 1, **+1 con la spunta "Lascia una traccia ben visibile"** (nel pannello di spostamento), più il modificatore del settore. La Lente vede una traccia per *forza × 2* giri e ne dice la forza (debole, chiara, evidente). Costanti in `lib/table/sectors.dart`.
- **Informazioni dai locali** (riquadro Master, a partita in corso, in **qualsiasi** settore; è l'unico bottone che resta
  fuori dagli strumenti del Master, che sono comprimibili). Il Master sceglie il giocatore: la finestra dice solo il
  **modificatore di CD** del settore (cittadino −2, rifugio −1, selvaggio 0, impervio +2, passaggio 0). Il tiro si fa al
  tavolo e il Master risponde "Sì" o "No" alla domanda "ha superato la CD?". Il racconto dei locali (chi è passato nella zona
  negli ultimi 3 giri con la forza della traccia, gli eventi in arrivo, se qualcuno ha nascosto indizi lì) lo vede **solo il
  giocatore**, in una scheda nella sua tab Tavolo: il Master, che gioca, non lo legge. Codice: `TableService.localsCheck` e
  `sendLocals` (salva su `Users/{uid}.localsInfo`).

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
Le mosse senza energia sono sbiadite con il motivo scritto. Caramella Rara e Fune di fuga restano a uso immediato.
La selezione non sposta le schede: il bordo ha spessore fisso e l'evidenziazione è un anello esterno (ombra), che non occupa spazio.

**Energia.** Ogni punto di energia è il glifo angolare `assets/images/energy_full.png` (pieno) o `energy_empty.png` (vuoto),
tinto del colore del tipo. Per cambiarlo basta sostituire quei due PNG (sfondo trasparente, forma nera); il widget è `EnergyPips` in `widgets/drop.dart`.

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
| Esplorazione | **Lente** (tracce: zone già battute e direzioni degli altri), **Sensore** (quanti indizi nascosti qui), **Allarme** (come la Trappola ma avvisa in segreto, non blocca), **Radar meteo** (eventi dei prossimi 2 giri), **Passo felpato** (ignora Trappole/Allarmi, nessuna traccia, invisibile al Radar), **Clessidra** (al tavolo azioni extra nel turno, dal vivo azzera le attese), **Chiave** (sblocca un settore chiuso da frana/marea) |
| Battaglia | **Elisir** (+5 energie), **Super Pozione** (+20 PS), **Antidoto** (toglie DOT e malus), **Amuleto** (blocca il primo status, da dichiarare prima del 1º turno), **Guanto** (+2 danno per uno scontro, da dichiarare prima del 1º turno) |
| Protezioni di bioma | Corda da scalata (Canyon), Bussola (Giungla), Tuta da neve (Regione innevata), Tuta ignifuga (Vulcano), Zattera (Isola), Parafulmine (Colline): per 2 giri annullano gli effetti dell'evento di quella zona (costo extra, settori bloccati, azioni perse, nebbia per il tuo Radar, bonus di tipo) |

Il Radar meteo sostituisce il Telescopio.

**Emporio** (al tavolo: bottone nella scheda "La tua posizione" della tab Tavolo; dal vivo: bottone nella Borsa)
- Tavolo: ogni zona ha il suo emporio (Pozione, Fune, Antidoto, Elisir, Sensore, **Biglietto** + la protezione del suo bioma); l'Hub è il mercato centrale con tutti gli strumenti. È aperto solo in un **settore cittadino**: fuori il bottone è grigio e dice in quale settore andare. Nella Borsa al tavolo resta solo il **Crafting**.
- Dal vivo: dentro una zona come al tavolo; fuori dalle zone si compra entro `kGymRadiusMeters` da una palestra (tutti gli strumenti tranne il Biglietto).
- Prezzi: `price` di ogni `ItemDef`.

**Come si ottengono**
- *Cerca* senza indizi: `kSearchItemChance` (15%) di trovare uno strumento.
- Dichiarare un indizio non tuo: strumento bonus + monete (`kCoinsDeclare`).
- Vittoria PvP: `kCoinsPvpWin` monete e `kPvpDropChance` di uno strumento. Primo badge di una palestra: `kCoinsGymWin` monete + 1 strumento. Leggendario: 2 strumenti + `kCoinsLegendary`.
- Eventi Mercato/Raccolto (già presenti).
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
`Users/{uid}.badges`, e nelle battaglie `npc`, `gymId`, `badgeEarned`.

## Differenze volute rispetto all'originale

- Un attacco con energia insufficiente ora **non** infligge danno (nell'originale veniva solo scritto nel log).
- Un tiro di 1 (Nullo) fa davvero 0 danni.
- Il numero del turno nel log parte da 1.

> Nota: il codice passa `flutter analyze` e `flutter build web`; il calcolo di zona e settore dal GPS ha un test
> (`flutter test`). Il gioco dal vivo va ancora provato sul campo.

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

- Partenza: 40 HP, 15 energie. Tiro d20 per ogni attacco; la statistica (Atk o AtkSpec) × 0,3
  abbassa le soglie: 1 = Nullo, poi Debole (+0), Medio (+2), Forte (+3), Forte e Imbloccabile (+3, ignora difesa/schivata).
- Danno = Dmg mossa + bonus categoria + modificatore elementale (+categoria se debolezza, −categoria se resistenza).
- Costo energia per Dmg 1..7: 1, 2, 4, 7, 9, 10, 11. Difesa: danno dimezzato e +3 energie. Schiva: evita i colpi non imbloccabili.
- Effetti (probabilità per Dmg ≤1: 0,8 · 2: 0,5 · 3: 0,35 · 4: 0,2 · ≥5: 0): Danno nel tempo, Rallentamento (Vel −2), Debuff (−1 a una stat).
- Il vincitore sblocca il proprio numero assegnato nel party `SecretBB` (costante `kRewardParty`).



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

## Strumenti (zaino)

Ogni giocatore parte con **tutti e 8 gli strumenti, 1 copia ciascuno** (`kStartingInventory` in `lib/items.dart`).
Gli utenti già esistenti ricevono la dotazione al primo accesso. Lo zaino si apre dall'icona in alto nella home.
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
Piazza della Motta (Fuoco), Battistero (Volante), Tribunale (Roccia). Si aprono dall'icona mappa nella home.

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
I badge compaiono nel profilo; nelle battaglie contro capipalestra non si sblocca il numero segreto.

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
- "Assegna numeri ai player" lavora sul party corrente (l'originale era fisso su `SecretBB`).
- Il numero del turno nel log parte da 1.

> Nota: questa versione non è stata compilata né provata (nell'ambiente di lavoro non c'è Flutter).
> Se `flutter analyze` segnala qualcosa, sono quasi certamente piccole correzioni di sintassi.

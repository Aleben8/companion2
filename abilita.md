# Zenitia — Abilità dei Pokémon (bozza di progettazione)

## 1. Schema comune (deciso)

- **Le abilità sono del Pokémon**, non del giocatore. Ogni giocatore ha un solo Pokémon per tutta la partita (non si cambia), quindi abilità e ricariche restano sempre le stesse.
- **Ogni tipo ha 3 abilità**: 2 attive (A e B) e 1 passiva.
- **Riserva del Pokémon**: le abilità dei suoi tipi.
  - **Tipo singolo**: le 2 attive e la passiva del suo tipo (3 abilità).
  - **Tipo doppio**: le attive e le passive di entrambi i tipi (4 attive e 2 passive).
- **Kit completo**: al massimo **2 attive e 1 passiva**.
- **Sblocco con i badge**: all'inizio della partita il Pokémon non ha abilità. A ogni palestra vinta la app **estrae a caso 2 abilità** tra quelle della riserva ancora sbloccabili e il giocatore **ne sceglie una**. "Sbloccabili" rispetta il kit massimo: con 2 attive già prese escono solo passive, con la passiva già presa escono solo attive. Se ne resta una sola, si sblocca quella.
  - **Tipo doppio**: kit completo in **3 badge** (un'abilità per badge).
  - **Tipo singolo**: kit completo in **2 badge**. Al 1º badge sceglie una delle 2 estratte, al 2º riceve **insieme** le due rimaste. Meno scelta, ma percorso garantito e più rapido (compensa la maggiore varietà del tipo doppio).
  - Dopo il kit completo i badge non danno più abilità.
  - Badge = capopalestra di zona al tavolo, palestra GPS dal vivo. Contano **solo i badge vinti nella partita in corso** (vedi note di implementazione).
- **Una sola attiva alla volta**: si usa al massimo un'attiva per giro e non se ne può usare un'altra finché l'effetto della precedente è ancora in corso (es. durante i 2 giri di Svanire). Ogni attiva ha la sua ricarica.
- **Attiva**: costa **1 azione** al tavolo (dal vivo un'attesa breve, come le altre azioni); le abilità "di reazione" non costano nulla. Dopo l'uso, la sua ricarica.
- **Passiva**: una volta sbloccata vale per tutto il resto della partita.
- **Stesse regole al tavolo e dal vivo.** L'unità comune è il **giro** (al tavolo = una fase del giorno, dal vivo = N minuti, `roundMinutes`). Le ricariche si contano in giri, non in azioni (dal vivo le azioni non esistono e al tavolo il numero di azioni per fase lo sceglie il Master). Si usano solo meccaniche che esistono in entrambi i giochi (zone, settori, eventi di zona, Radar, Trappole/Allarmi, tracce e Lente, ricerca, emporio, monete, PS/energie/status, lotta). Restano fuori furtività, collegamenti, Biglietto, regole "mai due volte di fila" e cambi di zona al giorno, che sono solo del tavolo; e niente abilità che spostano fisicamente un giocatore (dal vivo ci si muove a piedi).
- **Traduzione dal vivo**: "+1 azione" = `kLiveEnterWaitMinutes` (1) minuto di attesa; "perdi 1 azione" = `kLivePenaltyMinutes` (2) minuti; le durate in giri restano uguali.

### Ricariche delle attive (deciso)

Tre valori possibili: **2 giri** (mezza giornata), **4 giri** (1 giorno), **8 giri** (2 giorni). Ogni attiva ha un valore fisso, scritto nella tabella; il punto di partenza è "su di te 2, sugli altri 4, forti 8", poi corretto abilità per abilità in base alla forza (es. Ardore 4 perché a 2 si terrebbe sempre attiva; Sfida e Vedetta 2 perché da sole fanno poco; Sonda 8 perché disattiva anche le abilità di Ghiaccio e Veleno). Niente ricariche variabili: restano semplici da gestire.

## 2. Le abilità dei 18 tipi (prima stesura, da bilanciare)

Colonna **R** = ricarica in giri.

| Tipo | Attiva A | R | Attiva B | R | Passiva |
|---|---|---|---|---|---|
| **Normale** | **Racimolare**: ricevi subito 3 monete. | 2 | **Distrazione**: per 1 giro gli altri giocatori nel tuo settore non possono Cercare (indizi o strumenti). | 4 | **Cliente abituale**: all'emporio ogni acquisto costa 1 moneta in meno (minimo 1). |
| **Fuoco** | **Fiammata**: per 1 giro la tua zona è "rovente": chi ci entra paga +1 azione (non chi ha la Tuta ignifuga). | 8 | **Ardore**: per 2 giri le tue mosse di tipo Fuoco fanno +1 danno (come l'evento Vulcano). | 4 | **Sangue caldo**: gli effetti dell'evento Vulcano non ti toccano; in lotta il tuo Danno nel tempo dura 1 turno in più. |
| **Acqua** | **Pioggia**: tutte le tracce della tua zona tornano a forza 1 e per 1 giro il bonus Fuoco degli eventi lì è annullato. | 4 | **Idratazione**: subito +5 PS e via il tuo status alterato. | 4 | **Nuotatore**: entri nei settori sommersi dalla marea; gli effetti dell'evento Isola non ti toccano. |
| **Erba** | **Sintesi**: subito +10 PS e +3 energie (fuori dalla lotta). | 8 | **Rovi**: per 2 giri nel tuo settore: chi entra perde 2 PS e lascia una traccia evidente (forza 3). | 8 | **Fotosintesi**: a ogni nuovo giro +2 PS ovunque (si somma al rifugio); la nebbia della Giungla non acceca il tuo Radar. |
| **Elettro** | **Impulso**: come un Radar, ma solo sulla tua zona e senza consumare strumenti. | 4 | **Riflessi**: nella prossima lotta entro 2 giri la tua prima Schiva riesce anche contro un attacco imbloccabile. | 4 | **Statico**: gli effetti dell'evento Colline non ti toccano; chi lotta contro di te parte con −2 energie. |
| **Ghiaccio** | **Gelata**: per 2 giri il tuo settore è ghiacciato: chi ci entra paga +1 azione e tu ricevi un avviso segreto (come l'Allarme). | 8 | **Ibernazione**: per 1 giro nessuno può sfidarti (né tu puoi sfidare) e recuperi 5 PS, come in un rifugio. | 4 | **Pelle spessa**: la bufera della Regione innevata non ti tocca; in lotta il Rallentamento non ti colpisce. |
| **Lotta** | **Pugno di ferro**: nella prossima lotta entro 2 giri il primo attacco andato a segno conta almeno come Forte. | 2 | **Sfida**: un giocatore nel tuo settore deve lottare subito con te (non può rifiutare; non vale nei rifugi né contro chi ha il Repellente). | 2 | **Tenacia**: dopo una sconfitta non aspetti il recupero ma riparti con metà PS. |
| **Veleno** | **Esca tossica**: per 2 giri nel tuo settore: il primo altro giocatore che entra ha il Pokémon avvelenato (Danno nel tempo, `currentStatus`). | 4 | **Secrezione**: nella prossima lotta entro 2 giri il tuo primo attacco a segno avvelena sempre (Danno nel tempo), qualunque sia la mossa. | 8 | **Immunità**: il Danno nel tempo non ti colpisce. |
| **Terra** | **Scavo**: cerchi uno strumento nel tuo settore con il 50% di trovarlo (non cerca indizi, non vale come "Cerca"). | 2 | **Sismo**: per 1 giro un altro settore della tua zona, a scelta, è bloccato come per la frana (non quello del leggendario). | 8 | **Passo sicuro**: il costo extra dei settori impervi non ti riguarda. |
| **Volante** | **Ricognizione**: vedi in quali zone ci sono eventi in corso o annunciati e quanti giocatori ci sono in ogni zona (senza nomi). | 2 | **Vedetta**: per 2 giri ricevi un avviso segreto (con il nome) quando qualcuno entra nella tua zona. | 2 | **Correnti ascensionali**: gli effetti dell'evento Colline non ti toccano; il primo ingresso in una zona a ogni giro non lascia traccia. |
| **Psico** | **Preveggenza**: come un Radar meteo (eventi dei prossimi 2 giri), senza consumarlo. | 2 | **Depistaggio**: per 2 giri chi ti trova con Radar o Calmanella vede una zona a caso (dal vivo: distanza e direzione false). | 4 | **Mente lucida**: ricevi un avviso segreto quando qualcuno usa un Radar e ti vede. |
| **Coleottero** | **Fiuto**: leggi tutte le tracce del tuo settore come con la Lente, senza averla. | 2 | **Sciame**: per 1 giro nessuno nella tua zona (tranne te) può usare Radar, Lente o Sensore. | 8 | **Nido**: dagli incontri selvatici fuggi senza costo; vincendo, la probabilità di uno strumento sale al 50%. |
| **Roccia** | **Barricata**: per 1 giro il tuo settore è bloccato per gli altri (come la frana). | 4 | **Rinforzo**: nella prossima lotta entro 2 giri il primo colpo che subisci è dimezzato, senza dover usare Difesa. | 8 | **Corazza**: la frana del Canyon non ti blocca; in lotta Difesa ti dà +2 energie in più. |
| **Spettro** | **Svanire**: per 2 giri sei invisibile al Radar e non lasci tracce. | 2 | **Spavento**: un giocatore nel tuo settore perde 1 azione (dal vivo: 2 minuti di attesa). | 8 | **Attraversamuri**: Trappole e Allarmi non scattano su di te. |
| **Drago** | **Aura del drago**: nella prossima lotta contro un altro giocatore entro 2 giri l'avversario parte con −2 energie (non vale contro capipalestra, selvatici e leggendario). | 8 | **Danza del drago**: nella prossima lotta entro 2 giri +1 al dado per tutto lo scontro. | 8 | **Sangue antico**: +2 al dado contro il leggendario; le vittorie sui capipalestra danno +2 monete. |
| **Buio** | **Borseggio**: un giocatore a caso nel tuo settore ti passa uno strumento a caso (se non c'è nessuno, l'uso è perso). | 4 | **Imboscata**: per 2 giri, se qualcuno entra nel tuo settore puoi sfidarlo subito (avviso a te, non può rifiutare) con +2 al dado nel primo turno. Non vale nei rifugi né contro chi ha il Repellente. | 4 | **Ombra**: il Radar e la Calmanella degli altri mostrano solo la tua zona, non il settore né la distanza precisa. |
| **Acciaio** | **Forgia**: fai una ricetta di crafting con un solo ingrediente invece di due. | 2 | **Sonda**: disattivi nel tuo settore tutte le Trappole e gli Allarmi e gli effetti di Gelata ed Esca tossica, e scopri di chi erano. | 8 | **Lega**: la borsa contiene 2 oggetti in più (14); il Debuff non ti colpisce. |
| **Folletto** | **Benedizione**: tu e tutti i giocatori nel tuo settore recuperate 10 PS e perdete gli status alterati. | 4 | **Incanto**: nella prossima lotta entro 2 giri il primo status alterato che ricevi torna all'avversario. | 4 | **Fortuna**: quando trovi o vinci uno strumento, 25% di prenderne due (non vale per la MT). |

## 3. Strumento collegato: MT (deciso)

Strumento che permette di **sovrascrivere una delle 2 mosse** del Pokémon e crearne una nuova.

- **Come si ottiene: solo battendo un capopalestra per la prima volta** (capopalestra di zona al tavolo, palestra GPS dal vivo). Prende il posto dello strumento a caso che oggi dà il primo badge (le monete `kCoinsGymWin` restano).
- **Non si compra e non si trova**: niente emporio, Cerca, Scavo, vittorie PvP, selvatici, eventi, leggendario, crafting, Fortuna, Borseggio. Va esclusa da tutte le estrazioni a caso di strumenti.
- **È generica**: la nuova mossa può essere di qualsiasi tipo.
- **Limite: 1 MT in borsa.** Se ne hai già una quando batti un capopalestra, ricevi lo strumento a caso come prima.
- **Non si può scambiare.**
- **Come si usa**: dalla Borsa, fuori dalla lotta; costa 1 azione al tavolo (dal vivo un'attesa breve). Scegli quale mossa sovrascrivere e la ricrei con le stesse regole della creazione iniziale (`moves_screen.dart`: limiti su danno ed energia). Si consuma solo quando la nuova mossa è salvata: se annulli, la MT resta.

## 4. Note di bilanciamento

- Le attive che colpiscono gli altri (Fiammata, Gelata, Esca tossica, Barricata, Borseggio, Sfida, Imboscata, Spavento, Sismo, Rovi) sono le più forti nel gioco competitivo: tenerle sotto osservazione.
- Sfida ha ricarica breve (2 giri): da controllare che non diventi un modo per perseguitare un giocatore. Resta il limite dei rifugi e del Repellente.
- Buio è il tipo più difficile da usare (Borseggio e Imboscata richiedono qualcuno nel tuo settore), ma Ombra lo aiuta a non farsi trovare finché aspetta.
- Sonda (Acciaio) è la contromossa a Trappole, Allarmi, Gelata ed Esca tossica: per questo costa 8 giri.
- Aura del drago è stata indebolita (da −3 a −2 energie, solo contro altri giocatori) perché altrimenti diventa l'abilità da usare prima di ogni palestra.
- Diverse passive danno immunità all'evento della zona del tipo (Fuoco/Vulcano, Acqua/Isola, Ghiaccio/Neve, Roccia/Canyon, Elettro e Volante/Colline): sostituiscono di fatto la protezione di bioma per chi ce l'ha, quindi conviene che valgano solo per quell'evento.
- Le immunità agli status (Veleno, Ghiaccio, Acciaio) si sovrappongono all'Amuleto: va bene, l'Amuleto resta utile a tutti gli altri.
- Con lo sblocco a badge chi vince le palestre si rafforza ancora (abilità + MT): è voluto (premia chi gioca attivamente), ma va controllato che chi resta indietro abbia comunque modo di recuperare.

## 5. Note di implementazione (proposta)

- Definizioni in un nuovo `lib/abilities.dart` (`AbilityDef` con chiave, tipo, attiva/passiva, testo, ricarica in giri, durata dell'effetto in giri). Costanti: kit massimo `kMaxActives = 2`, `kMaxPassives = 1`; scelte offerte a ogni badge `kAbilityChoices = 2`; badge per il kit completo del tipo singolo `kMonoTypeFullKitBadges = 2`.
- **Badge della partita in corso**: `Users/{uid}.badges` oggi resta tra una partita e l'altra (e somma tavolo e dal vivo). Per lo sblocco serve un contatore che si azzera a "Nuova partita" insieme a monete e tracce, per esempio `Users/{uid}.gameBadges` (lista delle palestre vinte in questa partita), aggiornato quando si vince un capopalestra o una palestra GPS.
- Sul documento del Pokémon: `abilities` (chiavi sbloccate), `abilityOffer` (le 2 estratte in attesa di scelta, così la scelta sopravvive a una chiusura della app), `abilityUsedRound` per ogni attiva, `abilityActiveUntil` (giro di fine dell'effetto in corso, per la regola "una alla volta"). Anche questi si azzerano a "Nuova partita".
- Dopo la vittoria in palestra: finestra "Nuova abilità" con le 2 estratte (per il tipo singolo al 2º badge: "Hai sbloccato…" con le due rimaste); finché non scegli resta in cima alla Home / tab Tavolo.
- Imboscata: quando scatta, al giocatore di Buio arriva un avviso con il bottone *Sfida* (come "X è arrivato nel tuo settore" con *Ingaggia*).
- Gelata ed Esca tossica vanno salvate come effetti del settore con il proprietario (accanto a `traps` e `alarms`), così Sonda le trova e le toglie insieme a Trappole e Allarmi.
- Bottoni delle attive nella Home (accanto a PS ed energie) e nella scheda "La tua posizione" del Tavolo; grigi con il motivo se in ricarica ("Pronta tra 2 giri") o se un'altra è in corso. Gli slot vuoti dicono "Si sblocca con il prossimo badge".
- **MT**: nuovo `ItemDef` con chiave `mt` in `lib/items.dart`, senza `price` e con un flag (es. `noRandom: true`, `tradable: false`, `maxInBag: 1`) che lo esclude da emporio, estrazioni casuali e Scambia. Premio del primo badge in `gym_service.dart` / capipalestra del tavolo: MT se non ne hai già una, altrimenti strumento a caso. L'uso apre `moves_screen.dart` in modalità "sostituisci una mossa". Sprite in `assets/images/items/mt.png`.

## 6. Da decidere

- Bilanciamento numerico di ogni abilità dopo le prime partite di prova.

## 7. Idee per dopo (non ora)

- **Passiva potenziata per il tipo singolo**: al posto (o in aggiunta) dello sblocco veloce, una versione più forte della passiva del suo tipo. Più tematica, ma servono 18 descrizioni in più.
- **Abilità del giocatore** (generali, non legate al Pokémon). Rimandate per non appesantire il gioco. Il punto di partenza naturale sono destrezza e percezione della furtività, che oggi derivano dalle statistiche del Pokémon (Vel × 0,5, DefSpec × 0,5) e il README già prevede di trasformare in statistiche dedicate del giocatore.

# Ozzy Swing Timer

Projektbeskrivning och nuläge, uppdaterat 2026-10-31.

## Vad vi försöker bygga

Vi bygger en swing timer för hunters i World of Warcraft. Första spelversionen riktar sig till **TBC Classic Anniversary**. Målet är att senare anpassa addonen till **WoW Forever**, när vi kan testa där och verifiera dess mekanik och API.

Addonen ska hjälpa spelaren att känna rytmen mellan Auto Shot och sina andra förmågor. Det ska gå att förstå när man bör trycka, hur mycket plats en spell tar och om nästa förmåga får plats före nästa skott. Informationen ska kunna uppfattas med ett ögonkast, gärna i periferiseendet, utan att spelaren behöver läsa siffror hela tiden.

Utgångspunkten är en tidigare swing timer som gav bra taktkänsla genom en långsam rörelse i ena riktningen och en snabb rörelse tillbaka. Vi vill behålla den känslan och lägga till den information som saknades: spell cast, Global Cooldown, överlapp mellan cykler och ett tydligt köfönster.

Addonen är ett visuellt hjälpmedel. Spelaren trycker själv på sina förmågor. Automatisk casting finns bara i webbsimulatorn för att undersöka timing.

## Problemet vi vill lösa

En hunter behöver få sina förmågor att passa mellan Auto Shots. En spell kan vara färdigcastad samtidigt som dess Global Cooldown fortfarande pågår, eller tvärtom. En instant spell saknar casttid men kan ändå ta upp utrymme genom sin GCD.

Om en sen GCD fortsätter in i nästa cykel begränsar den när nästa spell kan börja. Haste och ändrad attack speed kan dessutom förändra hur mycket som får plats. En rotation som fungerar i ett läge kan därför komma ur takt i ett annat.

Vi vill synliggöra detta utan att göra gränssnittet svårt att läsa. Ambitionen är att spelaren ska kunna se när en cast och en instant får plats, när det bara finns utrymme för en förmåga och när man behöver avstå eller vänta en cykel.

## Tidsdelarna i vår modell

| Del | Betydelse i projektet |
| --- | --- |
| Weapon speed | Vapenintervallet mellan Auto Shots under ostörda förhållanden. Det är inte bara den långsamma delen av baren. |
| Weapon cooldown | Den långsamma väntedelen efter ett avfyrat Auto Shot och före nästa wind-up. I modellen är den vapenintervallet minus wind-up. |
| Auto Shot wind-up | Den snabba förberedelsefasen före avfyrningen. Dess exakta timing behöver verifieras i klienten. |
| Spell cast | Tiden då en förmåga faktiskt castas, exempelvis Steady Shot. |
| Global Cooldown, GCD | En separat spärr för nästa förmåga. Casttid och GCD kan överlappa och vara olika långa. |
| Action lock | Vår visuella gruppering av cast och GCD. Samtidiga tidsdelar räknas en gång; spärren gäller tills båda är färdiga. |
| Köfönster | Den del av wind-up där vår arbetsmodell säger att nästa cast kan förberedas när tidigare cast/GCD är klar. Serverns verkliga köbeteende är fortfarande en testfråga. |
| Clipping | Fördröjning av ett Auto Shot jämfört med när det annars skulle ha kunnat avfyras. |

Det är viktigt att skilja ett knapptryck eller en skickad castbegäran från faktisk caststart, Auto Shots avfyrning och projektilens träff. De tidpunkterna behöver inte sammanfalla.

## Gränssnittet vi har arbetat fram

Grunden är en pendelbar:

1. Under **Weapon cooldown** fylls baren långsamt från höger till vänster.
2. Under **Auto Shot wind-up** vänder den och fylls snabbt från vänster till höger.
3. Wind-up är **grön** när det är dags att trycka: Steady Shot köas till skottet och GCD börjar redan vid trycket, så GCD-tid tjänas in.
4. Wind-up är **röd** när spelaren är ur fas, alltså när cast eller GCD hänger kvar över wind-up. Då ska spelaren inte trycka utan låta ett orört Auto Shot gå för att komma i takt igen.
5. En **blå diagonal markering** visar hur mycket av Weapon cooldown som upptas av cast/GCD, så att spelaren grovt ser hur mycket tid som är kvar för en spell till. Om en spärr fortsätter in i nästa cykel visas den där också.

6. En **röd siffra till höger** om baren, till exempel **+0,8**, visar hur mycket det senaste Auto Shot försköts. Den syns bara när skottet faktiskt kom för sent.

Målet (2026-10-31): få plats med en Steady Shot och en instant i den långsamma fasen utan att Auto Shot skjuts upp. Om det får plats beror på vapnet och haste. Flashen och den turkosa ramen är borttagna (0.3.0); signalen ska gå att läsa i ögonvrån.

Spelversionen visar bara baren och förskjutningssiffran, utan fasnamn eller andra sekundvärden. Mer detaljerad information hör hemma i simulatorn eller diagnostiken.

## Vad vi har byggt hittills

### Webbsimulatorn

Vi började med en webbversion utan backend för att snabbt kunna prova och ändra modellen innan vi bygger färdigt addonen.

Simulatorn har separata tidsvisningar och en förhandsvisning av pendelbaren. Vi kan placera en cast och en instant i cykeln med reglage, ändra timingförutsättningar och se hur cast/GCD tar upp utrymme. Automatisk casting gör det möjligt att jämföra olika placeringar.

Vi har också lagt till förenklad skadesimulering med samma skada per Auto Shot och spell. Syftet är att jämföra timing, inte att beräkna en verklig hunters DPS. DPS och clipping visas per avslutad cykel. En valbar uppvärmning på tio träffar minskar påverkan från simuleringens startläge. Uppspelning kan köras upp till fem gånger snabbare, medan DPS räknas per simulerad sekund.

Simulatorn är en experimentmiljö. Dess antaganden är inte automatiskt bekräftad spelmekanik.

### Första TBC-addonen

Vi har nu skapat **Ozzy Swing Timer 0.1.0**, en fristående addonmapp för **TBC Classic Anniversary 2.5.6**, Interface 20506. Den använder WoW:s egna frames och texturer och behöver inga externa addonbibliotek.

Första versionen innehåller pendelbaren, cast/GCD-markering, köfönster och grön flash. Position, storlek och skala kan sparas. Det finns dragläge, låsning, ett visuellt testläge samt status och diagnostik via `/ozs`.

Skottens timing förankras i klientens rapporterade avfyrningar. Vapenintervallet läses från klienten, och casttid och GCD läses separat. Wind-up uppskattas först och kan sedan kalibreras från observerad skottstart och avfyrning. Addonen använder inte simulatorns fasta GCD-värde.

**20 automatiserade tester passerar** för tidsmodellen och händelsekopplingen med simulerade WoW-API:er.

### Första mätningarna i spelet (0.1.1–0.2.0)

Addonen har körts i TBC Anniversary med diagnostik och en testpanel (`/ozs panel`). Mätningarna finns i `docs/timing-design.md`. Kort sammanfattat:

- Vapenintervallet från klienten stämmer med uppmätta skott.
- Wind-up är cirka 0,36 s i median, inte 0,5 s, med brus på cirka ±0,1 s. Addonen lär sig nu medianen.
- Steady Shot som trycks under wind-up köas av klienten och startar exakt när Auto Shot avfyras. Skottet avbryts inte.
- Steady tryckt sent i den långsamma fasen kostar märkbart mer tid per cykel än Steady tryckt under wind-up.
- GCD-spellen 61304 rapporterar inget i denna klient. Version 0.2.0 läser GCD från Steady Shot i stället och bygger flashen på den observerade köningen. Detta är ännu inte provat i spelet.

## Vad vi fortfarande behöver ta reda på

- ~~Vad händer när man trycker Steady Shot under Auto Shots wind-up?~~ Casten köas till skottet (mätt i TBC 2.5.6). Kvar: börjar GCD tidigare än casten?
- Köas ett tryck även när GCD fortfarande pågår i början av wind-up? Hur påverkar latens och ett mindre SpellQueueWindow?
- ~~Vilka skottstartshändelser får vi pålitligt?~~ Start via stridsloggen, avfyrning via `UNIT_SPELLCAST_SUCCEEDED`; wind-up kan mätas med median.
- Hur påverkas vapenintervall, wind-up, casttid och GCD av olika haste- och attack speed-effekter?
- Kan en viss instantförmåga fördröja Auto Shot, och beror det då på GCD eller en separat regel för förmågan?
- Vilka förmågor återställer eller påverkar swingtimern på andra sätt?
- Vilka skillnader kräver en egen implementation för WoW Forever?

Arbetsmodellen låter GCD hindra nästa vanliga förmåga men inte Auto Shot i sig. Det är en utgångspunkt för testning, inte ett färdigverifierat svar för alla förmågor eller spelversioner. Den gröna flashen är en bekräftelse utifrån händelseordningen och garanterar inte att rotationen var optimal eller utan clipping.

## Nästa steg

1. ~~Installera addonen, testa ren Auto Shot och Steady Shot under wind-up.~~ Klart 2026-10-31.
2. Prova 0.2.0 i spelet: syns GCD i baren och kommer den gröna flashen när Steady köas till skottet?
3. Gör de tester som saknas: Steady i grön zon, rotation Steady + Arcane, Aimed Shot.
4. Mät GCD-start och GCD-längd relativt det köade trycket, och upprepa med haste.
5. Justera modellen efter observationerna och fortsätt iterera på gränssnittet.
6. Anpassa och verifiera Forever-versionen när den kan testas.

Vi räknar med att bygga om gränssnittet flera gånger. Pendelns rytm är grunden; hur extra information bäst visas ska utvecklas genom praktisk användning.

## Hitta i projektet

| Plats | Innehåll |
| --- | --- |
| `swing-lab/` | Webbprototyp och simulator. |
| `addon/OzzySwingTimer/` | Den kopierbara addonmappen för TBC Classic. |
| `addon/OzzySwingTimer/README.md` | Installation, kommandon och begränsningar för spelprototypen. |
| `addon/OzzySwingTimer/Model.lua` | Tidsmodell, cast/GCD-intervall och köbekräftelse. |
| `addon/OzzySwingTimer/Display.lua` | WoW-barens utseende och rörelse. |
| `addon/OzzySwingTimer/OzzySwingTimer.lua` | Koppling till WoW:s API och händelser, inställningar och diagnostik. |
| `addon/tests/run.lua` | Automatiserade tester med simulerade WoW-API:er. |
| `releases/OzzySwingTimer-0.1.0-TBC.zip` | Paketerad första addonversion. |
| `docs/timing-design.md` | Tidigare designanteckningar, hypoteser och källor kring timing. |
| `.diagnostics/` | Verktyg och underlag för lokal kontroll av prototyperna. |

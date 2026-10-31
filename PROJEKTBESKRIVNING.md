# Ozzy Swing Timer

Projektbeskrivning och nuläge, uppdaterat 2026-10-31. Projektet är pausat vid addon-version **0.12.0**.

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

6. En **siffra till höger** om baren, till exempel **+0,8**, visar hur mycket det senaste Auto Shot försköts. Den syns bara när skottet faktiskt kom för sent. **Gul** betyder att en extra spell orsakade det och att förskjutningen ligger under brytpunkten, alltså att den lönade sig. **Röd** betyder att den kostade DPS.

Målet (2026-10-31): få plats med en Steady Shot och en instant i den långsamma fasen utan att Auto Shot skjuts upp. Om det får plats beror på vapnet och haste. Flashen och den turkosa ramen är borttagna (0.3.0); signalen ska gå att läsa i ögonvrån.

Spelversionen visar baren, förskjutningssiffran i en svart bubbla med silverdrake, en castbar med spellnamn och en smal melee-swingtimer. Delarna kan flyttas var för sig. Mer detaljerad information hör hemma i simulatorn eller diagnostiken.

## Vad vi har byggt hittills

### Webbsimulatorn

Vi började med en webbversion utan backend för att snabbt kunna prova och ändra modellen innan vi bygger färdigt addonen.

Simulatorn har separata tidsvisningar och en förhandsvisning av pendelbaren. Vi kan placera en cast och en instant i cykeln med reglage, ändra timingförutsättningar och se hur cast/GCD tar upp utrymme. Automatisk casting gör det möjligt att jämföra olika placeringar.

Vi har också lagt till förenklad skadesimulering med samma skada per Auto Shot och spell. Syftet är att jämföra timing, inte att beräkna en verklig hunters DPS. DPS och clipping visas per avslutad cykel. En valbar uppvärmning på tio träffar minskar påverkan från simuleringens startläge. Uppspelning kan köras upp till fem gånger snabbare, medan DPS räknas per simulerad sekund.

Simulatorn är en experimentmiljö. Dess antaganden är inte automatiskt bekräftad spelmekanik.

### TBC-addonen (0.12.0)

En fristående addonmapp för **TBC Classic Anniversary 2.5.6**, Interface 20506. Den använder bara WoW:s egna frames och texturer och behöver inga externa addonbibliotek. Den har provats i spelet, även i en dungeon.

- **Huvudbaren** har castbarens ram (nio delar, tjocklek med `/ozs border`), gnista som markör och statusbar-textur. Guld för långsam fas, grön för tryck nu, röd för ur fas, grå för väntan före första skottet, blått för cast/GCD.
- **Auto Shot-bubblan** till höger visar förskjutningen: svart bubbla med silverdrake (`/ozs badge`), gul när en extra spell lönade sig (under brytpunkten, `/ozs breakeven`), röd när det kostade DPS. Off-GCD-spells som Kill Command räknas inte.
- **Castbar** i halv höjd med spellnamn och **melee-swingtimer** under huvudbaren.
- **Flyttbara delar** i upplåst läge, sparade relativt huvudbaren.
- **Data från klienten:** vapenintervall från `UnitRangedDamage`, wind-up som median av uppmätta skott, GCD från Steady Shot (61304 rapporterar inget), casttid från `UnitCastingInfo`.
- **Diagnostik och testpanel:** `/ozs debug on`, `/ozs mark`, `/ozs panel` med nio tester, egen skada per träff.

**30 automatiserade tester passerar** med simulerade WoW-API:er.

### Mätningar i spelet

Alla mätningar finns i `docs/timing-design.md`. Kort sammanfattat:

- Vapenintervallet från klienten stämmer. Hela cykeln är weapon speed; wind-up ingår i den.
- Wind-up är cirka 0,36 s i median, med brus på cirka ±0,1 s.
- Steady Shot som trycks under wind-up, eller strax före, köas till skottet. GCD börjar redan vid trycket.
- GCD är 1,5 s. Med 2,29 s cykel ryms högst 1,5 GCD-förmågor per cykel (Steady varje cykel, instant varannan).
- En handling som slutar inom cirka 0,4 s före wind-up verkar skjuta upp skottet 0,2–0,35 s (hypotes).
- Uppmätt skada: Auto Shot 632, Steady 561, Arcane 698. Brytpunkt för en Arcane cirka 1,3 s förskjutning.

## Vad vi fortfarande behöver ta reda på

- Bekräfta att en handling strax före wind-up skjuter upp skottet, och var gränsen går (fler cykler).
- Varför skickas en spell i långsam fas 0,15–0,47 s efter trycket? Testa utan makro.
- Brytpunkten bygger på 38 träffar; räkna om med fler fights (skadan loggas automatiskt).
- Hur påverkas vapenintervall, wind-up, casttid och GCD av haste-effekter utöver Quick Shots?
- Aimed Shot och andra förmågor som återställer swingtimern.
- Sitter silverdraken rätt? Dess position i texturen är uppskattad.
- Vilka skillnader kräver en egen implementation för WoW Forever?

## Nästa steg

1. Använda addonen i vanligt spel och notera vad som känns fel.
2. Mäta det som återstår ovan, med `/ozs panel` och `/ozs debug on`.
3. Eventuellt ett rotationsläge i simulatorn som växlar mellan cykler (Steady varje cykel, instant varannan).
4. Anpassa och verifiera Forever-versionen när den kan testas.

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

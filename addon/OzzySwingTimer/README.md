# Ozzy Swing Timer – TBC Classic 0.6.0

Första spelbara prototypen för **TBC Classic Anniversary 2.5.6**, Interface 20506.
Själva addonmappen kräver inga bibliotek eller andra addons.

## Installera

1. Kopiera hela mappen `OzzySwingTimer` till spelets `_anniversary_/Interface/AddOns/`.
2. Kontrollera att filen hamnar på `AddOns/OzzySwingTimer/OzzySwingTimer.toc` (ingen extra mellanliggande mapp).
3. Starta spelet och aktivera **Ozzy Swing Timer** i addonlistan. Logga in på din hunter.

Om du redan är inloggad: prova `/reload`. Starta om klienten om den nya mappen inte hittas.

## Första testet

- `/ozs test` visar en återkommande demonstration utan att kasta något. Samma kommando avslutar.
- `/ozs unlock` gör baren flyttbar med vänster musknapp. Positionen sparas.
- `/ozs lock` låser baren. Den döljs då när Auto Shot är avstängt.
- Skjut Auto Shot mot ett mål, och prova sedan Steady Shot under den snabba fasen.

Baren har en enda siffra, förskjutningen till höger:

- **Weapon cooldown:** långsam fyllning från höger till vänster.
- **Auto Shot wind-up, grön:** dags att trycka. Steady Shot köas till skottet, och dess GCD börjar redan vid trycket.
- **Auto Shot wind-up, röd:** ur fas. Cast eller GCD hänger kvar över wind-up. Tryck inget, låt ett orört Auto Shot gå för att komma i takt igen.
- **Siffra till höger, t.ex. +0,8:** hur många sekunder det senaste Auto Shot försköts jämfört med en ostörd cykel. **Gul** när en extra spell (allt utom Steady Shot som startar GCD, t.ex. Arcane) användes inom två cykler och förskjutningen är under brytpunkten (`/ozs breakeven`, standard 1,3 s): den lönade sig. **Röd** annars: den kostade DPS. Visas från 0,15 s, eftersom skotten varierar cirka ±0,1 s även utan clipping. Försvinner när ett skott kommer i tid.
- **Blå diagonal markering:** faktisk spell cast och GCD tillsammans. Överlapp räknas en gång; GCD som fortsätter in i nästa cykel visas där också.

## Kommandon

| Kommando | Funktion |
| --- | --- |
| `/ozs` | Visa hjälp |
| `/ozs size 300 20` | Bredd och höjd |
| `/ozs scale 1` | Skala 0.5–3 |
| `/ozs status` | Klientversion, skott, timing och GCD-status i chatten |
| `/ozs windup auto` | Uppskatta wind-up och lär från observerad skottstart |
| `/ozs windup 0.5` | Manuell wind-up i sekunder, vid kalibrering |
| `/ozs debug on` / `off` | Starta en ny logg med de senaste 1000 timinghändelserna / stäng av |
| `/ozs panel` | Visa/dölj testpanelen: nio tester med kort beskrivning, ny logg, spara, testläge, flytta/lås och status |
| `/ozs mark <text>` | Lägg en markering i loggen, t.ex. `/ozs mark steady tidigt` |
| `/ozs breakeven 1.3` | Brytpunkt i sekunder: hur mycket förskjutning en extra spell får kosta (gul siffra) |
| `/ozs reset` | Återställ storlek, position och automatisk wind-up |

Diagnostiken sparas när du loggar ut eller kör `/reload`, i klientens
`WTF/Account/<konto>/SavedVariables/OzzySwingTimer.lua`.
Den innehåller timing, spell-ID och din egen skada per träff (belopp, crit), inga målnamn
eller chattmeddelanden. Petens skada och missar/immunitet loggas inte.

## Vad som är observerat och uppskattat

Auto Shots avfyrning förankras i `UNIT_SPELLCAST_SUCCEEDED` för spell 75,
med `SPELL_CAST_SUCCESS` som alternativ. Projektilens skadehändelse används inte.
Vapenintervallet hämtas från `UnitRangedDamage`. Cast läses från `UnitCastingInfo`.
GCD läses som cooldown på en känd spell utan egen cooldown (Steady Shot, annars
Hunter's Mark eller Serpent Sting), eftersom GCD-spellen 61304 inte rapporterar
något i TBC 2.5.6. Simulatorns fasta GCD används inte.

Wind-up är en **prognos** tills klienten rapporterar en Auto Shot-caststart
och motsvarande avfyrning. Första uppskattningen är 0,5 sekunder, justerad med
`GetRangedHaste` om tillgängligt. Därefter används medianen av de senaste 9 uppmätta
wind-ups, skalad med vapentakten. I TBC 2.5.6 har den uppmätts till cirka 0,36 s.
Vapenbyte rensar inlärningen. `/ozs status` visar vilken källa som används.

Observerat i TBC 2.5.6 (SpellQueueWindow 400 ms): en Steady Shot som trycks under
wind-up hålls av klienten och skickas och startar exakt när Auto Shot avfyras.
Skottet avbryts inte, och GCD börjar vid trycket. Wind-up är grön när allt som
startade före wind-up (cast, GCD) är klart senast vid skottet. Ett tryck under en
GCD som hänger kvar över wind-up gav i ett mätfall en omstartad wind-up (0,95 s clipping).
Ett tryck upp till 0,4 s (SpellQueueWindow) före rapporterad wind-up räknas som köat och
ger inte rött: i mätningen köades Steady tryckt 0,03–0,16 s före wind-up till skottet.

GCD blockerar inte Auto Shot i modellen. Casts, rörelse och rapporterade misslyckade
skott hanteras separat. Om inget skott rapporteras startar ingen påhittad ny cykel.
Andra ranged-förmågor som återställer svingen behöver fortfarande testas särskilt.
Inga spells kastas automatiskt av addonen.

## Verifiering

Lua-modellen och händelsekopplingen testas med simulerade WoW-API:er i
`addon/tests/run.lua`. Skott, vapenintervall, wind-up och köning av Steady Shot
har mätts i spelklienten (se `docs/timing-design.md`), liksom GCD-läsningen och
GCD-start vid trycket (0.2.0). Testprotokollet finns i `/ozs panel`.
Forever-portningen kommer senare.

API-underlag: [Blizzards genererade Spell-API för Anniversary](https://github.com/Gethe/wow-ui-source/blob/classic_anniversary/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellDocumentation.lua)
och [cooldown-strukturen](https://github.com/Gethe/wow-ui-source/blob/classic_anniversary/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellSharedDocumentation.lua).
Händelsebeteende har jämförts med [WeaponSwingTimer för TBC](https://github.com/watchyoursixx/WeaponSwingTimer-SixxFix/blob/tbc-master/WeaponSwingTimer_Hunter.lua).
Ingen kod eller grafik från den addonen ingår här.

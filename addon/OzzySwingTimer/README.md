# Ozzy Swing Timer – TBC Classic 0.2.0

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

Baren innehåller inga texter eller sekundvärden:

- **Weapon cooldown:** långsam fyllning från höger till vänster.
- **Auto Shot wind-up:** snabb fyllning från vänster till höger. Röd före köfönstret, grön i fönstret.
- **Turkos ram:** köfönstrets del av wind-up.
- **Blå diagonal markering:** faktisk spell cast och GCD tillsammans. Överlapp räknas en gång; GCD som fortsätter in i nästa cykel visas där också.
- **Grön flash:** en cast som startar i samma ögonblick som Auto Shot avfyras, det vill säga ett tryck som köades under wind-up. En gång per skott.

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
| `/ozs panel` | Visa/dölj testpanelen med instruktioner och knappar |
| `/ozs mark <text>` | Lägg en markering i loggen, t.ex. `/ozs mark steady tidigt` |
| `/ozs reset` | Återställ storlek, position och automatisk wind-up |

Diagnostiken sparas när du loggar ut eller kör `/reload`, i klientens
`WTF/Account/<konto>/SavedVariables/OzzySwingTimer.lua`.
Den innehåller timing och spell-ID, inga målnamn eller chattmeddelanden.

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
Skottet avbryts inte. Flashen bekräftar just det: casten startade högst 0,1 s efter
avfyrningen. Köfönstret visar delen av wind-up efter aktuell cast/GCD; om ett tryck
före GCD:s slut också köas är ännu inte testat. En flash garanterar inte att
rotationen var optimal eller fri från clipping.

GCD blockerar inte Auto Shot i modellen. Casts, rörelse och rapporterade misslyckade
skott hanteras separat. Om inget skott rapporteras startar ingen påhittad ny cykel.
Andra ranged-förmågor som återställer svingen behöver fortfarande testas särskilt.
Inga spells kastas automatiskt av addonen.

## Verifiering

Lua-modellen och händelsekopplingen testas med simulerade WoW-API:er i
`addon/tests/run.lua`. Skott, vapenintervall, wind-up och köning av Steady Shot
har mätts i spelklienten (se `docs/timing-design.md`). GCD-läsningen och den nya
flash-regeln är ännu inte provade i spelet. Testprotokollet finns i `/ozs panel`.
Forever-portningen kommer senare.

API-underlag: [Blizzards genererade Spell-API för Anniversary](https://github.com/Gethe/wow-ui-source/blob/classic_anniversary/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellDocumentation.lua)
och [cooldown-strukturen](https://github.com/Gethe/wow-ui-source/blob/classic_anniversary/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellSharedDocumentation.lua).
Händelsebeteende har jämförts med [WeaponSwingTimer för TBC](https://github.com/watchyoursixx/WeaponSwingTimer-SixxFix/blob/tbc-master/WeaponSwingTimer_Hunter.lua).
Ingen kod eller grafik från den addonen ingår här.

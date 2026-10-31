# Ozzy Swing Timer – TBC Classic 0.1.0

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
- **Grön flash:** ett castförsök i köfönstret följt av nästa Auto Shot och en bekräftad caststart. Ett skickat eller misslyckat försök räcker inte.

## Kommandon

| Kommando | Funktion |
| --- | --- |
| `/ozs` | Visa hjälp |
| `/ozs size 300 20` | Bredd och höjd |
| `/ozs scale 1` | Skala 0.5–3 |
| `/ozs status` | Klientversion, skott, timing och GCD-status i chatten |
| `/ozs windup auto` | Uppskatta wind-up och lär från observerad skottstart |
| `/ozs windup 0.5` | Manuell wind-up i sekunder, vid kalibrering |
| `/ozs debug on` / `off` | Spara de senaste 200 timinghändelserna |
| `/ozs reset` | Återställ storlek, position och automatisk wind-up |

Diagnostiken sparas när du loggar ut eller kör `/reload`, i klientens
`WTF/Account/<konto>/SavedVariables/OzzySwingTimer.lua`.
Den innehåller timing och spell-ID, inga målnamn eller chattmeddelanden.

## Vad som är observerat och uppskattat

Auto Shots avfyrning förankras i `UNIT_SPELLCAST_SUCCEEDED` för spell 75,
med `SPELL_CAST_SUCCESS` som alternativ. Projektilens skadehändelse används inte.
Vapenintervallet hämtas från `UnitRangedDamage`. Cast och GCD läses separat
från klienten; simulatorns fasta GCD används inte.

Wind-up är en **prognos** tills klienten rapporterar en Auto Shot-caststart
och motsvarande avfyrning. Första uppskattningen är 0,5 sekunder, justerad med
`GetRangedHaste` om tillgängligt. Det kan avvika, exempelvis om en hastighetskälla
inte ingår i det värdet. En observerad wind-up används sedan och skalas med vapentakten.
Vapenbyte rensar inlärningen. `/ozs status` visar vilken källa som används.

Köfönstret visar delen av wind-up efter aktuell cast/GCD. Det är vår **arbetsmodell**,
inte ett bevis på när servern accepterar ett knapptryck. Addonen kan inte direkt läsa
serverns spellkö. Flashen är därför en efterhandsbekräftelse genom händelsernas ordning.
Om caststart sker före Auto Shots avfyrning väntar flashen på skottet.
Klientens SpellQueueWindow/latens kan begränsa möjligheten att köa tidigare i den gröna zonen.
En flash garanterar inte att rotationen var optimal eller fri från clipping.

GCD blockerar inte Auto Shot i modellen. Casts, rörelse och rapporterade misslyckade
skott hanteras separat. Om inget skott rapporteras startar ingen påhittad ny cykel.
Andra ranged-förmågor som återställer svingen behöver fortfarande testas särskilt.
Inga spells kastas automatiskt av addonen.

## Verifiering

Lua-modellen och händelsekopplingen testas med simulerade WoW-API:er i
`addon/tests/run.lua`. **Inte ännu verifierad i en körande spelklient.**
När du testar: kontrollera först ren Auto Shot, sedan Steady Shot under röd/grön fas,
en sen instant-GCD, rörelse och en haste-buff. Kör `/ozs debug on` om timingen avviker.
Exakt köbeteende och tidig GCD-start är fortsatt öppna frågor; Forever-portningen kommer senare.

API-underlag: [Blizzards genererade Spell-API för Anniversary](https://github.com/Gethe/wow-ui-source/blob/classic_anniversary/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellDocumentation.lua)
och [cooldown-strukturen](https://github.com/Gethe/wow-ui-source/blob/classic_anniversary/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellSharedDocumentation.lua).
Händelsebeteende har jämförts med [WeaponSwingTimer för TBC](https://github.com/watchyoursixx/WeaponSwingTimer-SixxFix/blob/tbc-master/WeaponSwingTimer_Hunter.lua).
Ingen kod eller grafik från den addonen ingår här.

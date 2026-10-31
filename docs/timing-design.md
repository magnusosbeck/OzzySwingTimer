# Ozzy Swingtimer: rytm och öppna mekanikfrågor

Dokumenterat 2026-10-31. Detta är en designanteckning och testplan, inte verifierade spelregler.

## Önskat GUI

Den primära rytmsignalen ska börja vid Auto Shots uppdragning (wind-up).
Användaren vill kunna känna skiftet till den snabba fasen och trycka där,
utan att behöva läsa en markör eller vänta tills vapenväntan börjar.

Målet är att hjälpa spelaren att trycka tidigt nog för att nästa förmåga ska
börja vid tidigaste tillåtna tillfälle. Ett senare tryck kan också fungera,
men får mindre marginal. Den del av uppdragningen där ett tryck faktiskt
accepteras måste verifieras per klient och förmåga.

En viktig användning är att passa in en förmåga med kasttid och därefter en
instantförmåga mellan Auto Shots. Både faktisk kasttid och GCD måste rymmas
enligt respektive klients regler. En instantförmåga saknar kasttid men kan
fortfarande kräva ledig GCD och påverka nästa tillgängliga handling.

GUI:t ska kunna använda samma rytmsignal även om klienternas köregler skiljer
sig. Signalen är en hjälp för knapptrycket; den är inte i sig bevis för att
en cast eller GCD har börjat.

## Öppen fråga: vad händer vid ett tryck under uppdragningen?

Status: **Delvis besvarad för TBC Anniversary 2.5.6: alternativ 1 stämmer med mätningen
(se Mätresultat nedan). Om GCD börjar tidigare (alternativ 2) är inte mätt, eftersom GCD
inte lästes under testet. Obesvarad för Forever.**

Håll isär dessa alternativ:

1. Förmågan köas. Casten och GCD börjar först efter Auto Shot-avfyrningen.
   Vinsten är att undvika spelarens reaktionstid efter avfyrningen.
2. Förmågan köas och casten börjar efter avfyrningen, men GCD börjar redan
   vid det accepterade knapptrycket. Det kan ge ett tidigare tillfälle för
   nästa förmåga utan att själva kasttiden förkortas.
3. Casten börjar faktiskt under uppdragningen och överlappar Auto Shot.
   Då kan mindre av kasttiden återstå när vapenväntan börjar.

Det kan även finnas avvisade knapptryck, begränsade köfönster och andra
förmågespecifika beteenden. Alternativen är hypoteser, inte universella regler.
Haste som ändrar kasttid ska skiljas från tidsvinst genom överlappning.
Förmågan behöver inte ha samma mekanik i TBC Classic och Forever.

## Mätresultat i TBC Anniversary 2.5.6, 2026-10-31

Mätt med addonens diagnostik (`/ozs debug on`) mot Azaloth, som inte slår tillbaka.
Klient 2.5.6 build 70577, latens 58–82 ms, SpellQueueWindow 400 ms, 200 FPS.
Tidpunkterna är klientens `GetTime()` när händelsen tas emot, inte serverns tid.
Spelaren trycker inte förmågorna direkt utan via makron. Varje makro innehåller även
pet-kommandon som pet attack och Kill Command. De räknas som instants utan GCD-påverkan
och bör inte påverka resultaten. Under testerna fanns ingen pet ute ("You do not have a pet").
Makrots Kill Command-fel ger dock en användbar tidsstämpel för själva knapptrycket.

**Händelser.** Auto Shots wind-up-start kommer bara som `SPELL_CAST_START` i stridsloggen,
avfyrningen som `UNIT_SPELLCAST_SUCCEEDED` (spell 75). `GetSpellCooldown(61304)` rapporterade
aldrig någon GCD; addonen läser nu GCD från en känd spell utan egen cooldown.

**Vapenintervall.** Medelintervall 2,31 s vid `UnitRangedDamage` 2,286 (9 skott) och 2,00 s
vid 1,988 (5 skott, Quick Shots). Klientens värde kan användas direkt.

**Wind-up.** Uppmätt start → avfyrning: median cirka 0,36–0,37 s i båda sessionerna,
spridning 0,25–0,49 s. Värdena klumpar sig kring cirka 0,32 och 0,42 s, och skottintervallen
hoppar med cirka ±0,08 s. Det tyder på att servern hanterar händelser i steg om cirka 0,1 s
(hypotes). Enskilda mätningar är därför brusiga; använd median.

**Tryck under wind-up (17 av 17 fall).** Steady Shot som trycks under wind-up skickas
(`UNIT_SPELLCAST_SENT`) och startar i samma bildruta som Auto Shot avfyras. Skottet avbryts
inte. Ibland rapporteras samtidigt "Another action is in progress" för Auto Shot, men
skottet går ändå. Steady Shot-casten tog cirka 1,15 s med denna haste.

**Kostnad per cykel** (medelintervall, jämfört med 2,31 s för ren Auto Shot):

| Fall | Medelintervall |
| --- | --- |
| Steady tryckt under wind-up | 2,35–2,40 s |
| Steady tryckt i långsam fas (0,2–1,3 s efter skott) | 2,52 s |
| Arcane Shot i långsam fas (5 tryck på 13 cykler) | 2,41 s |

En Steady Shot som startar vid skottet hinner bli klar före nästa wind-up. En sen Steady
fortsätter in i nästa wind-up och fördröjer skottet, som modellen förutsäger.
Under och efter en cast försöker Auto Shot igen ungefär var 0,5 s (`UNIT_SPELLCAST_FAILED_QUIET`),
vilket kan lägga till fördröjning efter castens slut. Arcane Shots effekt är för lite data.

**Rörelse.** Steg under cast eller wind-up gav "Interrupted" för både Steady Shot och Auto Shot.

### Andra mätomgången (addon 0.2.0), 2026-10-31

Samma klient och mål, latens 58–67 ms. GCD lästes nu från Steady Shot (34120).

**GCD är 1,5 s och startar vid trycket.** Alla 22 GCD-mätningar var exakt 1,50 s.
Tidpunkten sammanfaller med makrots Kill Command-fel, alltså själva knapptrycket.
Under wind-up startade GCD i snitt cirka 0,3 s (0,13–0,45 s) *före* skottet, medan
Steady Shot-casten startade vid skottet. Det motsvarar alternativ 2 ovan: casten köas,
men GCD löper redan från trycket. Ett tidigare tryck i wind-up ger alltså tidigare GCD-slut.
Även utanför wind-up kom `UNIT_SPELLCAST_SENT` 0,09–0,17 s efter GCD-starten; om det
beror på makrot är okänt.

**Steady i grön zon kostar ingenting mätbart.** Medelintervall 2,29 s (10 cykler),
samma som ren Auto Shot i samma session (2,29 s). Steady tryckt cirka 0,7 s efter skottet
gav 2,72 s.

**Flashen fungerade.** Alla 15 köade Steady Shots (startade vid skottet) gav flash.
Inga av de 5 som trycktes i långsam fas gav flash.

**Rotation Steady + instant.** När instanten (Arcane eller Multi-Shot) gick cirka
1,4–1,5 s efter skottet, direkt efter GCD, var cykeln 2,28–2,32 s, alltså utan förlust.
Multi-Shot hade cirka 0,39 s casttid. När Arcane gick sent (2,1 s efter skottet) blev
cykeln 2,77 s. I ett fall trycktes Steady under wind-up medan Arcanes GCD fortfarande
pågick. Då misslyckades Steady, Auto Shots wind-up startade om och cykeln blev 3,25 s.
Det är ett enda fall, men det stöder att den röda zonen (GCD inte klar) är verklig fara.

**Addonfel som rättades i 0.2.1.** Auto Shot rapporterar "Another action is in progress"
när man trycker under wind-up, men skottet går ändå. Addonen tolkade det som blockerat
och tappade wind-up-visningen. Det ignoreras nu under en observerad wind-up.

**Inte mätt än:** Aimed Shot (en tidigare logg visade cirka 2,2 s till nästa skottstart),
haste-effekter på GCD och wind-up, och tryck utan makro.

## Konsekvens för färgmarkering i simulatorn

Den önskade markeringen visar endast den del av faktisk eller förutsagd
spellcast som överlappar vapenväntan. Uppdragningen ska inte färgas av denna
markering. Vid överlappning över cykelgränsen visas den återstående casten
i nästa vapenväntan.

En köad cast förbrukar ingen kasttid medan den bara väntar i kön.
Tid under uppdragningen får därför bara räknas av om modellen uttryckligen
tillåter en pågående parallell cast, eller om spelmätningar bekräftar det.
En GCD-vinst får inte redovisas som minskad faktisk kasttid.

Det är ännu inte bestämt om markeringen ska vara en förhandsvisning från
sliderns position, en visualisering av pågående cast eller båda.
Denna anteckning ändrar inte simulatorns regler eller inför en ny GUI-vy.

## Mätplan

Registrera klientens exakta build, förmåga, effektiv attackhastighet,
effektiv kasttid, haste, latens, köinställning och använt makro/knapp.

Mät på samma tidsaxel:

- Knapptryck eller närmaste observerbara skickad castbegäran.
- Auto Shots verkliga uppdragningsstart, om tillgänglig; annars märk den som skattad.
- Auto Shots avfyrning, inte projektilens träff eller karaktärsanimationen.
- Spellens faktiska caststart, castslut, misslyckande eller avbrott.
- GCD-start och GCD-slut.
- Starten för en efterföljande instantförmåga och nästa Auto Shot.

Jämför tryck tidigt, mitt i och sent under uppdragningen samt direkt efter
avfyrningen. Börja med en förmåga och lägg därefter till en instantförmåga.
Testa först utan makro och därefter med relevant makro för att skilja
makroeffekter från grundläggande köning. Upprepa med olika haste och
köinställningar, flera gånger per fall.

Dokumentera observerade tidsdifferenser och mätosäkerhet. Ett addon kan inte
antas ha tillgång till den exakta servermottagningen av ett fysiskt knapptryck.
Bekräfta TBC Classic och Forever var för sig; historiska resultat är referenser.

## Källor från tidigare undersökning

### Spelarobservation och nya testfrågor, 2026-10-31

Användaren provade i TBC Classic och såg GCD bli klar före en cast som
uppfattades vara 1,5 sekunder. GCD verkade starta vid knapptrycket.
GCD:s exakta längd mättes inte, och klientbuild, förmåga, haste och köläge
är ännu inte dokumenterade. Observationen visar olika sluttidpunkter,
men bekräftar inte att grund-GCD är 1 sekund eller att GCD började före
caststart. Simulatorn använder nu 1 sekund som ändringsbart försöksvärde.

Öppen hypotes: kan en instantförmågas GCD i sig fördröja Auto Shot?
Skilj direkt GCD-blockering från förmågespecifik kasttid, återförsök,
makroeffekter och andra attackspärrar. Jämför Auto Shots avfyrning med
faktisk GCD-start/slut efter en instantförmåga, utan makro och rörelse.
Simulatorn antar tills vidare att GCD hindrar nästa vanliga förmåga men
inte Auto Shot i sig. En cast måste också vara klar innan nästa förmåga
kan börja även om dess GCD redan löpt ut.

- [Historisk TBC-forskning om köning och GCD](https://github.com/Schaka/TBC-research/issues/28)
  beskriver ursprungliga TBC och bekräftar inte dagens klient.
- [Analys av köning och GCD-skillnader](https://boukx.github.io/threetwo/)
  är en historisk communityanalys, inte verifiering av vår testbuild.
- [Forever: Shot Mechanics](https://github.com/classic-hunter/forever-hunter/wiki/Shot-Mechanics)
  och [Ability Mechanics](https://github.com/classic-hunter/forever-hunter/wiki/Ability-Mechanics)
  beskriver communityns observationer av kompatibla parallella ranged casts.
  Uppgifterna behöver verifieras mot den klient och förmåga som används.

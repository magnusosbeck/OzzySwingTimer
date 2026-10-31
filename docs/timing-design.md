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

Status: **OBESVARAD för den faktiska TBC Classic-klienten och separat för Forever.**

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

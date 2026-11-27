# Switching GuildEventManager on for your guild

[Deutsch weiter unten](#deutsch)

GuildEventManager stays silent until the guild leadership switches it on. Members can install it at any time; it sends nothing until the activation code is in the guild information.

## 1. Install

- Install **GuildEventManager** from CurseForge. The package contains three folders: `GuildEventManager` (core), `GuildEventManager_PvP` and `GuildEventManager_PvE` (raids). Keep all three.
- Every member who wants to take part needs the addon too. Members without it can still join events in the game, but cannot sign up in the addon and earn no honor.

## 2. Copy the activation code

1. Log in with the **guild master**.
2. Type `/gem` and click the **gear** at the top right.
3. Under **Activation** click **Activation code**.
4. A window shows a code such as `[GEM:1:a3f9]`. Press **Ctrl+C** (Mac: **Cmd+C**) to copy it.

## 3. Paste it into the guild information

1. Open the guild window and go to **Info**.
2. Click into the **guild information** and paste the code with **Ctrl+V** (Mac: **Cmd+V**). It can go anywhere – at the end of the text is fine.
3. Save.

Use the **guild information**, not the message of the day. Addons may read the guild information but not write it, so this step has to be done by hand. Besides the guild master, any rank with the right to edit the guild information can do it.

## 4. Check

- Click **Check again** in the settings. The box now says *"Active for ‹guild› · the code … is in the guild information."*
- Members who are online notice the code by themselves within about two minutes. `/reload` does it at once.
- The addon cannot read the guild information during combat; it reads it as soon as combat ends.

## 5. Set up the guild profile

Everything you set here reaches all members automatically – online members at once, the others when they log in.

- **Guild event managers:** the rank that may create and lead events, optionally all higher ranks too. Without a rank only the guild master can.
- **Raids** (gear → Raids): the lowest rank that may create and lead raids, for example a rank "Raid lead". Event managers always may.
- **Points**, **season length** and **active event types**: the defaults work; change them when you like. Members only see the event types that are active here.
- **Honor rules** (gear → Honor rules, PvP module): honor per kill, daily limits, bounties and so on.

## 6. Modules and areas

- **Modules** are separate addons (Fishing, Holidays, Management, Marketplace …). When the guild master or an event manager has a module installed, it counts as switched on for the guild – members get one notice with an info card and may say "not interested".
- **PvP and PvE parts:** some modules (Holidays) have PvP and PvE activities. They stay **locked until the guild master unlocks them**: gear → **Modules**, tick PvP and/or PvE. Nobody else can change this.

## 7. Guild organisation

- **Leadership:** gear → **Guild structure**. The guild master plus the ranks of the function "Leadership". Only the guild master changes who belongs to it.
- **Twinks:** members link their characters under gear → **My characters**; twinks count for the same person (GP, rankings, achievements). The leadership can link twinks of members without the addon.
- **Rank care:** gear → **Ranks** lists who should get which rank (twinks, inactive, bank). Addons cannot change ranks – a click opens Blizzard's guild window with the member, you pick the rank there.
- **Bank characters:** mark them in the guild structure. With the Marketplace module they report bags and bank when they log in.
- **Management module (optional):** member files (joined, probation, recruited by, notes – leadership only), activity of the last four weeks and promotion suggestions by your rules.

## Switching it off

Remove the code from the guild information. The addon then stops sending for the whole guild; members who are online notice it after `/reload` or when they log in next. Paste the code again to switch it back on – points and events are kept.

## Problems

| What you see | What to do |
|---|---|
| "Not activated yet" although the code is there | Is it in the **guild information** (not the message of the day) and saved? Then **Check again** or `/reload`. |
| A member sees nothing | Does he have the addon (all three folders)? `/reload`. `/gem status` shows whether it is active for him. |
| The settings show no code button | Only the guild master can create the code. |
| Anything else | `/gem errors` shows recorded errors; please report them on GitHub (link "Source" on CurseForge). |

---

<a name="deutsch"></a>
# GuildEventManager für die Gilde einschalten

GuildEventManager bleibt still, bis die Gildenleitung es einschaltet. Mitglieder können es jederzeit installieren; es sendet nichts, solange die Aktivierungskennung nicht in der Gildeninformation steht.

## 1. Installieren

- **GuildEventManager** über CurseForge installieren. Das Paket enthält drei Ordner: `GuildEventManager` (Kern), `GuildEventManager_PvP` und `GuildEventManager_PvE` (Raids). Alle drei behalten.
- Jedes Mitglied, das mitmachen will, braucht das Addon ebenfalls. Ohne Addon kann man im Spiel trotzdem an Events teilnehmen, sich aber nicht im Addon anmelden und bekommt keine Ehre.

## 2. Aktivierungskennung kopieren

1. Mit dem **Gildenmeister** einloggen.
2. `/gem` eingeben und oben rechts auf das **Zahnrad** klicken.
3. Unter **Aktivierung** auf **Aktivierungskennung** klicken.
4. Ein Fenster zeigt eine Kennung wie `[GEM:1:a3f9]`. Mit **Strg+C** (Mac: **Cmd+C**) kopieren.

## 3. In die Gildeninformation einfügen

1. Das Gildenfenster öffnen und zu **Info** wechseln.
2. In die **Gildeninformation** klicken und die Kennung mit **Strg+V** (Mac: **Cmd+V**) einfügen. Die Stelle ist egal, am Ende des Textes passt gut.
3. Speichern.

Es muss die **Gildeninformation** sein, nicht die Nachricht des Tages. Addons dürfen die Gildeninformation lesen, aber nicht schreiben – deshalb geht dieser Schritt nur von Hand. Außer dem Gildenmeister kann das jeder Rang, der die Gildeninformation bearbeiten darf.

## 4. Prüfen

- In den Einstellungen auf **Erneut prüfen** klicken. Im Kasten steht jetzt *„Aktiv für ‹Gilde› · die Kennung … steht in der Gildeninformation.“*
- Mitglieder, die gerade online sind, bemerken die Kennung von selbst innerhalb von etwa zwei Minuten. Mit `/reload` sofort.
- Im Kampf kann das Addon die Gildeninformation nicht lesen; es liest sie, sobald der Kampf vorbei ist.

## 5. Gildenprofil einstellen

Alles, was du hier einstellst, kommt automatisch bei allen Mitgliedern an – bei denen, die online sind, sofort, bei den anderen beim nächsten Login.

- **Gildenevent-Manager:** der Rang, der Events anlegen und leiten darf, wahlweise mit allen höheren Rängen. Ohne Rang darf das nur der Gildenmeister.
- **Raids** (Zahnrad → Raids): der niedrigste Rang, der Raids anlegen und leiten darf, zum Beispiel ein Rang „Raidleitung“. Event-Manager dürfen es immer.
- **Punkte**, **Season-Länge** und **aktive Event-Typen**: Die Vorgaben passen; ändern, wenn du willst. Mitglieder sehen nur die Event-Typen, die hier aktiv sind.
- **Ehre-Regeln** (Zahnrad → Ehre-Regeln, PvP-Modul): Ehre pro Sieg, Tageslimits, Kopfgelder und mehr.

## 6. Module und Bereiche

- **Module** sind eigene Addons (Angeln, Feiertage, Verwaltung, Gildenmarkt …). Hat der Gildenmeister oder ein Event-Leiter ein Modul installiert, gilt es für die Gilde als eingeschaltet – Mitglieder bekommen einen Hinweis mit Infokarte und können „Interessiert mich nicht“ wählen.
- **PvP- und PvE-Teile:** Manche Module (Feiertage) haben PvP- und PvE-Aktivitäten. Die bleiben **gesperrt, bis der Gildenmeister sie freischaltet**: Zahnrad → **Module**, PvP und/oder PvE anhaken. Niemand sonst kann das ändern.

## 7. Gildenorganisation

- **Gildenleitung:** Zahnrad → **Gildenstruktur**. Der Gildenmeister plus die Ränge der Funktion „Leitung“. Wer dazugehört, ändert nur der Gildenmeister.
- **Twinks:** Mitglieder verbinden ihre Charaktere unter Zahnrad → **Meine Charaktere**; Twinks zählen für dieselbe Person (GP, Ranglisten, Erfolge). Die Leitung kann Twinks von Mitgliedern ohne Addon zuordnen.
- **Rangpflege:** Zahnrad → **Ränge** zeigt, wer welchen Rang bekommen sollte (Twinks, Inaktive, Bank). Addons können Ränge nicht ändern – ein Klick öffnet Blizzards Gildenfenster mit dem Mitglied, dort wählst du den Rang.
- **Bankcharaktere:** in der Gildenstruktur markieren. Mit dem Modul Gildenmarkt melden sie Taschen und Bank beim Einloggen.
- **Modul Verwaltung (optional):** Mitgliederakten (Beitritt, Probezeit, geworben von, Notizen – nur Leitung), Aktivität der letzten vier Wochen und Beförderungsvorschläge nach euren Regeln.

## Ausschalten

Die Kennung aus der Gildeninformation entfernen. Dann sendet das Addon für die ganze Gilde nichts mehr; Mitglieder, die online sind, merken es nach `/reload` oder beim nächsten Login. Kennung wieder einfügen, und das Addon ist wieder an – Punkte und Events bleiben erhalten.

## Probleme

| Was du siehst | Was zu tun ist |
|---|---|
| „Noch nicht aktiviert“, obwohl die Kennung drinsteht | Steht sie in der **Gildeninformation** (nicht in der Nachricht des Tages) und ist gespeichert? Dann **Erneut prüfen** oder `/reload`. |
| Ein Mitglied sieht nichts | Hat es das Addon (alle drei Ordner)? `/reload`. `/gem status` zeigt, ob es bei ihm aktiv ist. |
| In den Einstellungen fehlt der Knopf für die Kennung | Nur der Gildenmeister kann die Kennung erzeugen. |
| Etwas anderes | `/gem errors` zeigt aufgezeichnete Fehler; bitte auf GitHub melden (Link „Source“ auf CurseForge). |

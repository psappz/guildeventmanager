# Security and trust in GuildEventManager

GuildEventManager has no server. Every client keeps the same data and checks every message it gets. This page says who may change what, and how a client checks it.

## Who is heard at all

- **Only guild members.** Messages from senders who are not in the guild roster are ignored on every channel (guild, officer, whisper).
- **Only in an activated guild.** Nothing is sent before the guild master has put the activation code into the guild information.
- **Officer channel** (`API.SendOfficer`): only ranks that may read the officer chat get these messages. Leadership data (member files of the Management module, link requests of twinks) travel there.

## Guild profile

The guild profile holds the settings of the guild (points, rules, event types, modules, holidays …). It is versioned; the newest version wins.

| Who | May change |
|---|---|
| Guild master | everything |
| Event managers / leadership | the profile, **except**: the rank with event rights, "higher ranks too", the raid rank, the GP cap per entry, the guild leadership, and the **areas of modules** (PvP/PvE unlock) |

A client that receives a profile from someone other than the guild master with a change to one of these fields **drops the whole profile**. The guild master's own client undoes such a change locally as well.

## Points (GP)

- **Every client books only its own deeds** (`API.ReportOwn`). Event managers book points for others (`API.AwardPoints`, results of an event).
- **Cap per entry** for managers (default 100 GP); more needs the guild master – requests go to him over the officer channel. Every entry is in the ledger with who booked it; managers can strike entries, and the review page lists unusual ones.

## Contests and duels

- **Scores are self-reported**: every client counts only its own score and sends it. The event leader is the referee and sends the final result; he can strike outliers.
- A score that arrives **after counting ended** is ignored (places stand as at the moment of the win).
- **Duels the addon cannot follow** (results by hand): one side reports, the other side or an event leader confirms. Reports from anyone who did not take part are ignored.
- **Snowball duels:** both clients count their own throws at the opponent and exchange the counts at the end. A count is accepted only from the opponent of that duel and never above the agreed number of snowballs.

## Persons and twinks

- A link main ↔ twink is sent only by the player himself; a twink may change an existing link only if the link already contains it. Links set by the leadership come only from managers, and what the player sets himself wins.

## Modules

- **Management:** member files are accepted only from the leadership (guild master, ranks of the function "lead", managers) and travel over the officer channel. Voluntary details are accepted only from the member they belong to.
- **Marketplace:** the guild bank can be reported by any member who opened it (with date and name); a bank character reports only itself and only if it is marked as bank character.

## What the addon cannot prevent

An addon can be modified. Self-reported values (scores, own deeds) can therefore be faked by someone who changes the code. That is why referees and witnesses exist, why everything is in the ledger with its author, and why managers can strike entries.

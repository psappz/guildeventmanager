# GuildEventManager 0.9.0

### New
- **Person instead of character:** main and twinks count as one person – GP, rankings, achievements and the PvP season. Settings → My characters; visibility for the guild, the leadership only, or nobody.
- **Guild organisation:** members list with functions, organisation chart, guild structure (ranks and functions, leadership), rank care (opens Blizzard's guild window), inactive and purge per person, bank characters, "view as rank" for the guild master.
- **Guild achievements and trophies:** 36 guild achievements (core, PvP, raids) in bronze, silver, gold and legendary; trophy wall on the banner page; modules can add their own.
- **Events:** recurring events, calendar in the side bar, event leader settings per event type, "How it works" cards, own reminders with a checklist, several event leaders (officers and the leadership may lead every event).
- **Contests:** live standings, shared places, referee results, big announcements, teams (draw, balanced or by hand), shared goal, "report end".
- **Modules of the guild:** catalogue with info cards, "not interested", notice when the guild runs a newer version. PvP and PvE parts of a module are unlocked by the guild master only.
- **Holidays** (core): modules bring holidays with dates the guild can move; their event types can be created from two weeks before.
- **Bounties:** WANTED posters, carousel on the overview, note up to 200 characters, own sounds.
- **GP:** guild points instead of "honor"; officers can add GP with a cap per entry, requests to the guild master, review page.
- **Deeds (GP like legacy points):** 2–5 characters at level 60 with both main professions at 300, double agent (60 on both factions, PvE realms), gold deposits into the guild bank (10 / 100 / 500 / 1000 / 2500 g, 1 g = 1 GP), "Softcore" on the first death (-1 GP, the guild sees it), first and second of every class to level 60 in the guild (50 / 1 GP).
- **API 7** for module authors (see docs/MODULES.md, section 6).

### New modules (separate downloads, published with 1.0)
- **GuildEventManager Fishing:** guild scoring at the Stranglethorn tournament, own fishing contest, fishing PvP teams, Anglergeddon.
- **GuildEventManager Holidays:** Winter Veil (gift giving, Secret Santa, snowball fight, snowball duels, Greench hunt), Lunar Festival (elder rally, meeting), Love is in the Air (guild ball).
- **GuildEventManager Management:** member files, activity of the last four weeks, promotion suggestions, voluntary details.
- **GuildEventManager Marketplace:** who can make what, gaps of the guild, guild stock from guild bank and bank characters.

### Changed
- Saved data no longer depends on the realm (`Name@EU`); old spellings are merged.
- Settings are grouped in the side bar and open with the gear.

### Fixed
- A score that arrives after a contest ended no longer changes the places.

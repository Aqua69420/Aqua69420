# Las Vegas – full roadmap (everything we've planned)

## Already done
- v236 saving fix ($50M floor for aquagaming22, safe loads, 1-min autosave)
- v237 gang hits (shivs, ambushes); killed in prison = full reset
- v238 Facility Mapper plugin; v238b no sitting while a CO walks you

---
## A. Arrest & custody rework
- **v239 Custody pipeline core** – stages Arrest → Transport → Station → Detention → Court → Serving → Release, each owns its respawn (fixes the intake respawn / escort bugs for good)
- **v240 Multi-building** – game reads your HQ, courthouse, city jail, bank, law office maps
- **v241 Arrest scene** – comply or resist, frisk, property seized, Miranda, into the car; routing: minor → HQ, serious → HQ then detention, escapee → straight to prison, crime inside → solitary; hook for the Premier lawyer showing up
- **v242 HQ processing & records** – booking desk, mugshot, holding, citations, court dates, turn yourself in, permanent criminal + court record, DAVID data (licence, address, cars), licences that get suspended
- **v243 City jail** – sentences under 30 min served there, day room, release door, transfer holding
- **v244 Prison bus** – city jail → prison, as needed (after a short wait for others) and at least every 30 min, 12–16 prisoners (players + real busted peds + filler), gates, unload line, batch intake, overflow then long-term holding, bigger livelier prison population
- **v245 Guard towers & vision** – tower snipers, sweeping spotlights, kill zone (shoot) / perimeter (warn, then shoot), alarm + lockdown; police vision cones fixed (narrower, tiny all-round bubble, radio makes them turn not see, night/stealth)

## B. Investigation
- **v246 Interrogation** – only when cops need their case stronger, ~48h hold clock, detective tactics, emotions (anxiety, fear, anger, exhaustion), clear "I want a lawyer" rules
- **v247 Interrogation QTEs** – bite tongue, breathing, hold nerve, eye contact, catch the slip; harder as pressure rises; mobile versions
- **v248 Crime log & co-defendants** – who planned / shot / drove, separate rooms, no chat between co-defendants
- **v249 Snitching** – blame, lie, minimise; stories cross-checked; first to talk gets the best deal (lesser sentence); lies void deals; testify at trial; snitch jacket → hits, protective custody

## C. Gangs
- **v250 Prison gang ranks** – associate / soldier / lieutenant / shot-caller, tasks, challenge fights to take rank, overthrow, lessons + underground contacts (e.g. cold plate referral)
- **v251 Street gangs** – crews and territory in the city, your prison standing follows you out (and back in)

## D. Drugs
- **v252 Drugs I** – alcohol, weed, pills, stimulants, heavy stuff, prison hooch/pills/synthetic; screen effects; impaired driving; DUI stops + breathalyzer; overdoses
- **v253 Drugs II** – hallucinations (players/objects look different, fake things, blackout dreamscape while you're really dragged to solitary), prison drug tests, drug debts, tolerance/withdrawal

## E. Bail, money & lawyers
- **v254 Bail** – bond at HQ, bail bondsmen, others can pay, tier table (released / bail / held without bail), pretrial detention
- ✅ **v255 Asset freeze & stashes** – dirty vs clean money, frozen accounts, seized cash/cars/helis/house lien, house safes, safe deposit boxes, hidden stashes, raids with warrants
- **v256 Phone calls** – cell phone ringing/answer/decline, prison phones (monitored), court date reminders
- **v257 Counsel billing** – retainer + hourly by activity, running out of money (lawyer quits / public defender), wrong-tier choices, pre-arrest retainer benefits, 3 AM response by tier (cheap ones sleep through it), law offices + in-person meetings, legal visits (glass or contact)
- **v258 Plea deals** – offers, negotiate, forfeiture splits, cooperation deals, expiring offers
- **v259 Firm asset management** – mid/high firms open deposit boxes, buy and hold metals, pay your bills while frozen

## F. Warrants & police intelligence
- **v260 Warrants** – no stars, failure to appear, bond forfeited, saved across sessions, HUD tag, turn yourself in, Chief console upgrade (warrant lists, BOLOs, cases)
- **v261 Recognition** – "?" meter, disguises, warrant stops (comply-to-cuff or felony stop), running → pursuit
- **v262 Plates & registration** – cars bought/registered at the dealership, plate readers, plate swapping, colour + type must match, respray, stolen plates, BOLOs with car description, civilian tips

## G. Courts
- **v263 Courtroom engine** – city courthouse + prison court, transport van, security checkpoint, bail + disciplinary hearings
- **v264 Bench trials** – charges, evidence from your real crimes, your choices, verdict, sentence → city jail / prison
- **v265 Jury trials** – 12 jurors, testifying QTE, hung juries, co-defendant testimony, player jurors/judge
- **v266 Judges with memory** – named judges & prosecutors who remember you, history-based sentencing, habitual offender, remove-judge motion, expungement
- **v267 Appeals & prison court** – appeals, trials for crimes inside prison

## H. Money rules
- **v268 Connections app** – elite lawyers, investigators, PR, gang protection payments (call off hits), CO bribes, lawyer as courier on contact visits
- **v269 Fixers** – witness tampering, evidence "lost", stings & risk, casino laundering, corrupt DAVID lookups, judges who can be bought
- **v270 Jury tampering** – get the jury list, bribe (easy) or intimidate / blackmail / kidnap-hostage (hard), works / partly / backfires (mistrial, sequestration, charges, SWAT hostage rescue)
- **v271 Underground** – cold plates via referral from a hidden moving plate maker, limited stock, underground scrutiny (busts + news make dealers wary), Elite Representation (Premier add-on: deals at the arrest scene, cite & release, quiet news)
- **v272 Metals & offshore** – bullion dealer at real spot prices, pawn / underground buyers, paper trails, offshore trust / private vault (slow, pricey, very hard for the DA to reach)

## I. Traffic rebuild
- **v273** lane network + turn curves, cars as data drawn on your device (500+ cars)
- **v274** junctions that can't lock up, signals, endless roaming, spawn out of sight
- **v275** real car when needed (crashes, carjacking, police), yield to sirens, brake lights & signals
- **v276** debug overlay + tuning

## J. Police gameplay (LCPDFR style)
- **v277 MDT / DAVID** – name & plate lookups, records, warrants, officer-safety flags, photo match
- **v278 Traffic stops** – AI pulls over, ID, frisk, breathalyzer, citation or arrest, some flee
- **v279 Callouts** – accept jobs, backup requests, ambient AI crimes

## K. News network
- **v280** news stories & app, breaking banners, wanted board, cases followed start to finish
- **v281** news helicopter, vans, reporters, perp walks, courthouse steps
- **v282** live broadcasts with cinematic camera cuts, courtroom broadcasts

**Side build (2026-10-01):** GTA IV handling for player cars - paste handling.dat lines into ReplicatedStorage.GTAHandlingData; F enters/exits cars, Space = handbrake. Police/traffic move over in v273+.

---
## Your to-do (Facility Mapper – see MAPPING_GUIDE.md)
1. Police HQ + prison additions (interrogation, prison court, guard towers, kill zone, perimeter, bus bay + unload line, stairs) → send the place
2. Courthouse, prison phones, law offices, bank deposit vault
3. City jail (incl. transfer holding + bus departure)
4. City points (dealers, plate maker spots, stashes, bars, drug corners, territories, news station …)
Settings: Studio API access ON, Allow HTTP Requests ON.

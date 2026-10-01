# LAS VEGAS (Roblox) – FULL DESIGN SPEC

This is the complete design for every planned system. Give it to the Claude session that's connected to Roblox Studio together with `HANDOFF.md` (how the repo and build work) and `plugins/ROADMAP.md` (the version order).

Core themes, which every system must respect:
1. **Realism first.** Systems follow real US/Las Vegas criminal justice, adapted to game time.
2. **Money rules.** Rich players can bend almost everything (lawyers, bail, gangs, COs, juries, evidence), but more hidden or illegal money is slower, more expensive and riskier, and nothing is 100% safe in a big enough case.
3. **Consequences carry.** Records, reputations, judges, gangs and the news remember you, inside and outside prison.
4. **Everything works on mobile.** Every UI, quick-time event and control has a touch version.
5. **No play-testing by Claude unless the user asks.** The user plays and reports; Claude reads the Output.

---

## 0. CURRENT STATE (built, through v239)

- **v236 Saving:** money (cash + bank), car keys and house save via DataStore `LasVegas_PlayerData_v1` with UpdateAsync, retries and a 1-minute autosave. A failed load never overwrites the save. **aquagaming22** always has at least **$50M total (cash + bank)** on join and keeps anything above that; a Death Row wipe resets them to exactly $50M. Every other player gets back exactly what they left with. Needs: the place published, Studio API access ON.
- **v237 Gang hits / prison death:**
  - Gangs that want you dead come with shivs and ambush when no CO is within ~35 studs:
    - respect ≤ −70,
    - you killed one of their members (a 15-minute blood feud),
    - or the `SnitchedOn` hook (future).
  - Ordinary beatdowns stop at 10 HP.
  - **An inmate killed by another inmate (NPC, player or rioter) is wiped like an executed player.** Self-reset and falling through the map don't count; the `PrisonKilledBy` attribute is set at the killing blow.
- **v238 Facility Mapper plugin** (see §19) and the v238b **NoSit** rule: players can't sit while a CO walks them (line-ups, returns). Client side, and the server breaks any seat weld.
- **v239 Custody stages:** `PrisonFlow.stageOf` maps the old flags onto **Arrest, Transport, Station, Detention, Medical, Serving, Release** (Court is reserved). It's published as the `CustodyStage` attribute and logged as `[Custody] STAGE`. Each stage owns its respawn spot (detainees → intake, housed inmates → their cell), placed before anything yields.
- **Already in the game:**
  - police AI (vision, pursuits, spike strips, SWAT, helicopters, SEALs, army at 6 stars), Chief of Police console (wanted level, warrants with real charges, dispatch)
  - prison: intake → booking → counsel → classification → housing; regimen and line-ups, CO sweeps, solitary, executions with C-SPAN, visits incl. contact-visit smuggling
  - gangs, CO respect, riots
  - helicopters, carjacking, vehicle health, casino, houses

---

## 1. ARREST & CUSTODY PIPELINE

### 1.1 Stages
`Arrest → Transport → Station (HQ) → Detention (city jail) → Court → Serving → Release`, plus `Medical`.
- One stage per player (`CustodyStage`).
- Each stage owns its respawn spot and its guards/pins. Guards and pins end the moment the stage changes; that was the cause of earlier bugs where a guard fought the booking escort.

### 1.2 One path for everyone; the tier changes the settings
**Nobody goes to prison without a conviction.** The route is the same for a jaywalker and a cop killer:
1. Arrest
2. Booking at the **Police HQ**
3. Bail decision
4. Pretrial: free on bail, or held at the **city jail**
5. Plea or trial
6. Sentence
7. Serve:
   - **under 30 real minutes** → city jail
   - **30 minutes or more, or any felony prison term** → state prison by **bus**

| | Minor | Mid felony | Serious (armed robbery, bank job, escape) | Murder / cop killing / 5 cops killed |
|---|---|---|---|---|
| HQ stop | Quick booking or cite & release | Short, maybe an interview | Interview likely | Long interrogation |
| Bail | Released with a court date, or small bail | Bail set | High, or denied | **Held without bail** |
| Pretrial housing | Home | Home or city jail | City jail | City jail max security / isolation |
| Plea | Easy | Real negotiation | Harder | "Life instead of death", or no deal |
| End | Fine / city jail | City jail / prison | Prison | Prison, Death Row possible |

### 1.3 Shortcuts (already convicted)
- **Recaptured escapee:** straight back to prison intake with time added; the escape charge is tried later in the prison court.
- **Crime inside prison:** solitary right away; a prison court hearing for serious crimes.
- **Parole hold:** straight back to prison, no bail.

### 1.4 Arrest scene (v241)
- **Comply** (hands up, cuff) vs **resist** (takedown, tackle). Then:
  - frisk; weapons and contraband seized; property logged
  - Miranda warning
  - placed in the car
- **Routing:** minor → HQ booking; serious → HQ (interrogation possible) then the city jail; escapee → prison; inside prison → solitary.
- **Hook:** a Premier lawyer with Elite Representation can appear at the scene (§9.7).

### 1.5 Police HQ processing (v242)
- Sally port drop-off → holding cell (30–60 s) → booking desk (mugshot, fingerprints, property) → decision.
- **Minor:** citation/fine, or cash bail → **released with a court date** (game clock).
- **Turn yourself in** at the HQ front desk (`TurnInPoint`) for a better outcome.
- **A short news story** only if notable: a famous or rich player, a repeat offender, a big fine, a weird crime.
- **Persistent criminal and court record** saved across sessions: every arrest, charge, plea, verdict and sentence, including acquittals, dismissals and "barely got off" results, plus failures to appear, escapes, contempt, behaviour in court, and which judge, prosecutor and lawyer handled it.

### 1.6 City jail (v243)
- Pretrial detainees, plus sentences **under 30 real minutes**.
- Cells, a day room, an optional small yard and a visit room. **No gang ranks or riots**, only the odd fight and shakedowns.
- **Transfer holding** room: convicted felons wait here for the prison bus.
- Release through the front door when time is up; bail or a fine can be paid early where allowed.

### 1.7 Prison transfer bus (v244)
- **Only city jail → prison.** Courthouse ↔ city jail and HQ ↔ city jail use **vans**.
- **Schedule:** as needed. When a real player is in transfer holding, it leaves after a short gather window (~2–3 minutes), and it **always runs at least once every 30 minutes**.
- **12–16 prisoners per trip:** real players + **real busted pedestrians** (NPCs actually arrested in the city) + generated **filler inmates** with names, charges, sentences and classes.
- A code-built bus with shackled prisoners in seats, a CO or officer on board, and an **escort car** for high-security loads.
  - It drives real roads; the prison gates open for it.
  - Riders can talk and fight on board; COs break it up.
  - A crew ambush or escape attempt is rare and very hard, and hits the news live.
- **Arrival:** `BusBay` → walk the `BusUnloadLine` route into intake.
- **Batch intake:**
  - **Placement order:** intake cells (capacity 8) → **overflow holding** (6 cells × ~4) → **long-term holding** (5 cells × ~4).
  - **Processing:** several officers process several inmates at once. Players are processed first; filler NPCs fast-track.
- Filler inmates become regular inmates. Releases and transfers out keep the population under a performance cap, so the prison is fuller and livelier. Far-away NPCs get cheaper level-of-detail updates.

### 1.8 Prison guard towers (v245)
- **Towers:** a sniper NPC per tower (`SniperPost`) with a long-range, slow-aim, high-damage rifle, and a spotlight (`Spotlight`) that sweeps the yard and perimeter at night, then locks onto anyone spotted in a kill zone or the perimeter.
- **`KillZone`** (between the fences): alarm, one shout, then they shoot.
- **`Perimeter`** (just outside): "STOP! Get on the ground!", a warning shot, then fire to kill.
- **Never** fire into the yard or normal areas, except at an **armed rioter attacking a CO in the open**.
- **An escape attempt:** alarm, lockdown, police helicopter.
- **Open decision (recommended yes):** being shot dead by a tower sniper while escaping counts as a prison death and wipes the profile.

### 1.9 Police vision fix (with v245)
Current: a 150° cone; a **22–24 stud all-around "notice" bubble** (that's the "eyes in the back of the head"); 4-second tracking memory; the radio skipping the cone for assigned officers.

Change to:
- **Cone:** ~110° clear sight, plus a 110–150° peripheral band where noticing is slower.
- **All-around bubble:** 6–8 studs, bigger only when loud (running, shooting, crashing, sirens).
- **Radio:** makes the officer **turn and look**; they only see you if you're in the new cone with line of sight.
- **Lighting:** darkness shortens sight; headlights, streetlights and spotlights extend it.
- **Stealth:** walking or crouching is harder to notice than sprinting.

### 1.10 Known leftover
Resetting in solitary respawns you in your home cell. Fix it when solitary becomes its own stage.

---

## 2. INTERROGATION (v246–v247)

### 2.1 When cops interrogate (not every crime)
- Serious crimes (murder, cop killing, bank robbery, heists).
- Weak or thin evidence.
- Accomplices involved, or people who got away.
- Unsolved crimes they suspect you of.
- First-timers or past talkers, who might crack.
- Caught red-handed on a minor crime, or an airtight case → **no interrogation**.

### 2.2 Where
- New serious arrests: **Police HQ interrogation rooms** (`Interrogation` zones; `SuspectSeat` + `DetectiveSeat`).
- Inmates suspected of crimes inside: **prison interrogation rooms**, questioned by COs or an investigator.
- Until the HQ is mapped, prison rooms are used after booking.

### 2.3 Legal limits (copied from US law)
- They can hold you **~48 hours** before a judge, scaled to game time (e.g. ~8–12 real minutes, tunable). An **on-screen hold clock**; when it runs out you go to the bail hearing no matter what.
- **Miranda** is read.
- **A clear "I want a lawyer"** ends questioning, and they can't restart unless *you* start talking.
- **A clear "I'm not saying anything"** pauses questioning; they may come back for another round later in the hold.
- **Ambiguous lines don't count** ("Maybe I should get a lawyer?"); questioning continues.
- **Allowed tactics:** lying about evidence, bluffs ("your buddy already talked"), good cop/bad cop, silence, waiting you out, fake sympathy.
- **Not allowed:** threats, violence, denying food/water/bathroom for hours, promising a specific deal. If a detective breaks a rule (rare flavour), statements after that **can be thrown out at trial** if your counsel catches it; better counsel catches it more often.

### 2.4 Emotions
- **Meters:** **anxiety, fear, anger, exhaustion**, plus a heartbeat, blur and screen-edge shake, sweat and fidget animations, and inner-thought text ("Just tell them, it'll be easier…").
- **Raised by:**
  - time held
  - detective tactics: bluffed evidence, family, death-penalty threats, good-cop kindness, leaving you alone in silence
  - your crimes; being a first-timer (career criminals start calmer)
  - drugs
- **Calmed by:** passing quick-time events, breaks, water, the lawyer arriving.

### 2.5 Quick-time events: keep your mouth shut (v247)
The character **tries to talk**; the player fights it.
- **Bite your tongue:** rapid taps before the words come out.
- **Steady your breath:** press in rhythm with a pulsing ring (anxiety makes it uneven).
- **Hold your nerve:** keep a marker inside a shrinking zone that fear pushes around.
- **Don't look away:** hold the eye-contact bar steady.
- **Catch the slip:** a sentence types out letter by letter; hit the prompt before it finishes. The further it gets, the more they learn.

Difficulty scales with the emotions and the detective's pressure: shorter windows, faster rhythms, fake-out prompts, double prompts. A big move ("your partner confessed and blamed you") triggers the hardest one.

**Failure stages:** small miss → **nervous tell** (pressure up); bigger → **slip** (partial info); collapse → **confession / naming names**.

**Asking for a lawyer under pressure is itself a quick-time event** when anxious. Success = said clearly; fumble = ambiguous, so it doesn't count. With a **retained lawyer present**, no quick-time event is needed.

**Touch:** every quick-time event has a mobile version (tap, hold, drag).

### 2.6 Outputs
These feed bail, the asset freeze, plea offers and the trial:
- **Evidence strength**
- **Confession** flag
- **Accomplices named**
- **"Lawyered up" / "Cooperative"** flags ("lawyered up" makes the first plea offer slightly harsher)

---

## 3. SNITCHING & CO-DEFENDANTS (v248–v249)

### 3.1 Secret truth log
The server records **who did what** in heists and crimes; the cops only have partial evidence per person.
- **Roles:** **planner** (hit the keypad first, bought tools, gathered the crew), **safecracker/hacker**, **shooter**, **driver**, **lookout**.
- **Evidence per person:** cameras, fingerprints (touched the vault), plate readers, witnesses.

### 3.2 Separate interrogations
- Every arrested crew member is in a **different room**.
- **No chat between co-defendants while in custody.** Stories planned before the job are fair game.

### 3.3 What you can say
- Stay silent / ask for a lawyer.
- **Tell the truth.**
- **Lie and blame someone:** a crewmate, someone who escaped, an invented person, a rival.
- **Minimise:** "I was just the driver."

### 3.4 Cross-checking
- A story matching the evidence is believed. A contradiction is caught: pressure spikes, credibility drops, possible **obstruction / false-statement** charge.
- Two people blaming the same person is believed (even a lie can railroad an innocent).
- Everyone blaming each other → nobody believed, everyone charged harder.
- Detectives **bluff** ("room 2 already said you planned it").

### 3.5 Snitching for a lesser sentence
- **First to talk** gets the best deal; later cooperators get less.
- **Reduction size:**
  - new info (the planner or shooter they didn't have) → about **40–60% off**, charges dropped, or a lower class
  - confirms suspicions → about 15–25%
  - already known → little or nothing
- **Role matters:** the lookout flipping on the planner gets far more than the reverse.
- **Better lawyers** get bigger reductions for the same info and spot detective overpromises.
- **Strings attached:**
  - Info must be **true and hold up**, or the deal is **voided** (full sentence plus a false-statement charge).
  - You may have to **testify** at the other person's trial; refusing or cracking on the stand voids the deal and adds perjury.
  - Locked in at sentencing.

### 3.6 Consequences
- The **blamed person** is charged; if not caught they get a **warrant**. If innocent, their lawyer can prove it (alibi, cameras) and your lie collapses on you.
- **Snitch jacket:**
  - paperwork can leak and rumours spread
  - the named gang's anger rises and respect tanks; they **put a hit on you** (the v237 hook, `SnitchedOn`)
  - riot risk
- Optional **protective custody** (`ProtectiveCustody` cells): isolated, no yard or gang life, and everyone knows why.
- Snitching burns **underground reputation**: the plate maker and contacts stop dealing with you.
- NPC accomplices can be blamed, or **flip on you**.

---

## 4. GANGS (v250–v251)

### 4.1 Prison ranks (per gang)
**Associate → Soldier → Lieutenant → Shot-caller** (one shot-caller per gang per prison). NPCs carry ranks; higher ranks have bodyguards and give orders (hits, deals, off-limits).
- **Respect path:** talk, favours, and **tasks** for higher ranks:
  - smuggle contraband
  - collect debts
  - deliver a beatdown
  - hold a shiv during a search
  - keep quiet in interrogation
- **Fight path:** **challenge** someone above you. Win = take their rank and soldiers; lose = demoted or kicked out, and maybe a hit on you. **Overthrowing the shot-caller** means beating the bodyguards and then them; loyalists may retaliate.
- **Money** buys loyalty and backup muscle.

### 4.2 Learning from high ranks
- **Skills:** faster lockpicking, shiv making, hiding contraband in searches, smuggling routes through visits.
- **Underground contacts:** cold plate maker referral, fixers, chop shop, fences, heist crews.
- **Escape intel:** patrol gaps, weak doors, a bribable CO.

### 4.3 Street gangs (v251)
- Gangs exist in the city with territory (`TerritoryEK/IS/DS/TL` zones).
- **Standing carries both ways, saved:** a feud from prison follows you out, and a street feud follows you in.
  - **High standing / friendly:** protection in their areas, jobs, contacts, backup, hiding you from police.
  - **At war** (overthrew their boss, killed their people, snitched): members **recognise and attack you**, hits follow you outside, and their turf is dangerous.
- Rival gangs treat you based on who you're tied to.

### 4.4 Already built
4 gangs (Eastside Kings vs Iron Syndicate, Desert Saints vs The Lifers), per-gang rep, CO respect, fights, riots (tension, CO anger, gang anger), gang hits.

---

## 5. DRUGS & INTOXICATION (v252–v253)

**Substances:**
- **Street/legal:** alcohol (bars, casino, shops; legal but illegal to drive on), weed (mellow), party pills (bright, then a crash), stimulants (twitchy, faster reactions, hard comedown), heavy drugs (strong hallucinations, overdose risk).
- **Prison:** hooch, prison pills (existing contraband), synthetic "spice" (most intense and dangerous). They come in via smuggling (visits, lawyers), gang dealers and CO bribes.

**Screen effects (client only):**
- light: blur, colour shift, sway, slower input
- medium: tunnel vision, double vision, wobble, input delay, muffled sound
- heavy: warped colours, breathing edges, trails, slow time
- each substance has its own style

**Hallucinations (client-only swaps, v253):**
- players/NPCs look different (a CO looks like a gang member, monsters, the same face on everyone)
- fake objects (doors, guards, walls, cars)
- whispers, fake chat and notices
- seeing yourself elsewhere
- **blackout dreamscape:** the screen dissolves into a hazy place while you're **really being dragged to solitary or arrested**; you wake in a cell

**Gameplay:**
- **Impaired driving:** steering delay, drift, slow braking.
- **Swerving → DUI stop:** breathalyzer / field sobriety → DUI charge, **licence suspended** (in DAVID), car towed.
- **Combat:** alcohol (aim sway, less pain), stimulants (faster punches), hallucinogens (might hit the wrong person).
- **Overdose:** collapse; needs an EMS/medic save or you die. In prison a drug death counts toward prison-death rules.

**Prison specifics:**
- **drug tests** (random or after searches): dirty = solitary, time added, CO respect hit
- **drug debts** on credit: unpaid → beatdowns or hits
- high populations raise riot tension

**Addiction (light):** tolerance; withdrawal (shaky screen, irritability); legal pharmacy meds ease it.

---

## 6. BAIL, BOND & DETENTION (v254)

- **Bail hearing tiers** as in §1.2. **Held without bail** for murder, cop killing and 5 cops killed (isolation pretrial).
- Record, failures to appear and escapes raise bail or deny it; counsel argues it down (except the no-bail tier).
- **Paying:**
  - yourself (unfrozen money)
  - **friends or other players**
  - a **bail bondsman** (10% cut; `BailBondsOffice`)
  - **not available** with prior failures to appear, an escape history, or if you're already on bond
- Released with a **court date** (phone calendar plus reminders).
- **Missing court:** a **failure to appear warrant** (no stars), bond forfeited, cars flagged, no bond next time (§10).

---

## 7. ASSET FREEZE, STASHES & PRECIOUS METALS (v255, v259, v272)

### 7.1 Freeze (felony money cases only, not every crime)
- **Dirty vs clean money:**
  - dirty = heists, robbery, drugs, selling carjacked cars
  - clean = jobs, paychecks, casino wins
  - optional casino laundering
- **At arrest:**
  - bank **frozen**; cash **seized**
  - cars and helicopters impounded; house lien if bought with dirty money
  - banking app shows "ACCOUNT FROZEN – Clark County DA"
- **Spending while frozen:** clean money can still pay the lawyer; friends and players can pay bail or send money.

### 7.2 Where money can live
| Place | Freeze-safe? | Risk |
|---|---|---|
| Bank | ❌ frozen | – |
| Cash on hand | ❌ seized | Dropped on death |
| **House safe** | ✅ | Search-warrant raid |
| **Safe deposit box** (yours) | ✅ at first | DA subpoenas and drills it once known |
| **Hidden stashes** (`StashSpot`: floor, storage unit, buried, business back room) | ✅ | Found only if someone talks or a detective tails you |
| Car trunk | Partly | Seized with the car |
| Friend / player | ✅ | Trust |
| **Firm/trust deposit box** (§7.4) | ✅ | Big cases with proof only |
| **Offshore / private vault** (§7.5) | ✅✅ | Rare; slow and expensive |

### 7.3 Precious metals at real spot prices (v272)
- Gold, silver, platinum and palladium at the **bullion dealer** (`BullionDealer`).
- **Prices follow real spot prices:** the server fetches them every ~10 minutes from a free metals price API (needs **Allow HTTP Requests**). Fallback: last price plus realistic drift. Players can gain or lose as prices move.
- **Buying:** legit purchases (bank, receipts) leave a **paper trail**; cash or pawn/underground buys (`PawnShop`, `UndergroundMetalBuyer`) are untraceable but cost a **premium over spot**.
- Metals take space and weight (gold packs dense value, silver is bulky).
- Sell back at spot minus the dealer's cut, or pay people directly.

### 7.4 Lawyer phone call using stashes; firm asset management (v259)
- Frozen and cash seized → the lawyer calls: *"Your retainer bounced."*
- You **disclose a stash location**; the firm's **runner** (or a named friend) collects and converts it, and the case continues.
  - The firm takes a handling fee (higher for cheap firms); **cheap lawyers may skim**.
  - **Prison phones are monitored**, so disclose in a **legal visit** (privileged) or the DA may raid it first.
- **Firm asset management** (Criminal Defense Firm and up, a paid add-on; Premier is best):
  - The firm opens a **safe deposit box** at the bank in **the firm's or a trust's name** (hard to link to you) or **jointly**.
  - It takes your money, **buys metals** at spot plus a fee, manages the box (add, withdraw, rebalance), and **pays your bills from it** while frozen (fees, bail, fixers).
  - It reports to your phone (contents, spot value, fees).
  - **Access modes:** hands-off (the lawyer does everything), joint (you can visit the bank too), lawyer-only (safest).

| Firm | Fees | Trust |
|---|---|---|
| Criminal Defense Firm | Moderate | Small chance of skimming |
| Elite / National | Higher | Reliable |
| Premier | Highest | Fully reliable, best DA shielding, fastest 3 AM access |

- **Catches:**
  - If the DA proves it's crime money (snitch, legit-purchase trail, firm scandal), privilege breaks and the box is frozen or seized; the firm may be charged and drop you.
  - A firm burned in a scandal (e.g. smuggling contraband) puts its boxes under scrutiny.
  - Moving money after charges looks like hiding assets (riskier); setting it up early is safer.
  - Unpaid fees freeze management, but the metals stay yours.

### 7.5 Offshore layer (Premier/Elite only, v272)
- Set up through a **private "fiduciary"**: an underground contact reachable only through your top-tier firm.
- **Two forms:**
  - an **offshore trust**: a virtual vault "outside the country" that normal subpoenas, warrants and freezes can't touch
  - a **private vault operator** (`PrivateVaultSpot`): a hidden, unmarked vault known only to the firm that **moves if compromised**
- **Slow:** transfers take ~15–30 minutes of game time each way, with a ~5–10% fee each way. Withdrawals on a bounced-payment call are delayed; the firm may **front you at interest**. Metals can be held at spot.
- **Still reachable, rarely:**
  - an **international cooperation request**, in top-tier cases only (5 cops killed, a massive heist, big news); slow and only sometimes successful
  - **snitches** who knew
  - the **fiduciary getting burned** (sting or news exposé), which freezes every client's holdings
  - a **paper trail into it** (moving money right before or after charges is a red flag)

### 7.6 DA fights back
- A financial investigation follows the paper trail and gets search warrants for safes and boxes.
- Snitches reveal stashes.
- Moving assets after charges adds obstruction or money laundering charges.

---

## 8. PHONE CALLS (v256)

- **Cell phone:** incoming-call screen (ring, answer, decline) and missed-call callbacks. Lawyer calls, plea offers, **court date reminders**; offers expire after missed callbacks.
- **Prison/jail phones** (`PrisonPhone`, `JailPhone`, `HoldingPhone`):
  - A CO says "legal call" or you're sent to the phone bank; you **must physically be at the phone**.
  - Handset UI with "This call is from a correctional facility".
  - **Prison phone calls are monitored** and usable as evidence.
  - Refuse and the lawyer comes for a legal visit instead (slower; the offer may expire).
- One shared call UI with two skins (cell and prison).

---

## 9. LAWYERS (v257–v259, plus money layer)

### 9.1 Tiers (existing counsel list)
Public Defender (free), Local Attorney ($10k), Experienced Defense Counsel ($50k), Criminal Defense Firm ($250k), Elite Defense Team ($1M), National Trial Firm ($5M), **Premier Counsel ($10M)**. The current one-time payment is **replaced** by retainer plus hourly billing.

### 9.2 Retainer + hourly billing
- Call or choose counsel and get a **quote**: retainer, hourly rate, and an estimate for your case type (e.g. "armed robbery, jury trial: 40–70 h").
- Pay the **retainer** into a **trust balance**; hours are billed against it in game time:

| Activity | Hours |
|---|---|
| Call / legal visit | 0.5–1 |
| At interrogation | 1–3 |
| Bail hearing | 2–4 |
| Plea round | 1–3 |
| Motions | 3–8 |
| Bench trial | 8–15 |
| Jury trial | 20–60+ |
| Appeal | 15–30 |

- Complex cases (co-defendants, heists, cop killings, many charges) take longer; early pleas are cheapest.
- **Running low:** the lawyer calls for a top-up (bank, friends, hidden cash).
- **Can't pay:** the lawyer **cuts corners** or **withdraws**; a public defender is appointed mid-case (catch-up, weaker); mid-trial it means a delay or a weak defense; unpaid bills become debt.
- **Frozen money can't pay; clean money can.**
- **Wrong choices:** Premier for shoplifting wastes money; a cheap lawyer for a triple homicide is out of their depth. Trial vs plea is also a money decision; switching lawyers costs a new retainer plus catch-up.
- **UI:** a legal bill in the phone (paper in prison) showing balance, hours, remaining estimate and rate, plus warnings before expensive moves ("jury trial ≈ 45 h ≈ $2.2M").

### 9.3 Pre-arrest retainer (vs hiring after)
- A monthly retainer (game billing cycle); the phone shows "Counsel: [Firm] (on retainer)".
- **Benefits:**
  - **instant call** at arrest
  - the lawyer **comes to the interrogation** ("I want a lawyer" needs **no quick-time event**)
  - faster bail hearing and lower bail
  - better first offer
  - they know your history (fewer catch-up hours)
  - **priority**
  - a **20–35% discounted hourly rate**
  - **no big retainer at arrest**, which matters when accounts freeze (the retainer is already paid)
  - elite extras: warnings about coming investigations, priority contact visits, fixer access
- **Hiring after the fact:** top firms may be booked, a full retainer from possibly frozen money, higher rate, catch-up hours, alone in interrogation at first.
- It's like insurance: you pay each cycle even if nothing happens.

### 9.4 Response at 3 AM (game clock; 10pm–6am is the test)
| Tier | Day | 3 AM |
|---|---|---|
| Cheap / Local | Answers, slow | **Good chance they sleep through it**: voicemail, show up in the morning after the interrogation |
| Mid-tier | Reliable | Usually answers, slow to arrive |
| Criminal Defense Firm | Fast | May send a **junior associate** (weaker) |
| Elite / Premier | Immediate | **24/7 line**, fast |

- It's **rolled each time**; a bigger retainer or "priority client" upgrade raises the odds. New clients or clients in debt are less likely to be answered.
- **No-show:** alone in interrogation (quick-time event to ask for a lawyer), bail hearing delayed, can call another firm at walk-in prices, a callback later ("Sorry, I was asleep… what did you tell them?").
- **Shows up:** pressure drops, no quick-time event, faster bail, better offer. Elite at 3 AM can shorten your hold ("Are you charging him or not?"); Premier can come to the arrest scene for big cases.

### 9.5 Law offices & meetings
- **Offices (built and mapped):** Public Defender (cramped, near the HQ), Local Attorney (storefront), mid-tier suite, **Premier high-rise** (lobby + conference room). A `LawOffice` model with a `Firm` attribute, `Reception`, `LawyerSeat`, `ClientSeat`, optional `ConferenceSeat`.
- **The lawyer requests in-person meetings:** a call/text with a time (game clock), shown in the phone calendar with a GPS route.
- **Must be in person:**
  - signing the retainer (bigger firms)
  - reviewing and signing a plea (incl. forfeiture)
  - a cooperation/**proffer** meeting (lawyer + prosecutor) before snitching counts
  - **trial prep** (testimony practice using the stand quick-time events; good prep makes the real testimony easier)
  - handing over assets / bail paperwork
  - bad news (new charge, offer pulled, co-defendant flipped)
- **Late:** billed waiting time and deadlines may pass. **No-show:** the offer may lapse, the lawyer gets annoyed (weaker effort or drops you), and the appointment is billed.
- **Warrant risk:** recognition and plate readers are active while you travel to the office.
- **Privilege:** office meetings and legal visits are **private** (police can't use them); **prison phone calls are not**.
- Better firms are more flexible and will come to you for a fee; the public defender makes you wait and reschedules.

### 9.6 Legal visits in custody
- **HQ legal visit rooms** (`LegalVisit` zones; `InmateVisitSeat` / `LawyerVisitSeat`).
- **Prison/jail visit rooms** (existing): **glass visit** for routine things, **contact visit** when the lawyer needs to go over a lot (trial prep, cooperation, big plea terms, evidence).
- **Money rules, the lawyer as courier:**
  - Pay your lawyer **a lot** extra and they push for a contact visit and **slip you something**: phone, cash, pills, lockpick, a message to your gang, or a shiv at the top tier. It uses the existing contact-visit smuggling quick-time event.
  - **Elite lawyers are searched less.**
  - **Messages out** to your crew/fixer/gang (privileged, not recorded).
- **If caught:**
  - you: item taken, solitary, contraband charge, CO respect hit
  - the lawyer: investigated, **drops your case** (even mid-trial), may be arrested, news story; underground scrutiny rises
  - **cheap lawyers** are riskier and may **snitch you out** to save themselves

### 9.7 Elite Representation (Premier-only add-on)
- Requires Premier on retainer, **plus** a big standing fee **plus** a big per-use fee (scaled to severity).
- **At the arrest scene** (the 24/7 line, even 3 AM):
  - **no cuffs**, quiet transport
  - **cite & release** instead of booking (mid-level charges)
  - **released pending investigation**
  - **charges knocked down** before booking
  - **car not impounded**
  - **arranged self-surrender** on your schedule
- **After:**
  - interrogation cut short or skipped ("written statement")
  - **bail set immediately** by an on-call judge
  - **news buried** or softened
  - **evidence "problems"** (chain of custody; the riskiest)
- **Limits:**
  - odds, not guarantees
  - severity: easy for minor/mid crimes, hard for violent felonies, near-impossible for cop killing; **5 officers killed can't be fixed** (only a nicer ride to jail)
  - harder with a live news broadcast, a player cop on scene, or crowds
  - record: repeat offenders are harder
  - **a real player Chief online gets a prompt and can refuse** (and could face pressure or offers)
  - failed attempts are still billed and noticed
- **Abuse:** a hidden "special treatment" suspicion leads to news exposés, internal affairs on the officers, a harsher DA next time, and rising underground scrutiny.

---

## 10. WARRANTS & POLICE INTELLIGENCE (v260–v262)

### 10.1 Warrants (no stars)
- **Sources:** failure to appear, being blamed by a snitch, escape, **Chief console** warrants.
- **Saved across sessions**; a HUD tag only you see ("ACTIVE WARRANT: Failure to Appear").
- Police act normally until they **identify** you. A **stop** is the arrest; **running** becomes a normal starred pursuit with the warrant still attached. Evading clears the stars, **not** the warrant.
- **Clearing:** turn yourself in (`TurnInPoint`; better outcome, maybe bail restored), arrest (bail revoked, held until trial), or the Chief clears it.
- **Stop type by severity:** low-risk (approach, comply, cuff, straight to court or holding) vs serious (**felony stop**, guns drawn, backup).

### 10.2 Recognition (v261)
- **Per-officer recognition chance:**
  - higher up close, in daylight, the longer they look
  - lower at night, at distance, when moving fast, in crowds
  - **disguises** (clothing store changes, hats, masks) lower it
- **Gradual:** "Hey… don't I know you?"; the officer follows before committing; a **"?" meter** above them.
- **Civilian and shopkeeper tips** call it in.
- **Traffic stops run your name** → a warrant hit.
- **Being on the news** raises recognition.

### 10.3 Plates, registration & cars (v262)
- **Cars are bought at the physical dealership** (the NPC dealer); the phone app becomes "reserve online, pick up and sign at the dealership". Purchase **registers** the plate, owner, make/type and colour.
- **Stolen/carjacked cars** come back to the real owner, flagged stolen once reported.
- **Plate readers** on cruisers (~60 studs plus line of sight). Radio: "ALPR hit: Blue Sports Car, plate 7KX-221, registered owner has an active warrant…"
- **The record must match the car:** the right type and colour = clean; "red Sedan" on a blue SUV = **"plate doesn't match vehicle"** (follow/stop); a stolen plate = immediate stop.
- **Plate swapping:** steal plates off parked or traffic cars (a few seconds; a crime if witnessed), buy stolen plates from the shady dealer or chop shop (cheap; reported and flagged later), or **cold plates** (§13.3; the only plates passing every check).
- **Respraying** at the spray shops (existing) changes colour: you no longer match the BOLO, but your registration still has the old colour until you **re-register** at the dealership (logged). A respray right after a crime is suspicious if seen.
- **BOLOs describe the car:** "black SUV, partial plate 7K…". Police check cars that **visually match** even without a plate hit.
- **Shady dealer / chop shop** sell unregistered cars and fake plates; a VIN mismatch on a stop is a new charge.
- **BOLO broadcasts** with clothing, car and last-seen location; AI patrols drift toward it.

### 10.4 DAVID (in-game Driver And Vehicle Information Database)
- **Person lookup:** licence photo (avatar headshot), name, age, **address** (owned house), **licence status** (valid / suspended for DUI, citations or failure to appear / revoked; **driving while suspended** is a charge), registered vehicles (incl. helicopters), citation history, **flags** (warrants, BOLOs, officer-safety alerts such as armed/violent/cop killer, probation/parole, stolen reports), criminal/court history.
- **Plate lookup:** owner, type, colour, stolen; **mismatch warnings**. Cold plates come back clean.
- **Photo match** on stops (disguise vs recognition).
- **Users:** police player teams (LVPD, SWAT, Marshals, FBI, Chief); AI uses the same data.
- **Licences:** automatic; suspended (DUI, citations, failure to appear); reinstated by fines or a lawyer.
- **Abuse:** every lookup is **logged** (officer plus reason). A **corrupt cop** (bribed via a fixer, or a player cop) can look up a **juror's address**, a witness or a snitch's home. **Audits** catch no-case lookups: fired, charged, in the news, traced back to who paid.

### 10.5 Chief of Police console (existing; upgrade in v260)
- **Existing (v235):** wanted level 0–6, warrants with selectable charges incl. "Murder of 5 police officers (Death Row)", dispatch any unit/count/vehicle/helis, authorize lethal force. Only aquagaming22 on the Chief team.
- **Upgrade:**
  - warrants become the no-star type (BOLO, plates, recognition), with an option to also set stars
  - severity sets the stop type
  - views for active warrants, BOLOs, pending cases and bail status
  - **prompts for Elite Representation requests** (accept or refuse)

---

## 11. COURTS (v263–v267)

### 11.1 Courthouses (built and mapped)
- **City courthouse** (`Courthouse` model):
  - security checkpoint (`MetalDetector`), lobby, **clerk window** (`ClerkWindow`: pay fines, check court dates, turn yourself in)
  - **courtrooms** (one or more)
  - **court holding** cells with a secure hallway to the courtroom
  - **jury room** (deliberations, the target of tampering)
  - **judge's chambers** (deals/bribes)
  - sally port (`VehicleDropoff`)
  - **front steps** (`CourthouseSteps`: news, perp walks)
  - optional attorney room and press area
- **Prison court** (inside the prison): courtroom + jury room (+ optional court holding and chambers) for inmate trials, disciplinary hearings, appeals and in-prison crimes.
- **Seats per courtroom:** `JudgeSeat`, `DefendantSeat`, `DefenseSeat`, `ProsecutorSeat`, `WitnessSeat`, `JurorSeat1–12`, `GallerySeat`. Seats belong to whichever `Courtroom` zone polygon they sit in. `BailiffSpot` per courtroom; optional `CourtCam` angles.

### 11.2 Getting there
- **On bond:** you must show up yourself at the court date (game time); missing it = failure to appear (§10.1).
- **In custody:** a van from the city jail (or a CO escort in the prison).

### 11.3 Plea first, then trial
- **Arraignment:** the charges and the **maximum sentence** are shown. Counsel reads the first offer: "Plead to Armed Robbery, they drop Assault on an Officer: 12:00 instead of up to 40:00."
- **Choices** (Telltale style, timed): **accept**, **counter/negotiate** (counsel tier drives the odds; the offer can improve, stay or be pulled), **reject → trial**.
- **Offer factors:** case strength (evidence from interrogation), discounts for weaker cases; cop killing gets a worse offer or none, Death Row cases "no deal"; counsel quality; **history** (§11.6). Offers are time-limited, and rejecting can make the next one worse or remove it.
- **Minor cases:** an out-of-court offer (pay a fine and walk).

### 11.4 Bench vs jury (player chooses)
- **Bench:** a judge only, ~1–2 minutes, predictable (follows evidence and counsel), fewer swing moments.
- **Jury:** longer (jury selection, openings, evidence, closings). **12 NPC jurors** with hidden leanings; your choices and counsel move individual jurors; **hung jury / mistrial** possible. **Real players can be jurors** (a vote panel) or **the judge** (a verdict and sentence panel; the NPC judge fills in).

### 11.5 The trial
- Charges, then **evidence from your real crimes** ("3 officers assaulted", "vault breached at Bank of America"), then your turns: **object**, **challenge evidence**, **testify** (risky; uses the stand quick-time events, good prep helps), **stay silent**.
- **Co-defendants testify** (snitch deals).
- Closings, then the **verdict**:
  - **not guilty** → released (assets unfrozen)
  - **guilty on some counts** → sentenced on those
  - **guilty on all** → near maximum (the "trial penalty")
  - **hung** → retrial or a new offer
- **Routing:** short → city jail; long/felony → transfer holding → **bus** → prison class (Low…Supermax/Death Row) → existing housing.
- **Bail hearings and disciplinary hearings** also use the courtrooms.
- **Death Row cases** (incl. 5 cops killed): a mandatory trial with death possible. (The existing Death Row test sentence is still 60 seconds.)

### 11.6 Judges & prosecutors with memory (v266)
- **A roster of named judges:** the Hanging Judge (harsh), the Fair One, the Lenient One, the One Who Can Be Bought (via the money layer). Assigned semi-randomly, so **the same judge can return**: "Back again. Last time you walked on a technicality. Not today."
- **Prosecutors** who lost to you hold grudges.
- **History effects:**
  - **bail:** repeat offenders and those with failures to appear get higher or no bail
  - **offers:** smaller
  - **sentencing:** repeat and same-charge enhancements; a **habitual offender** ("three strikes") status leads to much longer terms, and prison even for small stuff
  - **"barely got off" last time:** the prosecutor and judge are harsher
  - **clean history:** first-offence leniency
- **Fighting back:** a motion to **remove a biased judge** (costs hours/money, not guaranteed); **expungement** of old minor records after a clean period (paid lawyer); elite lawyers soften history (character witnesses); clean street time slowly softens it.

### 11.7 Appeals (v267)
After a trial conviction, **one appeal** from prison via the prison court, with a small chance of a reduced sentence or a new trial.

---

## 12. MONEY RULES – CONNECTIONS APP (v268–v269)

A phone **Connections** app (cell, or a monitored prison phone, where risk is higher) lists your lawyer, fixer, gang contacts and CO contacts: what each can do and the price.
- **Legal money:** elite lawyers (suppression, bigger deals, delays), **private investigators** (dig up evidence, break a snitch's story, dirt for blackmail), jury consultants, **PR** (sympathy; spinning news).
- **Prison money:**
  - pay gangs for **protection** (even with a snitch jacket, **call off hits**; price scales with how bad and how angry), buy respect
  - **bribe COs:** better cell, lost write-ups, contraband, move a rival, look away, early yard
  - hire muscle (protect you or hit the person who snitched)
  - luxury (commissary, phone, food)
- **Street money (fixers, `FixerSpot`):**
  - lean on a witness (change story, forget, don't show)
  - pressure a co-defendant or their lawyer
  - find out who snitched
- **System money:**
  - bribe a detective (lose evidence) or clerk (delay or lose a warrant)
  - lower your security class
  - corrupt DAVID lookups
  - buy a judge
- **Risk:** every illegal payment can be caught (stings, fixers who flip, CO reports) → **bribery / obstruction / tampering charges**, voided deals, a bigger freeze, a worse sentence. **More money means lower risk** (better fixers, more layers).
- **Limits:** the worst crimes need huge money *and* luck; **frozen dirty money can't be spent**, so hidden and clean money matters.

---

## 13. JURY TAMPERING & THE UNDERGROUND (v270–v271)

### 13.1 Jury tampering (v270)
- **Get the list first:** sealed; pay a clerk or fixer, or someone in the gallery follows jurors home on day one.
- **Each juror NPC** has a **home** (one of the 48 existing properties), a **family**, and hidden traits: **greedy, scared, brave, honest, loyal**.
- **Easy way: pay.** Via a fixer (safer) or yourself (riskier). Greedy jurors take it; honest ones report. More money and more middlemen = better odds and a "gift" feel.
- **Hard way:**
  - **intimidation** (threats, following, warnings): scared jurors fold, brave ones report
  - **blackmail** (a private investigator's dirt): quieter
  - **kidnap a family member as a hostage:** grab them at the juror's house, hold them at a **safehouse** (`Safehouse`) or your property for the whole trial, the juror is told how to vote. The strongest and most dangerous option; **someone must guard the hostage** (you, your crew, paid muscle).
- **Outcomes:**
  - works (votes your way, or holds out for a hung jury)
  - partial (folds, then cracks in deliberation)
  - **backfire:**
    - the juror reports → mistrial, **jury tampering / obstruction** charges, the jury is **sequestered**
    - a police or FBI sting catches the fixer, who may snitch on you
    - **kidnapping discovered** → **SWAT hostage-rescue raid** on the safehouse, kidnapping + extortion charges, live news
    - the family escapes if guards leave
- **High-profile cases** may be sequestered from the start (much harder, much pricier).
- **Player jurors** can be bribed or threatened too; their choice to report.

### 13.2 Underground scrutiny
- A hidden scrutiny level per underground trade: cold plates, fences, chop shops, fixers, fiduciaries.
- **Rises with** busts and **news coverage** (ticker < headline < **live/C-SPAN segment**, which spikes hard), snitches naming contacts, and stings.
- **High scrutiny:** dealers get **wary** (prices up, stock down, more referrals or higher gang rank needed), contacts **go dark / move / disappear** (a replacement appears later), police check for clones more carefully (where the real car is vs you), buyers of burned contacts get flagged.
- **Fades** slowly; PR or paying a reporter helps. **Server-wide:** one sloppy player's live-TV getaway makes it harder for everyone.

### 13.3 Cold plates (v271)
- **Very hard to get. No shop.** The shady dealer and chop shop only sell stolen plates.
- **Referral required:** high gang respect (prison or street), a record of big clean jobs (no snitching), or a fixer introduction via Connections.
- **The plate maker** is secret and **moves** between hidden spots (`PlateMakerSpot` ×3+), with vague tips ("ask for Lenny behind the laundromat after midnight") and only at certain hours.
- **Made to order:** bring the car (or its type and colour), pay a lot up front, wait 10–20 real minutes; **very limited stock** per server; **no receipts or logs**.
- **Risks:**
  - the plate maker can be an informant (stings)
  - burned plates (the real car stopped nearby, or the plate seen in a crime)
  - snitching burns your underground access
  - getting caught makes the contact vanish for everyone for a while

### 13.4 Elite Representation
See §9.7; it lives in this phase.

---

## 14. TRAFFIC REBUILD (v273–v276)

**Problems today:** ~180 full car models + driver NPCs on the server; clients only smooth the nearest 40; destination routing and gap checks deadlock junctions; stuck recovery takes 8–45 s.
- **Cars as data:** the server simulates lightweight virtual cars (lane, distance, speed); no models, raycasts or NPCs; **500+ cars**. Clients draw only nearby cars from **pooled models** at 60 fps, from compact per-player updates.
- **Real cars on demand:** a car becomes physical when a player is close, crashes into it, carjacks it, or police interact.
- **Lane network from the mapped roads:** lanes per direction, lane centres, one-ways, **pre-built smooth turn curves**, dead-end turnaround loops; prison roads stay closed to civilians.
- **Intelligent Driver Model following:** smooth acceleration and braking, safe gaps; **never stop mid-road** without a reason (a car ahead, a red light, a stop sign). Personalities kept.
- **Deadlock-free junctions:** a car **reserves its path** before entering and enters only if there's space past it ("don't block the box"). Signals cycle; stop signs are first-come. A watchdog breaks any queue stuck for a few seconds; truly stuck cars **out of view** get recycled.
- **Endless roaming:** no destinations; random weighted turns (main roads preferred, no U-turns, avoid dead ends).
- **Density follows players;** spawn/despawn out of sight; empty areas run few cars.
- **Looks:** curves, smooth speed, small lane offsets, **brake lights, turn signals, headlights at night**, spinning/steering wheels, suspension bob, more models and colours, drivers only up close.
- **Interaction:** player/police cars as obstacles via a grid; **sirens: pull right and slow** (never inside a junction); crashes, carjacking, spikes and pursuits hand off to real cars. Ready for **traffic stops** (pull over at the curb) and plate readers.
- **Debug overlay:** lanes, reservations, signals, any car waiting more than a few seconds.
- The user may need to fix road junctions or one-way flags in the existing road mapper.

---

## 15. POLICE GAMEPLAY – LCPDFR STYLE (v277–v279)

- **v277 MDT computer** in cruisers: the DAVID person/plate lookups (§10.4), records, warrants, BOLOs, officer-safety flags, photo match, all logged.
- **v278 Traffic stops** (on AI or players):
  - AI drivers **pull over at the curb**
  - ID, run name and plate
  - frisk (contraband/guns), breathalyzer / field sobriety
  - **citation** (a fine from the bank) or arrest
  - some drivers **flee or fight**
  - warrant hits; DUI → licence suspended
- **v279 Callouts:**
  - dispatch offers jobs to police players (robbery in progress, shots fired, stolen vehicle, warrant subject sighted, pursuit needs backup); accept → GPS route plus attached to the incident
  - **backup requests** (units, K9, helicopter, roadblock)
  - **ambient AI crimes** (muggings, fights, drunk drivers, stolen cars)
  - transporting your own arrests

**The loop:** crime → escape → warrant → plate hit / BOLO → callout → traffic stop → MDT → warrant hit → arrest → bail / plea / trial → jail/prison → record grows.

---

## 16. NEWS NETWORK (v280–v282)

- **Stories (existing phone News app, overhauled):** automatic stories on everything newsworthy:
  - **crime/police:** crimes, pursuits (live), crashes, standoffs, SWAT raids, 6-star military, officers killed, police helicopter down, warrants/BOLOs/mugshots, manhunts, arrests of famous players
  - **court:** **arrest → charged → bail → plea leaks ("sources: suspect cutting deal") → trial → co-defendant testimony → verdict (live countdown) → sentence → appeal**, followed as one story
  - **prison:** riots, lockdowns, gang wars, escapes, recaptures, CO assaults, executions (existing C-SPAN), $50M governor pardons
  - **money:** casino whales, asset seizures ("DA seizes $2M and 3 vehicles"), big purchases (mansion, VIP helicopter), heist totals
  - **people:** repeat offenders, notorious gangs, turning yourself in, released after years, snitch stories (which feed prison reputation), "Billionaire walks again", jury tampering probes, lawyers charged with smuggling, cloned-plate rings, offshore networks exposed
- **Newsworthiness score** (severity, people involved, money, stars, players involved, fame): low → ticker line; medium → article; high → **breaking banner + crews + live broadcast**. Repeats escalate into running stories ("third bank robbery this week").
- **Wanted board** with mugshots; being on the news raises recognition.
- **Crews (v281):**
  - **news helicopter** (NEWS livery, orbits pursuits/scenes from above, keeps distance), from `NewsStation`
  - **news vans** with dishes that park at scenes, the courthouse steps and the prison, with **reporter NPC stand-ups** and the **perp walk**
  - crews arrive after the action starts and linger; big events draw more
  - shooting at crews is a crime and makes headlines
- **Live broadcast (v282):** "WATCH LIVE" switches the viewer's camera to an **auto-director** cutting every few seconds:
  - shots: helicopter orbit (slight shake and zoom), ground camera pan, reporter over-the-shoulder, dramatic low or long-lens angles
  - courtroom broadcast (`CourtCam`) or **sketch mode**
  - graphics: ticker, LIVE bug, lower-third captions
  - optional picture-in-picture
- **Underground scrutiny** (§13.2) is raised by coverage.

---

## 17. HELICOPTERS, CARS & MISC (existing)

- **Player helicopters** (phone app): Robinson R22 $12k, Bell 206 $25k, News Chopper $32k, Airbus H125 $48k, Sikorsky S-76 Executive $95k (Aircraft Discount pass −20%).
  - Saved ownership; spawn on open ground; Fly/Ride prompts; WASD/thumbstick, E/Q or on-screen UP/DOWN; take-off assist; the server applies flight commands too.
  - Will register in DAVID (§10.4).
- **Carjacking** (E) gives a fresh drivable car of the same type and a star.
- **Vehicle health** (20× player): fire, then explosion.
- **Dress-out:** blocky avatar, body accessories removed (hats/hair/face kept), the full avatar restored on release.

---

## 18. BUILD ORDER (see ROADMAP.md for every version)

- **A** v239–v245: arrest & custody (stages ✔, multi-building, arrest scene, HQ processing & records, city jail, bus, towers + vision)
- **B** v246–v249: interrogation, quick-time events, crime log, snitching
- **C** v250–v251: gang ranks, street gangs
- **D** v252–v253: drugs
- **E** v254–v259: bail, freeze/stashes, phone calls, counsel billing / offices / visits, pleas, firm asset management
- **F** v260–v262: warrants, recognition, plates/DAVID data
- **G** v263–v267: courts, bench, jury, judges with memory, appeals
- **H** v268–v272: Connections/fixers, jury tampering, underground/cold plates/Elite Representation, metals/offshore
- **I** v273–v276: traffic rebuild
- **J** v277–v279: MDT, traffic stops, callouts
- **K** v280–v282: news

**Not planned:** GTA 4 handling (discussed: a raycast car controller reading pasted `handling.dat` lines via a `HandlingId` attribute; the user excluded it for now).

---

## 19. FACILITY MAPPER PLUGIN & WHAT THE USER MAPS

- **Plugin:** `plugins/FacilityMapper/FacilityMapper.server.lua` → `lune run tools/build_plugin.luau` → `plugins/FacilityMapper.rbxmx` (Studio Plugins folder).
- **Saves in the existing nav format:**
  - `Zones/<name>` folders: `ZoneType`, `Category` (rooms), `TopY/BottomY`, `NavIgnore`, polygon `ControlPoints`
  - `DoorMarkers/<name>`: `Center` part, `DoorObject` ObjectValue, `DoorType`, `Access`, `Description`, bound/clicked paths
  - `Routes/<name>`: `RouteType` (Escort / **Stairs** / **BusUnloadLine** / Patrol / Vehicle / Walk), path `ControlPoints`
  - `Points/<name>` parts with `PointType`
  - **seats** get a `SeatRole` attribute
- **Map roots:** `CorrectionalFacility.PrisonMap` (already has 144 zones, 156 doors, 3 routes), `<Building>.FacilityMap`, `Workspace.CityMap`.
- **Facilities:** Prison, Courthouse, PoliceHQ, CityJail, LawOffice (`Firm` attribute), Bank, City. Per-facility checklists in the plugin; the full list is in `plugins/MAPPING_GUIDE.md`.
- **Nav ignores `NavIgnore` zones** (KillZone, Perimeter).

### 19.1 Pending plugin fixes (requested by the user; NOT done yet)
1. **Door picking must use exactly the part clicked.**
   - Use the raw `mouse.Target`: no skipping transparent parts, no climbing to a parent "door" model.
   - Show a **hover highlight** (a SelectionBox on the part under the mouse) and the hovered part's full path in the status line.
   - Add a clear **"Pick door part"** selector button: click it, then click the door; it reports what was picked.
2. **Multi-part doors with Shift+click.**
   - **Picking:** while **Shift is held**, each click **adds** that part to a pending door (click again to remove it), and the pending parts are highlighted.
   - **Finishing:** **releasing Shift finalizes** the door (Enter / the Finish button also work). A normal click with no Shift = a single-part door.
   - **Saved data:**
     - `DoorObject` = the parts' **lowest common ancestor** if it's a Model that isn't the facility root/workspace and most of its BaseParts are the picked parts; otherwise the first part
     - a `DoorParts` folder with an ObjectValue per part
     - `Center` = the bounding box of all parts
     - a `PartCount` attribute
   - **Duplicates and Select:** the duplicate check and Select mode must consider `DoorParts`.
   - **Runtime door code** (`openMarkedDoor` etc.) must later open/unlock **all `DoorParts`**, not just `DoorObject`.

---

## 20. USER RULES / PREFERENCES
- Don't play-test unless asked; read the Output the user's tests leave behind.
- Builds are versioned `LasVegas_vNNN_Name.rbxl`. Commit and push to `claude/roblox-cuffwalk-nav-fixes-3ngf7a`.
- The user dislikes regressions: fix root causes, keep guards and pins scoped to their stage, read logs before patching.
- Mobile matters: test layouts at phone size (e.g. UIScale fitting, big touch targets).

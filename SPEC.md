# Let It Cook — Game Specification

## 1. Product Summary

**Let It Cook** is a short-session, isometric strategy game in which the player is a destructive fire deity. The player starts and guides a small fire through increasingly defended settlements while inhabitants react, organize, and try to extinguish it.

The game is not a passive destruction sandbox. A successful run requires the player to:

- preserve a fragile fire long enough for it to become self-sustaining;
- choose where to spend a limited ability resource;
- use wind and the environment to shape the spread;
- overcome human countermeasures such as bucket brigades, firefighters, rain rituals, stone firebreaks, and aerial water drops;
- create routes to high-value environmental targets such as explosive barrels.

The intended player fantasy is **a god observing and manipulating a living disaster**, with readable individual human reactions rather than abstract population markers.

## 2. Product Goals

1. Make fire propagation a strategic problem rather than an automatic level wipe.
2. Keep each level run close to **three minutes**.
3. Support a complete three-level session in approximately **ten minutes**, excluding menus.
4. Make human reactions legible and entertaining at the isometric gameplay scale.
5. Give each level a distinct escalation in density, defenses, and counterplay.
6. Preserve a readable isometric 3D/2.5D perspective while the final art direction is evaluated separately.
7. Design controls specifically for mouse and keyboard desktop play.

## 3. Non-Goals

- Finalizing the game's visual style during the current gameplay-design phase.
- Long-form city building or population management.
- Direct control of a player avatar.
- Persistent metagame progression for the initial polished demo.
- Large upgrade trees before the core three-minute fire-spreading loop is proven fun.

## 4. Target Experience

### 4.1 Core emotional arc

A level should move through four phases:

1. **Spark** — One structure catches fire. The fire is vulnerable and the player has limited influence.
2. **Alarm** — Nearby inhabitants notice the fire, leave buildings, and form an improvised bucket response.
3. **Escalation** — The fire reaches multiple structures while organized defenders and environmental hazards appear.
4. **Inferno** — The player executes a route through the remaining defenses and destroys every ordinary combustible settlement structure before the fire is contained.

The opening should be tense and deliberate. The final minute may become visually chaotic, but it must remain readable and require decisions.

### 4.2 Run duration targets

- Typical successful level: **2:30–3:30**.
- Typical failed level: at least **45 seconds**, unless the player makes an obvious early mistake.
- Full Village → Town → City session: approximately **10 minutes** of active play.
- A settlement must not routinely destroy itself within one to two minutes without player decisions.

## 5. Core Gameplay Loop

1. Survey the settlement, wind, inhabitants, defenses, and environmental targets.
2. Ignite one valid starter structure.
3. Allow the fire to spread naturally while monitoring its strength and direction.
4. Spend accumulated **Embers** to influence the disaster.
5. Counter inhabitants and responders by redirecting fire toward them or their support targets.
6. Create a path through flammable structures to reach barrels and other chain-reaction targets.
7. Destroy all ordinary combustible settlement structures before the fire is fully extinguished.
8. Review results and proceed to the next settlement.

## 6. Tactical Design

### 6.1 Intended tactical feel

Play should feel **deliberate, legible, tense, and increasingly chaotic**.

The idea is to protect ur fire + manage ur resources + opportunistically spread / reach flammable things.

- The player spends more time reading the settlement and anticipating reactions than rapidly clicking targets.
- Every paid action should materially change the likely path of the fire.
- Early fire is fragile, so positioning and restraint matter.
- Late fire is powerful, but isolated pockets and advanced responders still require direction.
- Chaos is the visible result of earlier planning rather than an uncontrollable random outcome.
- The game must not feel idle, click-spammy, dependent on lucky spread rolls, or like a sequence of unrelated emergencies.

The central tactical question is:

> Where should the player establish the next sustainable fire front before defenders close that route?

### 6.2 Decision cadence and level phases

A meaningful decision should occur approximately every **10–20 seconds**. A decision may be an Ember expenditure, a route choice, a threat-priority change, or a deliberate choice to wait and preserve resources.

The phases in Section 4 should produce different decisions:

| Phase | Approximate target | Tactical focus |
|---|---:|---|
| Spark | 0–35 seconds | Choose the opening route, establish the first connection, and avoid wasting Embers. |
| Alarm | 35–90 seconds | Read the bucket brigade, protect the fragile front, or begin a second front. |
| Escalation | 90–150 seconds | Prioritize firefighters, shamans, rain, and environmental shortcuts. |
| Inferno | 150–210 seconds | Maintain momentum while routing around suppression to reach remaining isolated buildings. |

These are pacing targets, not hard timer scripts. Phase changes should primarily follow visible events and destruction progress. The director may delay a new threat when the player is already handling two urgent threats; difficulty should come from interacting systems rather than unreadable overload.

### 6.3 Tactical topology and route design

Each level is designed as an implicit **spread network**:

- Ordinary combustible buildings are mandatory nodes.
- Distance, material, wetness, and obstructions determine whether fire can cross between nodes.
- Roads, canals, courtyards, and stone create breaks in the network.
- Trees may form optional bridges.
- Barrels may create optional shortcuts or area breakthroughs.
- Defender routes intersect the spread network and can be attacked or avoided.

Initial spatial tuning bands are:

- **Connected:** under approximately 4 metres; ordinary fire can cross without assistance.
- **Conditional:** approximately 4–6 metres; crossing requires favorable wind, combined heat from multiple fires, or an environmental chain.
- **Broken:** over approximately 6 metres or divided by a hard firebreak; ordinary spread cannot cross.

Exact distances are subject to playtesting, but every gap must visually communicate its category.

Every generated level must provide:

- at least two viable orders in which to clear mandatory buildings;
- one relatively safe but slower route;
- one faster or more rewarding route exposed to greater defender pressure;
- no mandatory building that can be reached only through a tree or barrel;
- no layout that becomes impossible because an optional prop failed to ignite;
- guaranteed routes around City stone through visible gates or lanes.

Because all ordinary combustible buildings are mandatory, the route decision concerns **order and front management**, not which buildings may be skipped.

### 6.4 Predictable fire, limited uncertainty

Fire spread uses accumulated **ignition pressure**, not repeated opaque all-or-nothing rolls.

- Burning neighbors add heat to a target over time.
- Wind, proximity, multiple burning neighbors, and dry material increase that rate.
- Rain, wetness, distance, and active suppression reduce it.
- A target ignites when its pressure reaches its threshold.
- Small seeded variation may alter timings by no more than approximately 10%; it must not repeatedly invalidate a sound plan.

The player receives progressive in-world feedback:

1. Warm edge or faint smoke: receiving heat.
2. Scorching and sparks: likely to ignite soon.
3. Bright directional embers: actively transferring fire from a specific source.
4. Wet sheen or droplets: currently resistant.
5. Blocked feedback: unreachable because of stone, distance, or another explicit rule.

Normal play should not display a dense graph or numeric probabilities. Hovering a structure or aiming Wind may reveal likely connections and concise states such as **Likely**, **Needs Wind**, **Wet**, or **Blocked**.

If a Wind preview says a target will ignite, the action must produce enough pressure to do so unless a clearly visible defender intervenes. The player should be able to explain why a spread succeeded or failed.

### 6.5 Ember economy and action value

Initial balancing values for the core demo are:

| Rule | Initial value |
|---|---:|
| Starting Embers | 2 |
| Ember capacity | 5 |
| Local Wind Gust | 1 Ember |
| Manual ignition after the free starter | 3 Embers |
| Wind cooldown | 6 seconds |
| Expected paid actions per level | 8–12 |
| Expected manual reignitions/new fronts | 1–2 |

Economy rules:

- Burning down an ordinary mandatory structure grants 1 Ember, subject to an 8-second reward cooldown so a chain reaction does not instantly fill the resource bar.
- Defeating a shaman or firefighter with fire may grant 1 Ember.
- A barrel chain may grant 1 Ember, but optional props must not be required for a viable economy.
- No passive regeneration occurs while the player is safely accumulating resources.
- If the player has zero Embers and still has an active but weak fire, an anti-stall Ember may be granted after 12 seconds without another Ember source.
- Waiting for the anti-stall rule must always be worse than sustaining an effective front.

Wind is the common tactical intervention. Manual ignition is expensive because it bypasses the spread network and creates a new front. A player should often want to keep one Ember available for Wind and should have to sacrifice several near-term gusts to afford a new ignition.

These numbers are starting tuning values. They may change together after playtesting, but the relative relationship—**Wind is frequent, manual ignition is costly**—is normative.

### 6.6 Wind as a local tactical tool

The player's Wind ability is a localized gust, distinct from the level's prevailing ambient wind.

- Right-mouse aiming begins on a burning structure or immediately adjacent flame.
- The drag direction defines an approximately 60-degree cone extending about 8 metres.
- The preview shows which heat-transfer connections will strengthen, remain unchanged, or stay blocked.
- On release, the gust lasts approximately 4 seconds.
- It strongly accelerates ignition pressure downwind within the cone.
- It visibly redirects flames, smoke, and embers.
- It cannot ignite a target without an existing connected flame source.
- It cannot burn City stone or cross a hard firebreak without a gate.
- It does not physically throw characters or directly damage them.

This creates several uses for the same ability:

- push the main front across a conditional gap;
- redirect heat away from a wet or heavily defended target;
- ignite a defender's route before they arrive;
- accelerate a path toward a shaman or barrel;
- recover momentum when a connection is close to failing.

### 6.7 Readable defenders and threat priority

Defenders must expose intent and remain committed long enough for the player to exploit it. They do not possess perfect knowledge of every new fire.

| Threat | Telegraph and commitment | Consequence if ignored | Intended response |
|---|---|---|---|
| Bucket carrier | Notices smoke, runs to a visible water source, then displays a target; one trip at a time. | Can extinguish an isolated opening fire but cannot overpower an established cluster. | Protect the opening, cut the route with fire, or create more pressure than one bucket can remove. |
| Firefighter | Arrival warning and visible target; commits to a target for at least 6 seconds unless it goes out. | Suppresses a lane and steadily damages an established front. | Overwhelm the lane, ignite their approach, or create a second front that forces inefficient travel. |
| Shaman | Visible ritual site, map callout, and approximately 10-second cast. | Summons settlement-wide rain; severe but recoverable rather than an instant loss. | Route fire to the ritual site, kill or displace the shaman, or prepare multiple strong fronts to survive rain. |
| Helicopter | Flight path and drop zone shown at least 5 seconds before impact. | Heavily wets one local cluster. | Stop investing in that cluster temporarily and push another lane. |

AI response rules:

- Civilians react only after seeing nearby fire or receiving an alarm.
- Bucket carriers and firefighters choose from fires they plausibly know about.
- Responders do not retarget every frame; target commitment makes feints possible.
- World-space movement, carried equipment, aim lines, icons, and effects communicate intent without reducing people to abstract dots.
- No single ignored response should erase a healthy inferno instantly.
- Ignoring several overlapping responses should be fatal.

### 6.8 Supported strategic approaches

Each level must support at least two of these approaches, and the complete campaign should reward all four:

#### Rolling front

Keep one dense, connected edge moving through the settlement with frequent Wind use.

- **Strength:** Ember-efficient and easy to sustain.
- **Risk:** responders can concentrate on one predictable lane.

#### Split fronts

Save Embers for an expensive manual ignition and force defenders to travel between two areas.

- **Strength:** divides bucket carriers and firefighters.
- **Risk:** each front is weaker, and the player has fewer Embers available for Wind.

#### Bait and redirect

Allow or create a visible fire that attracts responders, wait for their commitment, then accelerate the true priority route.

- **Strength:** exploits defender travel and commitment time.
- **Risk:** the bait consumes fuel and may not contribute enough momentum.

#### Environmental chain

Route through optional vegetation or toward a barrel to accelerate a difficult section.

- **Strength:** high tempo and area pressure without paying for another manual ignition.
- **Risk:** requires setup, gives defenders time to react, and cannot be mandatory for completion.

No approach should dominate every level. Layout, wind, water access, and defender placement should change which approach is attractive.

### 6.9 Mistakes, recovery, and failure

Mistakes have graduated consequences:

- A poorly aimed Wind costs one resource cycle and several seconds but is normally recoverable.
- Investing in a wet or defended lane may force a route change.
- An unnecessary manual ignition is a major economic mistake because it consumes three Embers.
- Ignoring a shaman causes a difficult rain period but does not automatically end the run.
- Allowing every fire front to collapse is the principal run-ending strategic failure.

Replace the prototype's opaque last-stand behavior with one visible **Last Spark** per level:

- The HUD shows whether Last Spark remains available.
- When the final active flame would be extinguished, its structure smolders for 8 seconds instead of going out immediately.
- During this window, the player may reignite that structure for 1 Ember.
- Last Spark is then consumed for the level.
- If the player cannot or chooses not to recover before the timer ends, the level fails.

This safety valve forgives one collapse while preserving resource consequences. It must not activate silently or restore global fire strength without player action.

### 6.10 Level-specific tactical identity

#### Village

- Teach connected and conditional gaps with a small number of clear building clusters.
- Present a safer route through closely spaced houses and a faster route using an exposed tree bridge.
- Bucket carriers are the main positional threat.
- The first firefighters arrive late enough for the player to understand the bucket response first.

#### Town

- Place the water source so bucket routes intersect useful fire lanes.
- Offer a barrel shortcut that is powerful but not necessary.
- Position the shaman so reaching the ritual competes with maintaining the main front.
- Rain tests whether the player built one fragile front or several mutually supporting fires.

#### City

- Stone divides the map into readable combustible districts linked by at least two gates.
- One gate offers a short route under heavy firefighter pressure; another is longer but less defended.
- Helicopter drops punish over-investment in one cluster without affecting the entire map.
- Elite responders increase pressure without violating normal targeting and commitment rules.

### 6.11 Tactical validation criteria

Playtesting must demonstrate that:

- players can usually identify the next likely ignition target without consulting numeric UI;
- players make at least six consequential route, threat, or resource decisions in a typical successful level;
- unattended opening fires are normally contained;
- a sound Wind preview is reliable unless visible suppression intervenes;
- players use at least two distinct strategic approaches across repeated runs;
- no mandatory route depends on random ignition of an optional prop;
- no individual defender or random outcome decides a healthy run by itself;
- experienced players improve primarily through prediction, timing, and route selection rather than faster clicking.

## 7. Player Resources and Abilities

### 7.1 Embers

Embers are the player's limited action resource. They are represented in the top-left HUD by clearly recognizable fire/ember icons; the current bullet-like presentation must be replaced or relabeled so the resource is unambiguous.

Embers are earned from ordinary mandatory structures burning down, selected defender defeats, optional barrel chains, and the strictly limited anti-stall rule in Section 6.5.

The player must not be able to solve a level by repeatedly clicking every target. Costs and regeneration should reward sustaining intentional fire fronts and exploiting the settlement's spread network.

### 7.2 Ignite

- The first ignition of a level is free.
- It may target only a highlighted starter structure.
- Later manual ignitions cost 3 Embers under the initial demo balance.
- Manual ignition is a recovery or tactical tool, not the primary way to burn the map.
- Explosive barrels, fireproof structures, and protected objective actors cannot be manually ignited.

### 7.3 Wind Gust

Wind is the primary tool for shaping fire spread.

A gust:

- has a visible world-space direction and affected area;
- temporarily accelerates ignition pressure downwind;
- visibly leans flames, smoke, embers, and foliage;
- costs 1 Ember and has a 6-second cooldown under the initial demo balance;
- cannot directly ignite an isolated target;
- cannot burn City stone or bypass a hard firebreak.

The current unexplained central blue arrow/highlight is not acceptable. Wind direction must be communicated through an intentional compass/arrow treatment plus environmental motion. Any target highlight must state why the target is valid.

### 7.4 Wind control

Wind uses a desktop-native right-mouse aiming control:

1. Press and hold the right mouse button on a burning structure or immediately adjacent flame.
2. Move the pointer to set the gust direction. A world-space cone previews the direction, affected area, and strengthened fire connections.
3. Release the right mouse button to cast the gust.
4. Press Escape before release to cancel.

The gust has fixed gameplay strength; drag distance is used only to establish a clear direction. Releasing below the minimum aiming distance cancels without spending Embers. The HUD displays the Ember cost and cooldown while aiming. Using the right mouse button keeps Wind distinct from left-click selection and ignition.

A dedicated Wind HUD button may enter the same aiming mode for discoverability, but touch and cross-platform gestures are outside the current scope.

## 8. Fire Simulation

### 8.1 Structure states

Every combustible structure has three visible states:

1. Unburned
2. Burning
3. Burnt

Transitions must be gradual and readable. Scorching, flame intensity, smoke, collapse, and the final silhouette should communicate remaining fuel without requiring selection.

### 8.2 Spread rules

Fire spreads only between nearby valid targets. Ignition pressure accumulates according to:

- distance;
- wind direction and strength;
- target material;
- target wetness;
- weather;
- active player abilities;
- local firefighting.

Base spread must be slow enough that the player can observe and react. A single burning house should not normally produce an unstoppable cascade. Sustaining several connected fires should create momentum while still allowing defenders to recover.

### 8.3 Fire strength

The global fire-strength meter represents the health and momentum of the overall disaster.

- Active, well-connected structure fires sustain or increase it.
- Rain, water, and firefighters reduce it.
- Burning characters alone cannot sustain the disaster.
- At zero strength, active flames rapidly collapse and the run ends unless an explicitly communicated recovery effect is available.

The system must avoid opaque emergency rules. The only emergency recovery is the visible, player-activated Last Spark defined in Section 6.9.

### 8.4 Wetness and water

Water should reduce flames and apply temporary wetness. It must not paradoxically make a structure reach its burnt/destruction state faster. Wet targets resist ignition until they dry.

### 8.5 Explosive barrels

Barrels are route-planning objectives rather than remote bombs.

- The player cannot manually ignite a barrel.
- A barrel ignites only when reached by an adjacent structure fire, burning character, or another environmental chain reaction.
- The player should need to narrow or guide a flame path toward it.
- Barrels telegraph danger before exploding.
- Explosions ignite or heat nearby valid targets and can open a route through a defended area.
- City stone remains unaffected by explosions and must not display misleading heat or ignition feedback.

## 9. Human Simulation and Counterplay

### 9.1 Villagers

Villagers make the settlement feel inhabited and expose the consequences of player actions.

Expected behavior:

1. Idle or perform simple ambient activities.
2. Notice nearby smoke or fire.
3. React visibly and alert nearby inhabitants.
4. Exit threatened buildings.
5. Panic, flee, or participate in a bucket brigade depending on role and danger.
6. Catch fire only after visible exposure.
7. Run and spread fire while burning.
8. Die only after a readable burning period, leaving a charred result.

A human must not instantly swap from alive to corpse when touched by fire. Burning requires flame effects, movement, vocal/speech feedback, and a survivable interval during which water can save them.

### 9.2 Bucket brigade

The bucket brigade is the first response tier and should appear before official firefighters.

- Nearby villagers notice the initial house fire and fetch water from a well, pond, canal, or other explicit source.
- They carry visibly limited buckets.
- Bucket water is weaker and less frequent than firefighter hoses.
- Their travel route creates strategic opportunities: the player can cut them off, redirect fire toward the water route, or overwhelm their chosen target.
- Bucket carriers retreat when personal danger exceeds their courage threshold.

### 9.3 Firefighters

Official firefighters arrive after the player has had time to establish the fire.

- Arrival is preceded by a clear warning.
- Firefighters prioritize burning structures and endangered humans.
- Hose streams, targets, and water impact must be readable.
- Burning firefighters stop fighting the fire and may spread it while fleeing.
- Later levels may introduce elite responders with visibly distinct gear and stronger statistics.

### 9.4 Shamans / ritualists

Shamans are high-priority mini-objectives.

- A shaman begins a visible ritual after the fire reaches a level-specific alarm threshold.
- The ritual has a clear cast duration and world-space telegraph.
- If completed, it summons rain that suppresses fire across the settlement for a limited time.
- The player cannot click the shaman to kill them directly; fire must be routed to the shaman or ritual site.
- Killing or forcing the shaman to flee interrupts the ritual.
- The HUD identifies the active ritual and remaining cast time without reducing the shaman to an abstract dot.

## 10. Weather and Environmental Interaction

### 10.1 Rain

Rain must have complete visual, audio, and gameplay feedback.

- Visible rain particles across the affected play area.
- Wet ground/structure feedback where feasible.
- Hissing and reduced flame/smoke intensity.
- Reduced spread and increased wetness.
- A finite duration and readable ending.

Town may introduce natural rain. Shaman-summoned rain can appear in any level that contains a shaman.

### 10.2 Stone structures and firebreaks

Stone structures do not burn from ordinary spread and create natural routing difficulty in the City.

- Stone must be visually distinct before the player attempts ignition.
- City stone structures are excluded from the completion denominator.
- Guaranteed gates or lanes provide mandatory routes through a firebreak; vegetation and barrels may provide optional shortcuts but are never required.
- Generated layouts must guarantee that at least one viable route exists.

### 10.3 Helicopters

City helicopters provide late-game suppression through telegraphed water drops.

- Flight path and drop zone must be visible before impact.
- Drops strongly wet a local area rather than arbitrarily reducing an invisible global value.
- The player should be able to redirect spread around a pending drop zone.

## 11. Levels and Progression

### 11.1 Level 1 — Village

Purpose: teach ignition, natural spread, wind, and the human response ladder.

- Sparse wooden structures and vegetation.
- One constrained starter ignition.
- Villagers first attempt a bucket brigade.
- Firefighters arrive only after the bucket response has had time to act.
- No unavoidable rain or stone firebreaks.
- Success requires destruction of every ordinary combustible settlement structure. Trees, barrels, and decorative props are optional.

### 11.2 Level 2 — Town

Purpose: introduce denser routing, water access, barrels, and ritual/weather pressure.

- Tighter wooden blocks.
- Pond, canal, or well used by bucket carriers.
- Barrels positioned as optional but valuable chain-reaction routes.
- At least one shaman or natural rain event.
- Faster official response than the Village.
- Success requires destruction of every ordinary combustible settlement structure. Trees, barrels, and decorative props are optional.

### 11.3 Level 3 — City

Purpose: test mastery against firebreaks and advanced suppression.

- Dense outer combustible districts.
- Stone inner structures or ring forming a firebreak.
- Guaranteed gates or routes through the stone boundary.
- Elite firefighters and telegraphed helicopter drops.
- Barrels or other environmental tools placed to reward route planning.
- Success requires destruction of every ordinary combustible settlement structure. City stone, trees, barrels, and decorative props are excluded.

### 11.4 Completion and failure

- The completion bar measures ordinary combustible settlement structures destroyed.
- The goal is **100% of ordinary combustible settlement structures**, not the prototype's 70–80% thresholds.
- City stone, trees, barrels, and decorative props do not count toward completion.
- The level fails when no viable player-controlled or naturally spreading flame remains and the player has no immediate recovery action.
- Results freeze gameplay simulation before presenting statistics.

## 12. Difficulty and Pacing

Difficulty should come from competing systems, not faster burn rates alone.

Escalation knobs include:

- longer distances between combustible targets;
- fewer starting Embers;
- stronger or more coordinated bucket brigades;
- earlier firefighter warnings after the first response phase;
- shamans and rain;
- stone firebreaks;
- local water drops;
- more selective barrel placement.

Balancing targets:

- The initial house burns long enough for neighbors to notice, exit, and begin a response.
- The player should make multiple consequential wind/resource decisions per level.
- An unattended fire should usually be contained.
- A carefully guided fire should reach a self-sustaining inferno late in the run.
- No single barrel or early spread roll should decide the whole level.

## 13. Roguelike Upgrades

The existing between-level upgrades are secondary to the core loop. They should remain disabled or minimal until all three levels reliably meet the pacing and challenge targets.

If retained for the demo:

- offer one choice after Village and Town;
- never offer an upgrade already owned;
- describe exact mechanical effects;
- avoid upgrades that merely make an already easy fire burn faster;
- prefer choices that alter strategy, such as wind control, recovery, or environmental interaction;
- reset upgrades at the start of a new three-level run.

No persistent save-based progression is required for the initial demo.

## 14. Controls

### 14.1 Desktop defaults

| Action | Input |
|---|---|
| Select / ignite target | Left click |
| Aim Wind | Hold right mouse button and move pointer |
| Cast Wind | Release right mouse button after a valid aim |
| Cancel Wind | Escape before release |
| Pan camera | WASD or arrow keys |
| Zoom | Mouse wheel, Q/E, or -/+ |
| Pause | Escape or P |

While Wind aiming is active, Escape cancels the aim instead of opening pause. A second Escape may then pause normally.

Camera movement must follow screen expectations:

- W / Up moves the view upward/north.
- S / Down moves the view downward/south.
- A / Left moves left/west.
- D / Right moves right/east.

The prototype behavior in which S moves the view upward is a defect. The implementation must be corrected if runtime validation reproduces it.

### 14.2 Input requirements

- Define custom Godot input actions rather than relying solely on hard-coded key checks.
- Input prompts match the configured desktop bindings.
- Left-click ignition, right-mouse Wind aiming, camera movement, and UI controls must not conflict.
- Every paid action previews its cost and validity before execution.

## 15. Camera and Presentation

- Fixed isometric-like orthographic perspective.
- Camera pans and zooms but does not need free rotation.
- The full active fire front and incoming threats should remain readable.
- Camera shake is reserved for major events and must have a reduced-motion option.
- Edge panning is optional and disabled by default unless onboarding explains it.

## 16. Visual Direction

### 16.1 Style status

The final art direction is deliberately postponed. The current voxel presentation and the proposed Polytopia-like low-poly direction remain references rather than an approved target. No implementation should commit the project to either style until a separate art-direction decision is made.

The isometric 3D/2.5D perspective remains approved independently of the asset style.

### 16.2 Readability requirements

- Wooden, wet, burning, burnt, explosive, and fireproof targets are distinguishable at gameplay zoom.
- Villagers, bucket carriers, firefighters, elite firefighters, and shamans have distinct silhouettes and colors.
- Fire direction and intensity are visible in-world.
- Highlights are used only for actionable targets and use consistent colors.
- Placeholder blue house overlays and the unexplained central blue wind marker must be removed or redesigned.
- Fire, rain, water streams, explosions, and human burning states require complete effects rather than code-only state changes.

### 16.3 Animation priorities

1. Villager notice/alert/exit behavior.
2. Bucket pickup, carry, throw, and refill.
3. Panic and burning reactions.
4. Firefighter spraying and retreat.
5. Shaman ritual and interruption.
6. Structure scorch and collapse.

## 17. Audio

Audio must reinforce state without clipping or distortion.

Required categories:

- layered fire crackle whose intensity follows active fire;
- ignition, spread, collapse, and barrel explosion effects;
- bucket splash, hose, rain, and steam/hiss;
- villager alarm/panic and responder warnings;
- shaman ritual cue;
- restrained music that does not mask effects.

Technical requirements:

- Normalize generated and imported sounds to prevent clipping.
- Limit simultaneous high-amplitude procedural voices.
- Use separate Music, SFX, Ambience, and Master buses.
- Provide persistent volume controls.
- Verify that default settings do not reproduce the prototype's distorted output.

## 18. HUD and Menus

### 18.1 In-game HUD

Display only information needed for immediate decisions:

- Embers and ability costs;
- global fire strength;
- combustible destruction progress and 100% goal marker;
- current wind direction/strength;
- selected ability and cooldown;
- active major threat, such as incoming firefighters, rain, helicopter drop, or ritual cast.

The HUD may celebrate combos, but announcements must not obscure targets.

### 18.2 Menus

- Main menu: New Run, unlocked level access for development/demo use, Options, Quit where supported.
- Pause: Resume, controls, audio, reduced motion, edge pan, restart, main menu.
- Results: duration, destruction percentage, villagers affected, responders defeated, best combo, peak simultaneous fires, and rank.
- Rank is based on fire continuity, Ember efficiency, environmental chain reactions, and optional objectives. Elapsed time is displayed for pacing analysis but does not grant a better rank merely for finishing faster.
- Results and upgrade overlays pause all simulation.

### 18.3 Persistence

Persist locally:

- audio settings;
- accessibility/camera preferences;
- level unlocks if level select is exposed.

Run-specific Embers and upgrades reset on New Run.

## 19. Technical Direction

The current project baseline is Godot 4.7, orthographic `Camera3D`, and runtime-generated low-poly geometry.

The implementation should preserve the simple scene model while separating responsibilities currently concentrated in `scenes/game.gd`:

- level definition and generation;
- fire simulation and spread;
- encounter/director timing;
- player abilities and input;
- UI presentation;
- audio generation/playback;
- run progression.

Level-specific behavior should be data-driven. A level definition must identify ordinary combustible settlement structures separately from optional trees, optional barrels, decorative props, and excluded City stone.

Use named Godot input actions for all controls. All actor and simulation processing must stop when paused or after results are shown.

## 20. Current Prototype Baseline

The repository currently implements:

- procedurally generated Village, Town, and City layouts;
- combustible houses, trees, barrels, and fireproof stone;
- global fire strength, Embers, wind, rain, barrel explosions, firefighters, helicopters, and three session upgrades;
- autonomous villagers and firefighters that can catch and spread fire;
- orthographic camera pan/zoom;
- HUD, pause, results, level unlock, and upgrade panels;
- runtime-generated voxel geometry, particles, music, and sound effects.

Verified implementation details:

- Town rain creates and toggles a 120-particle `GPUParticles3D` effect, dims scene lighting, wets burning structures and characters, reduces spread, and damages global fire strength. The particle mechanic is present; its wider presentation remains incomplete.
- Villagers and firefighters visibly burn through the shared `CharBurn` component before becoming remains. It provides animated flame meshes, ember and smoke particles, firelight, water extinguishing, and delayed death. Villagers burn for approximately 10–13 seconds, firefighters for approximately 5–6 seconds, and villagers display `AAA!!` while fleeing.

Known gaps between the current prototype and the target design:

- 70%, 75%, and 80% completion thresholds;
- rapid burn/spread pacing and early level wipes;
- unrestricted first ignition;
- direct manual barrel ignition;
- left-mouse drag Wind control that conflicts with desktop ignition input;
- ambiguous blue highlights and wind marker;
- rain without dedicated audio, wet-ground feedback, or explicit flame/smoke suppression;
- placeholder visuals pending a separate art-direction decision;
- distorted procedural audio;
- repeatable already-owned upgrades;
- game simulation continuing behind results;
- absence of bucket brigades and shamans.

Known implementation defects to resolve include incorrect generated house dimensions, missing City firebreak gates, elite firefighters using regular visuals, incomplete burnt-tree visuals, barrel explosions failing to prime stone as described, and controls whose movement direction does not match the displayed expectation.

## 21. Demo Acceptance Criteria

The polished initial demo is complete when:

1. Village, Town, and City are playable in sequence without restarting the application.
2. A representative successful run of each level lasts 2:30–3:30.
3. Leaving the initial fire unattended usually leads to containment rather than a level wipe.
4. The first ignition is restricted to an indicated starter structure.
5. Every ordinary combustible settlement structure must be destroyed; City stone, trees, barrels, and decorative props are clearly excluded from the counter.
6. Villagers notice the initial fire and attempt a visible bucket response before official firefighters arrive.
7. At least one level contains a shaman whose interruptible ritual summons fully presented rain.
8. Barrels cannot be manually ignited and must be reached through fire spread.
9. Holding the right mouse button previews Wind direction and area; releasing casts it, while an invalid aim or Escape cancels without spending Embers.
10. WASD and arrow camera movement match their screen directions.
11. Humans visibly burn for a period before death and can be rescued by water.
12. City stone creates a firebreak with at least one generated viable route.
13. All weather, water, fire, and explosion mechanics have matching visual and audio feedback.
14. UI highlights communicate a specific valid action; no unexplained placeholder markers remain.
15. Audio is free of audible clipping at default settings and volume preferences persist.
16. Results and pause screens stop gameplay simulation.
17. Already-owned upgrades cannot be selected again.
18. Final art-style approval is not an acceptance criterion for this gameplay-design phase; functional gameplay states must still remain distinguishable.

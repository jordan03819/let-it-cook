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
6. Establish a vibrant, sharp, authored low-poly style inspired by **The Battle of Polytopia**, viewed from an isometric 3D/2.5D perspective.
7. Support mouse and keyboard as a first-class control scheme. Touch gestures may be supported, but no core action may depend on swiping alone.

## 3. Non-Goals

- Hades-level character detail, animation count, or production scope.
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
4. **Inferno** — The player executes a route through the remaining defenses and destroys every required combustible target before the fire is contained.

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
7. Destroy all required combustible structures before the fire is fully extinguished.
8. Review results and proceed to the next settlement.

## 6. Player Resources and Abilities

### 6.1 Embers

Embers are the player's limited action resource. They are represented in the top-left HUD by clearly recognizable fire/ember icons; the current bullet-like presentation must be replaced or relabeled so the resource is unambiguous.

Embers are earned through active play, including:

- structures burning down;
- defeating firefighters or ritualists with fire;
- maintaining meaningful spread or combo milestones;
- a slow anti-stall regeneration when the player has no viable action.

The player must not be able to solve a level by repeatedly clicking every target. Costs and regeneration should reward maintaining one connected disaster.

### 6.2 Ignite

- The first ignition of a level is free.
- It may target only a highlighted starter structure.
- Later manual ignitions cost Embers.
- Manual ignition is a recovery or tactical tool, not the primary way to burn the map.
- Explosive barrels, fireproof structures, and protected objective actors cannot be manually ignited.

### 6.3 Wind Gust

Wind is the primary tool for shaping fire spread.

A gust:

- has a visible world-space direction and affected area;
- temporarily increases spread probability downwind;
- visibly leans flames, smoke, embers, and foliage;
- costs Embers and has a cooldown;
- cannot directly ignite an isolated target;
- may temporarily heat or weaken designated barriers where level rules allow it.

The current unexplained central blue arrow/highlight is not acceptable. Wind direction must be communicated through an intentional compass/arrow treatment plus environmental motion. Any target highlight must state why the target is valid.

### 6.4 Ability controls across platforms

Core abilities must not require a touch-only swipe gesture.

- **Desktop:** select the Wind ability using a HUD button or keyboard shortcut, then point and drag/click in the world to choose direction. The existing direct mouse-drag gesture may remain as a shortcut.
- **Touch:** select Wind and swipe or drag in the world.
- Both schemes must show an aiming preview before the ability is committed.
- Releasing an invalid or too-short gesture must cancel without spending Embers.

## 7. Fire Simulation

### 7.1 Structure states

Every combustible structure has three visible states:

1. Unburned
2. Burning
3. Burnt

Transitions must be gradual and readable. Scorching, flame intensity, smoke, collapse, and the final silhouette should communicate remaining fuel without requiring selection.

### 7.2 Spread rules

Fire spreads only between nearby valid targets. Spread probability is influenced by:

- distance;
- wind direction and strength;
- target material;
- target wetness;
- weather;
- active player abilities;
- local firefighting.

Base spread must be slow enough that the player can observe and react. A single burning house should not normally produce an unstoppable cascade. Sustaining several connected fires should create momentum while still allowing defenders to recover.

### 7.3 Fire strength

The global fire-strength meter represents the health and momentum of the overall disaster.

- Active, well-connected structure fires sustain or increase it.
- Rain, water, and firefighters reduce it.
- Burning characters alone cannot sustain the disaster.
- At zero strength, active flames rapidly collapse and the run ends unless an explicitly communicated recovery effect is available.

The system must avoid opaque emergency rules. If a last-stand recovery remains, its availability and effect must be visible to the player.

### 7.4 Wetness and water

Water should reduce flames and apply temporary wetness. It must not paradoxically make a structure reach its burnt/destruction state faster. Wet targets resist ignition until they dry.

### 7.5 Explosive barrels

Barrels are route-planning objectives rather than remote bombs.

- The player cannot manually ignite a barrel.
- A barrel ignites only when reached by an adjacent structure fire, burning character, or another environmental chain reaction.
- The player should need to narrow or guide a flame path toward it.
- Barrels telegraph danger before exploding.
- Explosions ignite or heat nearby valid targets and can open a route through a defended area.
- Explosion behavior against stone must match its feedback: either visibly heat/prime the stone or leave it unaffected.

## 8. Human Simulation and Counterplay

### 8.1 Villagers

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

### 8.2 Bucket brigade

The bucket brigade is the first response tier and should appear before official firefighters.

- Nearby villagers notice the initial house fire and fetch water from a well, pond, canal, or other explicit source.
- They carry visibly limited buckets.
- Bucket water is weaker and less frequent than firefighter hoses.
- Their travel route creates strategic opportunities: the player can cut them off, redirect fire toward the water route, or overwhelm their chosen target.
- Bucket carriers retreat when personal danger exceeds their courage threshold.

### 8.3 Firefighters

Official firefighters arrive after the player has had time to establish the fire.

- Arrival is preceded by a clear warning.
- Firefighters prioritize burning structures and endangered humans.
- Hose streams, targets, and water impact must be readable.
- Burning firefighters stop fighting the fire and may spread it while fleeing.
- Later levels may introduce elite responders with visibly distinct gear and stronger statistics.

### 8.4 Shamans / ritualists

Shamans are high-priority mini-objectives.

- A shaman begins a visible ritual after the fire reaches a level-specific alarm threshold.
- The ritual has a clear cast duration and world-space telegraph.
- If completed, it summons rain that suppresses fire across the settlement for a limited time.
- The player cannot click the shaman to kill them directly; fire must be routed to the shaman or ritual site.
- Killing or forcing the shaman to flee interrupts the ritual.
- The HUD identifies the active ritual and remaining cast time without reducing the shaman to an abstract dot.

## 9. Weather and Environmental Interaction

### 9.1 Rain

Rain must have complete visual, audio, and gameplay feedback.

- Visible rainfall across the affected play area.
- Wet ground/structure feedback where feasible.
- Hissing and reduced flame/smoke intensity.
- Reduced spread and increased wetness.
- A finite duration and readable ending.

Town may introduce natural rain. Shaman-summoned rain can appear in any level that contains a shaman.

### 9.2 Stone structures and firebreaks

Stone structures do not burn from ordinary spread and create natural routing difficulty in the City.

- Stone must be visually distinct before the player attempts ignition.
- Stone structures are excluded from the combustible-destruction completion denominator unless a level explicitly gives them a destructible state.
- Gaps, gates, vegetation, barrels, or temporarily heated sections provide intentional routes through a firebreak.
- Generated layouts must guarantee that at least one viable route exists.

### 9.3 Helicopters

City helicopters provide late-game suppression through telegraphed water drops.

- Flight path and drop zone must be visible before impact.
- Drops strongly wet a local area rather than arbitrarily reducing an invisible global value.
- The player should be able to redirect spread around a pending drop zone.

## 10. Levels and Progression

### 10.1 Level 1 — Village

Purpose: teach ignition, natural spread, wind, and the human response ladder.

- Sparse wooden structures and vegetation.
- One constrained starter ignition.
- Villagers first attempt a bucket brigade.
- Firefighters arrive only after the bucket response has had time to act.
- No unavoidable rain or stone firebreaks.
- Success requires destruction of every required combustible structure.

### 10.2 Level 2 — Town

Purpose: introduce denser routing, water access, barrels, and ritual/weather pressure.

- Tighter wooden blocks.
- Pond, canal, or well used by bucket carriers.
- Barrels positioned as optional but valuable chain-reaction routes.
- At least one shaman or natural rain event.
- Faster official response than the Village.
- Success requires destruction of every required combustible structure.

### 10.3 Level 3 — City

Purpose: test mastery against firebreaks and advanced suppression.

- Dense outer combustible districts.
- Stone inner structures or ring forming a firebreak.
- Guaranteed gates or routes through the stone boundary.
- Elite firefighters and telegraphed helicopter drops.
- Barrels or other environmental tools placed to reward route planning.
- Success requires destruction of every required combustible structure; permanent fireproof scenery is excluded.

### 10.4 Completion and failure

- The completion bar measures required combustible structures destroyed.
- The goal is **100% of required targets**, not the prototype's 70–80% thresholds.
- Decorative props and permanently fireproof scenery do not count.
- The level fails when no viable player-controlled or naturally spreading flame remains and the player has no immediate recovery action.
- Results freeze gameplay simulation before presenting statistics.

## 11. Difficulty and Pacing

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

## 12. Roguelike Upgrades

The existing between-level upgrades are secondary to the core loop. They should remain disabled or minimal until all three levels reliably meet the pacing and challenge targets.

If retained for the demo:

- offer one choice after Village and Town;
- never offer an upgrade already owned;
- describe exact mechanical effects;
- avoid upgrades that merely make an already easy fire burn faster;
- prefer choices that alter strategy, such as wind control, recovery, or environmental interaction;
- reset upgrades at the start of a new three-level run.

No persistent save-based progression is required for the initial demo.

## 13. Controls

### 13.1 Desktop defaults

| Action | Input |
|---|---|
| Select / ignite target | Left click |
| Aim and use selected ability | Left click/drag in world |
| Quick Wind shortcut | Dedicated key plus pointer aim |
| Pan camera | WASD or arrow keys |
| Zoom | Mouse wheel, Q/E, or -/+ |
| Pause | Escape or P |

Camera movement must follow screen expectations:

- W / Up moves the view upward/north.
- S / Down moves the view downward/south.
- A / Left moves left/west.
- D / Right moves right/east.

The prototype behavior in which S moves the view upward is a defect.

### 13.2 Touch defaults

- Tap to select or ignite.
- Select Wind, then drag to aim and release to commit.
- Pinch to zoom if implemented.
- Dragging for camera movement must not accidentally spend an ability.

### 13.3 Input requirements

- Define custom Godot input actions rather than relying solely on hard-coded key checks.
- Input prompts change to match the active input device.
- UI controls and world gestures must not conflict.
- Every paid action previews its cost and validity before execution.

## 14. Camera and Presentation

- Fixed isometric-like orthographic perspective.
- Camera pans and zooms but does not need free rotation.
- The full active fire front and incoming threats should remain readable.
- Camera shake is reserved for major events and must have a reduced-motion option.
- Edge panning is optional and disabled by default unless onboarding explains it.

## 15. Visual Direction

### 15.1 Style

Use **The Battle of Polytopia** as a practical visual benchmark:

- vibrant, deliberate palette;
- sharp silhouettes;
- clean low-poly geometry;
- strong separation between terrain, buildings, units, fire, and water;
- authored visual identity rather than generic voxel primitives.

Retain the isometric 3D/2.5D viewpoint associated with games such as Polytopia or Clash of Clans. Do not pursue Hades-level detail within this scope.

### 15.2 Readability requirements

- Wooden, wet, burning, burnt, explosive, and fireproof targets are distinguishable at gameplay zoom.
- Villagers, bucket carriers, firefighters, elite firefighters, and shamans have distinct silhouettes and colors.
- Fire direction and intensity are visible in-world.
- Highlights are used only for actionable targets and use consistent colors.
- Placeholder blue house overlays and the unexplained central blue wind marker must be removed or redesigned.
- Fire, rain, water streams, explosions, and human burning states require complete effects rather than code-only state changes.

### 15.3 Animation priorities

1. Villager notice/alert/exit behavior.
2. Bucket pickup, carry, throw, and refill.
3. Panic and burning reactions.
4. Firefighter spraying and retreat.
5. Shaman ritual and interruption.
6. Structure scorch and collapse.

## 16. Audio

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

## 17. HUD and Menus

### 17.1 In-game HUD

Display only information needed for immediate decisions:

- Embers and ability costs;
- global fire strength;
- combustible destruction progress and 100% goal marker;
- current wind direction/strength;
- selected ability and cooldown;
- active major threat, such as incoming firefighters, rain, helicopter drop, or ritual cast.

The HUD may celebrate combos, but announcements must not obscure targets.

### 17.2 Menus

- Main menu: New Run, unlocked level access for development/demo use, Options, Quit where supported.
- Pause: Resume, controls, audio, reduced motion, edge pan, restart, main menu.
- Results: duration, destruction percentage, villagers affected, responders defeated, best combo, peak simultaneous fires, and rank.
- Results and upgrade overlays pause all simulation.

### 17.3 Persistence

Persist locally:

- audio settings;
- accessibility/camera preferences;
- level unlocks if level select is exposed.

Run-specific Embers and upgrades reset on New Run.

## 18. Technical Direction

The current project baseline is Godot 4.7, orthographic `Camera3D`, and runtime-generated low-poly geometry.

The implementation should preserve the simple scene model while separating responsibilities currently concentrated in `scenes/game.gd`:

- level definition and generation;
- fire simulation and spread;
- encounter/director timing;
- player abilities and input;
- UI presentation;
- audio generation/playback;
- run progression.

Level-specific behavior should be data-driven. A level definition must identify required combustible targets separately from decorative props and permanent fireproof scenery.

Use named Godot input actions for all controls. All actor and simulation processing must stop when paused or after results are shown.

## 19. Current Prototype Baseline

The repository currently implements:

- procedurally generated Village, Town, and City layouts;
- combustible houses, trees, barrels, and fireproof stone;
- global fire strength, Embers, wind, rain, barrel explosions, firefighters, helicopters, and three session upgrades;
- autonomous villagers and firefighters that can catch and spread fire;
- orthographic camera pan/zoom;
- HUD, pause, results, level unlock, and upgrade panels;
- runtime-generated voxel geometry, particles, music, and sound effects.

The following are prototype behavior, not target behavior:

- 70%, 75%, and 80% completion thresholds;
- rapid burn/spread pacing and early level wipes;
- unrestricted first ignition;
- direct manual barrel ignition;
- touch input without a functional Wind gesture;
- ambiguous blue highlights and wind marker;
- rain logic without sufficient presentation;
- generic flat voxel visuals;
- distorted procedural audio;
- repeatable already-owned upgrades;
- game simulation continuing behind results;
- absence of bucket brigades and shamans.

Known implementation defects to resolve include incorrect generated house dimensions, missing City firebreak gates, elite firefighters using regular visuals, incomplete burnt-tree visuals, barrel explosions failing to prime stone as described, and controls whose movement direction does not match the displayed expectation.

## 20. Demo Acceptance Criteria

The polished initial demo is complete when:

1. Village, Town, and City are playable in sequence without restarting the application.
2. A representative successful run of each level lasts 2:30–3:30.
3. Leaving the initial fire unattended usually leads to containment rather than a level wipe.
4. The first ignition is restricted to an indicated starter structure.
5. Every required structure must be destroyed; excluded scenery is clearly identified and not counted.
6. Villagers notice the initial fire and attempt a visible bucket response before official firefighters arrive.
7. At least one level contains a shaman whose interruptible ritual summons fully presented rain.
8. Barrels cannot be manually ignited and must be reached through fire spread.
9. Desktop players can aim Wind without using a touch-style swipe as the only interaction.
10. WASD and arrow camera movement match their screen directions.
11. Humans visibly burn for a period before death and can be rescued by water.
12. City stone creates a firebreak with at least one generated viable route.
13. All weather, water, fire, and explosion mechanics have matching visual and audio feedback.
14. UI highlights communicate a specific valid action; no unexplained placeholder markers remain.
15. Audio is free of audible clipping at default settings and volume preferences persist.
16. Results and pause screens stop gameplay simulation.
17. Already-owned upgrades cannot be selected again.
18. The art pass demonstrates the approved vibrant, sharp low-poly direction with distinct silhouettes for all gameplay roles.

## 21. Open Questions and Information Conflicts

The following differences between the discussion and current implementation require confirmation or runtime validation.

### 21.1 Initial ignition

The discussion describes a fire initially sparking inside one house, which may imply an automatic scripted event. The prototype and this specification instead give the player a free choice among highlighted starter structures.

**Decision required:** choose between automatic ignition and constrained player-selected ignition.

### 21.2 Complete destruction and stone structures

The desired completion condition is to burn everything, while City stone blocks ordinary fire. A literal 100% requirement may therefore be impossible without a special way to destroy stone.

This specification currently defines success as destroying 100% of required combustible structures and excludes permanent stone scenery.

**Decision required:** confirm that exclusion or define how stone becomes destructible.

### 21.3 Swipe implementation

The discussion describes Wind as a touch-swipe mechanic and questions its usefulness outside mobile. The current code implements mouse dragging for Wind, while touch dragging does not activate it. The implementation is effectively the reverse of the description.

**Decision required:** retain the cross-platform select-and-aim design in this specification and treat direct mouse/touch dragging as optional shortcuts.

### 21.4 Rain presentation

The discussion says rain logic exists without visual effects. The current code generates blue cube rain particles. These may have been added after the discussion or may be too unclear to count as adequate feedback.

**Validation required:** inspect rain in a running build and determine whether it needs replacement or only refinement.

### 21.5 Burning-human presentation

The discussion presents visible burning instead of instant corpse replacement as intended work. The code already implements a burning duration, flame effects, movement, an `AAA!!` bubble, water rescue, and eventual death.

**Validation required:** determine whether the mechanic is functionally complete but visually inadequate.

### 21.6 Camera inversion

The observed build reportedly moves upward when S is pressed. The source assigns conventional W/S input signs but converts movement through camera-relative forward vectors, which may invert the resulting screen-space motion.

**Validation required:** test all pan directions in a running build. The observed behavior takes precedence over the apparent source-level intent.

### 21.7 Barrel ignition

The current code allows direct manual barrel ignition. The desired design requires fire to spread naturally to barrels so that reaching one is a route-planning challenge.

This specification treats natural-spread-only barrel ignition as authoritative.

### 21.8 Completion denominator

The current completion calculation counts houses, trees, barrels, and stone together. This specification introduces an explicit set of required combustible targets.

**Decision required:** determine whether trees and barrels are mandatory completion targets or optional environmental props.

### 21.9 Pacing and rank scoring

The target run duration is approximately three minutes, but the current rank system awards three stars below 100 seconds, two below 180 seconds, and one thereafter. It therefore rewards the overly fast pacing the redesign is intended to remove.

**Decision required:** replace time-only ranks with target-window scoring or rebalance thresholds after pacing is finalized.

### 21.10 Voxel and Polytopia art direction

The discussion supports voxels while also selecting Polytopia as the visual benchmark. Polytopia uses stylized low-poly forms rather than a strict voxel presentation.

This specification interprets the direction as retaining an isometric low-poly presentation while replacing generic cube-built visuals with authored silhouettes, palette, and materials.

**Decision required:** confirm that this low-poly compromise supersedes strict voxel art.

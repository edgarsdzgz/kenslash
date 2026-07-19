# Crafting Systems Research -- Cross-Game Survey (2026-07-16)

Research pause requested by user before building resumes. Goal: understand what makes crafting
systems loved vs tolerated vs hated across the survival/extraction genre, so Kenslash can adopt the
*praised mechanics* without inheriting the *common failure modes*. Sources are player-consensus +
game-design writing (not marketing). This is a RESEARCH doc, not a build spec.

---

## TL;DR (read this first)

- **The systems people praise regardless of whether they like the game** are: **Subnautica** (scan-to-
  learn, exploration IS progression), **Valheim** (biome-gated tiers, each new zone is a crafting wall
  you must beat), and **Minecraft** (spatial grid + discovery). Rust's **tech tree** is praised as a
  *fix* more than a joy. The Forest/Grounded get honorable mentions for tactile, low-friction recipes.
- **The single biggest thing the beloved systems share:** crafting progression is *earned through the
  world*, not through a menu you grind. You unlock the next tier by *going somewhere new and surviving
  it* -- not by clicking "research" 50 times.
- **The single biggest thing the disliked systems share:** friction that isn't fun -- deep recipe trees
  that confuse *complexity* with *depth* (Project Zomboid, sometimes Icarus), no craft-from-storage
  (Enshrouded's #1 complaint), and recipes gated behind grindy skill/magazine RNG rather than
  discovery.
- **For us:** we're a fast top-down hack-and-slash, not a base-builder. The right fit is a **lean,
  discovery-flavored, exploration-gated** system -- closer to Subnautica/Valheim's *feel* than to
  Icarus/PZ's *breadth*. Details in the "What this means for Kenslash" section.

---

## Per-game breakdown

### Minecraft -- the spatial grid + discovery (LAUDED, foundational)
- **What sets it apart:** you lay ingredients out in the *shape* of the thing you're making. The UI IS
  the mechanic -- "seeing something where nothing exists." Originally shipped with NO recipe book, so
  discovery drove a whole meta of players teaching each other. Design writers cite it as the canonical
  study piece for shape-based UI + mystery-driven progression.
- **Pros:** instantly intuitive; tactile; low reading; discovery creates community + "aha" moments;
  simple recipes keep you playing not menu-diving.
- **Cons:** modern imitators strip the mystery but keep the complexity (worst of both). The pure grid
  doesn't scale to hundreds of recipes without a recipe book bolted on (which Minecraft eventually
  added, diluting the discovery).
- **Players like:** the feeling of *making* rather than *filling out a form*; that early recipes are
  memorizable.
- **UI lesson:** a crafting UI should reinforce the game's identity, not be a generic list.

### Valheim -- biome-gated tier walls (LAUDED, the progression gold standard)
- **What sets it apart:** progression is **gated by biome**. Each new biome is a wall; to beat it you
  need the gear the *previous* biome's materials let you craft, and its own materials unlock the next
  tier. Crafting, exploration, and combat are the same loop. Upgrade stations must be *built and
  fed* (a workbench near your forge, upgraded with better parts) so your base grows with your power.
- **Pros:** every new material matters; equipment/upgrade choices feel meaningful; discovery-driven
  (you find a new metal, you know a new tier just opened); deep but legible.
- **Cons:** can feel grindy on the gather step; heavily tied to base-building (stations must be placed
  and near you), which a non-builder game can't lean on as hard.
- **Players like:** that reaching a new biome *is* the reward and the next crafting gate at once --
  goal and progression are the same thing.

### Subnautica -- scan-to-learn blueprints (LAUDED, exploration-as-progression)
- **What sets it apart:** you unlock recipes by **scanning** things in the world. Exploration is
  *literally* how you progress -- the Scanner is "the single tool that separates players who progress
  from those who spin their wheels." Some blueprints need multiple scans (a progress bar fills), so it
  paces discovery. The scanner also doubles as a harvest tool, so it's never dead weight.
- **Pros:** progression clarity (visible progress bar); ties unlocks to *going and looking*, not
  grinding; every wreck/creature is a potential unlock so the world stays interesting; the "unlock
  tool" being multi-use is a clean design trick.
- **Cons:** if scannables are sparse you can stall; leans on a rich hand-crafted world to have things
  worth scanning.
- **Players like:** that curiosity is directly rewarded; layered progression from simple gear -> power
  systems -> base sustainability.

### Rust -- workbench tiers + tech tree (PRAISED AS A FIX, not as joy)
- **What sets it apart:** 4 workbench tiers; you spend **Scrap** to research any craftable item on the
  tech tree instead of praying for a rare blueprint drop. Turned a punishing RNG-gated economy into a
  deterministic grind you control.
- **Pros:** accessibility -- newer players / small groups can reach top-tier gear without needing to
  raid for a blueprint; more viable strategies; clear tier ladder.
- **Cons:** *"diminishes the excitement of putting a high-tier item in your inventory for the first
  time."* Higher benches are very Scrap-expensive (125-500 scrap per blueprint), so the late tree is a
  slog. Praised as a *correction* to a bad old system more than as inherently delightful.
- **Players like:** control and predictability. **Dislike:** the loss of the rare-find thrill; the
  grind wall on T3.
- **Lesson:** deterministic "spend currency to unlock" fixes RNG frustration but *taxes* the joy of
  discovery. There's a real tension between "no bad luck" and "genuine surprise."

### The Forest / Grounded -- tactile, low-friction survival crafting (liked)
- **What sets it apart:** clear visual ingredient->output relationships (rags + bottle = molotov
  logic), fast to read, tension-managing (scarcity drives emotional pacing). Grounded gets cited
  alongside as an accessible modern take.
- **Pros:** intuitive; you rarely fight the menu; supports moment-to-moment survival tension.
- **Cons:** shallower long-tail than the tier-based games; less "build an empire" depth.
- **Players like:** that it stays out of the way and supports the horror/survival mood.

### Enshrouded -- settlement + crafting-NPC progression (mixed, casual-leaning)
- **What sets it apart:** you recruit crafting NPCs to a permanent settlement; each NPC unlocks a
  crafting domain, so base growth = crafting growth.
- **Pros:** strong QoL is its selling point -- many players call the QoL a "total upgrade" for survival
  crafting. Good for casual players.
- **Cons:** **the #1 complaint is no craft-from-storage** -- having to have materials in your personal
  inventory (not pulling from nearby chests) is repeatedly cited as *very noticeable and frustrating*.
  This is a pure friction tax with no gameplay upside.
- **Lesson (big one for us):** **craft-from-nearby-storage is table stakes now.** Its absence is one of
  the most-cited frustrations in the whole genre. If you have inventory + storage, let crafting pull
  from both.

### Icarus -- deep tech-tree, session-based (respected by hardcore, heavy)
- **What sets it apart:** *lots* of recipes, workbenches, and tech to manage; temporary bases you
  abandon at mission end. Explicitly the "if you love tech trees and unlocking recipes, this is your
  game" option.
- **Pros:** depth and breadth for players who want a management sim; satisfying for tech-tree lovers.
- **Cons:** heavy; the disposable-base loop means crafting investment feels temporary; overwhelming to
  casual players. Recommended *only* to hardcore survival fans.
- **Players like:** breadth. **Dislike:** the churn of rebuilding + volume of management.

### Project Zomboid -- realism-first depth (DIVISIVE, cautionary tale)
- **What sets it apart:** aims for deep, realistic crafting (Build 42 expanded it hugely).
- **Pros:** genuine depth; fans love that mastery is real and hard-won.
- **Cons (heavily cited):** confuses *complexity with realism*; clunky Build-42 menus; recipes locked
  behind **magazines you have to find** and a **maintenance/skill grind**; described as "unfinished";
  the realism-vs-fun balance tips toward tedium. A frequent example of "depth that became friction."
- **Lesson:** realism is not automatically fun. Gating recipes behind found-magazines + RNG skill
  grind is one of the most-complained-about patterns. Legible depth beats simulated depth.

### Extraction games (Tarkov-style hideout, referenced) -- meta-progression crafting
- **Pattern:** crafting is a *between-raid* meta layer (upgrade a hideout, craft items over real time
  to sell/use) rather than moment-to-moment. Rewards long-term investment and gives non-combat
  progression. Downside: often time-gated (real-clock crafts) which some love (idle payoff) and many
  find artificial.
- **Relevance to us:** low right now (single-player, no raids), but the "crafting as a persistent
  meta-layer between runs" idea is worth remembering if Kenslash ever gets a run/hub structure.

---

## Cross-cutting themes (what the genre agrees on)

### Progression -- the clearest consensus
- **Best-loved:** progression *gated by the world* -- new biome/depth/region = new tier (Valheim,
  Subnautica). Goal and gate are the same, so advancement never feels like menu grind.
- **Disliked:** progression gated by grind/RNG divorced from exploration -- magazine hunts + skill
  levels (PZ), pure Scrap grind on high tiers (Rust T3), disposable rebuilds (Icarus).
- **Rule of thumb:** *unlock by discovery/place, not by repetition.*

### Recipe discovery -- the "known vs experiment" axis
- **Two poles:** strongly-defined recipes (game controls, player has clarity) vs flexible/experimental
  (player creativity, less dev control). Minecraft's shape-grid and Subnautica's scanning are the two
  celebrated *middle* answers: defined recipes, but you *discover* them through play.
- **The magic is in the reveal, not the recipe.** Beloved systems make *learning* the recipe an
  event (scan a wreck, reach a biome, place ingredients in a shape). Disliked systems hand you a menu
  and make you grind mats.

### UI -- what the good ones do
- The UI should *reinforce identity* (Minecraft grid), not be a generic scrolling list.
- **Real-time resource tracking** is expected: show what a recipe needs, what you have, and *where to
  find the missing mats*. Modern survival players expect the UI to answer "what do I still need?"
- **Craft-from-storage** is now baseline (Enshrouded's cautionary absence).
- Progress indicators for multi-step unlocks (Subnautica's fill bar) pace discovery well.

### Difficulty / ease -- the balance point
- **Failure mode "too hard":** convoluted trees, realism-as-friction, RNG gates, no QoL (PZ, heavy
  Icarus). Players bounce off.
- **Failure mode "too easy":** if you can craft everything from a menu with no discovery, crafting
  becomes a chore with no reward loop (the "modern imitators strip the mystery, keep the complexity"
  critique).
- **The sweet spot everyone praises:** *simple to operate, meaningful to progress.* Low mechanical
  friction (few clicks, craft-from-storage, clear UI) but *earned* unlocks (exploration-gated). Ease of
  *use*, difficulty of *access*.

---

## Which games to look deeper into (recommendation)

Ranked by relevance to a fast top-down action game (not a base-builder):

1. **Subnautica** -- study the scan-to-learn loop. Highest-value idea for us: *exploration = unlock*,
   with a clear progress indicator and a multi-use unlock tool. Maps beautifully onto "explore chunks,
   find/kill things, learn to craft."
2. **Valheim** -- study biome-gated tier walls. The "each new zone is the next crafting gate" model is
   exactly how our streamed world + enemy tiers could gate a weapon/gear ladder.
3. **Minecraft** -- study the *discovery + tactile UI* principle (not the literal 3x3 grid). The lesson
   is "make learning a recipe feel like making something," not "copy the grid."
4. **The Forest / Grounded** -- study low-friction, high-clarity recipe UX for a fast game where the
   player shouldn't live in menus.
5. **Rust (tech tree)** -- study *only* as the cautionary "deterministic unlock vs discovery thrill"
   trade-off, so we go in eyes-open about what a "spend currency to unlock" model costs emotionally.

Skip going deep on **Project Zomboid** and **Icarus** except as *what-not-to-do* references (depth-as-
friction, disposable investment).

---

## The favorites, and are they "best regardless of the game"?

**Yes -- three systems get praised independent of whether people like the surrounding game:**

- **Subnautica's scanning** -- lauded as one of the best *because* it fuses exploration and
  progression; praised even by people who found the game slow or scary. What sets it apart: the world
  itself is the tech tree. What people like: curiosity is always rewarded, progression is always
  legible.
- **Valheim's biome gating** -- praised as maybe the best progression structure in the genre
  regardless of opinions on Valheim's grind or graphics. What sets it apart: goal, gate, and reward are
  a single loop. What people like: every new place is a meaningful new tier.
- **Minecraft's grid + discovery** -- the foundational study piece. What sets it apart: the UI IS the
  verb; discovery built a culture. What people like: tactility and the "aha."

**Rust's tech tree** is the fourth-most-cited but with an asterisk: praised as a *fix* (accessibility)
rather than loved as an *experience* -- people respect it, they don't rave about it.

The through-line of all the "best regardless of game" systems: **the crafting progression is inseparable
from the act of playing the world.** You don't progress by grinding a menu; you progress by going
somewhere, surviving it, and learning something. That is the transferable principle.

---

## What this means for Kenslash (synthesis, not yet a build spec)

We are a fast top-down hack-and-slash with streamed chunks, tiered enemies, harvestables (tree/rock/
bush/pebble), items, weight, and durability. We are NOT a base-builder, so we should borrow *feel*, not
breadth.

Direction that fits our game + the research consensus:
- **Exploration-gated, not grind-gated.** Tie new craftable tiers to *where you've been / what you've
  beaten* (which enemy tier, which future biome/boulder-region/cave), Valheim/Subnautica style -- our
  streamed world + enemy tiers already give us the "walls."
- **Discovery-flavored unlocks.** Prefer "learn the recipe by finding/doing" (pick up a material for
  the first time, defeat a tier, enter a region) over "click research N times." Cheap to add a
  first-time "you can now craft X" reveal.
- **Lean recipe set, tactile UI.** Few, legible recipes (weapons/tools/consumables that matter to
  combat), not a hundred-node tree. UI must show have/need + where-to-find, and it must be fast to
  operate -- we don't want players living in menus in an action game.
- **Craft-from-storage from day one** (Enshrouded's lesson) once we have storage -- never make players
  shuffle mats between inventory and chest.
- **Ease of use, difficulty of access.** Simple to craft; the *challenge* is surviving far enough to
  unlock the next tier. That matches a hack-and-slash's core fantasy (get stronger by fighting harder
  things) better than a management-sim tree.
- **Avoid:** realism-as-friction (PZ), magazine/RNG recipe gates, disposable investment (Icarus),
  and a pure buy-with-currency tree that kills the thrill of the first find (Rust's own admitted cost).

Open questions to decide when we resume design (not now): do recipes live at a workbench/station or
craft-anywhere? Is there a currency/scrap layer at all, or purely material recipes? How many tiers, and
do they map to enemy tiers, biomes, or both? Do we want any experimental/flexible recipes or all
strongly-defined?

## Sources
- Game Developer -- "7 crafting systems game designers should study" (Minecraft grid + discovery; UI-
  reinforces-identity; integration-not-addition).
- bit-tech -- "how to fix your stupid crafting system" (Minecraft grid praise; blueprint-gate critique).
- Subnautica / Subnautica 2 wikis + guides (scanner-as-progression, multi-scan progress bar, multi-use
  tool).
- Falcon Rust / HubPages -- Rust workbench tech tree (tiers, Scrap cost, accessibility-vs-thrill).
- Enshrouded Steam discussions (crafting feedback: QoL praise; no-craft-from-storage complaint) +
  Fragster Enshrouded-vs-Icarus (casual vs hardcore).
- Player-consensus writeups on Valheim (biome-gated progression) and Project Zomboid (complexity-as-
  realism, Build-42 menu/magazine/skill-gate criticism).
- gamedesignskills / Game Developer / Game UI Database -- survival crafting UI + recipe-definition axis
  (strict vs flexible; real-time resource tracking).

*Research doc. Last updated: 2026-07-16. Verified against player-consensus + design-writing sources.*

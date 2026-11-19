# Player-Driven Actions

How an action — an **Attack**, a **Spell**, an **Item** (Potion / Scroll) or a **Special Ability** — runs between the DM's web controls and the players' phones ([android_app.md](android_app.md)). The DM's own Action Builder is the one set of controls ([turn_action_stub.md](../common/ui/turn_action_stub.md) → Attack, Cast, Item, Special); every player with a part in the action answers on their phone, and their answers show up in the builder.

**Move** and **End Turn** stay a plain request: the DM's **Approve** applies it (Move spends its Combat Pool cost; End Turn advances the turn). An active Spell's request (`<Spell> (conc)`) is resolved by the DM by hand.

## Two ways in

- **A player asks.** The player picks the action on the phone (Initiative screen): Attack — target, weapon and dice; Spell / Item — the Spell (or Potion / Scroll), its dice, and its target (a creature, themselves included, themselves, an object, or an area); Ability — the Ability and, when channeled, its dice. It appears in the DM's **Player actions** panel with **Approve** and **Cancel**. When the DM approves, the matching builder opens on the turn panel with the player's choices already made — exactly as if the DM had pressed the action. From there it runs like any other action in the builder.
- **The DM starts it** in the builder, as usual. Nothing appears in the Player actions panel.

Either way, everything below happens in the builder.

## Rules

- **The builder is in charge.** The steps run in the builder's order.
- **A player's choice goes to their phone.** When the builder reaches a step that is another player's choice, that player is asked on their phone:
  - the target's **Defense** (No defense, Dodge, Block, Parry, Ring of Parry, Better Lucky Than Good — each with its dice);
  - an ally's **Shield** (Shield of Faith or similar): whether to interpose it, and with how many dice;
  - each **Luck** source's **Bardic Inspiration** (and Unsettling Words).

  The builder shows *Waiting on \<player\>'s phone, or choose for them here.* The player's answer is picked in the builder by itself. If the DM picks first, the builder moves on and the prompt leaves the phone. The DM can still **Change** any step.
- **Who is asked:** a player Character with a phone — one the DM assigned to a device on the Status page. Enemies, NPCs, players without the app and the DM's own Luck are decided by the DM in the builder, as before. The actor's own steps (target, weapon, Spell, dice) are made in the builder (or came from the player's request).
- **A Saving Throw is not asked**: it always spends the full Dice Cap, so the builder applies it by itself, and the target just rolls it.
- **Rolls.** Once the dice are up:
  - A Roll that belongs to a player with a phone is theirs to roll on the phone. Its row in the builder is locked (Roll All leaves it alone) and shows where it stands, with **Roll for \<player\>** (the DM rolls it instead) and **Approve**.
  - **Whoever rolls, only the DM sees it until the DM presses Approve.** A DM roll can be rolled again as often as the DM likes (**Roll again**). If the player rolls on the phone before the DM approves, the player's roll replaces the DM's. A player sees their own roll on their phone at once; nobody else sees it until it is approved.
  - **Roll All** rolls only the unclaimed Rolls: enemies, NPCs, and players without a phone.
  - **Confirm** shares every Roll with the players: the unclaimed ones Roll All rolled, and any claimed Roll with dice not yet approved.
  - Until then, a Roll the players may not see looks exactly like one nobody has rolled. The players are never told whether the DM rolled more than once.
  - If the DM changes a step that changes a Roll's dice or TN, that Roll is rolled again.
- **When the DM confirms, every phone in combat sees it**: the action as a title (*Garroth Vask Attacks Wolf with Great Sword*) and every Roll thrown on its dice table as if just rolled — first as rolled, then the Luck rerolls thrown again and any nudged die hopping to its new value (below). Each phone throws each Roll once.
- **Nothing is spent until the DM commits** from the usual damage screen. The commit closes the action.
- **What a player may ask for.** Every player may send requests at any time, limited by two things:
  - **Whose turn it is.** On their own turn, anything. On anyone else's turn, only **Free actions** (e.g. Rage) — never End Turn. Reactions are not requested: they are offered as prompts, in response to someone else's action.
  - **A die roll waiting on them.** While one of their Rolls is waiting to be rolled (or the DM rolled it and has not approved it — they may still roll over it), their actions are hidden on the phone and the server refuses new requests, until it is rolled.
- **An Ability with no builder** (Rage…) is used as soon as the DM approves it — on anyone's turn, from any page.
- **The DM on another page.** Requests wait, and every DM page shows them in the top bar (*Player actions* with a count, kept live): **Approve** (an Ability with no builder is used at once; anything else takes the DM to the Encounter page with its builder open) or **Cancel**; Move / End Turn can be approved there too. An action already running in a builder carries on: its phone prompts stay up and players can answer and roll. The notice lists it as *in progress*, and when the DM comes back to the Encounter page its builder reopens where it was — every step chosen, the phones' answers and dice kept (the DM's own Roll All dice are rolled again).
- **There is no time limit.**
- **A prompt stays until it is answered** or the builder moves on — however long the player takes. (A phone's answer reaches the DM's page at once over its live-updates connection.)
- A builder the DM closes by picking another action takes its prompts off the phones; an action the DM started is then dropped, and a player's request stays in the Player actions panel with **Open in … builder**. Leaving the Encounter page or reloading it does not drop anything (above).

## Fudging

The DM may fudge any Roll a player rolls on their phone. Nobody else ever sees it — not the players, not the builder after the fact.

- **With the request:** a dropdown next to **Approve** (on the Player actions panel and the notice on every DM page) — *No fudge*, *Success*, *Failure*, *Critical*, *Fumble* — for the requesting player's own Roll.
- **In the builder:** the same dropdown on every Roll that belongs to a phone (the target's Dodge, an ally's shield…), until that player has rolled.

The phone rolls the dice as usual; then, **before any Luck reroll**, if the result is not in the chosen band, it changes the fewest dice it must, each to a random value of the kind needed, and shows those dice as rolled. The bands, by Degree of Success (Starting Value included; a 10 counts +2, a 1 −1):

| Fudge | Degree of Success |
|---|---|
| No fudge | unchanged |
| Success | 2 or more |
| Failure | −1 to 1 |
| Critical | 4 or more, with at least one 10 |
| Fumble | −2 or less |

Luck rerolls then apply as usual. If the band cannot be reached at all (e.g. a large Starting Value), the dice are left as rolled. The DM's own rolls (Roll for …, Roll All) are never fudged.

## On the phone

- **Spell / Item:** a Spell aimed at a creature asks for a **Target** too — enemies, allies, and the player themselves last (e.g. a heal); the button reads *Cast \<spell\> on \<target\>* (or *on yourself*). A self, object or area Spell says so instead of asking. An area Spell is placed on the map by the DM. **Attack:** a **Target** (enemies first), then the dice; the button reads *Attack \<target\> with \<weapon\>*.
- **Your move:** a choice waiting on the player appears at the top of the Initiative screen, on anyone's turn:
  - the action as a heading — *Garroth Vask Attacks Wolf with Great Sword* (an attack by its weapon type, not the item's full name; *You* when it is the player);
  - the question — *Choose your defense*, *Shield \<ally\>?*, *Use your luck?* with *3 Luck remaining*;
  - the choices, each group under its bold name with the same dice picker as actions. Luck: *Help Garroth Vask's Attack*, *Hinder Garroth Vask's Attack*, *Help Wolf's Dodge*, *Hinder Wolf's Dodge* (Hinder only for a source that may hinder); then *No luck*;
  - the button with the choice (*Help Garroth Vask's Attack — reroll 2 dice*): green to help, red to hinder.
- **From any tab:** when a step is waiting, the Initiative tab shows a badge (●) and the phone says *Your move: …* once.
- **Roll card** — the action as a header from the player's side (*Casting Fire Dart at Wolf*; a target sees *Ash Windmere casting Fire Dart at you*), then every Roll of the action:
  - a bold label: the player's own roll by skill and bonus (*Arcana +3*), the others by name, what they roll and their bonus (*Wolf Dodging +2*, *Garroth Vask Wisdom save +1*);
  - its dice count and TN (and any Starting Value and Luck rerolls) in small print;
  - one die image per die — blank until shared;
  - under the player's own dice, the **Roll** button.

  Pressing **Roll** throws the player's dice on the **dice table** (below); when they stop, the result goes to the DM. The card stays until the DM commits the action.

### Rolling on the phone

The phone throws the dice, shows them tumbling, then — when Luck applies — rerolls the chosen dice (a positive reroll the lowest non-Successes, a negative reroll the highest Successes, each die at most once; [dice_resolution_design.md](../common/dice_resolution/dice_resolution_design.md) → Reroll). The server re-scores the dice itself (the phone's total is not trusted). When the DM rolls for a player, the server throws the dice the same way.

### The dice table

The dice are thrown right over the screen — no backdrop, no box; only the screen's edges stop them, and the Initiative screen stays visible underneath. Each die flies in from a side of the screen, bounces off the edges and the other dice (everyone's), spins and slows down, flickers through faces while it tumbles, and stops on its real value (about a second and a half). Luck rerolls are thrown again once the first throw has stopped.

Each Roll of the action has its own part of the screen — two rolls, two halves; three rolls, three thirds — the player's own first. Its dice are thrown into that part and gently pulled back if they wander; no line is drawn. Each Roll is in its roller's own dice colour, the same on every phone ([dice_colors.md](dice_colors.md)), with a label floating just above its dice (*You — Arcana +3*, *Wolf — Dodging +2*). When another Roll is shared, its dice are thrown into its part of the screen, whether or not the player's own dice are already there. A stopped die's number shows what it counts for: dark green for a Success, deep blue for a Critical Success, dark red for a 1, dark grey for no effect. A die rerolled by Luck carries a small gold **↻** badge, a nudged die a **±** badge — on the dice table and on the roll card. Each label adds its Successes when its dice stop. **The dice stay on the screen until the player taps it.**

## On the DM's Encounter page

- **Player actions** panel, above the Turn Action panel: each request from a phone — who does what to whom — with **Approve** (opens it in the builder) and **Cancel** (drops it; nothing was spent). An approved request that is not open in a builder (e.g. after a page reload) has **Open in Attack builder / Cast builder / Item builder / Ability**. The panel refreshes itself every few seconds.
- **In the builder:** *Waiting on \<player\>'s phone* under a step a player may answer; under each Roll that belongs to a phone, its status (*Waiting for \<player\> to roll*, *\<player\> rolled on their phone. Only you can see it until you approve*, *You rolled for \<player\>…*, *Shared with the players*) with **Roll for \<player\>** / **Roll again** and **Approve**.

## Implementation

- `lib/action_flow.rb` — the action: `declare` (a player's request) → `builder`. The builder's state mirrored onto the phones (`sync!`): choice tasks for player steps, roll tasks for every Roll (claimed when the owner has a phone), who sees which roll, Luck → rerolls, server-side scoring, and the request's choices for opening the builder.
- `POST /encounter/live/:id/rolls/:task_id/fudge` — the builder's fudge dropdown; the request's goes with `POST /encounter/flows/:id/tasks/:task_id/approve` (`fudge`). The phone gets it as its roll prompt's `roll.fudge` (only on its own Roll) and lands the dice in `DiceRules.fudge`.
- `GET /encounter/live/open` — the actions running in a builder, which the Encounter page reopens on load (replaying `GET /encounter/flows/:id/prefill`, which then holds every choice the builder had made). `POST /encounter/live/left` — sent as the page closes. `GET /dm/notices` and `views/_dm_notices.erb` / `public/js/ui/dmNotices.js` — the notice on every DM page, which also holds the page's live-updates connection.
- `GET /api/initiative` → `shared`: the actions whose Rolls the DM shared in the last two minutes, from the viewer's side, with every Roll's first dice, rerolls and final dice. `POST /encounter/live/reset` — the Encounter page loaded: no builder is open, so the last page's prompts are dropped.
- `public/js/ui/liveSync.js` — every builder on screen sends its state whenever it changes (`POST /encounter/live/sync`, which creates the action for a builder the DM opened), and fetches the phones' answers and Rolls when the server says something changed (`GET /encounter/live/:id`; [live_updates.md](live_updates.md)), picks a phone's answer, shows the phone Rolls' rows, and shares the Rolls on Confirm (`POST /encounter/live/:id/share`). `POST /encounter/live/:id/rolls/:task_id/{roll,approve}` — the DM's Roll for / Approve.
- `public/js/ui/flowsPanel.js` and `views/_action_flows.erb` — the Player actions panel; opens the builder for an approved request and replays the player's choices (`GET /encounter/flows/:id/prefill`).
- Player prompts: `GET /api/prompts`, `POST /api/prompts/:flow_id/:task_id`. `POST /api/turn/requests` with an `attack:`, `cast:`, `item:` or `special:` key (and a `target_id` when one is needed) starts a request; `GET /api/initiative` carries `targets`, `prompts` and the player's `flows`.
- `/encounter/resolve_attack`, `/encounter/resolve_cast` and `/encounter/use_special` close the action when their payload carries `flow_id` and commits. `POST /encounter/player_requests/:id/apply` applies an approved Move / End Turn.
- Actions in progress are kept in memory; restarting the server drops them (nothing has been spent).

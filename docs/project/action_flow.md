# Player-Driven Actions

How an action a player starts from the Android app ([android_app.md](android_app.md)) — an **Attack**, a **Spell**, an **Item** (Potion / Scroll) or a **Special Ability** — is answered by the other players and approved by the DM. This is the player side of the DM's turn flows ([turn_action_stub.md](../common/ui/turn_action_stub.md) → Attack, Cast, Item, Special); each runs on the same Action Builder data as the DM's pane, so every option, Combat Pool cost and Target Number is what the DM's builder would show.

**Move** and **End Turn** stay a plain request: the DM's **Approve** applies it (Move spends its Combat Pool cost; End Turn advances the turn). An active Spell's request (`<Spell> (conc)`) is resolved by the DM by hand.

## Rules

- **Each player rolls on their own phone.** Results are sent to the DM for approval.
- **Every player answer needs the DM's approval.** The DM can approve it or **Send back** to ask again.
- **The DM can act for anyone.** Whenever a step is waiting on a player, the DM can answer it for them (**Decide for …**, **Roll for …**). That approves it at once and removes the prompt from the player's phone.
- **Enemies, NPCs, and players without the app** are answered by the DM on the web page.
- **There is no time limit.**
- **Nothing is spent until the DM commits** the action in the normal builder.
- **One action at a time while it waits.** While one of a player's actions waits on other players or on dice — an Attack, a Spell or Item that rolls a check, a channeled Ability — their other actions are hidden on the phone (End Turn included), and the server refuses new requests, until the DM commits or cancels it. An action that waits on nothing (Rage, a buff, a Reservoir pour) does not hold anything up: a player may Rage and then attack.

## Stages

The steps of an attack run in the builder's order. Within a stage, several Combatants may have a choice at the same time; the next stage starts when every step of the current one is approved.

| Stage | Who | What |
|---|---|---|
| **Request** | The actor | Chosen on the phone (Initiative screen). Attack: target, weapon and dice. Spell / Item: the Spell (or Potion / Scroll), its dice, and its target — a creature (the player picks; themselves included), themselves, an object, or an area. Ability: the Ability and, when channeled, its dice. |
| **Defenses** | The target; an ally shielding the target | Attack: the target's Defensive Action — No defense, Dodge, Block, Parry with a weapon, Ring of Parry, Better Lucky Than Good — each with its dice; and an ally whose Shield of Faith (or similar) guards the target: whether to interpose it, and with how many dice. Attack-roll Spell: the target's No defense / Dodge / Block. A **Saving Throw** is not asked: it always spends the full Dice Cap, so it is applied by itself and the target just rolls it. |
| **Luck** | Each Luck source | Every other Combatant holding Bardic Inspiration, and the DM when holding DM Luck: whether to spend Luck on a Roll in play — a bonus reroll (low dice) and, with Unsettling Words or as the DM, a penalty reroll (high dice). After Defenses, because how much Luck a Roll can take depends on its dice. |
| **Rolls** | Whoever owns each Roll | The attacker's attack or the caster's casting check or the performer's Performance check; the target's defense or Saving Throw; the ally's shield. The server sends each phone its Dice Count, TN and Starting Value — computed after cross-side propagation, exactly as Check Resolution does in the builder — and its Luck rerolls. |
| **Resolve** | The DM | **Open in Attack builder / Cast builder / Item builder / Ability**: the matching pane opens with every choice already made and each Roll's dice and Result / Crits filled in from the phones (and locked, so Roll All does not replace them). The DM checks it, presses **Confirm**, and commits from the usual damage screen (Damage, Bleed, Poison, Damage Riders, post-roll Reactions). The commit closes the action. |

A stage with nothing to ask is skipped (e.g. no Luck sources).

### Straight to the DM

Some actions have nothing for the other players to answer, so after the DM approves the request they go straight to **Resolve**:

- A Spell or Item that rolls no check (a buff such as Bless or Ward, a heal with no check, a Reservoir pour such as Shield of Faith).
- An **area** Spell: the DM places it on the map in the Cast builder, which decides who is caught; those creatures roll their saves there.
- A Special Ability with no builder (e.g. Rage): the DM's **Open in Ability** presses its button, and the DM confirms the summary.

A multi-target Spell takes one target from the phone; the DM can add more in the builder.

### Rolling on the phone

The phone throws the dice, shows them tumbling, then — when Luck applies — rerolls the chosen dice (a positive reroll the lowest non-Successes, a negative reroll the highest Successes, each die at most once; [dice_resolution_design.md](../common/dice_resolution/dice_resolution_design.md) → Reroll). The result is sent to the DM at once; like a public Skill roll, it cannot be rolled again. The server re-scores the dice itself (the phone's total is not trusted). When the DM rolls for a player, the server throws the dice the same way.

## On the phone

- **Attack:** choosing an Attack on the Initiative screen asks for a **Target** (enemies first), then the dice. The confirm button reads *Attack \<target\> with \<weapon\>*.
- **Spell / Item:** a Spell aimed at a creature asks for a **Target** too — enemies, allies, and the player themselves last (e.g. a heal); the button reads *Cast \<spell\> on \<target\>* (or *on yourself*). A self, object or area Spell says so instead of asking. An area Spell is placed on the map by the DM.
- **Roll card** — the action as a header from the player's side (*Casting Fire Dart at Wolf*; a target sees *Ash Windmere casting Fire Dart at you*), then every Roll of the action:
  - a bold label: the player's own roll by skill and bonus (*Arcana +3*), the others by name, what they roll and their bonus (*Wolf Dodging +2*, *Garroth Vask Wisdom save +1*);
  - its dice count and TN (and any Starting Value and Luck rerolls) in small print;
  - one die image per die — blank until rolled;
  - under the player's own dice, the **Roll** button.

  Pressing **Roll** throws the player's dice on the **dice table** (below); when they stop, the result is sent to the DM. The card then shows each Roll's dice and Successes, and stays until the DM commits the action.

### The dice table

The dice are thrown right over the screen — no backdrop, no box; only the screen's edges stop them, and the Initiative screen stays visible underneath. Each die flies in from a side of the screen, bounces off the edges and the other dice (everyone's), spins and slows down, flickers through faces while it tumbles, and stops on its real value (about a second and a half). Luck rerolls are thrown again once the first throw has stopped.

Each Roll of the action has its own part of the screen — two rolls, two halves; three rolls, three thirds — the player's own first. Its dice are thrown into that part and gently pulled back if they wander; no line is drawn. Each Roll has its own dice colour (the player's own crimson; others blue, green, purple, orange, teal) and a label floating just above its dice (*You — Arcana +3*, *Wolf — Dodging +2*). When another player's result reaches the server, their dice are thrown into their part of the screen, whether or not the player's own dice are already there. A stopped die shows what it counts for: a Success is outlined white, a Critical Success gold, and a 1 is dimmed. Each label adds its Successes when its dice stop. **The dice stay on the screen until the player taps it.**

- **Your move:** steps waiting on the player appear at the top of the Initiative screen, on anyone's turn: the title (*Choose your defense*, *Shield \<ally\>?*, *Use your Luck?*, *Roll \<roll\>*), who is attacking whom, and the choices — grouped like the builder's, with the same dice picker as actions. Once sent, the step reads *Sent — waiting for the DM to approve* until the DM approves it.
- **From any tab:** when a step is waiting, the Initiative tab shows a badge (●) and the phone says *Your move: …* once.
- **Your attack:** the attacker sees each step of their attack and where it stands. Its Combat Pool and Main Action count against what the player has left until the DM commits it.

## On the DM's Encounter page

A **Player actions** panel above the Turn Action panel lists each action in progress: who does what to whom, the stage, and every step of the current stage with its owner and status (*waiting*, the submitted answer, or approved). Buttons: **Approve**, **Send back**, **Decide for …** (with the step's options), **Roll for …**, **Cancel** (drops the action; nothing was spent), and at the end **Open in Attack builder / Cast builder / Item builder / Ability** (when the actor is the acting Combatant). The panel refreshes itself every few seconds.

## Implementation

- `lib/action_flow.rb` — the flow (kinds attack / cast / item / special): stages, tasks, options from the builder blob, a Ruby port of the builder's patch application and of Check Resolution's cross-side propagation, Luck → rerolls, server-side scoring, and the pre-fill.
- `lib/routes/action_flows.rb` — player prompts (`GET /api/prompts`, `POST /api/prompts/:flow_id/:task_id`), DM actions (`POST /encounter/flows/:id/tasks/:task_id/{approve,reject,decide,roll}`, `POST /encounter/flows/:id/cancel`), `GET /encounter/flows/:id/prefill`, and `GET /encounter/flows_panel`.
- `POST /api/turn/requests` with an `attack:`, `cast:`, `item:` or `special:` key (and a `target_id` when one is needed) starts a flow; `GET /api/initiative` carries `targets`, `prompts` and the player's `flows`.
- `views/_action_flows.erb` and `public/js/ui/flowsPanel.js` — the DM's panel and the builder pre-fill. `/encounter/resolve_attack`, `/encounter/resolve_cast` and `/encounter/use_special` close the flow when their payload carries `flow_id` and commits. `POST /encounter/player_requests/:id/apply` applies an approved Move / End Turn.
- Actions in progress are kept in memory; restarting the server drops them (nothing has been spent).

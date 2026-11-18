# Player-Driven Attacks

How an attack a player starts from the Android app ([android_app.md](android_app.md)) is answered by the other players and approved by the DM. This is the player side of the DM's Attack flow ([turn_action_stub.md](../common/ui/turn_action_stub.md) → Attack); it runs on the same Attack builder data, so every option, Combat Pool cost and Target Number is what the DM's builder would show.

Spells, items and abilities are not yet player-driven: on the phone they are still a plain request the DM resolves (see *Requests* in [android_app.md](android_app.md)).

## Rules

- **Each player rolls on their own phone.** Results are sent to the DM for approval.
- **Every player answer needs the DM's approval.** The DM can approve it or **Send back** to ask again.
- **The DM can act for anyone.** Whenever a step is waiting on a player, the DM can answer it for them (**Decide for …**, **Roll for …**). That approves it at once and removes the prompt from the player's phone.
- **Enemies, NPCs, and players without the app** are answered by the DM on the web page.
- **There is no time limit.**
- **Nothing is spent until the DM commits** the attack in the normal Attack builder.

## Stages

The steps of an attack run in the builder's order. Within a stage, several Combatants may have a choice at the same time; the next stage starts when every step of the current one is approved.

| Stage | Who | What |
|---|---|---|
| **Request** | The attacker | Target, weapon and dice — chosen on the phone (Initiative screen). |
| **Defenses** | The target; an ally shielding the target | The target's Defensive Action: No defense, Dodge, Block, Parry with a weapon, Ring of Parry, Better Lucky Than Good — each with its dice. An ally whose Shield of Faith (or similar) guards the target: whether to interpose it, and with how many dice. |
| **Luck** | Each Luck source | Every other Combatant holding Bardic Inspiration, and the DM when holding DM Luck: whether to spend Luck on a Roll in play — a bonus reroll (low dice) and, with Unsettling Words or as the DM, a penalty reroll (high dice). After Defenses, because how much Luck a Roll can take depends on its dice. |
| **Rolls** | Whoever owns each Roll | The attacker's attack, the target's defense, the ally's shield. The server sends each phone its Dice Count, TN and Starting Value — computed after cross-side propagation, exactly as Check Resolution does in the builder — and its Luck rerolls. |
| **Resolve** | The DM | **Open in Attack builder**: the DM's Attack pane opens with every choice already made and each Roll's dice and Result / Crits filled in from the phones (and locked, so Roll All does not replace them). The DM checks it, presses **Confirm**, and commits from the usual damage screen (Damage, Bleed, Poison, Damage Riders, post-roll Reactions). The commit closes the attack. |

A stage with nothing to ask is skipped (e.g. no Luck sources).

### Rolling on the phone

The phone throws the dice, shows them tumbling, then — when Luck applies — rerolls the chosen dice (a positive reroll the lowest non-Successes, a negative reroll the highest Successes, each die at most once; [dice_resolution_design.md](../common/dice_resolution/dice_resolution_design.md) → Reroll). The result is sent to the DM at once; like a public Skill roll, it cannot be rolled again. The server re-scores the dice itself (the phone's total is not trusted). When the DM rolls for a player, the server throws the dice the same way.

## On the phone

- **Attack:** choosing an Attack on the Initiative screen asks for a **Target** (enemies first), then the dice. The confirm button reads *Attack \<target\> with \<weapon\>*.
- **Your move:** steps waiting on the player appear at the top of the Initiative screen, on anyone's turn: the title (*Choose your defense*, *Shield \<ally\>?*, *Use your Luck?*, *Roll \<roll\>*), who is attacking whom, and the choices — grouped like the builder's, with the same dice picker as actions. Once sent, the step reads *Sent — waiting for the DM to approve* until the DM approves it.
- **From any tab:** when a step is waiting, the Initiative tab shows a badge (●) and the phone says *Your move: …* once.
- **Your attack:** the attacker sees each step of their attack and where it stands. Its Combat Pool and Main Action count against what the player has left until the DM commits it.

## On the DM's Encounter page

A **Player actions** panel above the Turn Action panel lists each attack in progress: who attacks whom with what, the stage, and every step of the current stage with its owner and status (*waiting*, the submitted answer, or approved). Buttons: **Approve**, **Send back**, **Decide for …** (with the step's options), **Roll for …**, **Cancel** (drops the attack; nothing was spent), and at the end **Open in Attack builder** (when the attacker is the acting Combatant). The panel refreshes itself every few seconds.

## Implementation

- `lib/action_flow.rb` — the flow: stages, tasks, options from the builder blob, a Ruby port of the builder's patch application and of Check Resolution's cross-side propagation, Luck → rerolls, server-side scoring, and the pre-fill.
- `lib/routes/action_flows.rb` — player prompts (`GET /api/prompts`, `POST /api/prompts/:flow_id/:task_id`), DM actions (`POST /encounter/flows/:id/tasks/:task_id/{approve,reject,decide,roll}`, `POST /encounter/flows/:id/cancel`), `GET /encounter/flows/:id/prefill`, and `GET /encounter/flows_panel`.
- `POST /api/turn/requests` with an `attack:` key and a `target_id` starts a flow; `GET /api/initiative` carries `targets`, `prompts` and the player's `flows`.
- `views/_action_flows.erb` and `public/js/ui/flowsPanel.js` — the DM's panel and the builder pre-fill. `/encounter/resolve_attack` closes the flow when its payload carries `flow_id` and commits.
- Attacks in progress are kept in memory; restarting the server drops them (nothing has been spent).

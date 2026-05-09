 ▐▛███▜▌   Claude Code v2.1.137
▝▜█████▛▘  Opus 4.7 · Claude Max
  ▘▘ ▝▝    ~/Claude/crimson-steel

❯ Bards have the ability to perform for luck points that can be used to allow   
  allies/force enemies to reroll dice. How should that be handled?              

● Explore(Explore bard class and mechanics)
  ⎿  Backgrounded agent (↓ to manage · ctrl+o to expand)

● I launched an Explore agent to investigate the codebase structure, bard class
  documentation, existing class-ability patterns, and any reroll/points
  mechanics. I'll wait for its findings before proceeding to design.

● Agent "Explore bard class and mechanics" completed

● I have enough context to form a preliminary plan. Let me read a few critical
  files directly so I can write accurate, grounded plan details.

  Read 3 files (ctrl+o to expand)

● Let me check the existing better_lucky_than_good UI pattern and an
  ability-mutation POST route to see what I'd be following.

  Read 2 files (ctrl+o to expand)

● Let me check two more things: how turn advancement works (for expiration) and
  whether there's an existing skill-roll flow.

  Searched for 3 patterns, read 1 file (ctrl+o to expand)

● I have enough context. Let me draft the initial plan and then ask clarifying
  questions.

● Write(/root/.claude/plans/bards-have-the-ability-delegated-snowglobe.md)
  ⎿  Wrote 47 lines to ../../../../root/.claude/plans/bards-have-the-abilit
     y-delegated-snowglobe.md
       2 # Bard Luck Points — Implementation Plan
       4 ## Context
          a "luck point" pool, but no runtime implementation exists:ences
       7 - **bardic_inspiration** (Bard 1): Generates the pool. "Creates 
         a pool of luck that can be spent by you or your team to reroll d
         ne point of luck per success… each point must be used before you
       8 - **unsettling_words** (Bard 3) and **versatile_performance** (B
         ly identical).luck to force an enemy die reroll (text is current
      10 Today, `data/combat.json` participants track mana, combat pool, 
         and saturation, but
     … +93 lines (ctrl+o to expand)

● Now let me ask the user the key clarifying questions.

● User answered Claude's questions:
  ⎿  · How should luck points be generated when the bard performs? → Manual 
     success entry (Recommended)
     · Should I handle the 'fumble → DM luck' clause now? → Include now
     · Who should be able to spend luck from the pool? → DM-only via combat 
     tracker (Recommended)
     · versatile_performance has copy-paste text with unsettling_words. What 
     should it actually do? → Ally-reroll version (Recommended)

● Answers received. Let me finalize the plan file with the resolved decisions.

● Write(/root/.claude/plans/bards-have-the-ability-delegated-snowglobe.md)
  ⎿  Added 42 lines, removed 30 lines
       4  
       5  The bard class has three abilities whose text already reference
          s a "luck point" pool, but no runtime implementation exists:
       6  
       7 -- **bardic_inspiration** (Bard 1): Generates the pool. "Creates
         - a pool of luck that can be spent by you or your team to reroll
         - dice on any check… costs one point of mana… once per turn… gai
         -n one point of luck per success… each point must be used before
         - your next turn or it is lost."                                
       8 -- **unsettling_words** (Bard 3) and **versatile_performance** (
         -Bard 4): Spend luck to force an enemy die reroll (text is curre
         -ntly identical).                                               
       7 +- **bardic_inspiration** (Bard 1): Generates the pool. Costs 1 
         +mana, once per turn, main action. Each success on the performan
         +ce roll adds 1 luck; each fumble gives the DM 1 adversarial luc
         +k. Pool expires at the start of the bard's next turn.          
       8 +- **unsettling_words** (Bard 3): Spend 1 luck to force an enemy
         + to reroll one die.                                            
       9 +- **versatile_performance** (Bard 4): Spend 1 luck to let an al
         +ly reroll one die. (Compendium text is currently a copy-paste o
         +f unsettling_words; it will be rewritten to describe the ally-r
         +eroll version.)                                                
      10  
      10 -Today, `data/combat.json` participants track mana, combat pool,
         - and saturation, but nothing tracks luck. The combat tracker (`
         -views/combat_tracker.erb`) has a working pattern for similar de
         -fensive abilities (`better_lucky_than_good`, `danger_sense`) — 
         -a conditional button gated on `abilities` + a resource threshol
         -d that pays a cost and applies an effect. We want the same leve
         -l of integration for luck: a visible, spendable pool on the bar
         -d's row in the combat tracker, plus the ability for allies (and
         - the DM, against allies) to spend from it.                     
      11 +Today, `data/combat.json` participants track mana, combat pool,
         + and saturation, but nothing tracks luck. The combat tracker (`
         +views/combat_tracker.erb`) has a working pattern for similar de
         +fensive abilities (`better_lucky_than_good`, `danger_sense`) — 
         +a conditional button gated on `abilities` + a resource threshol
         +d that pays a cost and applies an effect. Luck will follow the 
         +same pattern.                                                  
      12  
      12 -The intended outcome: the DM can click "Perform" on the bard's 
         -turn to spend 1 mana and add N luck points to the bard's pool; 
         -those points are visible on every combatant's row so allies/ene
         -mies can spend them on rerolls; points auto-expire when the bar
         -d's turn comes around again.                                   
      13 +The intended outcome: on the bard's turn the DM clicks "Perform
         +", enters successes and fumbles, and the tool deducts 1 mana, a
         +dds the successes to the bard's luck pool, and adds the fumbles
         + to a DM-side luck pool. Both pools are visible during combat; 
         +the DM clicks "Spend Luck" on an ally row (player pool) or enem
         +y row (DM pool) to apply a reroll. Both pools auto-clear when t
         +he bard's turn comes around again.                             
      14  
      15  ## Key files
      16  
      16 -- `data/classes.json:14` — Bard ability_progression (already li
         -sts all three abilities; no change needed).                    
      17 -- `data/compendium.json:1908-1909` — `unsettling_words` and `ve
         -rsatile_performance` text is currently duplicated; versatile_pe
         -rformance should describe allies (not repeat enemies).         
      18 -- `data/combat.json` — Participant schema; add `luck_points` fi
         -eld.                                                           
      19 -- `character.rb:3-72` — `CombatTurn` class; add `luck_points` a
         -ttr, persist in `to_json`, clear in `new_turn` if this is the b
         -ard's turn.                                                    
      20 -- `app.rb` (near existing combat POST routes, e.g. around line 
         -1218) — Add `/combat/bardic_inspiration/:id` (pay 1 mana, add l
         -uck), `/combat/spend_luck/:bard_id` (decrement pool; caller sup
         -plies a reason label for the log).                             
      21 -- `views/combat_tracker.erb:865-869` — Extend the abilities-but
         -ton pattern: add a "Perform (+N Luck)" button on the bard's tur
         -n, and a "Spend Luck (reroll)" button on any participant row wh
         -en the bard's pool > 0.                                        
      22 -- `data/combat_log.json` via existing logging — Log luck genera
         -tion and spends.                                               
      17 +- `data/compendium.json:1881` — `bardic_inspiration` text (no c
         +hange needed; already accurate).                               
      18 +- `data/compendium.json:1909` — `versatile_performance` text: r
         +ewrite to "You can use points of luck from your performance to 
         +aid your allies. Before they roll you can spend one luck point;
         + afterwards you choose one of their dice to reroll."           
      19 +- `data/combat.json` — Participant schema: add `luck_points` an
         +d `dm_luck_points` fields (non-negative integers, default 0). A
         +dd `performed_this_turn` boolean (default false) on the bard's 
         +row to enforce once-per-turn.                                  
      20 +- `character.rb:3-72` (`CombatTurn`) — Add `luck_points`, `dm_l
         +uck_points`, `performed_this_turn` attrs; persist in `to_json`;
         + in `new_turn` reset all three to 0/false (new turn = this comb
         +atant's turn starting, which is exactly when the bard's pools s
         +hould expire).                                                 
      21 +- `character.rb:81+` (`Combat`) — No structural change; existin
         +g per-turn dispatch already calls `new_turn` on the combatant w
         +hose turn is starting.                                         
      22 +- `app.rb` — Add three POST routes near the existing combat rou
         +tes (around line 1218):                                        
      23 +  - `POST /combat/bardic_inspiration/:id` — body params `succes
         +ses`, `fumbles`. Validate bard has `bardic_inspiration`, has ≥ 
         +1 mana, and `!performed_this_turn`. Deduct 1 mana, add successe
         +s to `luck_points`, add fumbles to `dm_luck_points`, set `perfo
         +rmed_this_turn=true`, append a combat_log entry.               
      24 +  - `POST /combat/spend_luck/:bard_id` — body param `target_nam
         +e`, `kind` in (`ally`, `enemy`). Validate pool > 0 on the match
         +ing field (`luck_points` for ally, `dm_luck_points` for enemy).
         + Decrement, append combat_log.                                 
      25 +- `views/combat_tracker.erb:865-869` — Extend the abilities-but
         +ton block:                                                     
      26 +  - On the acting combatant's step, if they have `bardic_inspir
         +ation` and mana ≥ 1 and !performed_this_turn, render a "Perform
         +" button that opens a two-field prompt (successes / fumbles) an
         +d POSTs to `/combat/bardic_inspiration/:id`.                   
      27 +  - In every combatant's row header, render compact badges show
         +ing `Luck: N` (bard's pool) and `DM Luck: M` when the active co
         +mbat has a bard with a non-zero pool.                          
      28 +  - On each ally-row defense/check step, if any bard's `luck_po
         +ints > 0`, add a "Spend Luck (reroll)" button that POSTs to `/c
         +ombat/spend_luck/:bard_id` with `kind=ally`.                   
      29 +  - On each enemy-row defense/check step, if any bard's `dm_luc
         +k_points > 0`, add a "Spend DM Luck (reroll)" button that POSTs
         + with `kind=enemy`.                                            
      30 +- `data/combat_log.json` — Existing logging helper used by othe
         +r abilities; reuse for the two log entries (generation + each s
         +pend).                                                         
      31  
      24 -## Design decisions (recommended)                              
      32 +## Design decisions                                            
      33  
      26 -1. **Storage**: Single pool stored on the bard's participant ro
         -w (`luck_points: N`). Allies and enemies don't get their own co
         -pies — the UI reads from the bard's row. (Text: "pool… spent by
         - you or your team"; ownership is the bard's since expiration is
         - tied to their turn.)                                          
      27 -2. **Generation**: On clicking **Perform**, prompt the DM for t
         -he number of successes (integer input), deduct 1 mana, add that
         - many luck points. Auto-rolling the performance check is out of
         - scope — the rest of the codebase uses manual-entry for skill c
         -hecks.                                                         
      28 -3. **Spending**: Clicking **Spend Luck** on any row decrements 
         -the bard's pool by 1 and writes a log entry ("Spent luck to rer
         -oll for <name>"). The actual die reroll is physical/verbal at t
         -he table — this matches how `better_lucky_than_good` works (it 
         -records the effect; the reroll outcome is narrated).           
      29 -4. **Expiration**: In `CombatTurn#new_turn`, if `self` is the b
         -ard who owns the pool, reset `luck_points` to 0. This triggers 
         -when their turn comes back around.                             
      30 -5. **Once-per-turn cap**: Track a `performed_this_turn` boolean
         - on the bard's row; clear it in `new_turn`. Gate the Perform bu
         -tton on `!performed_this_turn`.                                
      31 -6. **Fumble / DM luck**: Out of scope for v1 (can be added as a
         - negative-or-separate pool later). Mention in v2 follow-up.    
      34 +1. **Storage**: Both pools live on the bard's participant row (
         +`luck_points`, `dm_luck_points`). No top-level keys; expiration
         + is naturally scoped to the bard's turn. Allies and enemies rea
         +d the pool via a helper that scans participants for the bard.  
      35 +2. **Multi-bard handling**: If two bards are in combat each has
         + their own pool; the spend UI labels buttons "Spend Luck (Alice
         +)" vs "Spend Luck (Bob)" so the DM picks which pool to drain. N
         +ot a common case but cheap to support correctly.               
      36 +3. **Generation UI**: Single "Perform" button opens an inline p
         +rompt with two small integer inputs ("successes", "fumbles"). S
         +ubmit triggers the POST. Manual entry matches how skill checks 
         +work elsewhere in the tool.                                    
      37 +4. **Spending UI**: Existing defense/check steps already render
         + per-participant ability buttons (see `combat_tracker.erb:865-8
         +69`). The spend buttons slot into the same step. Reroll outcome
         + is narrated at the table — tool only records the spend, same a
         +s `better_lucky_than_good`.                                    
      38 +5. **Once-per-turn**: `performed_this_turn` clears in `CombatTu
         +rn#new_turn`, so it resets each round.                         
      39 +6. **Expiration**: `new_turn` also resets both pools to 0, matc
         +hing "each point must be used before your next turn or it is lo
         +st."                                                           
      40 +7. **DM pool expiration**: The ability text only explicitly exp
         +ires the player pool, but applying the same rule to the DM pool
         + is the least surprising default and avoids stale state carryin
         +g across encounters. Call this out in the compendium text if ne
         +eded.                                                          
      41  
      33 -## Verification                                                
      42 +## Compendium text update                                      
      43  
      35 -1. Load combat with a bard PC; confirm their row shows a "Perfo
         -rm" button only on their turn and only when mana ≥ 1.          
      36 -2. Click Perform, enter `3` for successes; verify mana drops by
         - 1 and luck reads 3.                                           
      37 -3. On an ally's row, click "Spend Luck" — verify bard's pool dr
         -ops to 2 and combat_log records the spend.                     
      38 -4. Advance initiative back to the bard; verify pool resets to 0
         - and Perform is available again.                               
      39 -5. Try to Perform twice in the same turn — second attempt shoul
         -d be blocked (button hidden or error).                         
      40 -6. Run existing specs: `bundle exec rspec spec/` — nothing shou
         -ld regress.                                                    
      44 +Rewrite `data/compendium.json:1909` (`versatile_performance`): 
      45  
      42 -## Open questions for user (resolve before finalizing)         
      46 +> "You can use points of luck from your performance to aid your
         + allies. You must decide to use your luck point before they rol
         +l and afterwards you can choose one of their dice to reroll."  
      47  
      44 -- Auto-roll performance check vs. manual success entry?        
      45 -- Should players see/spend luck from their own character-sheet 
         -view, or DM-only via combat tracker?                           
      46 -- Handle the fumble → DM-luck clause now or defer?             
      47 -- versatile_performance text is currently a copy-paste of unset
         -tling_words. Is that the intended game rule (both abilities do 
         -the same thing), or should versatile_performance be the ally-re
         -roll version?                                                  
      48 +Leave `unsettling_words` (line 1908) as-is — it already correct
         +ly describes the enemy-reroll case.                            
      49 +                                                               
      50 +## Verification                                                
      51 +                                                               
      52 +1. Load combat with a bard PC who has `bardic_inspiration`; con
         +firm a "Perform" button appears on their turn and only when man
         +a ≥ 1.                                                         
      53 +2. Click Perform, enter `successes=3, fumbles=1`; verify mana d
         +rops by 1, `Luck: 3` and `DM Luck: 1` badges appear on the bard
         +'s row, and combat_log has the generation entry.               
      54 +3. Try to Perform again the same turn — button should be absent
         +/disabled.                                                     
      55 +4. On an ally's defense step, click "Spend Luck" — verify bard'
         +s `luck_points` drops to 2 and combat_log records the spend wit
         +h the ally's name.                                             
      56 +5. On an enemy's defense step, click "Spend DM Luck" — verify `
         +dm_luck_points` drops to 0 and combat_log records the spend.   
      57 +6. Advance initiative back to the bard; verify both pools reset
         + to 0 and `performed_this_turn` is false (Perform button return
         +s).                                                            
      58 +7. Add a second bard to combat; verify each has an independent 
         +pool and the spend buttons are labeled by bard name.           
      59 +8. Run `bundle exec rspec spec/` — no regressions.             
  ⎿  User rejected Claude's plan:
     ╭─────────────────────────────────────────────────────────────────────────╮
     │ Bard Luck Points — Implementation Plan                                  │
     │                                                                         │
     │ Context                                                                 │
     │                                                                         │
     │ The bard class has three abilities whose text already references a      │
     │ "luck point" pool, but no runtime implementation exists:                │
     │                                                                         │
     │ - bardic_inspiration (Bard 1): Generates the pool. Costs 1 mana, once   │
     │ per turn, main action. Each success on the performance roll adds 1      │
     │ luck; each fumble gives the DM 1 adversarial luck. Pool expires at the  │
     │ start of the bard's next turn.                                          │
     │ - unsettling_words (Bard 3): Spend 1 luck to force an enemy to reroll   │
     │ one die.                                                                │
     │ - versatile_performance (Bard 4): Spend 1 luck to let an ally reroll    │
     │ one die. (Compendium text is currently a copy-paste of                  │
     │ unsettling_words; it will be rewritten to describe the ally-reroll      │
     │ version.)                                                               │
     │                                                                         │
     │ Today, data/combat.json participants track mana, combat pool, and       │
     │ saturation, but nothing tracks luck. The combat tracker                 │
     │ (views/combat_tracker.erb) has a working pattern for similar defensive  │
     │ abilities (better_lucky_than_good, danger_sense) — a conditional button │
     │  gated on abilities + a resource threshold that pays a cost and applies │
     │  an effect. Luck will follow the same pattern.                          │
     │                                                                         │
     │ The intended outcome: on the bard's turn the DM clicks "Perform",       │
     │ enters successes and fumbles, and the tool deducts 1 mana, adds the     │
     │ successes to the bard's luck pool, and adds the fumbles to a DM-side    │
     │ luck pool. Both pools are visible during combat; the DM clicks "Spend   │
     │ Luck" on an ally row (player pool) or enemy row (DM pool) to apply a    │
     │ reroll. Both pools auto-clear when the bard's turn comes around again.  │
     │                                                                         │
     │ Key files                                                               │
     │                                                                         │
     │ - data/compendium.json:1881 — bardic_inspiration text (no change        │
     │ needed; already accurate).                                              │
     │ - data/compendium.json:1909 — versatile_performance text: rewrite to    │
     │ "You can use points of luck from your performance to aid your allies.   │
     │ Before they roll you can spend one luck point; afterwards you choose    │
     │ one of their dice to reroll."                                           │
     │ - data/combat.json — Participant schema: add luck_points and            │
     │ dm_luck_points fields (non-negative integers, default 0). Add           │
     │ performed_this_turn boolean (default false) on the bard's row to        │
     │ enforce once-per-turn.                                                  │
     │ - character.rb:3-72 (CombatTurn) — Add luck_points, dm_luck_points,     │
     │ performed_this_turn attrs; persist in to_json; in new_turn reset all    │
     │ three to 0/false (new turn = this combatant's turn starting, which is   │
     │ exactly when the bard's pools should expire).                           │
     │ - character.rb:81+ (Combat) — No structural change; existing per-turn   │
     │ dispatch already calls new_turn on the combatant whose turn is          │
     │ starting.                                                               │
     │ - app.rb — Add three POST routes near the existing combat routes        │
     │ (around line 1218):                                                     │
     │   - POST /combat/bardic_inspiration/:id — body params successes,        │
     │ fumbles. Validate bard has bardic_inspiration, has ≥ 1 mana, and        │
     │ !performed_this_turn. Deduct 1 mana, add successes to luck_points, add  │
     │ fumbles to dm_luck_points, set performed_this_turn=true, append a       │
     │ combat_log entry.                                                       │
     │   - POST /combat/spend_luck/:bard_id — body param target_name, kind in  │
     │ (ally, enemy). Validate pool > 0 on the matching field (luck_points for │
     │  ally, dm_luck_points for enemy). Decrement, append combat_log.         │
     │ - views/combat_tracker.erb:865-869 — Extend the abilities-button block: │
     │   - On the acting combatant's step, if they have bardic_inspiration and │
     │  mana ≥ 1 and !performed_this_turn, render a "Perform" button that      │
     │ opens a two-field prompt (successes / fumbles) and POSTs to             │
     │ /combat/bardic_inspiration/:id.                                         │
     │   - In every combatant's row header, render compact badges showing      │
     │ Luck: N (bard's pool) and DM Luck: M when the active combat has a bard  │
     │ with a non-zero pool.                                                   │
     │   - On each ally-row defense/check step, if any bard's luck_points > 0, │
     │  add a "Spend Luck (reroll)" button that POSTs to                       │
     │ /combat/spend_luck/:bard_id with kind=ally.                             │
     │   - On each enemy-row defense/check step, if any bard's dm_luck_points  │
     │ > 0, add a "Spend DM Luck (reroll)" button that POSTs with kind=enemy.  │
     │ - data/combat_log.json — Existing logging helper used by other          │
     │ abilities; reuse for the two log entries (generation + each spend).     │
     │                                                                         │
     │ Design decisions                                                        │
     │                                                                         │
     │ 1. Storage: Both pools live on the bard's participant row (luck_points, │
     │  dm_luck_points). No top-level keys; expiration is naturally scoped to  │
     │ the bard's turn. Allies and enemies read the pool via a helper that     │
     │ scans participants for the bard.                                        │
     │ 2. Multi-bard handling: If two bards are in combat each has their own   │
     │ pool; the spend UI labels buttons "Spend Luck (Alice)" vs "Spend Luck   │
     │ (Bob)" so the DM picks which pool to drain. Not a common case but cheap │
     │  to support correctly.                                                  │
     │ 3. Generation UI: Single "Perform" button opens an inline prompt with   │
     │ two small integer inputs ("successes", "fumbles"). Submit triggers the  │
     │ POST. Manual entry matches how skill checks work elsewhere in the tool. │
     │ 4. Spending UI: Existing defense/check steps already render             │
     │ per-participant ability buttons (see combat_tracker.erb:865-869). The   │
     │ spend buttons slot into the same step. Reroll outcome is narrated at    │
     │ the table — tool only records the spend, same as                        │
     │ better_lucky_than_good.                                                 │
     │ 5. Once-per-turn: performed_this_turn clears in CombatTurn#new_turn, so │
     │  it resets each round.                                                  │
     │ 6. Expiration: new_turn also resets both pools to 0, matching "each     │
     │ point must be used before your next turn or it is lost."                │
     │ 7. DM pool expiration: The ability text only explicitly expires the     │
     │ player pool, but applying the same rule to the DM pool is the least     │
     │ surprising default and avoids stale state carrying across encounters.   │
     │ Call this out in the compendium text if needed.                         │
     │                                                                         │
     │ Compendium text update                                                  │
     │                                                                         │
     │ Rewrite data/compendium.json:1909 (versatile_performance):              │
     │                                                                         │
     │ ▎ "You can use points of luck from your performance to aid your allies. │
     │ ▎  You must decide to use your luck point before they roll and          │
     │ ▎ afterwards you can choose one of their dice to reroll."               │
     │                                                                         │
     │ Leave unsettling_words (line 1908) as-is — it already correctly         │
     │ describes the enemy-reroll case.                                        │
     │                                                                         │
     │ Verification                                                            │
     │                                                                         │
     │ 1. Load combat with a bard PC who has bardic_inspiration; confirm a     │
     │ "Perform" button appears on their turn and only when mana ≥ 1.          │
     │ 2. Click Perform, enter successes=3, fumbles=1; verify mana drops by 1, │
     │  Luck: 3 and DM Luck: 1 badges appear on the bard's row, and combat_log │
     │  has the generation entry.                                              │
     │ 3. Try to Perform again the same turn — button should be                │
     │ absent/disabled.                                                        │
     │ 4. On an ally's defense step, click "Spend Luck" — verify bard's        │
     │ luck_points drops to 2 and combat_log records the spend with the ally's │
     │  name.                                                                  │
     │ 5. On an enemy's defense step, click "Spend DM Luck" — verify           │
     │ dm_luck_points drops to 0 and combat_log records the spend.             │
     │ 6. Advance initiative back to the bard; verify both pools reset to 0    │
     │ and performed_this_turn is false (Perform button returns).              │
     │ 7. Add a second bard to combat; verify each has an independent pool and │
     │  the spend buttons are labeled by bard name.                            │
     │ 8. Run bundle exec rspec spec/ — no regressions.                        │
     ╰─────────────────────────────────────────────────────────────────────────╯

● Understood — the two pools are mutually exclusive, like a signed ledger. Let
  me update the plan.

● Update(/root/.claude/plans/bards-have-the-ability-delegated-snowglobe.md)
  ⎿  Added 1 line, removed 1 line
       4  
       5  The bard class has three abilities whose text already reference
          s a "luck point" pool, but no runtime implementation exists:
       6  
       7 -- **bardic_inspiration** (Bard 1): Generates the pool. Costs 1 
         -mana, once per turn, main action. Each success on the performan
         -ce roll adds 1 luck; each fumble gives the DM 1 adversarial luc
         -k. Pool expires at the start of the bard's next turn.          
       7 +- **bardic_inspiration** (Bard 1): Generates the pool. Costs 1 
         +mana, once per turn, main action. Successes and fumbles net aga
         +inst a single signed ledger: successes add to the bard's luck p
         +ool, fumbles subtract from it, and only if fumbles drive the po
         +ol below zero does the overflow become DM luck (spendable again
         +st players). The two pools are mutually exclusive — only one is
         + ever non-zero at a time. Pool expires at the start of the bard
         +'s next turn.                                                  
       8  - **unsettling_words** (Bard 3): Spend 1 luck to force an enemy
           to reroll one die.
       9  - **versatile_performance** (Bard 4): Spend 1 luck to let an al
          ly reroll one die. (Compendium text is currently a copy-paste o
          f unsettling_words; it will be rewritten to describe the ally-r
          eroll version.)
      10  

● Update(/root/.claude/plans/bards-have-the-ability-delegated-snowglobe.md)
  ⎿  Added 1 line, removed 1 line
      10  
      11  Today, `data/combat.json` participants track mana, combat pool,
           and saturation, but nothing tracks luck. The combat tracker (`
          views/combat_tracker.erb`) has a working pattern for similar de
          fensive abilities (`better_lucky_than_good`, `danger_sense`) — 
          a conditional button gated on `abilities` + a resource threshol
          d that pays a cost and applies an effect. Luck will follow the 
          same pattern.
      12  
      13 -The intended outcome: on the bard's turn the DM clicks "Perform
         -", enters successes and fumbles, and the tool deducts 1 mana, a
         -dds the successes to the bard's luck pool, and adds the fumbles
         - to a DM-side luck pool. Both pools are visible during combat; 
         -the DM clicks "Spend Luck" on an ally row (player pool) or enem
         -y row (DM pool) to apply a reroll. Both pools auto-clear when t
         -he bard's turn comes around again.                             
      13 +The intended outcome: on the bard's turn the DM clicks "Perform
         +", enters successes and fumbles, and the tool deducts 1 mana an
         +d applies `successes - fumbles` to the bard's luck ledger. A po
         +sitive ledger shows as `Luck: N` (player pool, spendable on all
         +ies); a negative ledger shows as `DM Luck: N` (spendable agains
         +t players). The DM clicks "Spend Luck" on an ally row (when the
         + ledger is positive) or enemy row (when it's negative) to apply
         + a reroll. The ledger auto-clears to zero when the bard's turn 
         +comes around again.                                            
      14  
      15  ## Key files
      16  

● Update(/root/.claude/plans/bards-have-the-ability-delegated-snowglobe.md)  ⎿  Added 2 lines, removed 2 lines
      16  
      17  - `data/compendium.json:1881` — `bardic_inspiration` text (no c
          hange needed; already accurate).
      18  - `data/compendium.json:1909` — `versatile_performance` text: r
          ewrite to "You can use points of luck from your performance to 
          aid your allies. Before they roll you can spend one luck point;
           afterwards you choose one of their dice to reroll."
      19 -- `data/combat.json` — Participant schema: add `luck_points` an
         -d `dm_luck_points` fields (non-negative integers, default 0). A
         -dd `performed_this_turn` boolean (default false) on the bard's 
         -row to enforce once-per-turn.                                  
      20 -- `character.rb:3-72` (`CombatTurn`) — Add `luck_points`, `dm_l
         -uck_points`, `performed_this_turn` attrs; persist in `to_json`;
         - in `new_turn` reset all three to 0/false (new turn = this comb
         -atant's turn starting, which is exactly when the bard's pools s
         -hould expire).                                                 
      19 +- `data/combat.json` — Participant schema: add a single signed 
         +`luck_ledger` integer field (default 0; positive = player pool,
         + negative magnitude = DM pool). Add `performed_this_turn` boole
         +an (default false) on the bard's row to enforce once-per-turn. 
      20 +- `character.rb:3-72` (`CombatTurn`) — Add `luck_ledger` and `p
         +erformed_this_turn` attrs; persist in `to_json`; in `new_turn` 
         +reset both to 0/false (new turn = this combatant's turn startin
         +g, which is exactly when the bard's ledger should expire). Expo
         +se helper accessors `luck_points` (max(ledger, 0)) and `dm_luck
         +_points` (max(-ledger, 0)) for display.                        
      21  - `character.rb:81+` (`Combat`) — No structural change; existin
          g per-turn dispatch already calls `new_turn` on the combatant w
          hose turn is starting.
      22  - `app.rb` — Add three POST routes near the existing combat rou
          tes (around line 1218):
      23    - `POST /combat/bardic_inspiration/:id` — body params `succes
          ses`, `fumbles`. Validate bard has `bardic_inspiration`, has ≥ 
          1 mana, and `!performed_this_turn`. Deduct 1 mana, add successe
          s to `luck_points`, add fumbles to `dm_luck_points`, set `perfo
          rmed_this_turn=true`, append a combat_log entry.

● Update(/root/.claude/plans/bards-have-the-ability-delegated-snowglobe.md)
  ⎿  Added 3 lines, removed 3 lines
      19  - `data/combat.json` — Participant schema: add a single signed 
          `luck_ledger` integer field (default 0; positive = player pool,
           negative magnitude = DM pool). Add `performed_this_turn` boole
          an (default false) on the bard's row to enforce once-per-turn.
      20  - `character.rb:3-72` (`CombatTurn`) — Add `luck_ledger` and `p
          erformed_this_turn` attrs; persist in `to_json`; in `new_turn` 
          reset both to 0/false (new turn = this combatant's turn startin
          g, which is exactly when the bard's ledger should expire). Expo
          se helper accessors `luck_points` (max(ledger, 0)) and `dm_luck
          _points` (max(-ledger, 0)) for display.
      21  - `character.rb:81+` (`Combat`) — No structural change; existin
          g per-turn dispatch already calls `new_turn` on the combatant w
          hose turn is starting.
      22 -- `app.rb` — Add three POST routes near the existing combat rou
         -tes (around line 1218):                                        
      23 -  - `POST /combat/bardic_inspiration/:id` — body params `succes
         -ses`, `fumbles`. Validate bard has `bardic_inspiration`, has ≥ 
         -1 mana, and `!performed_this_turn`. Deduct 1 mana, add successe
         -s to `luck_points`, add fumbles to `dm_luck_points`, set `perfo
         -rmed_this_turn=true`, append a combat_log entry.               
      24 -  - `POST /combat/spend_luck/:bard_id` — body param `target_nam
         -e`, `kind` in (`ally`, `enemy`). Validate pool > 0 on the match
         -ing field (`luck_points` for ally, `dm_luck_points` for enemy).
         - Decrement, append combat_log.                                 
      22 +- `app.rb` — Add two POST routes near the existing combat route
         +s (around line 1218):                                          
      23 +  - `POST /combat/bardic_inspiration/:id` — body params `succes
         +ses`, `fumbles`. Validate bard has `bardic_inspiration`, has ≥ 
         +1 mana, and `!performed_this_turn`. Deduct 1 mana, apply `luck_
         +ledger += successes - fumbles`, set `performed_this_turn=true`,
         + append a combat_log entry showing the delta and the new ledger
         +.                                                              
      24 +  - `POST /combat/spend_luck/:bard_id` — body params `target_na
         +me`, `kind` in (`ally`, `enemy`). Validate ledger sign matches 
         +(`luck_ledger > 0` for ally reroll, `luck_ledger < 0` for enemy
         + reroll). Move the ledger one step toward zero (`ledger -= 1` i
         +f positive, `ledger += 1` if negative). Append combat_log.     
      25  - `views/combat_tracker.erb:865-869` — Extend the abilities-but
          ton block:
      26    - On the acting combatant's step, if they have `bardic_inspir
          ation` and mana ≥ 1 and !performed_this_turn, render a "Perform
          " button that opens a two-field prompt (successes / fumbles) an
          d POSTs to `/combat/bardic_inspiration/:id`.
      27    - In every combatant's row header, render compact badges show
          ing `Luck: N` (bard's pool) and `DM Luck: M` when the active co
          mbat has a bard with a non-zero pool.

● Update(/root/.claude/plans/bards-have-the-ability-delegated-snowglobe.md)
  ⎿  Added 3 lines, removed 3 lines
      24    - `POST /combat/spend_luck/:bard_id` — body params `target_na
          me`, `kind` in (`ally`, `enemy`). Validate ledger sign matches 
          (`luck_ledger > 0` for ally reroll, `luck_ledger < 0` for enemy
           reroll). Move the ledger one step toward zero (`ledger -= 1` i
          f positive, `ledger += 1` if negative). Append combat_log.
      25  - `views/combat_tracker.erb:865-869` — Extend the abilities-but
          ton block:
      26    - On the acting combatant's step, if they have `bardic_inspir
          ation` and mana ≥ 1 and !performed_this_turn, render a "Perform
          " button that opens a two-field prompt (successes / fumbles) an
          d POSTs to `/combat/bardic_inspiration/:id`.
      27 -  - In every combatant's row header, render compact badges show
         -ing `Luck: N` (bard's pool) and `DM Luck: M` when the active co
         -mbat has a bard with a non-zero pool.                          
      28 -  - On each ally-row defense/check step, if any bard's `luck_po
         -ints > 0`, add a "Spend Luck (reroll)" button that POSTs to `/c
         -ombat/spend_luck/:bard_id` with `kind=ally`.                   
      29 -  - On each enemy-row defense/check step, if any bard's `dm_luc
         -k_points > 0`, add a "Spend DM Luck (reroll)" button that POSTs
         - with `kind=enemy`.                                            
      27 +  - In the combat tracker header (or bard's row), render a sing
         +le badge showing `Luck: N` when the ledger is positive or `DM L
         +uck: N` when negative. Hide when zero.                         
      28 +  - On each ally-row defense/check step, if any bard's `luck_le
         +dger > 0`, add a "Spend Luck (reroll)" button that POSTs to `/c
         +ombat/spend_luck/:bard_id` with `kind=ally`.                   
      29 +  - On each enemy-row defense/check step, if any bard's `luck_l
         +edger < 0`, add a "Spend DM Luck (reroll)" button that POSTs wi
         +th `kind=enemy`.                                               
      30  - `data/combat_log.json` — Existing logging helper used by othe
          r abilities; reuse for the two log entries (generation + each s
          pend).
      31  
      32  ## Design decisions

● Update(/root/.claude/plans/bards-have-the-ability-delegated-snowglobe.md)
  ⎿  Added 4 lines, removed 5 lines
      31  
      32  ## Design decisions
      33  
      34 -1. **Storage**: Both pools live on the bard's participant row (
         -`luck_points`, `dm_luck_points`). No top-level keys; expiration
         - is naturally scoped to the bard's turn. Allies and enemies rea
         -d the pool via a helper that scans participants for the bard.  
      35 -2. **Multi-bard handling**: If two bards are in combat each has
         - their own pool; the spend UI labels buttons "Spend Luck (Alice
         -)" vs "Spend Luck (Bob)" so the DM picks which pool to drain. N
         -ot a common case but cheap to support correctly.               
      36 -3. **Generation UI**: Single "Perform" button opens an inline p
         -rompt with two small integer inputs ("successes", "fumbles"). S
         -ubmit triggers the POST. Manual entry matches how skill checks 
         -work elsewhere in the tool.                                    
      34 +1. **Single signed ledger**: One integer (`luck_ledger`) on the
         + bard's participant row represents both pools. Positive = playe
         +r luck, negative magnitude = DM luck. The sign flips naturally 
         +when fumbles exceed accumulated successes, enforcing the "eithe
         +r player or DM, never both" invariant without special-case code
         +.                                                              
      35 +2. **Multi-bard handling**: Each bard has their own ledger; the
         + spend UI labels buttons with the bard's name ("Spend Luck (Ali
         +ce)" vs "Spend Luck (Bob)") so the DM picks which ledger to dra
         +in. Cheap to support correctly.                                
      36 +3. **Generation UI**: Single "Perform" button opens an inline p
         +rompt with two small integer inputs ("successes", "fumbles"). S
         +ubmit triggers the POST, which applies `ledger += successes - f
         +umbles`. Manual entry matches how skill checks work elsewhere i
         +n the tool.                                                    
      37  4. **Spending UI**: Existing defense/check steps already render
           per-participant ability buttons (see `combat_tracker.erb:865-8
          69`). The spend buttons slot into the same step. Reroll outcome
           is narrated at the table — tool only records the spend, same a
          s `better_lucky_than_good`.
      38  5. **Once-per-turn**: `performed_this_turn` clears in `CombatTu
          rn#new_turn`, so it resets each round.
      39 -6. **Expiration**: `new_turn` also resets both pools to 0, matc
         -hing "each point must be used before your next turn or it is lo
         -st."                                                           
      40 -7. **DM pool expiration**: The ability text only explicitly exp
         -ires the player pool, but applying the same rule to the DM pool
         - is the least surprising default and avoids stale state carryin
         -g across encounters. Call this out in the compendium text if ne
         -eded.                                                          
      39 +6. **Expiration**: `new_turn` also resets the ledger to 0, matc
         +hing "each point must be used before your next turn or it is lo
         +st" — and extending the same rule to DM luck for symmetry (avoi
         +ds stale adversarial state across encounters).                 
      40  
      41  ## Compendium text update
      42  

● Update(/root/.claude/plans/bards-have-the-ability-delegated-snowglobe.md)
  ⎿  Added 7 lines, removed 6 lines
      49  ## Verification
      50  
      51  1. Load combat with a bard PC who has `bardic_inspiration`; con
          firm a "Perform" button appears on their turn and only when man
          a ≥ 1.
      52 -2. Click Perform, enter `successes=3, fumbles=1`; verify mana d
         -rops by 1, `Luck: 3` and `DM Luck: 1` badges appear on the bard
         -'s row, and combat_log has the generation entry.               
      52 +2. Click Perform, enter `successes=3, fumbles=1`; verify mana d
         +rops by 1, ledger is +2, badge reads `Luck: 2`, no DM Luck badg
         +e, combat_log has the entry.                                   
      53  3. Try to Perform again the same turn — button should be absent
          /disabled.
      54 -4. On an ally's defense step, click "Spend Luck" — verify bard'
         -s `luck_points` drops to 2 and combat_log records the spend wit
         -h the ally's name.                                             
      55 -5. On an enemy's defense step, click "Spend DM Luck" — verify `
         -dm_luck_points` drops to 0 and combat_log records the spend.   
      56 -6. Advance initiative back to the bard; verify both pools reset
         - to 0 and `performed_this_turn` is false (Perform button return
         -s).                                                            
      57 -7. Add a second bard to combat; verify each has an independent 
         -pool and the spend buttons are labeled by bard name.           
      58 -8. Run `bundle exec rspec spec/` — no regressions.             
      54 +4. Advance to the next round; Perform with `successes=0, fumble
         +s=4`; verify ledger becomes -2, badge now reads `DM Luck: 2`, L
         +uck badge is hidden.                                           
      55 +5. On an enemy's defense step, click "Spend DM Luck" — verify l
         +edger moves to -1; spend again, verify ledger = 0 and the butto
         +n disappears.                                                  
      56 +6. Set up a ledger at +2, then Perform with `successes=1, fumbl
         +es=4`: ledger should become 2 + 1 - 4 = -1 (DM Luck: 1), confir
         +ming the single-ledger transition.                             
      57 +7. Advance initiative back to the bard; verify ledger resets to
         + 0 and `performed_this_turn` is false (Perform button returns).
      58 +8. Add a second bard to combat; verify each has an independent 
         +ledger and the spend buttons are labeled by bard name.         
      59 +9. Run `bundle exec rspec spec/` — no regressions.             

● User approved Claude's plan
  ⎿  Plan saved to: 
     /root/.claude/plans/bards-have-the-ability-delegated-snowglobe.md · /plan 
     to edit
     Bard Luck Points — Implementation Plan

     Context

     The bard class has three abilities whose text already references a "luck
     point" pool, but no runtime implementation exists:

     - bardic_inspiration (Bard 1): Generates the pool. Costs 1 mana, once per
     turn, main action. Successes and fumbles net against a single signed
     ledger: successes add to the bard's luck pool, fumbles subtract from it,
     and only if fumbles drive the pool below zero does the overflow become DM
     luck (spendable against players). The two pools are mutually exclusive —
     only one is ever non-zero at a time. Pool expires at the start of the
     bard's next turn.
     - unsettling_words (Bard 3): Spend 1 luck to force an enemy to reroll one
     die.
     - versatile_performance (Bard 4): Spend 1 luck to let an ally reroll one
     die. (Compendium text is currently a copy-paste of unsettling_words; it
     will be rewritten to describe the ally-reroll version.)

     Today, data/combat.json participants track mana, combat pool, and
     saturation, but nothing tracks luck. The combat tracker
     (views/combat_tracker.erb) has a working pattern for similar defensive
     abilities (better_lucky_than_good, danger_sense) — a conditional button
     gated on abilities + a resource threshold that pays a cost and applies an
     effect. Luck will follow the same pattern.

     The intended outcome: on the bard's turn the DM clicks "Perform", enters
     successes and fumbles, and the tool deducts 1 mana and applies successes - 
     fumbles to the bard's luck ledger. A positive ledger shows as Luck: N
     (player pool, spendable on allies); a negative ledger shows as DM Luck: N
     (spendable against players). The DM clicks "Spend Luck" on an ally row
     (when the ledger is positive) or enemy row (when it's negative) to apply a
     reroll. The ledger auto-clears to zero when the bard's turn comes around
     again.

     Key files

     - data/compendium.json:1881 — bardic_inspiration text (no change needed;
     already accurate).
     - data/compendium.json:1909 — versatile_performance text: rewrite to "You
     can use points of luck from your performance to aid your allies. Before
     they roll you can spend one luck point; afterwards you choose one of their
     dice to reroll."
     - data/combat.json — Participant schema: add a single signed luck_ledger
     integer field (default 0; positive = player pool, negative magnitude = DM
     pool). Add performed_this_turn boolean (default false) on the bard's row to
      enforce once-per-turn.
     - character.rb:3-72 (CombatTurn) — Add luck_ledger and performed_this_turn
     attrs; persist in to_json; in new_turn reset both to 0/false (new turn =
     this combatant's turn starting, which is exactly when the bard's ledger
     should expire). Expose helper accessors luck_points (max(ledger, 0)) and
     dm_luck_points (max(-ledger, 0)) for display.
     - character.rb:81+ (Combat) — No structural change; existing per-turn
     dispatch already calls new_turn on the combatant whose turn is starting.
     - app.rb — Add two POST routes near the existing combat routes (around
     line 1218):
       - POST /combat/bardic_inspiration/:id — body params successes, fumbles.
     Validate bard has bardic_inspiration, has ≥ 1 mana, and
     !performed_this_turn. Deduct 1 mana, apply luck_ledger += successes - 
     fumbles, set performed_this_turn=true, append a combat_log entry showing
     the delta and the new ledger.
       - POST /combat/spend_luck/:bard_id — body params target_name, kind in
     (ally, enemy). Validate ledger sign matches (luck_ledger > 0 for ally
     reroll, luck_ledger < 0 for enemy reroll). Move the ledger one step toward
     zero (ledger -= 1 if positive, ledger += 1 if negative). Append combat_log.
     - views/combat_tracker.erb:865-869 — Extend the abilities-button block:
       - On the acting combatant's step, if they have bardic_inspiration and
     mana ≥ 1 and !performed_this_turn, render a "Perform" button that opens a
     two-field prompt (successes / fumbles) and POSTs to
     /combat/bardic_inspiration/:id.
       - In the combat tracker header (or bard's row), render a single badge
     showing Luck: N when the ledger is positive or DM Luck: N when negative.
     Hide when zero.
       - On each ally-row defense/check step, if any bard's luck_ledger > 0, add
      a "Spend Luck (reroll)" button that POSTs to /combat/spend_luck/:bard_id
     with kind=ally.
       - On each enemy-row defense/check step, if any bard's luck_ledger < 0,
     add a "Spend DM Luck (reroll)" button that POSTs with kind=enemy.
     - data/combat_log.json — Existing logging helper used by other abilities;
     reuse for the two log entries (generation + each spend).

     Design decisions

     1. Single signed ledger: One integer (luck_ledger) on the bard's
     participant row represents both pools. Positive = player luck, negative
     magnitude = DM luck. The sign flips naturally when fumbles exceed
     accumulated successes, enforcing the "either player or DM, never both"
     invariant without special-case code.
     2. Multi-bard handling: Each bard has their own ledger; the spend UI labels
      buttons with the bard's name ("Spend Luck (Alice)" vs "Spend Luck (Bob)")
     so the DM picks which ledger to drain. Cheap to support correctly.
     3. Generation UI: Single "Perform" button opens an inline prompt with two
     small integer inputs ("successes", "fumbles"). Submit triggers the POST,
     which applies ledger += successes - fumbles. Manual entry matches how skill
      checks work elsewhere in the tool.
     4. Spending UI: Existing defense/check steps already render per-participant
      ability buttons (see combat_tracker.erb:865-869). The spend buttons slot
     into the same step. Reroll outcome is narrated at the table — tool only
     records the spend, same as better_lucky_than_good.
     5. Once-per-turn: performed_this_turn clears in CombatTurn#new_turn, so it
     resets each round.
     6. Expiration: new_turn also resets the ledger to 0, matching "each point
     must be used before your next turn or it is lost" — and extending the same
     rule to DM luck for symmetry (avoids stale adversarial state across
     encounters).

     Compendium text update

     Rewrite data/compendium.json:1909 (versatile_performance):

     ▎ "You can use points of luck from your performance to aid your allies. You
     ▎  must decide to use your luck point before they roll and afterwards you 
     ▎ can choose one of their dice to reroll."

     Leave unsettling_words (line 1908) as-is — it already correctly describes
     the enemy-reroll case.

     Verification

     1. Load combat with a bard PC who has bardic_inspiration; confirm a
     "Perform" button appears on their turn and only when mana ≥ 1.
     2. Click Perform, enter successes=3, fumbles=1; verify mana drops by 1,
     ledger is +2, badge reads Luck: 2, no DM Luck badge, combat_log has the
     entry.
     3. Try to Perform again the same turn — button should be absent/disabled.
     4. Advance to the next round; Perform with successes=0, fumbles=4; verify
     ledger becomes -2, badge now reads DM Luck: 2, Luck badge is hidden.
     5. On an enemy's defense step, click "Spend DM Luck" — verify ledger moves
     to -1; spend again, verify ledger = 0 and the button disappears.
     6. Set up a ledger at +2, then Perform with successes=1, fumbles=4: ledger
     should become 2 + 1 - 4 = -1 (DM Luck: 1), confirming the single-ledger
     transition.
     7. Advance initiative back to the bard; verify ledger resets to 0 and
     performed_this_turn is false (Perform button returns).
     8. Add a second bard to combat; verify each has an independent ledger and
     the spend buttons are labeled by bard name.
     9. Run bundle exec rspec spec/ — no regressions.

● Bash(git status && echo "---" && git branch --show-current)
  ⎿  On branch claude/bard-luck-reroll-mechanic-3DFmV
     nothing to commit, working tree clean
     ---
     claude/bard-luck-reroll-mechanic-3DFmV

● Already on the feature branch. Now let me study the existing patterns I'll be
  mirroring.

  Searched for 7 patterns, read 3 files (ctrl+o to expand)

● Good grounding. Moving to implementation.

● Update(/home/user/crimson-steel/character.rb)
  ⎿  Added 7 lines, removed 1 line
      1  require_relative 'tools'
      2  
      3  class CombatTurn
      4 -  attr_reader :rules, :character, :combat_id, :initiative, :mana
        -, :combat_pool, :minor_damage, :moderate_damage, :major_damage, 
        -:saturation, :temporary_hit_points, :conditions, :condition_meta
        -, :ability_damage                                               
      4 +  attr_reader :rules, :character, :combat_id, :initiative, :mana
        +, :combat_pool, :minor_damage, :moderate_damage, :major_damage, 
        +:saturation, :temporary_hit_points, :conditions, :condition_meta
        +, :ability_damage, :luck_ledger, :performed_this_turn           
      5  
      6    def initialize(combat_turn, character)
      7      @rules = Tools.load_json('rules.json')
     ...
      21      # Ability damage: nested hash of ability (str/dex/...) -> s
          everity
      22      # (minor/moderate/major) -> amount. Persists until cured.
      23      @ability_damage = (combat_turn['ability_damage'] || {}).dup
      24 +    # Bardic inspiration ledger. Positive = player luck pool (s
         +pend on                                                        
      25 +    # allies). Negative = DM luck pool (spend against players).
         + Only one                                                      
      26 +    # side is ever non-zero; sign flips naturally as fumbles ex
         +ceed                                                           
      27 +    # successes during Perform. Cleared on the bard's new_turn.
      28 +    @luck_ledger = combat_turn['luck_ledger'].to_i             
      29 +    @performed_this_turn = combat_turn['performed_this_turn'] =
         += true                                                         
      30      @character = CharacterSheet.new(character)
      31      # Inject this participant's combat state into the Character
          Sheet so
      32      # every derived stat (effective ability scores, combat_pool
           via dex,

● Update(/home/user/crimson-steel/character.rb)
  ⎿  Added 13 lines, removed 1 line
      60      result
      61    end
      62  
      63 -  def new_turn; @combat_pool = @character.combat_pool; end     
      63 +  def new_turn                                                 
      64 +    @combat_pool = @character.combat_pool                      
      65 +    # Bardic inspiration luck expires "before your next turn" —
         + clearing on                                                   
      66 +    # the new-round dice reset is the closest hook the combat t
         +racker has                                                     
      67 +    # to a per-combatant turn tick. Also re-arms the once-per-t
         +urn Perform.                                                   
      68 +    @luck_ledger = 0                                           
      69 +    @performed_this_turn = false                               
      70 +  end                                                          
      71 +                                                               
      72 +  def luck_points; [@luck_ledger, 0].max; end                  
      73 +  def dm_luck_points; [-@luck_ledger, 0].max; end              
      74 +                                                               
      75 +  def has_ability?(name); @character.ability_list.include?(name
         +); end                                                         
      76    def reroll_init
      77      bonus = @character.respond_to?(:initiative_die_bonus) ? @ch
          aracter.initiative_die_bonus : 0
      78      @initiative = (1..10).to_a.sample(@character.initiative).ma
          p { |i| [i + bonus, 10].min }.sort.reverse.map { |i| i == 10 ? 
          'X' : i.to_s}.join

● Update(/home/user/crimson-steel/character.rb)
  ⎿  Added 2 lines, removed 1 line
      86        'minor_damage' => @minor_damage, 'moderate_damage' => @mo
          derate_damage, 'major_damage' => @major_damage,
      87        'saturation' => @saturation, 'temporary_hit_points' => @t
          emporary_hit_points,
      88        'conditions' => @conditions, 'condition_meta' => @conditi
          on_meta,
      89 -      'ability_damage' => @ability_damage}                     
      89 +      'ability_damage' => @ability_damage,                     
      90 +      'luck_ledger' => @luck_ledger, 'performed_this_turn' => @
         +performed_this_turn}                                           
      91    end
      92  
      93    def hp; return @character.hp_max - @minor_damage - @moderate_
          damage - @major_damage + @temporary_hit_points.to_i; end

● Now add a helper on Combat to find bards with active ledgers, useful for the
  UI.

  Read 1 file (ctrl+o to expand)

● Update(/home/user/crimson-steel/character.rb)  ⎿  Added 3 lines
      123    def living_turn_list; @combat_turn_list.reject(&:dead?); end
      124    def killed_list; @combat_turn_list.select(&:dead?); end
      125  
      126 +  # Bards whose luck ledger is non-zero; drives the Spend-Luck
          + UI.                                                          
      127 +  def active_luck_bards; @combat_turn_list.select { |ct| ct.lu
          +ck_ledger != 0 }; end                                         
      128 +                                                              
      129    def display_name(combat_turn)
      130      return "Unknown" unless combat_turn&.character
      131      char_id = combat_turn.character.id

● Now update the routes in app.rb. Let me find the right spot.

  Read 1 file (ctrl+o to expand)

● Update(/home/user/crimson-steel/app.rb)
  ⎿  Added 74 lines
      1230    redirect '/combat'
      1231  end
      1232  
      1233 +# Bardic inspiration. Bard's Perform action: deduct 1 mana, a
           +pply                                                         
      1234 +# (successes - fumbles) to the bard's luck_ledger. A positive
           + ledger is                                                   
      1235 +# player luck (spend on allies); negative is DM luck (spend a
           +gainst                                                       
      1236 +# players). Gated to once per turn via performed_this_turn, w
           +hich clears                                                  
      1237 +# on new_turn.                                               
      1238 +post '/combat/bardic_inspiration/:id' do                     
      1239 +  redirect '/character/0' unless local_request?              
      1240 +  combat = Combat.new                                        
      1241 +  bard = combat.combat_turn_list.find { |ct| ct.combat_id == 
           +params[:id].to_i }                                           
      1242 +  halt 400, 'Bard not found' unless bard                     
      1243 +  halt 400, 'Character lacks bardic_inspiration' unless bard.
           +has_ability?('bardic_inspiration')                           
      1244 +  halt 400, 'Already performed this turn' if bard.performed_t
           +his_turn                                                     
      1245 +  halt 400, 'Not enough mana' if bard.mana < 1               
      1246 +                                                             
      1247 +  successes = params[:successes].to_i                        
      1248 +  fumbles = params[:fumbles].to_i                            
      1249 +  halt 400, 'Successes and fumbles must be non-negative' if s
           +uccesses < 0 || fumbles < 0                                  
      1250 +                                                             
      1251 +  combat_data = Tools.load_json('combat.json')               
      1252 +  participant = combat_data['participants'].find { |p| p['id'
           +] == bard.combat_id }                                        
      1253 +  halt 400, 'Participant row missing' unless participant     
      1254 +                                                             
      1255 +  participant['mana'] = bard.mana - 1                        
      1256 +  new_ledger = bard.luck_ledger + successes - fumbles        
      1257 +  participant['luck_ledger'] = new_ledger                    
      1258 +  participant['performed_this_turn'] = true                  
      1259 +  Tools.save_json('combat.json', combat_data)                
      1260 +                                                             
      1261 +  name = combat.display_name(bard)                           
      1262 +  delta = successes - fumbles                                
      1263 +  sign = delta >= 0 ? '+' : ''                               
      1264 +  ledger_label = if new_ledger > 0 then "Luck #{new_ledger}" 
      1265 +                 elsif new_ledger < 0 then "DM Luck #{-new_le
           +dger}"                                                       
      1266 +                 else 'ledger 0'                             
      1267 +                 end                                         
      1268 +  Combat.add_log("#{name} performs (#{successes} successes, #
           +{fumbles} fumbles, #{sign}#{delta}; #{ledger_label}).")      
      1269 +  redirect '/combat'                                         
      1270 +end                                                          
      1271 +                                                             
      1272 +# Spend one point from a bard's luck ledger. kind=ally requir
           +es a                                                         
      1273 +# positive ledger (ally reroll via bardic_inspiration / versa
           +tile_performance);                                           
      1274 +# kind=enemy requires a negative ledger (unsettling_words or 
           +DM-side                                                      
      1275 +# reroll against players). The actual die reroll happens at t
           +he table;                                                    
      1276 +# this endpoint just decrements the ledger and logs.         
      1277 +post '/combat/spend_luck/:bard_id' do                        
      1278 +  redirect '/character/0' unless local_request?              
      1279 +  combat = Combat.new                                        
      1280 +  bard = combat.combat_turn_list.find { |ct| ct.combat_id == 
           +params[:bard_id].to_i }                                      
      1281 +  halt 400, 'Bard not found' unless bard                     
      1282 +                                                             
      1283 +  kind = params[:kind].to_s                                  
      1284 +  halt 400, 'Invalid kind' unless %w[ally enemy].include?(kin
           +d)                                                           
      1285 +  if kind == 'ally'                                          
      1286 +    halt 400, 'No player luck to spend' unless bard.luck_ledg
           +er > 0                                                       
      1287 +    delta = -1                                               
      1288 +  else                                                       
      1289 +    halt 400, 'No DM luck to spend' unless bard.luck_ledger <
           + 0                                                           
      1290 +    delta = 1                                                
      1291 +  end                                                        
      1292 +                                                             
      1293 +  combat_data = Tools.load_json('combat.json')               
      1294 +  participant = combat_data['participants'].find { |p| p['id'
           +] == bard.combat_id }                                        
      1295 +  halt 400, 'Participant row missing' unless participant     
      1296 +  participant['luck_ledger'] = bard.luck_ledger + delta      
      1297 +  Tools.save_json('combat.json', combat_data)                
      1298 +                                                             
      1299 +  bard_name = combat.display_name(bard)                      
      1300 +  target_name = params[:target_name].to_s.strip              
      1301 +  target_clause = target_name.empty? ? '' : " for #{target_na
           +me}"                                                         
      1302 +  action_label = kind == 'ally' ? 'ally reroll' : 'enemy rero
           +ll'                                                          
      1303 +  Combat.add_log("#{bard_name} spends 1 luck (#{action_label}
           +#{target_clause}).")                                         
      1304 +  redirect '/combat'                                         
      1305 +end                                                          
      1306 +                                                             
      1307  get '/' do
      1308    redirect '/character/0'
      1309  end

● Now the UI. Three pieces: luck badge on bard's row, Perform button in the
  turn-panel, and a spend-luck panel.

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 5 lines
      58            <td><input type="number" name="saturation" value="<%=
           combat_turn.saturation %>" style="width: 45px;">/<%= combat_tu
          rn.character.cha %></td>
      59            <td class="conditions-cell">
      60              <div class="conditions-list">
      61 +              <% if combat_turn.luck_points > 0 %>             
      62 +                <span class="condition-badge condition-luck" ti
         +tle="Bardic luck pool (spendable on ally rerolls)">Luck: <%= co
         +mbat_turn.luck_points %></span>                                
      63 +              <% elsif combat_turn.dm_luck_points > 0 %>       
      64 +                <span class="condition-badge condition-dm-luck"
         + title="DM luck from fumbled performance (spendable against pla
         +yers)">DM Luck: <%= combat_turn.dm_luck_points %></span>       
      65 +              <% end %>                                        
      66                <% combat_turn.active_conditions.each do |cname, 
          cval| %>
      67                  <% short, full = condition_label(cname) %>
      68                  <span class="condition-badge condition-<%= cnam
          e %>" title="<%= full %>"><%= short %>: <%= cval %></span>

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 2 lines, removed 2 lines
      59            <td class="conditions-cell">
      60              <div class="conditions-list">
      61                <% if combat_turn.luck_points > 0 %>
      62 -                <span class="condition-badge condition-luck" ti
         -tle="Bardic luck pool (spendable on ally rerolls)">Luck: <%= co
         -mbat_turn.luck_points %></span>                                
      62 +                <span class="condition-badge" style="background
         +:#fff7c2;color:#6b5800;border:1px solid #d4b84a;" title="Bardic
         + luck pool (spendable on ally rerolls)">Luck: <%= combat_turn.l
         +uck_points %></span>                                           
      63                <% elsif combat_turn.dm_luck_points > 0 %>
      64 -                <span class="condition-badge condition-dm-luck"
         - title="DM luck from fumbled performance (spendable against pla
         -yers)">DM Luck: <%= combat_turn.dm_luck_points %></span>       
      64 +                <span class="condition-badge" style="background
         +:#3a1f1f;color:#f7c9c9;border:1px solid #8a3838;" title="DM luc
         +k from fumbled performance (spendable against players)">DM Luck
         +: <%= combat_turn.dm_luck_points %></span>                     
      65                <% end %>
      66                <% combat_turn.active_conditions.each do |cname, 
          cval| %>
      67                  <% short, full = condition_label(cname) %>

● Now add the Perform button into the turn-panel and the bardic-luck spend
  panel. First, gate the Perform button on abilities.

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 3 lines
      158            <button class="action-btn" onclick="selectAction('ca
           st')">Cast</button>
      159            <button class="action-btn" onclick="selectAction('it
           em')">Item</button>
      160            <button class="action-btn" onclick="selectAction('sp
           ecial')">Special</button>
      161 +          <% if current.has_ability?('bardic_inspiration') && 
          +!current.performed_this_turn && current.mana >= 1 %>          
      162 +            <button class="action-btn" onclick="selectAction('
          +perform')">Perform</button>                                   
      163 +          <% end %>                                           
      164          <% end %>
      165          <button class="action-btn" onclick="selectAction('end_
           turn')">End Turn</button>
      166        </div>

● Now wire the 'perform' action into the JS selectAction dispatcher, and add an
  inline prompt.

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 5 lines
      339          return;
      340        }
      341  
      342 +      if (action === 'perform') {                             
      343 +        showBardicInspiration();                              
      344 +        return;                                               
      345 +      }                                                       
      346 +                                                              
      347        if (action === 'start_of_turn') {
      348          showStartOfTurn();
      349          return;

● Now add the showBardicInspiration() function. Let me place it near the other
  step-building helpers.

  Read 1 file (ctrl+o to expand)

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 27 lines
      896            weaponOptions + shieldOptions + '</select></label>' 
           : ''));
      897      }
      898  
      899 +    // Bardic Inspiration: prompt DM for the performance roll'
          +s successes                                                   
      900 +    // and fumbles, POST to /combat/bardic_inspiration/:id. Th
          +e handler                                                     
      901 +    // deducts 1 mana and applies (successes - fumbles) to the
          + bard's                                                       
      902 +    // luck_ledger, with overflow to DM luck handled naturally
          + by sign.                                                     
      903 +    function showBardicInspiration() {                        
      904 +      addStep('<strong>Perform (Bardic Inspiration)</strong>: 
          +' + currentCharName + ' performs (1 mana).' +                 
      905 +        '<br><span class="math-detail">Enter the performance r
          +oll\'s successes and fumbles; the tool will update the luck le
          +dger. Successes build player luck; fumbles drain it (and becom
          +e DM luck on overflow).</span>' +                             
      906 +        '<br><label style="margin-top:6px;display:inline-block
          +;">Successes: <input type="number" id="bi-successes" min="0" v
          +alue="0" style="width:55px;"></label>' +                      
      907 +        ' <label style="display:inline-block;">Fumbles: <input
          + type="number" id="bi-fumbles" min="0" value="0" style="width:
          +55px;"></label>' +                                            
      908 +        '<br><button class="action-btn" onclick="submitBardicI
          +nspiration()" style="margin-top:8px;">Confirm Perform</button>
          +');                                                           
      909 +    }                                                         
      910 +                                                              
      911 +    function submitBardicInspiration() {                      
      912 +      var s = parseInt(document.getElementById('bi-successes')
          +.value, 10);                                                  
      913 +      var f = parseInt(document.getElementById('bi-fumbles').v
          +alue, 10);                                                    
      914 +      if (isNaN(s) || s < 0) { alert('Enter a non-negative num
          +ber of successes.'); return; }                                
      915 +      if (isNaN(f) || f < 0) { alert('Enter a non-negative num
          +ber of fumbles.'); return; }                                  
      916 +      var form = document.createElement('form');              
      917 +      form.method = 'POST';                                   
      918 +      form.action = '/combat/bardic_inspiration/' + currentCha
          +rId;                                                          
      919 +      form.innerHTML =                                        
      920 +        '<input type="hidden" name="successes" value="' + s + 
          +'">' +                                                        
      921 +        '<input type="hidden" name="fumbles" value="' + f + '"
          +>';                                                           
      922 +      document.body.appendChild(form);                        
      923 +      form.submit();                                          
      924 +    }                                                         
      925 +                                                              
      926      // --- Utility functions ---
      927      function addStep(html) {
      928        var context = document.getElementById('action-context');

● Now the spend-luck panel. Placing it right after the "Reset All Dice / Reroll
  Init / End Combat" block, visible only when a bard has an active ledger.

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 32 lines
      111      </form>
      112    </div>
      113  
      114 +  <% luck_bards = @combat.active_luck_bards %>                
      115 +  <% if luck_bards.any? %>                                    
      116 +    <% player_names = @combat.living_turn_list.select { |ct| c
          +t.character.group == 'PC' }.map { |ct| @combat.display_name(ct
          +) } %>                                                        
      117 +    <% enemy_names = @combat.living_turn_list.reject { |ct| ct
          +.character.group == 'PC' }.map { |ct| @combat.display_name(ct)
          + } %>                                                         
      118 +    <div class="bardic-luck" style="margin-top: 15px; padding:
          + 8px; background: #f7f3e8; border-left: 3px solid #b38a2f; bor
          +der-radius: 2px;">                                            
      119 +      <h3 style="margin: 0 0 6px 0; font-size: 14px;">Bardic L
          +uck</h3>                                                      
      120 +      <% luck_bards.each do |bard| %>                         
      121 +        <% ledger = bard.luck_ledger %>                       
      122 +        <% targets = ledger > 0 ? player_names : enemy_names %
          +>                                                             
      123 +        <% kind = ledger > 0 ? 'ally' : 'enemy' %>            
      124 +        <% label = ledger > 0 ? "Luck: #{bard.luck_points}" : 
          +"DM Luck: #{bard.dm_luck_points}" %>                          
      125 +        <% reroll_label = ledger > 0 ? 'ally reroll' : 'enemy 
          +reroll' %>                                                    
      126 +        <div style="display: flex; align-items: center; gap: 8
          +px; margin-bottom: 4px; font-size: 13px;">                    
      127 +          <strong><%= @combat.display_name(bard) %></strong>  
      128 +          <span><%= label %></span>                           
      129 +          <form method="post" action="/combat/spend_luck/<%= b
          +ard.combat_id %>" style="margin:0;display:flex;gap:4px;align-i
          +tems:center;">                                                
      130 +            <input type="hidden" name="kind" value="<%= kind %
          +>">                                                           
      131 +            <label style="font-size: 12px;">Spend on:         
      132 +              <select name="target_name" style="font-size: 12p
          +x;">                                                          
      133 +                <option value="">(unspecified)</option>       
      134 +                <% targets.each do |n| %>                     
      135 +                  <option value="<%= n %>"><%= n %></option>  
      136 +                <% end %>                                     
      137 +              </select>                                       
      138 +            </label>                                          
      139 +            <button type="submit" style="font-size: 12px;" tit
          +le="Spend 1 luck for a <%= reroll_label %>">Spend Luck</button
          +>                                                             
      140 +          </form>                                             
      141 +        </div>                                                
      142 +      <% end %>                                               
      143 +    </div>                                                    
      144 +  <% end %>                                                   
      145 +                                                              
      146    <% if @combat.active_effects.any? %>
      147      <div class="active-effects" style="margin-top: 15px;">
      148        <h3 style="margin-bottom: 8px;">Active Effects</h3>

  Searched for 3 patterns, read 1 file (ctrl+o to expand)

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 2 lines, removed 2 lines
      113  
      114    <% luck_bards = @combat.active_luck_bards %>
      115    <% if luck_bards.any? %>
      116 -    <% player_names = @combat.living_turn_list.select { |ct| c
          -t.character.group == 'PC' }.map { |ct| @combat.display_name(ct
          -) } %>                                                        
      117 -    <% enemy_names = @combat.living_turn_list.reject { |ct| ct
          -.character.group == 'PC' }.map { |ct| @combat.display_name(ct)
          - } %>                                                         
      116 +    <% player_names = @combat.living_turn_list.select { |ct| c
          +t.character.data['group'] == 'PC' }.map { |ct| @combat.display
          +_name(ct) } %>                                                
      117 +    <% enemy_names = @combat.living_turn_list.reject { |ct| ct
          +.character.data['group'] == 'PC' }.map { |ct| @combat.display_
          +name(ct) } %>                                                 
      118      <div class="bardic-luck" style="margin-top: 15px; padding:
            8px; background: #f7f3e8; border-left: 3px solid #b38a2f; bor
           der-radius: 2px;">
      119        <h3 style="margin: 0 0 6px 0; font-size: 14px;">Bardic L
           uck</h3>
      120        <% luck_bards.each do |bard| %>

● Update(/home/user/crimson-steel/data/compendium.json)
  ⎿  File must be read first

  Read 1 file (ctrl+o to expand)

● Update(/home/user/crimson-steel/data/compendium.json)
  ⎿  Added 1 line, removed 1 line
      1906      "turn_undead": "All undead within 30 feet must make a wis
            dom saving throw or become panicked.",
      1907      "uncanny_dodge": "You are always considered to be dodging
             an attack even if you are unaware of it or do not have any d
            ice to spend. You must be capable of moving and some abilitie
            s negate this ability. If you gain the rage ability then you 
            can enter a rage even if surprised.",
      1908      "unsettling_words": "You can use points of luck from your
             performance to affect the checks of your enemies. You must d
            ecide to use your luck point before they roll and afterwards 
            you can choose one of their dice to reroll.",
      1909 -    "versatile_performance": "You can use points of luck from
           - your performance to affect the checks of your enemies. You m
           -ust decide to use your luck point before they roll and afterw
           -ards you can choose one of their dice to reroll.",           
      1909 +    "versatile_performance": "You can use points of luck from
           + your performance to aid your allies. You must decide to use 
           +your luck point before they roll and afterwards you can choos
           +e one of their dice to reroll.",                             
      1910      "weapon_training": "Increases attack bonus for weapons in
             chosen weapon group by 1 plus an additional point for every 
            4 levels.",
      1911      "armor_training": "Increases damage reduction and damage 
            resilience by 1 while wearing armor. This increases by an add
            itional point every 4 levels.",
      1912      "bite": "Natural bite attack. Deals str/4 damage.",
● Now run rspec and do a syntax sanity check on the Ruby files.

● Bash(ruby -c character.rb && ruby -c app.rb)
  ⎿  Syntax OK
     Syntax OK

● Bash(ruby -e 'require "json"; JSON.parse(File.read("data/compendium.json"));
      puts "OK"')
  ⎿  OK

● Bash(ls spec/ && bundle exec rspec spec/ 2>&1 | tail -50)
  ⎿  character_spec.rb
     character_spec.rb.bak
     character_view_spec.rb
     … +6 lines (ctrl+o to expand)

  Read 1 file, listed 1 directory (ctrl+o to expand)

● Bash(rspec spec/ 2>&1 | tail -60)
  ⎿  /bin/bash: line 1: rspec: command not found

● Bash(which ruby && ruby -v && gem list --local 2>/dev/null | grep -i rspec)
  ⎿  /usr/local/bin/ruby
     ruby 3.3.6 (2024-11-05 revision 75015d4c1f) [x86_64-linux]

● No rspec/Gemfile available. Let me verify by booting the server and loading
  the combat tracker page.

● Bash(gem list --local 2>/dev/null | grep -iE "sinatra|rackup" | head)
  ⎿  (No output)

  Listed 1 directory (ctrl+o to expand)

● Bash(ruby -e '
      require "json"…)
  ⎿  -e:31: syntax error, unexpected backslash, expecting ')'
     ...ty?(bogus): #{ct.has_ability?(\"bogus_ability_xyz\")}"
     ...                              ^
     … +2 lines (ctrl+o to expand)

● Write(/tmp/luck_smoke.rb)
  ⎿  Wrote 36 lines to ../../../../tmp/luck_smoke.rb
       2 $LOAD_PATH.unshift(".")
       3 load "tools.rb"
       4 load "character.rb"
       5 
       6 char = JSON.parse(File.read("data/characters.json")).first
       7 participant = {
       8   "id" => char["id"], "char_id" => char["id"],
       9   "initiative" => "X", "mana" => 10, "combat_pool" => 10,
      10   "minor_damage" => 0, "moderate_damage" => 0, "major_damage" =>
          0,
     … +34 lines (ctrl+o to expand)

● Bash(ruby /tmp/luck_smoke.rb 2>&1 | tail -40)
  ⎿  luck_ledger=3 luck_points=3 dm_luck_points=0 performed=true
     has_ability?(bogus_xyz)=false
     to_json round-trip OK
     … +3 lines (ctrl+o to expand)

● All smoke tests pass. Let me also validate the ERB template parses without
  raising.

● Bash(ruby -r erb -e 'ERB.new(File.read("views/combat_tracker.erb"), trim_mode:
       "-").src; puts "ERB parses OK"')
  ⎿  ERB parses OK

❯ Continue from where you left off.                                             

● Let me do a final review of the changes before committing.

● Bash(git diff --stat)
  ⎿   app.rb                   | 74 +++++++++++++++++++++++++++++++++++++++
     +++++++++
      character.rb             | 28 ++++++++++++++++--
     … +4 lines (ctrl+o to expand)

● Bash(git diff character.rb)
  ⎿  diff --git a/character.rb b/character.rb
     index 3aa4f7c..0215858 100644
     --- a/character.rb
     … +47 lines (ctrl+o to expand)

● Bash(git diff app.rb data/compendium.json)
  ⎿  diff --git a/app.rb b/app.rb
     index 0e4c185..a4ce23d 100644
     --- a/app.rb
     … +70 lines (ctrl+o to expand)

● Bash(git diff views/combat_tracker.erb)
  ⎿  diff --git a/views/combat_tracker.erb b/views/combat_tracker.erb
     index fbb22ae..8b0019a 100644
     --- a/views/combat_tracker.erb
     … +88 lines (ctrl+o to expand)
● All changes look coherent. Committing.

● Bash(git log --oneline -5)
  ⎿  5e81970 Refactor enemies into templates with variants, loot, and potio
     ns (#1)
     98a7227 Merge branch 'claude/dm-scene-management-smfJ7'
     … +3 lines (ctrl+o to expand)

● Bash(git add character.rb app.rb views/combat_tracker.erb data/compendium.json
       && git commit -m "$(cat <<'EOF'
      Bardic inspiration: luck ledger tracked in combat…)
  ⎿  [claude/bard-luck-reroll-mechanic-3DFmV 483ebf2] Bardic inspiration: l
     uck ledger tracked in combat
      4 files changed, 172 insertions(+), 4 deletions(-)

● Bash(git push -u origin claude/bard-luck-reroll-mechanic-3DFmV 2>&1)
  ⎿  remote:
     remote: Create a pull request for 'claude/bard-luck-reroll-mechanic-3D
     FmV' on GitHub by visiting:
     … +8 lines (ctrl+o to expand)

● Pushed to claude/bard-luck-reroll-mechanic-3DFmV.

  Summary

  - character.rb: CombatTurn gains luck_ledger (single signed int; + = player
  luck, − = DM luck) and performed_this_turn; both clear in new_turn. Added
  luck_points, dm_luck_points, has_ability?, and Combat#active_luck_bards
  helpers.
  - app.rb: Two POST routes — /combat/bardic_inspiration/:id (1 mana, applies
  successes − fumbles to the ledger, once per turn) and
  /combat/spend_luck/:bard_id (decrements toward zero; logs target).
  - views/combat_tracker.erb: Luck/DM Luck badge in the bard's row, conditional
  "Perform" action button, and a Bardic Luck spend panel that shows whenever any
   bard has a non-zero ledger.
  - data/compendium.json: versatile_performance text rewritten to describe ally
  rerolls (it was a verbatim copy of unsettling_words).

  Caveats to flag
  - rspec isn't installed in this sandbox and there's no Gemfile, so the full
  test suite didn't run. I did ruby/erb syntax checks and a standalone smoke
  test of CombatTurn covering construction, to_json round-trip, new_turn
  clearing, negative-ledger → dm_luck_points, and missing-field defaults — all
  passed. Browser-level verification still needs to happen against a real
  running server.
  - Luck expiration hooks CombatTurn#new_turn, which fires from the "Reset All
  Dice" button (per-round), not truly per-combatant turn start. That's the
  closest existing hook; calling it out so you can decide if a tighter hook is
  warranted.

❯ Always add the roll option whenever asking for successes. I want to clarify   
  something. Fumbles and failures are different. A fumble is when there is two  
  or more failures, so when you asked for the number of fumbles you meant to    
  ask for the number of failures. Also there is no reason to ask for both the   
  number of successes and the number of failures. We need to know the           
  difference of successes and failures. If there are more successes then        
  Cottonballs gets that many luck points, if there are more failures then the   
  enemies gets that many luck points. It isn't possible for both to gain this   
  from the same check. So instead of asking for successes and failures, you     
  should just ask for successes and accept a negative value to indicate the DM  
  gets them rather then cottonballs.                                            
                                                                                
  Each perform skill can be used which might result in a different TN. The TN   
  is of course affected by the perform's proficiency bonus. So you should ask   
  for each skill that the character can perform                                 
  The TN also suffers a penalty equal to the tier of  the highest tier enemy.   
                                                                                
  Cottonballs has a magical drum with a +1 enhancement bonus to it. All         
  perform_percussion checks have a +1 on their checks. Please add that item and 
   adjust accordingly                                                           
                                                                                
  Also we don't want to clutter the interface. There is no need for a Perform   
  button when we already have Special. Special is where they should  go for     
  these types of abilities                                                      

● Let me explore the codebase to understand the TN/skill/item pieces I need to
  wire up.

● Explore(Understand skills, TN, items, Cottonballs)
  ⎿  Done (38 tool uses · 73.6k tokens · 1m 35s)
  (ctrl+o to expand)

● Let me look at existing TN calculation patterns and the current state of the
  Special action dispatch.

  Searched for 3 patterns, read 5 files (ctrl+o to expand)

● Now making the changes. Starting with the data, then character.rb, then the
  UI.

● Update(/home/user/crimson-steel/data/equipment.json)
  ⎿  Added 1 line
      612      "subtype": "instrument",
      613      "bonus": 1,
      614      "properties": {
      615 +      "enhancement": {"type": "skill", "skill": "perform_percu
          +ssion", "amount": 1}                                          
      616      },
      617      "equipped": true
      618    },

● Update(/home/user/crimson-steel/character.rb)
  ⎿  Added 7 lines
       999      collect_enhancement_amounts { |e| e["type"] == "save" }.m
            ax || 0
      1000    end
      1001  
      1002 +  # Enhancement bonuses that apply to a specific skill (e.g. 
           ++1 Drums for                                                 
      1003 +  # perform_percussion). Highest matching item wins; bonuses 
           +never stack.                                                 
      1004 +  def skill_enhancement(skill)                               
      1005 +    key = skill.to_s                                         
      1006 +    collect_enhancement_amounts { |e| e["type"] == "skill" &&
           + e["skill"].to_s == key }.max || 0                           
      1007 +  end                                                        
      1008 +                                                             
      1009    def collect_enhancement_amounts
      1010      amounts = []
      1011      (@item_list || []).each do |item|

● Now fold the skill enhancement into skill_bonus. The CharacterSheet
  skill_bonus is in a different module from CharacterEquipment, so I'll call the
   enhancement helper from there.

● Update(/home/user/crimson-steel/character.rb)
  ⎿  Added 2 lines, removed 1 line
      855    def skill_bonus(skill)
      856      base = compute_bonus(skill_ranks(skill), half_mod(get_skil
           l_attr(skill)))
      857      class_bonus = @klass_list.sum { |progress| progress.skill_
           bonus(skill, @rules) }
      858 -    return base + class_bonus                                 
      858 +    item_bonus = respond_to?(:skill_enhancement) ? skill_enhan
          +cement(skill) : 0                                             
      859 +    return base + class_bonus + item_bonus                    
      860    end
      861  
      862    def bab; return @klass_list.sum { |progress| progress.bab(@r
           ules) }; end

● Now add a helper on Combat for highest enemy tier.

● Update(/home/user/crimson-steel/character.rb)
  ⎿  Added 9 lines
      126    # Bards whose luck ledger is non-zero; drives the Spend-Luck
            UI.
      127    def active_luck_bards; @combat_turn_list.select { |ct| ct.lu
           ck_ledger != 0 }; end
      128  
      129 +  # Highest tier among living non-PC participants; 0 if no ene
          +mies are                                                      
      130 +  # present. Used as a TN penalty on bardic performance checks
          +.                                                             
      131 +  def max_enemy_tier                                          
      132 +    living_turn_list                                          
      133 +      .reject { |ct| ct.character.data['group'] == 'PC' }     
      134 +      .map { |ct| ct.character.tier.to_i }                    
      135 +      .max || 0                                               
      136 +  end                                                         
      137 +                                                              
      138    def display_name(combat_turn)
      139      return "Unknown" unless combat_turn&.character
      140      char_id = combat_turn.character.id

● Now rewrite the POST route to accept a signed net param.

● Update(/home/user/crimson-steel/app.rb)
  ⎿  Added 11 lines, removed 12 lines
      1230    redirect '/combat'
      1231  end
      1232  
      1233 -# Bardic inspiration. Bard's Perform action: deduct 1 mana, a
           -pply                                                         
      1234 -# (successes - fumbles) to the bard's luck_ledger. A positive
           - ledger is                                                   
      1235 -# player luck (spend on allies); negative is DM luck (spend a
           -gainst                                                       
      1236 -# players). Gated to once per turn via performed_this_turn, w
           -hich clears                                                  
      1237 -# on new_turn.                                               
      1233 +# Bardic inspiration. Bard's Perform action: deduct 1 mana, a
           +pply a                                                       
      1234 +# signed net (successes - failures) to the bard's luck_ledger
           +. Positive                                                   
      1235 +# net feeds the player luck pool; negative net feeds DM luck 
           +(spendable                                                   
      1236 +# against players). Only one side can ever be non-zero at a t
           +ime, so the                                                  
      1237 +# DM just enters the net. Gated to once per turn via performe
           +d_this_turn.                                                 
      1238  post '/combat/bardic_inspiration/:id' do
      1239    redirect '/character/0' unless local_request?
      1240    combat = Combat.new
     ...
      1244    halt 400, 'Already performed this turn' if bard.performed_t
            his_turn
      1245    halt 400, 'Not enough mana' if bard.mana < 1
      1246  
      1247 -  successes = params[:successes].to_i                        
      1248 -  fumbles = params[:fumbles].to_i                            
      1249 -  halt 400, 'Successes and fumbles must be non-negative' if s
           -uccesses < 0 || fumbles < 0                                  
      1247 +  net = params[:net].to_i                                    
      1248 +  skill = params[:skill].to_s                                
      1249  
      1250    combat_data = Tools.load_json('combat.json')
      1251    participant = combat_data['participants'].find { |p| p['id'
            ] == bard.combat_id }
      1252    halt 400, 'Participant row missing' unless participant
      1253  
      1254    participant['mana'] = bard.mana - 1
      1256 -  new_ledger = bard.luck_ledger + successes - fumbles        
      1255 +  new_ledger = bard.luck_ledger + net                        
      1256    participant['luck_ledger'] = new_ledger
      1257    participant['performed_this_turn'] = true
      1258    Tools.save_json('combat.json', combat_data)
      1259  
      1260    name = combat.display_name(bard)
      1262 -  delta = successes - fumbles                                
      1263 -  sign = delta >= 0 ? '+' : ''                               
      1261 +  sign = net >= 0 ? '+' : ''                                 
      1262    ledger_label = if new_ledger > 0 then "Luck #{new_ledger}"
      1263                   elsif new_ledger < 0 then "DM Luck #{-new_le
            dger}"
      1264                   else 'ledger 0'
      1265                   end
      1268 -  Combat.add_log("#{name} performs (#{successes} successes, #
           -{fumbles} fumbles, #{sign}#{delta}; #{ledger_label}).")      
      1266 +  skill_label = skill.empty? ? 'performance' : skill.tr('_', 
           +' ')                                                         
      1267 +  Combat.add_log("#{name} performs #{skill_label} (#{sign}#{n
           +et}; #{ledger_label}).")                                     
      1268    redirect '/combat'
      1269  end
      1270  
● Now the UI. Remove the Perform button, route Special → Perform, enumerate
  perform skills + TN/dice, add Roll option and signed net input.

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Removed 3 lines
      190            <button class="action-btn" onclick="selectAction('ca
           st')">Cast</button>
      191            <button class="action-btn" onclick="selectAction('it
           em')">Item</button>
      192            <button class="action-btn" onclick="selectAction('sp
           ecial')">Special</button>
      193 -          <% if current.has_ability?('bardic_inspiration') && 
          -!current.performed_this_turn && current.mana >= 1 %>          
      194 -            <button class="action-btn" onclick="selectAction('
          -perform')">Perform</button>                                   
      195 -          <% end %>                                           
      193          <% end %>
      194          <button class="action-btn" onclick="selectAction('end_
           turn')">End Turn</button>
      195        </div>

● Now wire Special → showSpecialMenu and reroute the existing action === 
  'perform' handler to fit:

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 2 lines, removed 2 lines
      368          return;
      369        }
      370  
      371 -      if (action === 'perform') {                             
      372 -        showBardicInspiration();                              
      371 +      if (action === 'special') {                             
      372 +        showSpecialMenu();                                    
      373          return;
      374        }
      375  

● Now I need to expose per-skill dice/TN data to JS and rewrite
  showBardicInspiration. Let me find a good spot near the other ERB-generated JS
   data and add a performSkills payload.

  Read 1 file (ctrl+o to expand)

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 34 lines
      341        '[]'
      342      end %>;
      343  
      344 +    // Per-character perform skills for Bardic Inspiration. Ea
          +ch entry is                                                   
      345 +    // { skill, label, dice, tn }. TN applies the bard's skill
          + bonus                                                        
      346 +    // (which already folds in item enhancements like the +1 D
          +rums) and a                                                   
      347 +    // penalty equal to the highest-tier enemy in combat, clam
          +ped to the                                                    
      348 +    // rules' [tn_minimum, tn_maximum]. Empty when current cha
          +racter                                                        
      349 +    // can't perform or isn't a bard.                         
      350 +    var performSkills = <%=                                   
      351 +      if current && current.has_ability?('bardic_inspiration')
      352 +        dice_rules = Tools.load_json('rules.json')['dice']    
      353 +        base_tn = dice_rules['base_target_number'].to_i       
      354 +        tn_min = dice_rules['tn_minimum'].to_i                
      355 +        tn_max = dice_rules['tn_maximum'].to_i                
      356 +        enemy_tier = @combat.max_enemy_tier                   
      357 +        perform_skills = (current.character.skill_list || []).
          +select { |s| s.to_s.start_with?('perform_') }                 
      358 +        JSON.generate(                                        
      359 +          perform_skills.map do |s|                           
      360 +            bonus = current.character.skill_bonus(s).to_i     
      361 +            raw_tn = base_tn - bonus + enemy_tier             
      362 +            clamped = [[raw_tn, tn_min].max, tn_max].min      
      363 +            {                                                 
      364 +              skill: s.to_s,                                  
      365 +              label: s.to_s.tr('_', ' ').split.map(&:capitaliz
          +e).join(' '),                                                 
      366 +              dice: current.character.skill_dice(s).to_i,     
      367 +              bonus: bonus,                                   
      368 +              raw_tn: raw_tn,                                 
      369 +              tn: clamped,                                    
      370 +              enemy_tier_penalty: enemy_tier                  
      371 +            }                                                 
      372 +          end                                                 
      373 +        )                                                     
      374 +      else                                                    
      375 +        '[]'                                                  
      376 +      end %>;                                                 
      377 +                                                              
      378      // --- Client-side attack state ---
      379      var attackState = null;
      380      // --- Client-side start-of-turn state ---

● Now rewrite showBardicInspiration + add showSpecialMenu and a signed dice
  roller.

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 84 lines, removed 14 lines
       959            weaponOptions + shieldOptions + '</select></label>'
             : ''));
       960      }
       961  
       962 -    // Bardic Inspiration: prompt DM for the performance roll
           -'s successes                                                 
       963 -    // and fumbles, POST to /combat/bardic_inspiration/:id. T
           -he handler                                                   
       964 -    // deducts 1 mana and applies (successes - fumbles) to th
           -e bard's                                                     
       965 -    // luck_ledger, with overflow to DM luck handled naturall
           -y by sign.                                                   
       962 +    // Special actions menu. Currently only surfaces Bardic I
           +nspiration;                                                  
       963 +    // other class specials can be added here later.         
       964 +    function showSpecialMenu() {                             
       965 +      var btns = '';                                         
       966 +      var canPerform = performSkills.length > 0 && currentMan
           +a >= 1 && !currentPerformedThisTurn;                         
       967 +      if (performSkills.length > 0) {                        
       968 +        btns += '<button class="action-btn" onclick="showBard
           +icInspiration()"' +                                          
       969 +          (canPerform ? '' : ' disabled title="Need 1 mana an
           +d unused per-turn Perform"') +                               
       970 +          '>Perform (Bardic Inspiration)</button>';          
       971 +      }                                                      
       972 +      if (!btns) {                                           
       973 +        addStep('<strong>Special</strong>: no special actions
           + available for ' + currentCharName + '.');                   
       974 +        return;                                              
       975 +      }                                                      
       976 +      addStep('<strong>Special</strong>: ' + btns);          
       977 +    }                                                        
       978 +                                                             
       979 +    // Bardic Inspiration: pick a perform skill, see its dice
           +/TN, roll or                                                 
       980 +    // enter the net (successes − failures), then confirm. Po
           +sitive net                                                   
       981 +    // goes to the bard's luck pool; negative goes to DM luck
           +.                                                            
       982      function showBardicInspiration() {
       983 +      if (performSkills.length === 0) {                      
       984 +        addStep('<strong>Perform</strong>: this character has
           + no perform skills.');                                       
       985 +        return;                                              
       986 +      }                                                      
       987 +      var options = performSkills.map(function(p, i) {       
       988 +        return '<option value="' + i + '">' + p.label + ' &md
           +ash; ' + p.dice + 'd @ TN ' + p.tn +                         
       989 +          (p.enemy_tier_penalty > 0 ? ' (incl. +' + p.enemy_t
           +ier_penalty + ' enemy tier penalty)' : '') +                 
       990 +          '</option>';                                       
       991 +      }).join('');                                           
       992        addStep('<strong>Perform (Bardic Inspiration)</strong>:
             ' + currentCharName + ' performs (1 mana).' +
       968 -        '<br><span class="math-detail">Enter the performance 
           -roll\'s successes and fumbles; the tool will update the luck 
           -ledger. Successes build player luck; fumbles drain it (and be
           -come DM luck on overflow).</span>' +                         
       969 -        '<br><label style="margin-top:6px;display:inline-bloc
           -k;">Successes: <input type="number" id="bi-successes" min="0"
           - value="0" style="width:55px;"></label>' +                   
       970 -        ' <label style="display:inline-block;">Fumbles: <inpu
           -t type="number" id="bi-fumbles" min="0" value="0" style="widt
           -h:55px;"></label>' +                                         
       971 -        '<br><button class="action-btn" onclick="submitBardic
           -Inspiration()" style="margin-top:8px;">Confirm Perform</butto
           -n>');                                                        
       993 +        '<br><label>Skill: <select id="bi-skill" onchange="re
           +nderPerformRoll()">' + options + '</select></label>' +       
       994 +        '<div id="bi-roll-area" style="margin-top:6px;"></div
           +>');                                                         
       995 +      renderPerformRoll();                                   
       996      }
       997  
       998 +    function renderPerformRoll() {                           
       999 +      var sel = document.getElementById('bi-skill');         
      1000 +      if (!sel) return;                                      
      1001 +      var p = performSkills[parseInt(sel.value, 10)];        
      1002 +      var tnDetail = 'base ' + <%= Tools.load_json('rules.jso
           +n')['dice']['base_target_number'].to_i %> +                  
      1003 +        ' − bonus ' + p.bonus +                              
      1004 +        (p.enemy_tier_penalty > 0 ? ' + enemy tier ' + p.enem
           +y_tier_penalty : '') +                                       
      1005 +        ' = ' + p.raw_tn + (p.raw_tn !== p.tn ? ' (clamped to
           + ' + p.tn + ')' : '');                                       
      1006 +      var html =                                             
      1007 +        '<div class="math-detail">Roll ' + p.dice + 'd at TN 
           +' + p.tn + ' <em>(' + tnDetail + ')</em></div>' +            
      1008 +        '<label style="margin-top:4px;display:inline-block;">
           +Net (successes − failures): ' +                              
      1009 +          '<input type="number" id="bi-net" value="0" style="
           +width:60px;">' +                                             
      1010 +        '</label>' +                                         
      1011 +        ' <button class="action-btn" onclick="rollPerformDice
           +()">Roll</button>' +                                         
      1012 +        '<div id="bi-rolls" class="math-detail" style="margin
           +-top:4px;"></div>' +                                         
      1013 +        '<br><button class="action-btn" onclick="submitBardic
           +Inspiration()" style="margin-top:8px;">Confirm Perform</butto
           +n>';                                                         
      1014 +      document.getElementById('bi-roll-area').innerHTML = htm
           +l;                                                           
      1015 +    }                                                        
      1016 +                                                             
      1017 +    // Roll the perform pool and write the SIGNED net into bi
           +-net so the                                                  
      1018 +    // sign-based routing to player/DM luck is preserved. Mir
           +rors the                                                     
      1019 +    // coloring scheme of rollDicePool but keeps negative tot
           +als.                                                         
      1020 +    function rollPerformDice() {                             
      1021 +      var sel = document.getElementById('bi-skill');         
      1022 +      var p = performSkills[parseInt(sel.value, 10)];        
      1023 +      var rolls = [];                                        
      1024 +      var net = 0;                                           
      1025 +      for (var r = 0; r < p.dice; r++) {                     
      1026 +        var d = Math.floor(Math.random() * 10) + 1;          
      1027 +        rolls.push(d);                                       
      1028 +        if (d === 10) net += 2;                              
      1029 +        else if (d >= p.tn) net += 1;                        
      1030 +        else if (d === 1) net -= 1;                          
      1031 +      }                                                      
      1032 +      document.getElementById('bi-net').value = net;         
      1033 +      var colored = rolls.map(function(d) {                  
      1034 +        var bg = null;                                       
      1035 +        if (d === 1) bg = '#e57373';                         
      1036 +        else if (d === 10) bg = '#64b5f6';                   
      1037 +        else if (d >= p.tn) bg = '#81c784';                  
      1038 +        if (bg) return '<span style="background:' + bg + ';co
           +lor:#000;padding:1px 6px;border-radius:3px;font-weight:bold;"
           +>' + d + '</span>';                                          
      1039 +        return '<span style="color:#777;">' + d + '</span>'; 
      1040 +      }).join(', ');                                         
      1041 +      document.getElementById('bi-rolls').innerHTML = 'Rolled
           +: [' + colored + '] &rarr; net ' + (net >= 0 ? '+' : '') + ne
           +t;                                                           
      1042 +    }                                                        
      1043 +                                                             
      1044      function submitBardicInspiration() {
       975 -      var s = parseInt(document.getElementById('bi-successes'
           -).value, 10);                                                
       976 -      var f = parseInt(document.getElementById('bi-fumbles').
           -value, 10);                                                  
       977 -      if (isNaN(s) || s < 0) { alert('Enter a non-negative nu
           -mber of successes.'); return; }                              
       978 -      if (isNaN(f) || f < 0) { alert('Enter a non-negative nu
           -mber of fumbles.'); return; }                                
      1045 +      var sel = document.getElementById('bi-skill');         
      1046 +      var p = performSkills[parseInt(sel.value, 10)];        
      1047 +      var net = parseInt(document.getElementById('bi-net').va
           +lue, 10);                                                    
      1048 +      if (isNaN(net)) { alert('Enter a net value (negative me
           +ans the DM gets the luck).'); return; }                      
      1049        var form = document.createElement('form');
      1050        form.method = 'POST';
      1051        form.action = '/combat/bardic_inspiration/' + currentCh
            arId;
      1052        form.innerHTML =
       983 -        '<input type="hidden" name="successes" value="' + s +
           - '">' +                                                      
       984 -        '<input type="hidden" name="fumbles" value="' + f + '
           -">';                                                         
      1053 +        '<input type="hidden" name="net" value="' + net + '">
           +' +                                                          
      1054 +        '<input type="hidden" name="skill" value="' + p.skill
           + + '">';                                                     
      1055        document.body.appendChild(form);
      1056        form.submit();
      1057      }

  Searched for 1 pattern (ctrl+o to expand)

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 1 line
      228      var currentAttackerAbilities = <%= current ? JSON.generate
           (current.character.ability_list) : '[]' %>;
      229      var diceRemaining = <%= current ? current.combat_pool : 0 
           %>;
      230      var currentMana = <%= current ? current.mana : 0 %>;
      231 +    var currentPerformedThisTurn = <%= current && current.perf
          +ormed_this_turn ? 'true' : 'false' %>;                        
      232      var moveSpeed = <%= current ? current.character.speed : 0 
           %>;
      233      var spellList = <%= if current && current.character.spell_
           list
      234        compendium = Compendium.new

● Now let me verify the Ruby and ERB syntax.

● Bash(ruby -c character.rb && ruby -c app.rb && ruby -r erb -e
      'ERB.new(File.read("views/combat_tracker.erb"), trim_mode: "-").src; puts
      "ERB OK"' && ruby -e 'require…)
  ⎿  Syntax OK
     Syntax OK
     ERB OK
     JSON OK

● Now a smoke test: ensure Cottonballs's drum bonus actually propagates through
  skill_bonus('perform_percussion') and doesn't affect perform_sing.

● Write(/tmp/drum_smoke.rb)
  ⎿  Wrote 35 lines to ../../../../tmp/drum_smoke.rb
      1 require "json"
      2 $LOAD_PATH.unshift(".")
      3 load "tools.rb"
      4 load "character.rb"
      5 
      6 chars = JSON.parse(File.read("data/characters.json"))
      7 cotton = chars.find { |c| c["name"] == "Cottonballs" }
      8 raise "Cottonballs missing" unless cotton
      9 sheet = CharacterSheet.new(cotton)
     … +29 lines (ctrl+o to expand)

● Bash(ruby /tmp/drum_smoke.rb 2>&1 | tail -30)
  ⎿  perform_percussion bonus: 3
     perform_sing bonus: 2
     diff (should be >= 1): 1
     … +7 lines (ctrl+o to expand)

● Drum enhancement applies only to perform_percussion (+1 diff). Let me verify
  the combat_tracker ERB evaluates the new data block with fixture data.

● Write(/tmp/erb_smoke.rb)
  ⎿  Wrote 38 lines to ../../../../tmp/erb_smoke.rb
       2 require "erb""
       3 $LOAD_PATH.unshift(".")
       4 load "tools.rb"
       5 load "character.rb"
       6 
         llsimulate @combat and @combat.current_turn_character = Cottonba
       8 combat = Combat.new
       9 cotton_ct = combat.combat_turn_list.find { |ct| ct.character.nam
         e == 'Cottonballs' }
      10 raise 'Cottonballs not in combat' unless cotton_ct
     … +33 lines (ctrl+o to expand)

● Bash(ruby /tmp/erb_smoke.rb 2>&1 | tail -40)
  ⎿  [
       {
         "skill": "perform_sing",
     … +19 lines (ctrl+o to expand)

● Bash(rm /tmp/drum_smoke.rb /tmp/erb_smoke.rb /tmp/luck_smoke.rb)
  ⎿  Error: Exit code 1
     rm: cannot remove '/tmp/luck_smoke.rb': No such file or directory

● Bash(git diff --stat)
  ⎿   app.rb                   |  23 ++++----
      character.rb             |  19 ++++++-
      data/equipment.json      |   1 +
     … +3 lines (ctrl+o to expand)

● Bash(git add app.rb character.rb data/equipment.json views/combat_tracker.erb
      && git commit -m "$(cat <<'EOF'
      Bardic perform: skill picker, signed net, drum enhancem…)  ⎿  [claude/bard-luck-reroll-mechanic-3DFmV 17daebf] Bardic perform: skill
      picker, signed net, drum enhancement
      4 files changed, 151 insertions(+), 32 deletions(-)

● Bash(git push origin claude/bard-luck-reroll-mechanic-3DFmV 2>&1)
  ⎿  To http://127.0.0.1:63769/git/dividetask/crimson-steel
        483ebf2..17daebf  claude/bard-luck-reroll-mechanic-3DFmV -> claude/
     bard-luck-reroll-mechanic-3DFmV

● Pushed.

  What changed

  - Special menu: Perform now lives under the existing "Special" action; the
  standalone Perform button is gone.
  - Skill picker: When the DM opens Perform, every perform_* skill the bard has
  trained is listed with its dice count and computed TN. TN formula is
  base_target_number − skill_bonus + max_enemy_tier, clamped to [tn_minimum, 
  tn_maximum].
  - Roll button: Mirrors rollDicePool's coloring; writes the signed net into the
   input so negative results still route to DM luck.
  - Single signed input: "Net (successes − failures)". Negative = DM luck,
  positive = player luck. Route handler takes net (and skill for the log).
  - Drum: +1 Drums now carries enhancement: {type: "skill", skill: 
  "perform_percussion", amount: 1} in data/equipment.json.
  CharacterSheet.skill_bonus picks up the new type: "skill" enhancement the same
   way it already handles attribute and save enhancements (non-stacking, highest
   wins).

  Smoke-test results (Cottonballs, no enemies in combat): perform_sing → 6d @ TN
   5 (bonus +2), perform_percussion → 6d @ TN 4 (bonus +3, confirming the drum's
   +1 applied).

  Caveat: I'm still only syntax-/unit-checking; I didn't exercise this through a
   live Sinatra server. The currentPerformedThisTurn guard on the Special
  submenu uses a JS global I set from the bard's participant row — worth
  clicking through once in the browser to confirm the gating feels right.

❯ When spending luck, they can choose to spend more then one point at a time.   
  Instead of putting bardic luck where you did, I want you to move it. Whenever 
   anyone is about to roll I want you to ask me if they want to use luck on     
  that check, specifically how much luck they want to spend with a default of   
  0. Then after that roll button (assuming I spent luck) add two additional     
  buttons next to roll that called Inspiration, and Unsettling Words.           
  Inspiration will reroll a number of dice equal to luck choosing the lowest    
  dice. Unsetting words will do the same except choosing the highest dice       
                                                                                
  Does this make sense?                                                         

● Makes sense. Let me restate to make sure I've got it right — and I need to
  peek at the roll sites so I can plan the injection properly.

  Searched for 1 pattern (ctrl+o to expand)

● Yes, this makes sense. Restating to verify and flag a few design points before
   I start patching:

  Flow (per roll site)
  1. Pre-roll prompt: a "Luck to spend" input, default 0.
  2. Roll button rolls dice as today.
  3. If luck > 0 was set, after the roll two buttons appear next to Roll:
    - Inspiration — rerolls the N lowest dice (helps the roller).
    - Unsettling Words — rerolls the N highest dice (hurts the roller).
  Clicking one re-runs those specific dice, updates the displayed pool +
  successes, and debits the relevant ledger.

  Scope — the roll button pattern appears in ~9 places in combat_tracker.erb
  (saves, stabilize, perform, attack, dodge, parry, block, ally-block, healing).
   I'll replace those inline Roll-button strings with a shared helper so all
  nine sites get the luck UI in one place. Also removing the top-of-tracker
  Bardic Luck panel.

  Open questions I want to settle first

  1. Multi-bard: If Cottonballs and another bard both have non-zero ledgers,
  should the luck input be paired with a bard-picker, or just pull from the
  first bard with enough points? (Real combats rarely have two bards; happy to
  go with first-available for simplicity unless you'd rather see a picker.)
  2. Button availability: Inspiration needs player luck (+ ledger); Unsettling
  Words needs DM luck (− ledger). Show both always and grey out the one without
  a source, or only render the viable one? I'd default to greying out so the
  flow is predictable.
  3. Commit timing: When the DM clicks Inspiration/Unsettling Words, should the
  ledger decrement fire immediately (atomic POST) or roll up into the parent
  action's submit? Immediate is simpler and survives page reloads; the downside
  is you can't "undo" the luck spend if you also cancel the parent action.
  4. Re-rerolling: After Inspiration rerolls the 3 lowest, can the DM click
  Unsettling Words on the new pool? I'd say no — one reroll per pre-declared
  spend. Make both buttons disappear after either is clicked.

  If those sound right I'll proceed; otherwise tell me which to change.

❯ 1. This is a good question. When luck is spent you will need to ask which     
  bard when there are multiple. I will not allow multiple bards to use luck on  
  the same roll                                                                 
  2. That is not correct. Unsettling words can be used by the player on         
  enemies. Inspiration would be used by the bard on allies. If there is DM luck 
   then the DM will use inspiration on monsters, and unsettling words on        
  players. The code should treat the DM as a different bard, and grant the luck 
   to the DM or the player.                                                     

● Got it. A couple of design decisions I need to confirm before rewriting — this
   refactor is nontrivial because my current model treats DM luck as the
  negative half of each bard's ledger, which doesn't match what you just
  described.

  My revised understanding

  - Each bard has their own non-negative luck_points.
  - The DM has a single separate dm_luck_points pool (treated as "another
  bard").
  - On a Perform net, successes add to that bard's pool; failures drain that
  bard's pool first and any overflow increments the DM pool.
  - On any roll: pick a source (a bard or the DM), declare an amount to spend,
  Roll, then Inspiration (reroll N lowest) or Unsettling Words (reroll N
  highest) — both buttons drain the same selected source. One source per roll.

● User answered Claude's questions:
  ⎿  · Confirm the data model refactor? → Separate pools (Recommended)
     · When should the DM choose which source (bard vs DM) the luck comes from? 
     → Pick source before Roll (Recommended)
     · When should the DM luck pool expire? → Expires each round

● Decisions locked in. Starting the refactor. First let me inventory everywhere
  luck_ledger is referenced so I can migrate cleanly.

  Searched for 1 pattern (ctrl+o to expand)

● Update(/home/user/crimson-steel/character.rb)
  ⎿  Added 1 line, removed 1 line
      1  require_relative 'tools'
      2  
      3  class CombatTurn
      4 -  attr_reader :rules, :character, :combat_id, :initiative, :mana
        -, :combat_pool, :minor_damage, :moderate_damage, :major_damage, 
        -:saturation, :temporary_hit_points, :conditions, :condition_meta
        -, :ability_damage, :luck_ledger, :performed_this_turn           
      4 +  attr_reader :rules, :character, :combat_id, :initiative, :mana
        +, :combat_pool, :minor_damage, :moderate_damage, :major_damage, 
        +:saturation, :temporary_hit_points, :conditions, :condition_meta
        +, :ability_damage, :luck_points, :performed_this_turn           
      5  
      6    def initialize(combat_turn, character)
      7      @rules = Tools.load_json('rules.json')

● Update(/home/user/crimson-steel/character.rb)
  ⎿  Added 4 lines, removed 5 lines
      21      # Ability damage: nested hash of ability (str/dex/...) -> s
          everity
      22      # (minor/moderate/major) -> amount. Persists until cured.
      23      @ability_damage = (combat_turn['ability_damage'] || {}).dup
      24 -    # Bardic inspiration ledger. Positive = player luck pool (s
         -pend on                                                        
      25 -    # allies). Negative = DM luck pool (spend against players).
         - Only one                                                      
      26 -    # side is ever non-zero; sign flips naturally as fumbles ex
         -ceed                                                           
      27 -    # successes during Perform. Cleared on the bard's new_turn.
      28 -    @luck_ledger = combat_turn['luck_ledger'].to_i             
      24 +    # Bardic luck pool. Non-negative; Perform adds net successe
         +s here,                                                        
      25 +    # and fumbles drain it (overflow goes to Combat#dm_luck_poi
         +nts).                                                          
      26 +    # Cleared on the bard's new_turn so each turn starts fresh.
      27 +    @luck_points = [combat_turn['luck_points'].to_i, 0].max    
      28      @performed_this_turn = combat_turn['performed_this_turn'] =
          = true
      29      @character = CharacterSheet.new(character)
      30      # Inject this participant's combat state into the Character
          Sheet so

● Update(/home/user/crimson-steel/character.rb)
  ⎿  Added 4 lines, removed 7 lines
      61  
      62    def new_turn
      63      @combat_pool = @character.combat_pool
      64 -    # Bardic inspiration luck expires "before your next turn" —
         - clearing on                                                   
      65 -    # the new-round dice reset is the closest hook the combat t
         -racker has                                                     
      66 -    # to a per-combatant turn tick. Also re-arms the once-per-t
         -urn Perform.                                                   
      67 -    @luck_ledger = 0                                           
      64 +    # Bardic luck expires "before your next turn"; the new-roun
         +d dice                                                         
      65 +    # reset is the closest per-combatant hook the tracker has. 
         +Also                                                           
      66 +    # re-arms the once-per-turn Perform.                       
      67 +    @luck_points = 0                                           
      68      @performed_this_turn = false
      69    end
      70  
      71 -  def luck_points; [@luck_ledger, 0].max; end                  
      72 -  def dm_luck_points; [-@luck_ledger, 0].max; end              
      73 -                                                               
      71    def has_ability?(name); @character.ability_list.include?(name
          ); end
      72    def reroll_init
      73      bonus = @character.respond_to?(:initiative_die_bonus) ? @ch
          aracter.initiative_die_bonus : 0

● Update(/home/user/crimson-steel/character.rb)
  ⎿  Added 1 line, removed 1 line
      83        'saturation' => @saturation, 'temporary_hit_points' => @t
          emporary_hit_points,
      84        'conditions' => @conditions, 'condition_meta' => @conditi
          on_meta,
      85        'ability_damage' => @ability_damage,
      86 -      'luck_ledger' => @luck_ledger, 'performed_this_turn' => @
         -performed_this_turn}                                           
      86 +      'luck_points' => @luck_points, 'performed_this_turn' => @
         +performed_this_turn}                                           
      87    end
      88  
      89    def hp; return @character.hp_max - @minor_damage - @moderate_
          damage - @major_damage + @temporary_hit_points.to_i; end

● Now the Combat class changes: add dm_luck_points as a top-level state,
  load/save it, and clear on new_turn. Plus update the helper.

  Read 1 file (ctrl+o to expand)

● Update(/home/user/crimson-steel/character.rb)
  ⎿  Added 4 lines, removed 1 line
       94  end
       95  
       96  class Combat
       97 -  attr_reader :combat_turn_list, :current_turn_id, :active_eff
          -ects                                                          
       97 +  attr_reader :combat_turn_list, :current_turn_id, :active_eff
          +ects, :dm_luck_points                                         
       98  
       99    def initialize
      100      character_list = Tools.load_json('characters.json')
      101      combat_data = Tools.load_json('combat.json')
      102      @current_turn_id = combat_data['current_turn_id'] || 0
      103      @active_effects = combat_data['active_effects'] || []
      104 +    # DM's own luck pool, accumulated from Perform overflow ac
          +ross all                                                      
      105 +    # bards. Treated as a separate "bard" for spending purpose
          +s.                                                            
      106 +    @dm_luck_points = [combat_data['dm_luck_points'].to_i, 0].
          +max                                                           
      107      @combat_turn_list = combat_data['participants'].filter_map
            do |combat_turn|
      108        char_id = combat_turn['char_id'] || combat_turn['id']
      109        character = character_list.find { |c| c["id"] == char_id
            }

● Update(/home/user/crimson-steel/character.rb)
  ⎿  Added 2 lines, removed 2 lines
      122    def living_turn_list; @combat_turn_list.reject(&:dead?); end
      123    def killed_list; @combat_turn_list.select(&:dead?); end
      124  
      125 -  # Bards whose luck ledger is non-zero; drives the Spend-Luck
          - UI.                                                          
      126 -  def active_luck_bards; @combat_turn_list.select { |ct| ct.lu
          -ck_ledger != 0 }; end                                         
      125 +  # Bards whose luck pool is non-empty; drives the Spend-Luck 
          +UI.                                                           
      126 +  def active_luck_bards; @combat_turn_list.select { |ct| ct.lu
          +ck_points > 0 }; end                                          
      127  
      128    # Highest tier among living non-PC participants; 0 if no ene
           mies are
      129    # present. Used as a TN penalty on bardic performance checks
           .

● Now update Combat#new_turn to clear DM luck and update_data to persist it.
  Read 1 file (ctrl+o to expand)

● Update(/home/user/crimson-steel/character.rb)
  ⎿  Added 6 lines, removed 1 line
      158      return 1 if b_cur > a_cur or a_cur == nil
      159    end
      160  
      161 -  def new_turn; @combat_turn_list.each(&:new_turn); update_dat
          -a; end                                                        
      161 +  def new_turn                                                
      162 +    @combat_turn_list.each(&:new_turn)                        
      163 +    # DM luck expires each round, symmetric with bard luck.   
      164 +    @dm_luck_points = 0                                       
      165 +    update_data                                               
      166 +  end                                                         
      167  
      168    def reroll_init
      169      @combat_turn_list.each(&:reroll_init)

  Read 1 file (ctrl+o to expand)

● Update(/home/user/crimson-steel/character.rb)
  ⎿  Added 1 line
      196    def update_data
      197      combat_data = Tools.load_json('combat.json')
      198      combat_data['participants'] = @combat_turn_list.map(&:to_j
           son)
      199 +    combat_data['dm_luck_points'] = @dm_luck_points.to_i      
      200      Tools.save_json('combat.json', combat_data)
      201    end
      202  

● Now rewrite the two POST routes.

● Update(/home/user/crimson-steel/app.rb)
  ⎿  Added 50 lines, removed 36 lines
      1231  end
      1232  
      1233  # Bardic inspiration. Bard's Perform action: deduct 1 mana, a
            pply a
      1234 -# signed net (successes - failures) to the bard's luck_ledger
           -. Positive                                                   
      1235 -# net feeds the player luck pool; negative net feeds DM luck 
           -(spendable                                                   
      1236 -# against players). Only one side can ever be non-zero at a t
           -ime, so the                                                  
      1237 -# DM just enters the net. Gated to once per turn via performe
           -d_this_turn.                                                 
      1234 +# signed net (successes - failures). Positive net adds to the
           + bard's                                                      
      1235 +# luck_points. Negative net drains the bard's pool first; any
           + overflow                                                    
      1236 +# goes to Combat#dm_luck_points (the DM's separate pool). Gat
           +ed to once                                                   
      1237 +# per turn via performed_this_turn.                          
      1238  post '/combat/bardic_inspiration/:id' do
      1239    redirect '/character/0' unless local_request?
      1240    combat = Combat.new
     ...
      1251    participant = combat_data['participants'].find { |p| p['id'
            ] == bard.combat_id }
      1252    halt 400, 'Participant row missing' unless participant
      1253  
      1254 +  bard_pool_before = bard.luck_points                        
      1255 +  dm_pool_before = combat.dm_luck_points                     
      1256 +  if net >= 0                                                
      1257 +    bard_pool_after = bard_pool_before + net                 
      1258 +    dm_gain = 0                                              
      1259 +  else                                                       
      1260 +    bard_pool_after = [bard_pool_before + net, 0].max        
      1261 +    dm_gain = [-net - bard_pool_before, 0].max               
      1262 +  end                                                        
      1263 +  dm_pool_after = dm_pool_before + dm_gain                   
      1264 +                                                             
      1265    participant['mana'] = bard.mana - 1
      1255 -  new_ledger = bard.luck_ledger + net                        
      1256 -  participant['luck_ledger'] = new_ledger                    
      1266 +  participant['luck_points'] = bard_pool_after               
      1267    participant['performed_this_turn'] = true
      1268 +  combat_data['dm_luck_points'] = dm_pool_after              
      1269    Tools.save_json('combat.json', combat_data)
      1270  
      1271    name = combat.display_name(bard)
      1272    sign = net >= 0 ? '+' : ''
      1262 -  ledger_label = if new_ledger > 0 then "Luck #{new_ledger}" 
      1263 -                 elsif new_ledger < 0 then "DM Luck #{-new_le
           -dger}"                                                       
      1264 -                 else 'ledger 0'                             
      1265 -                 end                                         
      1273 +  parts = []                                                 
      1274 +  parts << "Luck #{bard_pool_after}" if bard_pool_after != ba
           +rd_pool_before || net > 0                                    
      1275 +  parts << "DM Luck #{dm_pool_after}" if dm_gain > 0         
      1276    skill_label = skill.empty? ? 'performance' : skill.tr('_', 
            ' ')
      1267 -  Combat.add_log("#{name} performs #{skill_label} (#{sign}#{n
           -et}; #{ledger_label}).")                                     
      1277 +  Combat.add_log("#{name} performs #{skill_label} (#{sign}#{n
           +et}; #{parts.join(', ')}).")                                 
      1278    redirect '/combat'
      1279  end
      1280  
      1271 -# Spend one point from a bard's luck ledger. kind=ally requir
           -es a                                                         
      1272 -# positive ledger (ally reroll via bardic_inspiration / versa
           -tile_performance);                                           
      1273 -# kind=enemy requires a negative ledger (unsettling_words or 
           -DM-side                                                      
      1274 -# reroll against players). The actual die reroll happens at t
           -he table;                                                    
      1275 -# this endpoint just decrements the ledger and logs.         
      1276 -post '/combat/spend_luck/:bard_id' do                        
      1281 +# Spend luck from a named source on a roll. source_id is eith
           +er a bard's                                                  
      1282 +# combat_id or the literal 'dm' for the DM's separate pool. T
           +he actual                                                    
      1283 +# die rerolls happen client-side; this endpoint validates the
           + amount is                                                   
      1284 +# available, debits the source, and logs the spend so combat_
           +log                                                          
      1285 +# reflects every luck movement.                              
      1286 +post '/combat/spend_luck/:source_id' do                      
      1287    redirect '/character/0' unless local_request?
      1288    combat = Combat.new
      1279 -  bard = combat.combat_turn_list.find { |ct| ct.combat_id == 
           -params[:bard_id].to_i }                                      
      1280 -  halt 400, 'Bard not found' unless bard                     
      1289 +  source_id = params[:source_id].to_s                        
      1290 +  amount = params[:amount].to_i                              
      1291 +  ability = params[:ability].to_s                            
      1292 +  target_name = params[:target_name].to_s.strip              
      1293  
      1282 -  kind = params[:kind].to_s                                  
      1283 -  halt 400, 'Invalid kind' unless %w[ally enemy].include?(kin
           -d)                                                           
      1284 -  if kind == 'ally'                                          
      1285 -    halt 400, 'No player luck to spend' unless bard.luck_ledg
           -er > 0                                                       
      1286 -    delta = -1                                               
      1287 -  else                                                       
      1288 -    halt 400, 'No DM luck to spend' unless bard.luck_ledger <
           - 0                                                           
      1289 -    delta = 1                                                
      1290 -  end                                                        
      1294 +  halt 400, 'Amount must be positive' unless amount > 0      
      1295 +  halt 400, 'Invalid ability' unless %w[inspiration unsettlin
           +g_words].include?(ability)                                   
      1296  
      1297    combat_data = Tools.load_json('combat.json')
      1293 -  participant = combat_data['participants'].find { |p| p['id'
           -] == bard.combat_id }                                        
      1294 -  halt 400, 'Participant row missing' unless participant     
      1295 -  participant['luck_ledger'] = bard.luck_ledger + delta      
      1298 +                                                             
      1299 +  if source_id == 'dm'                                       
      1300 +    halt 400, 'Not enough DM luck' if combat.dm_luck_points <
           + amount                                                      
      1301 +    combat_data['dm_luck_points'] = combat.dm_luck_points - a
           +mount                                                        
      1302 +    source_label = 'DM'                                      
      1303 +  else                                                       
      1304 +    bard = combat.combat_turn_list.find { |ct| ct.combat_id =
           += source_id.to_i }                                           
      1305 +    halt 400, 'Source bard not found' unless bard            
      1306 +    halt 400, 'Not enough luck' if bard.luck_points < amount 
      1307 +    participant = combat_data['participants'].find { |p| p['i
           +d'] == bard.combat_id }                                      
      1308 +    halt 400, 'Participant row missing' unless participant   
      1309 +    participant['luck_points'] = bard.luck_points - amount   
      1310 +    source_label = combat.display_name(bard)                 
      1311 +  end                                                        
      1312    Tools.save_json('combat.json', combat_data)
      1313  
      1298 -  bard_name = combat.display_name(bard)                      
      1299 -  target_name = params[:target_name].to_s.strip              
      1300 -  target_clause = target_name.empty? ? '' : " for #{target_na
           -me}"                                                         
      1301 -  action_label = kind == 'ally' ? 'ally reroll' : 'enemy rero
           -ll'                                                          
      1302 -  Combat.add_log("#{bard_name} spends 1 luck (#{action_label}
           -#{target_clause}).")                                         
      1314 +  ability_label = ability == 'inspiration' ? 'Inspiration' : 
           +'Unsettling Words'                                           
      1315 +  target_clause = target_name.empty? ? '' : " on #{target_nam
           +e}"                                                          
      1316 +  Combat.add_log("#{source_label} spends #{amount} luck — #{a
           +bility_label}#{target_clause}.")                             
      1317    redirect '/combat'
      1318  end
      1319  

● Now UI cleanup: remove the standalone Bardic Luck panel, update the badges to
  the new model.

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 1 line, removed 3 lines
      59            <td class="conditions-cell">
      60              <div class="conditions-list">
      61                <% if combat_turn.luck_points > 0 %>
      62 -                <span class="condition-badge" style="background
         -:#fff7c2;color:#6b5800;border:1px solid #d4b84a;" title="Bardic
         - luck pool (spendable on ally rerolls)">Luck: <%= combat_turn.l
         -uck_points %></span>                                           
      63 -              <% elsif combat_turn.dm_luck_points > 0 %>       
      64 -                <span class="condition-badge" style="background
         -:#3a1f1f;color:#f7c9c9;border:1px solid #8a3838;" title="DM luc
         -k from fumbled performance (spendable against players)">DM Luck
         -: <%= combat_turn.dm_luck_points %></span>                     
      62 +                <span class="condition-badge" style="background
         +:#fff7c2;color:#6b5800;border:1px solid #d4b84a;" title="Bardic
         + luck pool (spendable on rerolls)">Luck: <%= combat_turn.luck_p
         +oints %></span>                                                
      63                <% end %>
      64                <% combat_turn.active_conditions.each do |cname, 
          cval| %>
      65                  <% short, full = condition_label(cname) %>

● Now remove the standalone Bardic Luck panel and replace it with just a DM-luck
   badge in the top header so the DM's pool is visible.

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 3 lines, removed 29 lines
      109      </form>
      110    </div>
      111  
      112 -  <% luck_bards = @combat.active_luck_bards %>                
      113 -  <% if luck_bards.any? %>                                    
      114 -    <% player_names = @combat.living_turn_list.select { |ct| c
          -t.character.data['group'] == 'PC' }.map { |ct| @combat.display
          -_name(ct) } %>                                                
      115 -    <% enemy_names = @combat.living_turn_list.reject { |ct| ct
          -.character.data['group'] == 'PC' }.map { |ct| @combat.display_
          -name(ct) } %>                                                 
      116 -    <div class="bardic-luck" style="margin-top: 15px; padding:
          - 8px; background: #f7f3e8; border-left: 3px solid #b38a2f; bor
          -der-radius: 2px;">                                            
      117 -      <h3 style="margin: 0 0 6px 0; font-size: 14px;">Bardic L
          -uck</h3>                                                      
      118 -      <% luck_bards.each do |bard| %>                         
      119 -        <% ledger = bard.luck_ledger %>                       
      120 -        <% targets = ledger > 0 ? player_names : enemy_names %
          ->                                                             
      121 -        <% kind = ledger > 0 ? 'ally' : 'enemy' %>            
      122 -        <% label = ledger > 0 ? "Luck: #{bard.luck_points}" : 
          -"DM Luck: #{bard.dm_luck_points}" %>                          
      123 -        <% reroll_label = ledger > 0 ? 'ally reroll' : 'enemy 
          -reroll' %>                                                    
      124 -        <div style="display: flex; align-items: center; gap: 8
          -px; margin-bottom: 4px; font-size: 13px;">                    
      125 -          <strong><%= @combat.display_name(bard) %></strong>  
      126 -          <span><%= label %></span>                           
      127 -          <form method="post" action="/combat/spend_luck/<%= b
          -ard.combat_id %>" style="margin:0;display:flex;gap:4px;align-i
          -tems:center;">                                                
      128 -            <input type="hidden" name="kind" value="<%= kind %
          ->">                                                           
      129 -            <label style="font-size: 12px;">Spend on:         
      130 -              <select name="target_name" style="font-size: 12p
          -x;">                                                          
      131 -                <option value="">(unspecified)</option>       
      132 -                <% targets.each do |n| %>                     
      133 -                  <option value="<%= n %>"><%= n %></option>  
      134 -                <% end %>                                     
      135 -              </select>                                       
      136 -            </label>                                          
      137 -            <button type="submit" style="font-size: 12px;" tit
          -le="Spend 1 luck for a <%= reroll_label %>">Spend Luck</button
          ->                                                             
      138 -          </form>                                             
      139 -        </div>                                                
      140 -      <% end %>                                               
      112 +  <% if @combat.dm_luck_points > 0 %>                         
      113 +    <div style="margin-top: 10px; font-size: 13px;">          
      114 +      <span class="condition-badge" style="background:#3a1f1f;
          +color:#f7c9c9;border:1px solid #8a3838;" title="DM luck (spend
          +able on any roll via Inspiration/Unsettling Words)">DM Luck: <
          +%= @combat.dm_luck_points %></span>                           
      115      </div>
      116    <% end %>
      117  

● Now the JS side. First expose luckSources to JS, then build a helper that
  replaces all Roll-button emissions.

  Searched for 1 pattern (ctrl+o to expand)

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 11 lines
      201      var diceRemaining = <%= current ? current.combat_pool : 0 
           %>;
      202      var currentMana = <%= current ? current.mana : 0 %>;
      203      var currentPerformedThisTurn = <%= current && current.perf
           ormed_this_turn ? 'true' : 'false' %>;
      204 +                                                              
      205 +    // Bard and DM luck pools, exposed to every roll prompt so
          + the DM can                                                   
      206 +    // pre-declare a source + amount before rolling, then use 
          +Inspiration                                                   
      207 +    // (reroll N lowest) or Unsettling Words (reroll N highest
          +) afterward.                                                  
      208 +    // Treats the DM as a separate "bard"; /combat/spend_luck 
          +accepts                                                       
      209 +    // either a bard's combat_id or the literal 'dm' as a sour
          +ce.                                                           
      210 +    var luckSources = <%=                                     
      211 +      sources = @combat.active_luck_bards.map { |ct| { id: ct.
          +combat_id.to_s, name: @combat.display_name(ct), amount: ct.luc
          +k_points } }                                                  
      212 +      sources << { id: 'dm', name: 'DM', amount: @combat.dm_lu
          +ck_points } if @combat.dm_luck_points > 0                     
      213 +      JSON.generate(sources)                                  
      214 +    %>;                                                       
      215      var moveSpeed = <%= current ? current.character.speed : 0 
           %>;
      216      var spellList = <%= if current && current.character.spell_
           list
      217        compendium = Compendium.new

● Now build the shared roll-row helper. Replace rollDicePool to return richer
  data (the raw rolls), and add a new rollRowHtml / attachRollRow pair that all
  call sites can use.

  Read 1 file (ctrl+o to expand)

● Now the big JS refactor. I'll rewrite rollDicePool to retain dice state, add
  the shared luck row helper, and swap every Roll-button call site to use it.

  Read 1 file (ctrl+o to expand)

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 131 lines, removed 28 lines
      490      // floored at 0 for the input. Colors: red=1 (fumble), blu
           e=10 (crit),
      491      // green=other success, grey=other failure. Re-clickable s
           o the DM
      492      // can fudge by re-rolling. Used by every combat roll (att
           ack/
      493 -    // defense/ally/healing/condition saves).                 
      494 -    function rollDicePool(dice, tn, inputId, rollsId) {       
      493 +    // defense/ally/healing/condition saves). Saves the raw di
          +ce in                                                         
      494 +    // rollContexts[inputId] so Inspiration/Unsettling Words c
          +an reroll                                                     
      495 +    // specific dice later. signed=true writes negative net in
          +to the                                                        
      496 +    // input (used by Perform); signed=false floors at 0.     
      497 +    var rollContexts = {};                                    
      498 +    function rollDicePool(dice, tn, inputId, rollsId, signed) 
          +{                                                             
      499        var rolls = [];
      496 -      var successes = 0;                                      
      497 -      for (var r = 0; r < dice; r++) {                        
      498 -        var d = Math.floor(Math.random() * 10) + 1;           
      499 -        rolls.push(d);                                        
      500 -        if (d === 10) successes += 2;                         
      501 -        else if (d >= tn) successes++;                        
      502 -        else if (d === 1) successes--;                        
      503 -      }                                                       
      504 -      var displaySuccesses = Math.max(0, successes);          
      500 +      for (var r = 0; r < dice; r++) rolls.push(Math.floor(Mat
          +h.random() * 10) + 1);                                        
      501 +      rollContexts[inputId] = {rolls: rolls, tn: tn, rollsId: 
          +rollsId, signed: !!signed};                                   
      502 +      paintRollResult(inputId);                               
      503 +      enableLuckButtons(inputId);                             
      504 +    }                                                         
      505 +                                                              
      506 +    function countRollSuccesses(rolls, tn) {                  
      507 +      var s = 0;                                              
      508 +      rolls.forEach(function(d) {                             
      509 +        if (d === 10) s += 2;                                 
      510 +        else if (d >= tn) s += 1;                             
      511 +        else if (d === 1) s -= 1;                             
      512 +      });                                                     
      513 +      return s;                                               
      514 +    }                                                         
      515 +                                                              
      516 +    function paintRollResult(inputId) {                       
      517 +      var ctx = rollContexts[inputId];                        
      518 +      if (!ctx) return;                                       
      519 +      var raw = countRollSuccesses(ctx.rolls, ctx.tn);        
      520 +      var display = ctx.signed ? raw : Math.max(0, raw);      
      521        var inputEl = document.getElementById(inputId);
      506 -      if (inputEl) inputEl.value = displaySuccesses;          
      507 -      var rollsEl = document.getElementById(rollsId);         
      508 -      if (rollsEl) {                                          
      509 -        var colored = rolls.map(function(d) {                 
      510 -          var bg = null;                                      
      511 -          if (d === 1) bg = '#e57373';          // red   (fumb
          -le)                                                           
      512 -          else if (d === 10) bg = '#64b5f6';    // blue  (crit
          -)                                                             
      513 -          else if (d >= tn) bg = '#81c784';     // green (succ
          -ess)                                                          
      514 -          if (bg) {                                           
      515 -            return '<span style="background:' + bg + ';color:#
          -000;padding:1px 6px;border-radius:3px;font-weight:bold;">' + d
          - + '</span>';                                                 
      516 -          }                                                   
      517 -          return '<span style="color:#777;">' + d + '</span>';
      518 -        }).join(', ');                                        
      519 -        rollsEl.innerHTML = 'Rolled: [' + colored + '] &rarr; 
          -' + displaySuccesses + ' success' + (displaySuccesses === 1 ? 
          -'' : 'es') +                                                  
      520 -          (successes < 0 ? ' <span class="math-detail">(raw ' 
          -+ successes + ', floored)</span>' : '');                      
      521 -      }                                                       
      522 +      if (inputEl) inputEl.value = display;                   
      523 +      var rollsEl = document.getElementById(ctx.rollsId);     
      524 +      if (!rollsEl) return;                                   
      525 +      var colored = ctx.rolls.map(function(d) {               
      526 +        var bg = null;                                        
      527 +        if (d === 1) bg = '#e57373';                          
      528 +        else if (d === 10) bg = '#64b5f6';                    
      529 +        else if (d >= ctx.tn) bg = '#81c784';                 
      530 +        if (bg) return '<span style="background:' + bg + ';col
          +or:#000;padding:1px 6px;border-radius:3px;font-weight:bold;">'
          + + d + '</span>';                                             
      531 +        return '<span style="color:#777;">' + d + '</span>';  
      532 +      }).join(', ');                                          
      533 +      var label = ctx.signed ? ('net ' + (display >= 0 ? '+' :
          + '') + display)                                               
      534 +        : (display + ' success' + (display === 1 ? '' : 'es') 
          ++ (raw < 0 ? ' <span class="math-detail">(raw ' + raw + ', flo
          +ored)</span>' : ''));                                         
      535 +      rollsEl.innerHTML = 'Rolled: [' + colored + '] &rarr; ' 
          ++ label;                                                      
      536      }
      537  
      538      function rollSaveDice(i, inputId, rollsId) {
      539        var cond = startOfTurnConditions[i];
      526 -      rollDicePool(cond.dice, cond.tn, inputId, rollsId);     
      540 +      rollDicePool(cond.dice, cond.tn, inputId, rollsId, false
          +);                                                            
      541      }
      542  
      543 +    // Current cached snapshot of luck pools; the Inspiration 
          +/ Unsettling                                                  
      544 +    // Words buttons decrement this locally so a single roll c
          +an't spend                                                    
      545 +    // more than the source has, even before the server round-
          +trip.                                                         
      546 +    var luckSourceCache = luckSources.slice().map(function(s) 
          +{ return {id: s.id, name: s.name, amount: s.amount}; });      
      547 +    function luckSourceAmount(id) {                           
      548 +      for (var i = 0; i < luckSourceCache.length; i++) if (luc
          +kSourceCache[i].id === id) return luckSourceCache[i].amount;  
      549 +      return 0;                                               
      550 +    }                                                         
      551 +                                                              
      552 +    // Build the inline Roll-row HTML: optional luck source/am
          +ount inputs,                                                  
      553 +    // a Roll button, and hidden Inspiration / Unsettling Word
          +s buttons.                                                    
      554 +    // Each call must pass a unique inputId so the context map
          + doesn't                                                      
      555 +    // collide across simultaneously-visible rolls.           
      556 +    function rollRowHtml(cfg) {                               
      557 +      var iid = cfg.inputId;                                  
      558 +      var rid = cfg.rollsId;                                  
      559 +      var signed = cfg.signed ? 'true' : 'false';             
      560 +      var target = (cfg.targetName || '').replace(/'/g, "&#39;
          +");                                                           
      561 +      var srcId = 'luck-src-' + iid;                          
      562 +      var amtId = 'luck-amt-' + iid;                          
      563 +      var insId = 'luck-ins-' + iid;                          
      564 +      var uwId  = 'luck-uw-' + iid;                           
      565 +      var srcOpts = '<option value="">(no luck)</option>';    
      566 +      luckSourceCache.forEach(function(s) {                   
      567 +        if (s.amount > 0) srcOpts += '<option value="' + s.id 
          ++ '">' + s.name + ' (' + s.amount + ')</option>';             
      568 +      });                                                     
      569 +      var hasSources = luckSourceCache.some(function(s) { retu
          +rn s.amount > 0; });                                          
      570 +      var luckControls = hasSources ?                         
      571 +        '<span style="display:inline-block;margin-right:6px;pa
          +dding:2px 6px;background:#fff7c2;border:1px solid #d4b84a;bord
          +er-radius:3px;">' +                                           
      572 +          '<label style="font-size:11px;">Luck: <select id="' 
          ++ srcId + '" style="font-size:11px;padding:0 2px;">' + srcOpts
          + + '</select></label>' +                                      
      573 +          ' <label style="font-size:11px;">spend <input type="
          +number" id="' + amtId + '" min="0" value="0" style="width:42px
          +;font-size:11px;"></label>' +                                 
      574 +        '</span>' : '';                                       
      575 +      return luckControls +                                   
      576 +        '<button class="action-btn" onclick="rollDicePool(' + 
          +cfg.dice + ',' + cfg.tn + ",'" + iid + "','" + rid + "'," + si
          +gned + ')">Roll</button>' +                                   
      577 +        ' <button class="action-btn" id="' + insId + '" style=
          +"display:none;" title="Reroll the N lowest dice" onclick="appl
          +yLuckReroll(\'' + iid + "','inspiration','" + target + "')\">I
          +nspiration</button>" +                                        
      578 +        ' <button class="action-btn" id="' + uwId + '" style="
          +display:none;" title="Reroll the N highest dice" onclick="appl
          +yLuckReroll(\'' + iid + "','unsettling_words','" + target + "'
          +)\">Unsettling Words</button>";                               
      579 +    }                                                         
      580 +                                                              
      581 +    function enableLuckButtons(inputId) {                     
      582 +      var srcEl = document.getElementById('luck-src-' + inputI
          +d);                                                           
      583 +      var amtEl = document.getElementById('luck-amt-' + inputI
          +d);                                                           
      584 +      var ins = document.getElementById('luck-ins-' + inputId)
          +;                                                             
      585 +      var uw  = document.getElementById('luck-uw-' + inputId);
      586 +      var amt = amtEl ? parseInt(amtEl.value, 10) : 0;        
      587 +      var src = srcEl ? srcEl.value : '';                     
      588 +      var show = amt > 0 && src !== '' && amt <= luckSourceAmo
          +unt(src);                                                     
      589 +      if (ins) ins.style.display = show ? '' : 'none';        
      590 +      if (uw)  uw.style.display  = show ? '' : 'none';        
      591 +    }                                                         
      592 +                                                              
      593 +    // Reroll N of the stored dice in-place. Inspiration picks
          + the N                                                        
      594 +    // lowest; Unsettling Words picks the N highest. After the
          + reroll we                                                    
      595 +    // repaint, POST the debit to /combat/spend_luck (server-s
          +ide audit                                                     
      596 +    // log + pool decrement), and hide the buttons so one comm
          +it per                                                        
      597 +    // declared spend. The luckSourceCache mirrors the decreme
          +nt so a                                                       
      598 +    // subsequent roll in the same view can't overspend.      
      599 +    function applyLuckReroll(inputId, ability, targetName) {  
      600 +      var ctx = rollContexts[inputId];                        
      601 +      if (!ctx) return;                                       
      602 +      var srcEl = document.getElementById('luck-src-' + inputI
          +d);                                                           
      603 +      var amtEl = document.getElementById('luck-amt-' + inputI
          +d);                                                           
      604 +      var amt = amtEl ? parseInt(amtEl.value, 10) : 0;        
      605 +      var src = srcEl ? srcEl.value : '';                     
      606 +      if (amt <= 0 || !src) { alert('Pick a luck source and am
          +ount first.'); return; }                                      
      607 +      if (amt > luckSourceAmount(src)) { alert('That source on
          +ly has ' + luckSourceAmount(src) + ' luck.'); return; }       
      608 +      var n = Math.min(amt, ctx.rolls.length);                
      609 +      var indexed = ctx.rolls.map(function(v, i) { return {v: 
          +v, i: i}; });                                                 
      610 +      indexed.sort(function(a, b) { return ability === 'inspir
          +ation' ? a.v - b.v : b.v - a.v; });                           
      611 +      for (var k = 0; k < n; k++) {                           
      612 +        ctx.rolls[indexed[k].i] = Math.floor(Math.random() * 1
          +0) + 1;                                                       
      613 +      }                                                       
      614 +      paintRollResult(inputId);                               
      615 +      var fd = new FormData();                                
      616 +      fd.append('amount', amt);                               
      617 +      fd.append('ability', ability);                          
      618 +      fd.append('target_name', targetName || '');             
      619 +      fetch('/combat/spend_luck/' + encodeURIComponent(src), {
          +method: 'POST', body: fd});                                   
      620 +      for (var i = 0; i < luckSourceCache.length; i++) {      
      621 +        if (luckSourceCache[i].id === src) {                  
      622 +          luckSourceCache[i].amount = Math.max(0, luckSourceCa
          +che[i].amount - amt);                                         
      623 +          break;                                              
      624 +        }                                                     
      625 +      }                                                       
      626 +      var ins = document.getElementById('luck-ins-' + inputId)
          +;                                                             
      627 +      var uw  = document.getElementById('luck-uw-' + inputId);
      628 +      if (ins) ins.style.display = 'none';                    
      629 +      if (uw)  uw.style.display  = 'none';                    
      630 +    }                                                         
      631 +                                                              
      632      // Preview of what a save with `successes` will do to `con
           d` on Confirm.
      633      // Mirrors the server-side resolution in app.rb start_of_t
           urn so the DM
      634      // can see damage/paralysis/decay before submitting.

● Now replace each inline Roll button emission with rollRowHtml. Let me find
  them precisely.

  Searched for 1 pattern, read 1 file (ctrl+o to expand)

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 1 line, removed 1 line
      446            '<strong>Save vs ' + cond.label + '</strong> <span c
           lass="math-detail">(severity ' + cond.value + ')</span>' +
      447            '<br><span class="math-detail">Roll ' + cond.dice + 
           ' dice at TN ' + cond.tn + '</span>' + tnSuffix +
      448            '<br><label>Successes: <input type="number" id="' + 
           inputId + '" min="0" max="' + cond.dice + '" value="0" style="
           width:50px;"></label>' +
      449 -          ' <button class="action-btn" onclick="rollSaveDice('
          - + i + ', \'' + inputId + '\', \'' + rollsId + '\')">Roll</but
          -ton>' +                                                       
      449 +          ' ' + rollRowHtml({dice: cond.dice, tn: cond.tn, inp
          +utId: inputId, rollsId: rollsId, signed: false, targetName: cu
          +rrentCharName}) +                                             
      450            '<div id="' + rollsId + '" class="math-detail" style
           ="margin-top:4px;"></div>' +
      451            '</div>';
      452        }).join('');

  Read 1 file (ctrl+o to expand)
● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 1 line, removed 1 line
      854        addStep('<strong>Stabilize Roll</strong>: ' + dice + ' d
           ice, TN ' + tn +
      855          '<br><label>Successes: <input type="number" id="stabil
           ize-successes" min="0" value="0" style="width:50px;"></label>'
            +
      856          ' <button class="action-btn" onclick="showStabilizeSum
           mary(\'' + spellName.replace(/'/g, "\\'") + '\', ' + spellTier
            + ', ' + targetId + ', ' + dice + ')">Next</button>' +
      857 -        ' <button class="action-btn" onclick="rollDicePool(' +
          - dice + ', ' + tn + ', \'stabilize-successes\', \'stabilize-ro
          -ll-display\')">Roll</button>' +                               
      857 +        ' ' + rollRowHtml({dice: dice, tn: tn, inputId: 'stabi
          +lize-successes', rollsId: 'stabilize-roll-display', signed: fa
          +lse, targetName: currentCharName}) +                          
      858          '<div id="stabilize-roll-display" class="math-detail" 
           style="margin-top:4px;"></div>');
      859      }
      860  

● Now the Perform roll (line ~1098). Replace the standalone rollPerformDice with
   the shared flow using signed: true.

  Read 1 file (ctrl+o to expand)

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 1 line, removed 28 lines
      1095          '<label style="margin-top:4px;display:inline-block;">
            Net (successes − failures): ' +
      1096            '<input type="number" id="bi-net" value="0" style="
            width:60px;">' +
      1097          '</label>' +
      1098 -        ' <button class="action-btn" onclick="rollPerformDice
           -()">Roll</button>' +                                         
      1098 +        ' ' + rollRowHtml({dice: p.dice, tn: p.tn, inputId: '
           +bi-net', rollsId: 'bi-rolls', signed: true, targetName: curre
           +ntCharName}) +                                               
      1099          '<div id="bi-rolls" class="math-detail" style="margin
            -top:4px;"></div>' +
      1100          '<br><button class="action-btn" onclick="submitBardic
            Inspiration()" style="margin-top:8px;">Confirm Perform</butto
            n>';
      1101        document.getElementById('bi-roll-area').innerHTML = htm
            l;
      1102      }
      1103  
      1104 -    // Roll the perform pool and write the SIGNED net into bi
           --net so the                                                  
      1105 -    // sign-based routing to player/DM luck is preserved. Mir
           -rors the                                                     
      1106 -    // coloring scheme of rollDicePool but keeps negative tot
           -als.                                                         
      1107 -    function rollPerformDice() {                             
      1108 -      var sel = document.getElementById('bi-skill');         
      1109 -      var p = performSkills[parseInt(sel.value, 10)];        
      1110 -      var rolls = [];                                        
      1111 -      var net = 0;                                           
      1112 -      for (var r = 0; r < p.dice; r++) {                     
      1113 -        var d = Math.floor(Math.random() * 10) + 1;          
      1114 -        rolls.push(d);                                       
      1115 -        if (d === 10) net += 2;                              
      1116 -        else if (d >= p.tn) net += 1;                        
      1117 -        else if (d === 1) net -= 1;                          
      1118 -      }                                                      
      1119 -      document.getElementById('bi-net').value = net;         
      1120 -      var colored = rolls.map(function(d) {                  
      1121 -        var bg = null;                                       
      1122 -        if (d === 1) bg = '#e57373';                         
      1123 -        else if (d === 10) bg = '#64b5f6';                   
      1124 -        else if (d >= p.tn) bg = '#81c784';                  
      1125 -        if (bg) return '<span style="background:' + bg + ';co
           -lor:#000;padding:1px 6px;border-radius:3px;font-weight:bold;"
           ->' + d + '</span>';                                          
      1126 -        return '<span style="color:#777;">' + d + '</span>'; 
      1127 -      }).join(', ');                                         
      1128 -      document.getElementById('bi-rolls').innerHTML = 'Rolled
           -: [' + colored + '] &rarr; net ' + (net >= 0 ? '+' : '') + ne
           -t;                                                           
      1129 -    }                                                        
      1130 -                                                             
      1104      function submitBardicInspiration() {
      1105        var sel = document.getElementById('bi-skill');
      1106        var p = performSkills[parseInt(sel.value, 10)];

● Now the remaining Roll-button sites: attack, dodge, parry, block, ally block,
  heal. Let me fetch each.

  Searched for 1 pattern, read 1 file (ctrl+o to expand)

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 1 line, removed 1 line
      1503        addStep('<strong>Attack Roll</strong>: ' + rollDice + '
             dice' + diceNote + ', TN ' + attackState.attackTn +
      1504          '<br><label>Attack successes: <input type="number" id
            ="attack-successes-input" min="0" value="0" style="width:50px
            ;"></label>' +
      1505          ' <button class="action-btn" onclick="confirmAttackSu
            ccesses()">Confirm</button>' +
      1506 -        ' <button class="action-btn" onclick="rollDicePool(' 
           -+ rollDice + ', ' + attackState.attackTn + ', \'attack-succes
           -ses-input\', \'attack-roll-display\')">Roll</button>' +      
      1506 +        ' ' + rollRowHtml({dice: rollDice, tn: attackState.at
           +tackTn, inputId: 'attack-successes-input', rollsId: 'attack-r
           +oll-display', signed: false, targetName: currentCharName}) + 
      1507          '<div id="attack-roll-display" class="math-detail" st
            yle="margin-top:4px;"></div>');
      1508      }
      1509  

  Searched for 2 patterns, read 1 file (ctrl+o to expand)

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 3 lines, removed 3 lines
      1531        addStep('<strong>Dodge Roll</strong>: ' + attackState.d
            efenseDice + ' dice, TN ' + attackState.dodgeTn +
      1532          '<br><label>Dodge successes: <input type="number" id=
            "defense-successes-input" min="0" value="0" style="width:50px
            ;"></label>' +
      1533          ' <button class="action-btn" onclick="confirmDefenseS
            uccesses()">Confirm</button>' +
      1534 -        ' <button class="action-btn" onclick="rollDicePool(' 
           -+ attackState.defenseDice + ', ' + attackState.dodgeTn + ', \
           -'defense-successes-input\', \'defense-roll-display\')">Roll</
           -button>' +                                                   
      1534 +        ' ' + rollRowHtml({dice: attackState.defenseDice, tn:
           + attackState.dodgeTn, inputId: 'defense-successes-input', rol
           +lsId: 'defense-roll-display', signed: false, targetName: atta
           +ckState.target.name}) +                                      
      1535          '<div id="defense-roll-display" class="math-detail" s
            tyle="margin-top:4px;"></div>');
      1536      }
      1537  
     ...
      1539        addStep('<strong>Parry Roll</strong>: ' + attackState.p
            arryDice + ' dice, TN ' + attackState.parryTn +
      1540          '<br><label>Parry successes: <input type="number" id=
            "defense-successes-input" min="0" value="0" style="width:50px
            ;"></label>' +
      1541          ' <button class="action-btn" onclick="confirmDefenseS
            uccesses()">Confirm</button>' +
      1542 -        ' <button class="action-btn" onclick="rollDicePool(' 
           -+ attackState.parryDice + ', ' + attackState.parryTn + ', \'d
           -efense-successes-input\', \'defense-roll-display\')">Roll</bu
           -tton>' +                                                     
      1542 +        ' ' + rollRowHtml({dice: attackState.parryDice, tn: a
           +ttackState.parryTn, inputId: 'defense-successes-input', rolls
           +Id: 'defense-roll-display', signed: false, targetName: attack
           +State.target.name}) +                                        
      1543          '<div id="defense-roll-display" class="math-detail" s
            tyle="margin-top:4px;"></div>');
      1544      }
      1545  
     ...
      1547        addStep('<strong>Block Roll</strong>: ' + attackState.b
            lockDice + ' dice, TN ' + attackState.blockTn +
      1548          '<br><label>Block successes: <input type="number" id=
            "defense-successes-input" min="0" value="0" style="width:50px
            ;"></label>' +
      1549          ' <button class="action-btn" onclick="confirmDefenseS
            uccesses()">Confirm</button>' +
      1550 -        ' <button class="action-btn" onclick="rollDicePool(' 
           -+ attackState.blockDice + ', ' + attackState.blockTn + ', \'d
           -efense-successes-input\', \'defense-roll-display\')">Roll</bu
           -tton>' +                                                     
      1550 +        ' ' + rollRowHtml({dice: attackState.blockDice, tn: a
           +ttackState.blockTn, inputId: 'defense-successes-input', rolls
           +Id: 'defense-roll-display', signed: false, targetName: attack
           +State.target.name}) +                                        
      1551          '<div id="defense-roll-display" class="math-detail" s
            tyle="margin-top:4px;"></div>');
      1552      }
      1553  

  Read 1 file (ctrl+o to expand)

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 1 line, removed 1 line
      1586          '<br><span class="math-detail">' + tnMath + '</span>'
             +
      1587          '<br><label>Block successes: <input type="number" id=
            "ally-block-successes" min="0" value="0" style="width:50px;">
            </label>' +
      1588          ' <button class="action-btn" onclick="confirmAllyBloc
            kSuccesses()">Confirm</button>' +
      1589 -        ' <button class="action-btn" onclick="rollDicePool(' 
           -+ ally.dice + ', ' + blockTn + ', \'ally-block-successes\', \
           -'ally-block-display\')">Roll</button>' +                     
      1589 +        ' ' + rollRowHtml({dice: ally.dice, tn: blockTn, inpu
           +tId: 'ally-block-successes', rollsId: 'ally-block-display', s
           +igned: false, targetName: (caster ? caster.name : 'Ally')}) +
      1590          '<div id="ally-block-display" class="math-detail" sty
            le="margin-top:4px;"></div>');
      1591      }
      1592  

  Read 1 file (ctrl+o to expand)

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 1 line, removed 1 line
      1719        addStep('<strong>' + healer.name + ' rolls Healing Word
            </strong>: ' + dice + ' dice, TN ' + healTn +
      1720          '<br><label>Successes (each reduces damage by 1): <in
            put type="number" id="hw-successes" min="0" value="0" style="
            width:50px;"></label>' +
      1721          ' <button class="action-btn" onclick="confirmHealingW
            ordSuccesses()">Confirm</button>' +
      1722 -        ' <button class="action-btn" onclick="rollDicePool(' 
           -+ dice + ', ' + healTn + ', \'hw-successes\', \'hw-roll-displ
           -ay\')">Roll</button>' +                                      
      1722 +        ' ' + rollRowHtml({dice: dice, tn: healTn, inputId: '
           +hw-successes', rollsId: 'hw-roll-display', signed: false, tar
           +getName: healer.name}) +                                     
      1723          '<div id="hw-roll-display" class="math-detail" style=
            "margin-top:4px;"></div>');
      1724      }
      1725  

● Bash(ruby -c character.rb && ruby -c app.rb && ruby -r erb -e
      'ERB.new(File.read("views/combat_tracker.erb"), trim_mode: "-").src; puts
      "ERB OK"')
  ⎿  Syntax OK
     Syntax OK
     ERB OK

  Searched for 1 pattern (ctrl+o to expand)

● Write(/tmp/luck_refactor_smoke.rb)
  ⎿  Wrote 48 lines to ../../../../tmp/luck_refactor_smoke.rb
       1 require "json"
       2 $LOAD_PATH.unshift(".")
       3 load "tools.rb"
       4 load "character.rb"
       5 
       6 chars = JSON.parse(File.read("data/characters.json"))
       7 cotton = chars.find { |c| c["name"] == "Cottonballs" }
       8 participant = {
       9   "id" => cotton["id"], "char_id" => cotton["id"],
      10   "initiative" => "X", "mana" => 10, "combat_pool" => 10,
     … +42 lines (ctrl+o to expand)

● Bash(ruby /tmp/luck_refactor_smoke.rb 2>&1 | tail -20)
  ⎿  luck_points (fresh): 0
     luck_points clamped from -5: 0
     current combat dm_luck_points field: nil
     … +7 lines (ctrl+o to expand)

● Let me tighten enableLuckButtons and wire reactive change handlers on the luck
   controls.

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 3 lines, removed 2 lines
      567          if (s.amount > 0) srcOpts += '<option value="' + s.id 
           + '">' + s.name + ' (' + s.amount + ')</option>';
      568        });
      569        var hasSources = luckSourceCache.some(function(s) { retu
           rn s.amount > 0; });
      570 +      var refresh = "enableLuckButtons('" + iid + "')";       
      571        var luckControls = hasSources ?
      572          '<span style="display:inline-block;margin-right:6px;pa
           dding:2px 6px;background:#fff7c2;border:1px solid #d4b84a;bord
           er-radius:3px;">' +
      572 -          '<label style="font-size:11px;">Luck: <select id="' 
          -+ srcId + '" style="font-size:11px;padding:0 2px;">' + srcOpts
          - + '</select></label>' +                                      
      573 -          ' <label style="font-size:11px;">spend <input type="
          -number" id="' + amtId + '" min="0" value="0" style="width:42px
          -;font-size:11px;"></label>' +                                 
      573 +          '<label style="font-size:11px;">Luck: <select id="' 
          ++ srcId + '" style="font-size:11px;padding:0 2px;" onchange="'
          + + refresh + '">' + srcOpts + '</select></label>' +           
      574 +          ' <label style="font-size:11px;">spend <input type="
          +number" id="' + amtId + '" min="0" value="0" style="width:42px
          +;font-size:11px;" oninput="' + refresh + '"></label>' +       
      575          '</span>' : '';
      576        return luckControls +
      577          '<button class="action-btn" onclick="rollDicePool(' + 
           cfg.dice + ',' + cfg.tn + ",'" + iid + "','" + rid + "'," + si
           gned + ')">Roll</button>' +

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 2 lines, removed 1 line
      580      }
      581  
      582      function enableLuckButtons(inputId) {
      583 +      var ctx = rollContexts[inputId];                        
      584        var srcEl = document.getElementById('luck-src-' + inputI
           d);
      585        var amtEl = document.getElementById('luck-amt-' + inputI
           d);
      586        var ins = document.getElementById('luck-ins-' + inputId)
           ;
      587        var uw  = document.getElementById('luck-uw-' + inputId);
      588        var amt = amtEl ? parseInt(amtEl.value, 10) : 0;
      589        var src = srcEl ? srcEl.value : '';
      589 -      var show = amt > 0 && src !== '' && amt <= luckSourceAmo
          -unt(src);                                                     
      590 +      var show = ctx && amt > 0 && src !== '' && amt <= luckSo
          +urceAmount(src);                                              
      591        if (ins) ins.style.display = show ? '' : 'none';
      592        if (uw)  uw.style.display  = show ? '' : 'none';
      593      }

● Bash(ruby -c character.rb && ruby -c app.rb && ruby -r erb -e
      'ERB.new(File.read("views/combat_tracker.erb"), trim_mode: "-").src; puts
      "ERB OK"')
  ⎿  Syntax OK
     Syntax OK
     ERB OK
● Bash(rm /tmp/luck_refactor_smoke.rb && git status && git diff --stat)
  ⎿  On branch claude/bard-luck-reroll-mechanic-3DFmV
     Your branch is up to date with 'origin/claude/bard-luck-reroll-mechani
     c-3DFmV'.
     … +15 lines (ctrl+o to expand)

● Bash(git add app.rb character.rb views/combat_tracker.erb && git commit -m
      "$(cat <<'EOF'
      Luck spend on every roll; separate DM pool…)
  ⎿  [claude/bard-luck-reroll-mechanic-3DFmV 726941b] Luck spend on every r
     oll; separate DM pool
      3 files changed, 230 insertions(+), 150 deletions(-)

● Bash(git push origin claude/bard-luck-reroll-mechanic-3DFmV 2>&1)
  ⎿  To http://127.0.0.1:59765/git/dividetask/crimson-steel
        17daebf..726941b  claude/bard-luck-reroll-mechanic-3DFmV -> claude/
     bard-luck-reroll-mechanic-3DFmV

● Pushed.

  What shipped

  - Data model: each bard gets a non-negative luck_points; Combat owns a
  top-level dm_luck_points. Perform applies net = successes − failures, draining
   the bard pool first and overflowing any leftover failures into the DM pool.
  Both clear on Reset Dice.
  - spend_luck route now takes source_id (a bard's combat_id or the literal dm),
   an amount, an ability (inspiration/unsettling_words), and optional
  target_name for the log.
  - UI at every roll: an inline luck chip — Luck: [source ▼] spend [N] — sits
  next to Roll on every dice prompt (saves, stabilize, perform, attack, dodge,
  parry, block, ally-block, healing word). After Roll, if a source and amount
  are both set, Inspiration (reroll N lowest) and Unsettling Words (reroll N
  highest) appear; clicking either rerolls those dice in place, repaints the
  successes, and POSTs the debit. Client-side cache mirrors the decrement so the
   DM can't overspend across multiple buttons in the same view.
  - Standalone panel removed; a small DM Luck: N badge appears near the top
  controls when the DM pool is non-zero.
  - rollDicePool is now the only roll entrypoint (signed flag handles Perform);
  rollSaveDice delegates; rollPerformDice is gone.

  Still worth a live sanity pass — I syntax-checked Ruby/ERB and smoke-tested
  the overflow arithmetic, but the full reroll flow only exercises in-browser.
  Worth clicking once through Cottonballs performing, a save with 2 luck →
  Unsettling Words, and an attack with DM luck → Inspiration to confirm the
  buttons appear and the DM Luck badge updates after reload.

❯ Please ask for luck before asking for successes. There isn't a need to ask me 
   where the luck comes from if there is only one option, so please             
  automatically select the only option. I would also like to know how much luck 
   remains when I am deciding how much luck to spend                            

● Good tweaks. I'll split the luck picker from the roll buttons, auto-collapse
  to static text when only one source exists, and surface remaining luck next to
   the amount input.

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 61 lines, removed 20 lines
      549        return 0;
      550      }
      551  
      552 -    // Build the inline Roll-row HTML: optional luck source/am
          -ount inputs,                                                  
      553 -    // a Roll button, and hidden Inspiration / Unsettling Word
          -s buttons.                                                    
      554 -    // Each call must pass a unique inputId so the context map
          - doesn't                                                      
      555 -    // collide across simultaneously-visible rolls.           
      556 -    function rollRowHtml(cfg) {                               
      552 +    // Pre-roll luck picker. Rendered BEFORE the successes inp
          +ut at each                                                    
      553 +    // roll site so the DM declares their spend first. When on
          +ly one bard                                                   
      554 +    // (or the DM) has luck, the source is shown as static tex
          +t instead                                                     
      555 +    // of a dropdown. The "N available" span is refreshed acro
          +ss every                                                      
      556 +    // visible prompt after a spend so multi-save screens stay
          + accurate.                                                    
      557 +    function luckPickerHtml(inputId) {                        
      558 +      var sources = luckSourceCache.filter(function(s) { retur
          +n s.amount > 0; });                                           
      559 +      if (sources.length === 0) return '';                    
      560 +      var iid = inputId;                                      
      561 +      var srcId = 'luck-src-' + iid;                          
      562 +      var amtId = 'luck-amt-' + iid;                          
      563 +      var availId = 'luck-avail-' + iid;                      
      564 +      var refresh = "onLuckChange('" + iid + "')";            
      565 +      var sourceField;                                        
      566 +      if (sources.length === 1) {                             
      567 +        sourceField = '<span style="font-weight:bold;">' + sou
          +rces[0].name + '</span>' +                                    
      568 +          '<input type="hidden" id="' + srcId + '" value="' + 
          +sources[0].id + '">';                                         
      569 +      } else {                                                
      570 +        var opts = sources.map(function(s) {                  
      571 +          return '<option value="' + s.id + '">' + s.name + '<
          +/option>';                                                    
      572 +        }).join('');                                          
      573 +        sourceField = '<select id="' + srcId + '" style="font-
          +size:11px;padding:0 2px;" onchange="' + refresh + '">' + opts 
          ++ '</select>';                                                
      574 +      }                                                       
      575 +      var initial = sources[0].amount;                        
      576 +      return '<div style="display:inline-block;margin:4px 0;pa
          +dding:3px 8px;background:#fff7c2;border:1px solid #d4b84a;bord
          +er-radius:3px;font-size:12px;">' +                            
      577 +        '<span style="font-size:11px;color:#6b5800;margin-righ
          +t:4px;">Spend luck:</span>' +                                 
      578 +        sourceField +                                         
      579 +        ' <input type="number" id="' + amtId + '" min="0" valu
          +e="0" data-luck-amt="1" style="width:42px;font-size:12px;" oni
          +nput="' + refresh + '">' +                                    
      580 +        ' <span id="' + availId + '" data-luck-avail-for="' + 
          +iid + '" style="font-size:11px;color:#6b5800;">(' + initial + 
          +' available)</span>' +                                        
      581 +        '</div>';                                             
      582 +    }                                                         
      583 +                                                              
      584 +    // Post-successes roll buttons: Roll (always) plus hidden 
          +Inspiration /                                                 
      585 +    // Unsettling Words. The reroll buttons reveal themselves 
          +once dice                                                     
      586 +    // have been rolled AND the luck picker has a valid source
          + + amount.                                                    
      587 +    function rollButtonsHtml(cfg) {                           
      588        var iid = cfg.inputId;
      589        var rid = cfg.rollsId;
      590        var signed = cfg.signed ? 'true' : 'false';
      591        var target = (cfg.targetName || '').replace(/'/g, "&#39;
           ");
      561 -      var srcId = 'luck-src-' + iid;                          
      562 -      var amtId = 'luck-amt-' + iid;                          
      592        var insId = 'luck-ins-' + iid;
      593        var uwId  = 'luck-uw-' + iid;
      565 -      var srcOpts = '<option value="">(no luck)</option>';    
      566 -      luckSourceCache.forEach(function(s) {                   
      567 -        if (s.amount > 0) srcOpts += '<option value="' + s.id 
          -+ '">' + s.name + ' (' + s.amount + ')</option>';             
      568 -      });                                                     
      569 -      var hasSources = luckSourceCache.some(function(s) { retu
          -rn s.amount > 0; });                                          
      570 -      var refresh = "enableLuckButtons('" + iid + "')";       
      571 -      var luckControls = hasSources ?                         
      572 -        '<span style="display:inline-block;margin-right:6px;pa
          -dding:2px 6px;background:#fff7c2;border:1px solid #d4b84a;bord
          -er-radius:3px;">' +                                           
      573 -          '<label style="font-size:11px;">Luck: <select id="' 
          -+ srcId + '" style="font-size:11px;padding:0 2px;" onchange="'
          - + refresh + '">' + srcOpts + '</select></label>' +           
      574 -          ' <label style="font-size:11px;">spend <input type="
          -number" id="' + amtId + '" min="0" value="0" style="width:42px
          -;font-size:11px;" oninput="' + refresh + '"></label>' +       
      575 -        '</span>' : '';                                       
      576 -      return luckControls +                                   
      577 -        '<button class="action-btn" onclick="rollDicePool(' + 
          -cfg.dice + ',' + cfg.tn + ",'" + iid + "','" + rid + "'," + si
          -gned + ')">Roll</button>' +                                   
      594 +      return '<button class="action-btn" onclick="rollDicePool
          +(' + cfg.dice + ',' + cfg.tn + ",'" + iid + "','" + rid + "',"
          + + signed + ')">Roll</button>' +                              
      595          ' <button class="action-btn" id="' + insId + '" style=
           "display:none;" title="Reroll the N lowest dice" onclick="appl
           yLuckReroll(\'' + iid + "','inspiration','" + target + "')\">I
           nspiration</button>" +
      596          ' <button class="action-btn" id="' + uwId + '" style="
           display:none;" title="Reroll the N highest dice" onclick="appl
           yLuckReroll(\'' + iid + "','unsettling_words','" + target + "'
           )\">Unsettling Words</button>";
      597      }
      598  
      599 +    // Update the "(N available)" hint for a single prompt, pl
          +us re-gate                                                    
      600 +    // the Inspiration / Unsettling Words buttons on the same 
          +prompt.                                                       
      601 +    function onLuckChange(inputId) {                          
      602 +      refreshLuckAvailability(inputId);                       
      603 +      enableLuckButtons(inputId);                             
      604 +    }                                                         
      605 +                                                              
      606 +    function refreshLuckAvailability(inputId) {               
      607 +      var srcEl = document.getElementById('luck-src-' + inputI
          +d);                                                           
      608 +      var availEl = document.getElementById('luck-avail-' + in
          +putId);                                                       
      609 +      if (!srcEl || !availEl) return;                         
      610 +      availEl.textContent = '(' + luckSourceAmount(srcEl.value
          +) + ' available)';                                            
      611 +    }                                                         
      612 +                                                              
      613 +    // Keep every visible luck hint in sync with the cache; ca
          +lled after                                                    
      614 +    // each spend so concurrently-visible prompts (e.g. multip
          +le saves                                                      
      615 +    // during Start of Turn) don't still show the stale total.
      616 +    function refreshAllLuckAvailability() {                   
      617 +      var nodes = document.querySelectorAll('[data-luck-avail-
          +for]');                                                       
      618 +      for (var i = 0; i < nodes.length; i++) {                
      619 +        refreshLuckAvailability(nodes[i].getAttribute('data-lu
          +ck-avail-for'));                                              
      620 +      }                                                       
      621 +    }                                                         
      622 +                                                              
      623      function enableLuckButtons(inputId) {
      624        var ctx = rollContexts[inputId];
      625        var srcEl = document.getElementById('luck-src-' + inputI
           d);

● Now refresh all luck hints after a spend.

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 1 line
      666            break;
      667          }
      668        }
      669 +      refreshAllLuckAvailability();                           
      670        var ins = document.getElementById('luck-ins-' + inputId)
           ;
      671        var uw  = document.getElementById('luck-uw-' + inputId);
      672        if (ins) ins.style.display = 'none';

  Searched for 1 pattern (ctrl+o to expand)

● Now update each site — luck picker goes before the Successes input, Roll
  buttons stay after it. Let me view each call site and reorder.

  Read 1 file (ctrl+o to expand)

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 2 lines, removed 1 line
      445          return '<div style="margin:6px 0;padding:4px 6px;borde
           r-left:3px solid #ddd;">' +
      446            '<strong>Save vs ' + cond.label + '</strong> <span c
           lass="math-detail">(severity ' + cond.value + ')</span>' +
      447            '<br><span class="math-detail">Roll ' + cond.dice + 
           ' dice at TN ' + cond.tn + '</span>' + tnSuffix +
      448 +          '<br>' + luckPickerHtml(inputId) +                  
      449            '<br><label>Successes: <input type="number" id="' + 
           inputId + '" min="0" max="' + cond.dice + '" value="0" style="
           width:50px;"></label>' +
      449 -          ' ' + rollRowHtml({dice: cond.dice, tn: cond.tn, inp
          -utId: inputId, rollsId: rollsId, signed: false, targetName: cu
          -rrentCharName}) +                                             
      450 +          ' ' + rollButtonsHtml({dice: cond.dice, tn: cond.tn,
          + inputId: inputId, rollsId: rollsId, signed: false, targetName
          +: currentCharName}) +                                         
      451            '<div id="' + rollsId + '" class="math-detail" style
           ="margin-top:4px;"></div>' +
      452            '</div>';
      453        }).join('');

  Read 1 file (ctrl+o to expand)

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 2 lines, removed 1 line
      897        var maxDice = Math.min(currentHealingDice, diceRemaining
           );
      898        if (isNaN(dice) || dice < 1 || dice > maxDice) { alert('
           Enter 1-' + maxDice + '.'); return; }
      899        addStep('<strong>Stabilize Roll</strong>: ' + dice + ' d
           ice, TN ' + tn +
      900 +        '<br>' + luckPickerHtml('stabilize-successes') +      
      901          '<br><label>Successes: <input type="number" id="stabil
           ize-successes" min="0" value="0" style="width:50px;"></label>'
            +
      902          ' <button class="action-btn" onclick="showStabilizeSum
           mary(\'' + spellName.replace(/'/g, "\\'") + '\', ' + spellTier
            + ', ' + targetId + ', ' + dice + ')">Next</button>' +
      902 -        ' ' + rollRowHtml({dice: dice, tn: tn, inputId: 'stabi
          -lize-successes', rollsId: 'stabilize-roll-display', signed: fa
          -lse, targetName: currentCharName}) +                          
      903 +        ' ' + rollButtonsHtml({dice: dice, tn: tn, inputId: 's
          +tabilize-successes', rollsId: 'stabilize-roll-display', signed
          +: false, targetName: currentCharName}) +                      
      904          '<div id="stabilize-roll-display" class="math-detail" 
           style="margin-top:4px;"></div>');
      905      }
      906  

  Read 1 file (ctrl+o to expand)

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 3 lines, removed 2 lines
      1138          ' = ' + p.raw_tn + (p.raw_tn !== p.tn ? ' (clamped to
             ' + p.tn + ')' : '');
      1139        var html =
      1140          '<div class="math-detail">Roll ' + p.dice + 'd at TN 
            ' + p.tn + ' <em>(' + tnDetail + ')</em></div>' +
      1141 -        '<label style="margin-top:4px;display:inline-block;">
           -Net (successes − failures): ' +                              
      1141 +        luckPickerHtml('bi-net') +                           
      1142 +        '<br><label style="margin-top:4px;display:inline-bloc
           +k;">Net (successes − failures): ' +                          
      1143            '<input type="number" id="bi-net" value="0" style="
            width:60px;">' +
      1144          '</label>' +
      1144 -        ' ' + rollRowHtml({dice: p.dice, tn: p.tn, inputId: '
           -bi-net', rollsId: 'bi-rolls', signed: true, targetName: curre
           -ntCharName}) +                                               
      1145 +        ' ' + rollButtonsHtml({dice: p.dice, tn: p.tn, inputI
           +d: 'bi-net', rollsId: 'bi-rolls', signed: true, targetName: c
           +urrentCharName}) +                                           
      1146          '<div id="bi-rolls" class="math-detail" style="margin
            -top:4px;"></div>' +
      1147          '<br><button class="action-btn" onclick="submitBardic
            Inspiration()" style="margin-top:8px;">Confirm Perform</butto
            n>';
      1148        document.getElementById('bi-roll-area').innerHTML = htm
            l;

● Now the attack/defense/ally/heal sites.

  Read 1 file (ctrl+o to expand)

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 2 lines, removed 1 line
      1548        var rollDice = attackState.attackDiceOverride || attack
            State.attackDice;
      1549        var diceNote = attackState.attackDiceOverride ? ' (redu
            ced from ' + attackState.attackDice + ')' : '';
      1550        addStep('<strong>Attack Roll</strong>: ' + rollDice + '
             dice' + diceNote + ', TN ' + attackState.attackTn +
      1551 +        '<br>' + luckPickerHtml('attack-successes-input') +  
      1552          '<br><label>Attack successes: <input type="number" id
            ="attack-successes-input" min="0" value="0" style="width:50px
            ;"></label>' +
      1553          ' <button class="action-btn" onclick="confirmAttackSu
            ccesses()">Confirm</button>' +
      1553 -        ' ' + rollRowHtml({dice: rollDice, tn: attackState.at
           -tackTn, inputId: 'attack-successes-input', rollsId: 'attack-r
           -oll-display', signed: false, targetName: currentCharName}) + 
      1554 +        ' ' + rollButtonsHtml({dice: rollDice, tn: attackStat
           +e.attackTn, inputId: 'attack-successes-input', rollsId: 'atta
           +ck-roll-display', signed: false, targetName: currentCharName}
           +) +                                                          
      1555          '<div id="attack-roll-display" class="math-detail" st
            yle="margin-top:4px;"></div>');
      1556      }
      1557  

  Read 1 file (ctrl+o to expand)

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 6 lines, removed 3 lines
      1577      // --- Defense roll steps ---
      1578      function showDodgeRoll() {
      1579        addStep('<strong>Dodge Roll</strong>: ' + attackState.d
            efenseDice + ' dice, TN ' + attackState.dodgeTn +
      1580 +        '<br>' + luckPickerHtml('defense-successes-input') + 
      1581          '<br><label>Dodge successes: <input type="number" id=
            "defense-successes-input" min="0" value="0" style="width:50px
            ;"></label>' +
      1582          ' <button class="action-btn" onclick="confirmDefenseS
            uccesses()">Confirm</button>' +
      1582 -        ' ' + rollRowHtml({dice: attackState.defenseDice, tn:
           - attackState.dodgeTn, inputId: 'defense-successes-input', rol
           -lsId: 'defense-roll-display', signed: false, targetName: atta
           -ckState.target.name}) +                                      
      1583 +        ' ' + rollButtonsHtml({dice: attackState.defenseDice,
           + tn: attackState.dodgeTn, inputId: 'defense-successes-input',
           + rollsId: 'defense-roll-display', signed: false, targetName: 
           +attackState.target.name}) +                                  
      1584          '<div id="defense-roll-display" class="math-detail" s
            tyle="margin-top:4px;"></div>');
      1585      }
      1586  
      1587      function showParryRoll() {
      1588        addStep('<strong>Parry Roll</strong>: ' + attackState.p
            arryDice + ' dice, TN ' + attackState.parryTn +
      1589 +        '<br>' + luckPickerHtml('defense-successes-input') + 
      1590          '<br><label>Parry successes: <input type="number" id=
            "defense-successes-input" min="0" value="0" style="width:50px
            ;"></label>' +
      1591          ' <button class="action-btn" onclick="confirmDefenseS
            uccesses()">Confirm</button>' +
      1590 -        ' ' + rollRowHtml({dice: attackState.parryDice, tn: a
           -ttackState.parryTn, inputId: 'defense-successes-input', rolls
           -Id: 'defense-roll-display', signed: false, targetName: attack
           -State.target.name}) +                                        
      1592 +        ' ' + rollButtonsHtml({dice: attackState.parryDice, t
           +n: attackState.parryTn, inputId: 'defense-successes-input', r
           +ollsId: 'defense-roll-display', signed: false, targetName: at
           +tackState.target.name}) +                                    
      1593          '<div id="defense-roll-display" class="math-detail" s
            tyle="margin-top:4px;"></div>');
      1594      }
      1595  
      1596      function showBlockRoll() {
      1597        addStep('<strong>Block Roll</strong>: ' + attackState.b
            lockDice + ' dice, TN ' + attackState.blockTn +
      1598 +        '<br>' + luckPickerHtml('defense-successes-input') + 
      1599          '<br><label>Block successes: <input type="number" id=
            "defense-successes-input" min="0" value="0" style="width:50px
            ;"></label>' +
      1600          ' <button class="action-btn" onclick="confirmDefenseS
            uccesses()">Confirm</button>' +
      1598 -        ' ' + rollRowHtml({dice: attackState.blockDice, tn: a
           -ttackState.blockTn, inputId: 'defense-successes-input', rolls
           -Id: 'defense-roll-display', signed: false, targetName: attack
           -State.target.name}) +                                        
      1601 +        ' ' + rollButtonsHtml({dice: attackState.blockDice, t
           +n: attackState.blockTn, inputId: 'defense-successes-input', r
           +ollsId: 'defense-roll-display', signed: false, targetName: at
           +tackState.target.name}) +                                    
      1602          '<div id="defense-roll-display" class="math-detail" s
            tyle="margin-top:4px;"></div>');
      1603      }
      1604  
  Read 1 file (ctrl+o to expand)

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 2 lines, removed 1 line
      1635          blockTn);
      1636        addStep('<strong>' + (caster ? caster.name : 'Ally') + 
            ' blocks with Shield of Faith</strong>: ' + ally.dice + ' dic
            e' +
      1637          '<br><span class="math-detail">' + tnMath + '</span>'
             +
      1638 +        '<br>' + luckPickerHtml('ally-block-successes') +    
      1639          '<br><label>Block successes: <input type="number" id=
            "ally-block-successes" min="0" value="0" style="width:50px;">
            </label>' +
      1640          ' <button class="action-btn" onclick="confirmAllyBloc
            kSuccesses()">Confirm</button>' +
      1640 -        ' ' + rollRowHtml({dice: ally.dice, tn: blockTn, inpu
           -tId: 'ally-block-successes', rollsId: 'ally-block-display', s
           -igned: false, targetName: (caster ? caster.name : 'Ally')}) +
      1641 +        ' ' + rollButtonsHtml({dice: ally.dice, tn: blockTn, 
           +inputId: 'ally-block-successes', rollsId: 'ally-block-display
           +', signed: false, targetName: (caster ? caster.name : 'Ally')
           +}) +                                                         
      1642          '<div id="ally-block-display" class="math-detail" sty
            le="margin-top:4px;"></div>');
      1643      }
      1644  

  Read 1 file (ctrl+o to expand)

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 2 lines, removed 1 line
      1769        attackState.healingWordActions.push({combat_id: cid, di
            ce: dice});
      1770  
      1771        addStep('<strong>' + healer.name + ' rolls Healing Word
            </strong>: ' + dice + ' dice, TN ' + healTn +
      1772 +        '<br>' + luckPickerHtml('hw-successes') +            
      1773          '<br><label>Successes (each reduces damage by 1): <in
            put type="number" id="hw-successes" min="0" value="0" style="
            width:50px;"></label>' +
      1774          ' <button class="action-btn" onclick="confirmHealingW
            ordSuccesses()">Confirm</button>' +
      1774 -        ' ' + rollRowHtml({dice: dice, tn: healTn, inputId: '
           -hw-successes', rollsId: 'hw-roll-display', signed: false, tar
           -getName: healer.name}) +                                     
      1775 +        ' ' + rollButtonsHtml({dice: dice, tn: healTn, inputI
           +d: 'hw-successes', rollsId: 'hw-roll-display', signed: false,
           + targetName: healer.name}) +                                 
      1776          '<div id="hw-roll-display" class="math-detail" style=
            "margin-top:4px;"></div>');
      1777      }
      1778  

  Searched for 1 pattern (ctrl+o to expand)

● All sites migrated. Syntax-check.

● Bash(ruby -r erb -e 'ERB.new(File.read("views/combat_tracker.erb"), trim_mode:
       "-").src; puts "ERB OK"')
  ⎿  ERB OK

● Bash(git diff --stat && git add views/combat_tracker.erb && git commit -m
      "$(cat <<'EOF'
      Luck prompt precedes successes; show remaining; auto-pick sole source…)
  ⎿   views/combat_tracker.erb | 111 ++++++++++++++++++++++++++++++++++----
     ---------
      1 file changed, 81 insertions(+), 30 deletions(-)
     … +6 lines (ctrl+o to expand)

● Pushed.

  What changed

  - Every roll prompt now shows Spend luck: <source> [0] (N available) on its
  own line before the Successes input.
  - When only one source has luck (typical case: just Cottonballs, or just the
  DM), the source renders as bold static text + a hidden input; no one-option
  dropdown.
  - The (N available) hint lives next to the amount field, updates on source
  change, and refreshes across every visible prompt after a spend — so Start of
  Turn with multiple saves doesn't leave stale totals behind.
  - rollRowHtml is now two helpers — luckPickerHtml(inputId) placed ahead of the
   Successes input, and rollButtonsHtml(cfg) placed after Confirm alongside Roll
   / Inspiration / Unsettling Words.

  ERB parses clean; committed and pushed to
  claude/bard-luck-reroll-mechanic-3DFmV. Worth a quick live check that: (a) the
   single-source case looks right on a fresh combat where only Cottonballs has
  luck, and (b) two Start-of-Turn saves visible at once both reflect the same
  updated availability after one Inspiration spend.

❯ When I use Inspiration or Unsettling words I want to see the original roll,   
  so please just roll the additional dice and adjust the results accordingly.   
  This way I can verify the results are correct.                                

● Makes sense. I'll keep the original dice on display and append the reroll as a
   second line so the math is verifiable.

  Read 1 file (ctrl+o to expand)

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 53 lines, removed 15 lines
      494      // defense/ally/healing/condition saves). Saves the raw di
           ce in
      495      // rollContexts[inputId] so Inspiration/Unsettling Words c
           an reroll
      496      // specific dice later. signed=true writes negative net in
           to the
      497 -    // input (used by Perform); signed=false floors at 0.     
      497 +    // input (used by Perform); signed=false floors at 0. Pres
          +erves the                                                     
      498 +    // original dice in originalRolls; applyLuckReroll attache
          +s a                                                           
      499 +    // separate `reroll` entry so the original line stays read
          +able.                                                         
      500      var rollContexts = {};
      501      function rollDicePool(dice, tn, inputId, rollsId, signed) 
           {
      502        var rolls = [];
      503        for (var r = 0; r < dice; r++) rolls.push(Math.floor(Mat
           h.random() * 10) + 1);
      502 -      rollContexts[inputId] = {rolls: rolls, tn: tn, rollsId: 
          -rollsId, signed: !!signed};                                   
      504 +      rollContexts[inputId] = {originalRolls: rolls, tn: tn, r
          +ollsId: rollsId, signed: !!signed, reroll: null};             
      505        paintRollResult(inputId);
      506        enableLuckButtons(inputId);
      507      }
     ...
      516        return s;
      517      }
      518  
      519 +    function colorizeDie(d, tn) {                             
      520 +      var bg = null;                                          
      521 +      if (d === 1) bg = '#e57373';                            
      522 +      else if (d === 10) bg = '#64b5f6';                      
      523 +      else if (d >= tn) bg = '#81c784';                       
      524 +      if (bg) return '<span style="background:' + bg + ';color
          +:#000;padding:1px 6px;border-radius:3px;font-weight:bold;">' +
          + d + '</span>';                                               
      525 +      return '<span style="color:#777;">' + d + '</span>';    
      526 +    }                                                         
      527 +                                                              
      528 +    function successLabel(successes, signed) {                
      529 +      var display = signed ? successes : Math.max(0, successes
          +);                                                            
      530 +      if (signed) return 'net ' + (display >= 0 ? '+' : '') + 
          +display;                                                      
      531 +      return display + ' success' + (display === 1 ? '' : 'es'
          +) +                                                           
      532 +        (successes < 0 ? ' <span class="math-detail">(raw ' + 
          +successes + ', floored)</span>' : '');                        
      533 +    }                                                         
      534 +                                                              
      535 +    // Render the original roll, and if a reroll has been appl
          +ied, append                                                   
      536 +    // a second line showing which dice got replaced and the a
          +djusted                                                       
      537 +    // total. The DM can cross-check the math without losing t
          +he initial                                                    
      538 +    // outcome.                                               
      539      function paintRollResult(inputId) {
      540        var ctx = rollContexts[inputId];
      541        if (!ctx) return;
      520 -      var raw = countRollSuccesses(ctx.rolls, ctx.tn);        
      521 -      var display = ctx.signed ? raw : Math.max(0, raw);      
      542 +      var origRolls = ctx.originalRolls;                      
      543 +      var origSuccesses = countRollSuccesses(origRolls, ctx.tn
          +);                                                            
      544 +                                                              
      545 +      // Build effective rolls (apply reroll replacements).   
      546 +      var effective = origRolls.slice();                      
      547 +      if (ctx.reroll) {                                       
      548 +        ctx.reroll.indices.forEach(function(idx, k) {         
      549 +          effective[idx] = ctx.reroll.newValues[k];           
      550 +        });                                                   
      551 +      }                                                       
      552 +      var finalSuccesses = ctx.reroll ? countRollSuccesses(eff
          +ective, ctx.tn) : origSuccesses;                              
      553 +                                                              
      554        var inputEl = document.getElementById(inputId);
      523 -      if (inputEl) inputEl.value = display;                   
      555 +      if (inputEl) inputEl.value = ctx.signed ? finalSuccesses
          + : Math.max(0, finalSuccesses);                               
      556 +                                                              
      557        var rollsEl = document.getElementById(ctx.rollsId);
      558        if (!rollsEl) return;
      526 -      var colored = ctx.rolls.map(function(d) {               
      527 -        var bg = null;                                        
      528 -        if (d === 1) bg = '#e57373';                          
      529 -        else if (d === 10) bg = '#64b5f6';                    
      530 -        else if (d >= ctx.tn) bg = '#81c784';                 
      531 -        if (bg) return '<span style="background:' + bg + ';col
          -or:#000;padding:1px 6px;border-radius:3px;font-weight:bold;">'
          - + d + '</span>';                                             
      532 -        return '<span style="color:#777;">' + d + '</span>';  
      559 +      var origColored = origRolls.map(function(d, i) {        
      560 +        var replaced = ctx.reroll && ctx.reroll.indices.indexO
          +f(i) !== -1;                                                  
      561 +        var span = colorizeDie(d, ctx.tn);                    
      562 +        return replaced ? '<s style="opacity:0.6;">' + span + 
          +'</s>' : span;                                                
      563        }).join(', ');
      534 -      var label = ctx.signed ? ('net ' + (display >= 0 ? '+' :
          - '') + display)                                               
      535 -        : (display + ' success' + (display === 1 ? '' : 'es') 
          -+ (raw < 0 ? ' <span class="math-detail">(raw ' + raw + ', flo
          -ored)</span>' : ''));                                         
      536 -      rollsEl.innerHTML = 'Rolled: [' + colored + '] &rarr; ' 
          -+ label;                                                      
      564 +      var html = 'Rolled: [' + origColored + '] &rarr; ' + suc
          +cessLabel(origSuccesses, ctx.signed);                         
      565 +      if (ctx.reroll) {                                       
      566 +        var newColored = ctx.reroll.newValues.map(function(d) 
          +{ return colorizeDie(d, ctx.tn); }).join(', ');               
      567 +        var abilityLabel = ctx.reroll.ability === 'inspiration
          +' ? 'Inspiration' : 'Unsettling Words';                       
      568 +        var delta = finalSuccesses - origSuccesses;           
      569 +        var deltaText = (delta >= 0 ? '+' : '') + delta;      
      570 +        html += '<br>' + abilityLabel + ' rerolled ' + ctx.rer
          +oll.indices.length +                                          
      571 +          ' &rarr; [' + newColored + '] &rarr; ' + successLabe
          +l(finalSuccesses, ctx.signed) +                               
      572 +          ' <span class="math-detail">(' + deltaText + ')</spa
          +n>';                                                          
      573 +      }                                                       
      574 +      rollsEl.innerHTML = html;                               
      575      }
      576  
      577      function rollSaveDice(i, inputId, rollsId) {

● Now update applyLuckReroll to write to ctx.reroll instead of mutating
  ctx.rolls.

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 7 lines, removed 3 lines
      687        var src = srcEl ? srcEl.value : '';
      688        if (amt <= 0 || !src) { alert('Pick a luck source and am
           ount first.'); return; }
      689        if (amt > luckSourceAmount(src)) { alert('That source on
           ly has ' + luckSourceAmount(src) + ' luck.'); return; }
      690 -      var n = Math.min(amt, ctx.rolls.length);                
      691 -      var indexed = ctx.rolls.map(function(v, i) { return {v: 
          -v, i: i}; });                                                 
      690 +      var n = Math.min(amt, ctx.originalRolls.length);        
      691 +      var indexed = ctx.originalRolls.map(function(v, i) { ret
          +urn {v: v, i: i}; });                                         
      692        indexed.sort(function(a, b) { return ability === 'inspir
           ation' ? a.v - b.v : b.v - a.v; });
      693 +      var indices = [];                                       
      694 +      var newValues = [];                                     
      695        for (var k = 0; k < n; k++) {
      694 -        ctx.rolls[indexed[k].i] = Math.floor(Math.random() * 1
          -0) + 1;                                                       
      696 +        indices.push(indexed[k].i);                           
      697 +        newValues.push(Math.floor(Math.random() * 10) + 1);   
      698        }
      699 +      ctx.reroll = {ability: ability, indices: indices, newVal
          +ues: newValues};                                              
      700        paintRollResult(inputId);
      701        var fd = new FormData();
      702        fd.append('amount', amt);

● Bash(ruby -r erb -e 'ERB.new(File.read("views/combat_tracker.erb"), trim_mode:
       "-").src; puts "ERB OK"')
  ⎿  ERB OK

● Bash(git add views/combat_tracker.erb && git commit -m "$(cat <<'EOF'
      Show original roll alongside luck reroll for verifiability…)
  ⎿  [claude/bard-luck-reroll-mechanic-3DFmV 8a668bc] Show original roll al
     ongside luck reroll for verifiability
      1 file changed, 60 insertions(+), 18 deletions(-)
     … +3 lines (ctrl+o to expand)

● Pushed.

  What changed

  - rollContexts[inputId] now stores originalRolls (immutable) and an optional
  reroll entry with indices + newValues. The original dice line is never
  overwritten.
  - After Inspiration / Unsettling Words, the display becomes:
    - Line 1: the original roll, with replaced indices shown struck-through
  (coloring preserved so you can see what got dropped).
    - Line 2: Inspiration rerolled N → [new dice] → M successes (+delta).
  - Success count in the input comes from the effective pool (original with
  replacements applied), matching what actually counts — but the original
  successes are still printed on line 1 so you can verify the math.

  Live-check suggestion: roll 5 dice, Inspiration with 2 luck. You should see
  the two lowest crossed out on line 1, two new colored dice on line 2, and a
  delta like (+1) reflecting whatever the reroll netted.

❯ This is looking much better. When you ask me how many luck dice to use ask me 
   to confirm before asking for succesess                                       
● Got it — adding a Confirm Luck gate between the luck input and the successes
  UI.

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 29 lines
      593      // (or the DM) has luck, the source is shown as static tex
           t instead
      594      // of a dropdown. The "N available" span is refreshed acro
           ss every
      595      // visible prompt after a spend so multi-save screens stay
            accurate.
      596 +    // Includes a Confirm Luck button that reveals the success
          +es + roll                                                     
      597 +    // UI (wrapped in postLuckOpen/Close at each call site) --
          + gating the                                                   
      598 +    // luck decision before the dice get rolled.              
      599      function luckPickerHtml(inputId) {
      600        var sources = luckSourceCache.filter(function(s) { retur
           n s.amount > 0; });
      601        if (sources.length === 0) return '';
     ...
      603        var srcId = 'luck-src-' + iid;
      604        var amtId = 'luck-amt-' + iid;
      605        var availId = 'luck-avail-' + iid;
      606 +      var confirmId = 'luck-confirm-' + iid;                  
      607        var refresh = "onLuckChange('" + iid + "')";
      608        var sourceField;
      609        if (sources.length === 1) {
     ...
      621          sourceField +
      622          ' <input type="number" id="' + amtId + '" min="0" valu
           e="0" data-luck-amt="1" style="width:42px;font-size:12px;" oni
           nput="' + refresh + '">' +
      623          ' <span id="' + availId + '" data-luck-avail-for="' + 
           iid + '" style="font-size:11px;color:#6b5800;">(' + initial + 
           ' available)</span>' +
      624 +        ' <button class="action-btn" id="' + confirmId + '" st
          +yle="font-size:11px;padding:1px 6px;" onclick="confirmLuck(\''
          + + iid + '\')">Confirm Luck</button>' +                       
      625          '</div>';
      626      }
      627  
      628 +    function hasLuckSources() {                               
      629 +      return luckSourceCache.some(function(s) { return s.amoun
          +t > 0; });                                                    
      630 +    }                                                         
      631 +                                                              
      632 +    // Wrapper that hides the successes input, Roll button, an
          +d roll                                                        
      633 +    // display until the DM clicks Confirm Luck. When no luck 
          +is                                                            
      634 +    // available (or already spent down), the wrapper starts v
          +isible --                                                     
      635 +    // there's nothing to confirm.                            
      636 +    function postLuckOpen(inputId) {                          
      637 +      var initial = hasLuckSources() ? 'none' : 'block';      
      638 +      return '<div id="post-luck-' + inputId + '" style="displ
          +ay:' + initial + ';">';                                       
      639 +    }                                                         
      640 +                                                              
      641 +    function postLuckClose() {                                
      642 +      return '</div>';                                        
      643 +    }                                                         
      644 +                                                              
      645 +    function confirmLuck(inputId) {                           
      646 +      var wrapper = document.getElementById('post-luck-' + inp
          +utId);                                                        
      647 +      if (wrapper) wrapper.style.display = 'block';           
      648 +      var btn = document.getElementById('luck-confirm-' + inpu
          +tId);                                                         
      649 +      if (btn) btn.style.display = 'none';                    
      650 +    }                                                         
      651 +                                                              
      652      // Post-successes roll buttons: Roll (always) plus hidden 
           Inspiration /
      653      // Unsettling Words. The reroll buttons reveal themselves 
           once dice
      654      // have been rolled AND the luck picker has a valid source
            + amount.

● Now wrap each of the 9 roll sites.

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 5 lines, removed 3 lines
      446            '<strong>Save vs ' + cond.label + '</strong> <span c
           lass="math-detail">(severity ' + cond.value + ')</span>' +
      447            '<br><span class="math-detail">Roll ' + cond.dice + 
           ' dice at TN ' + cond.tn + '</span>' + tnSuffix +
      448            '<br>' + luckPickerHtml(inputId) +
      449 -          '<br><label>Successes: <input type="number" id="' + 
          -inputId + '" min="0" max="' + cond.dice + '" value="0" style="
          -width:50px;"></label>' +                                      
      450 -          ' ' + rollButtonsHtml({dice: cond.dice, tn: cond.tn,
          - inputId: inputId, rollsId: rollsId, signed: false, targetName
          -: currentCharName}) +                                         
      451 -          '<div id="' + rollsId + '" class="math-detail" style
          -="margin-top:4px;"></div>' +                                  
      449 +          postLuckOpen(inputId) +                             
      450 +            '<label>Successes: <input type="number" id="' + in
          +putId + '" min="0" max="' + cond.dice + '" value="0" style="wi
          +dth:50px;"></label>' +                                        
      451 +            ' ' + rollButtonsHtml({dice: cond.dice, tn: cond.t
          +n, inputId: inputId, rollsId: rollsId, signed: false, targetNa
          +me: currentCharName}) +                                       
      452 +            '<div id="' + rollsId + '" class="math-detail" sty
          +le="margin-top:4px;"></div>' +                                
      453 +          postLuckClose() +                                   
      454            '</div>';
      455        }).join('');
      456        addStep('<strong>Start of Turn</strong>: ' + currentChar
           Name + ' has ' +

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 6 lines, removed 4 lines
      971        if (isNaN(dice) || dice < 1 || dice > maxDice) { alert('
           Enter 1-' + maxDice + '.'); return; }
      972        addStep('<strong>Stabilize Roll</strong>: ' + dice + ' d
           ice, TN ' + tn +
      973          '<br>' + luckPickerHtml('stabilize-successes') +
      974 -        '<br><label>Successes: <input type="number" id="stabil
          -ize-successes" min="0" value="0" style="width:50px;"></label>'
          - +                                                            
      975 -        ' <button class="action-btn" onclick="showStabilizeSum
          -mary(\'' + spellName.replace(/'/g, "\\'") + '\', ' + spellTier
          - + ', ' + targetId + ', ' + dice + ')">Next</button>' +       
      976 -        ' ' + rollButtonsHtml({dice: dice, tn: tn, inputId: 's
          -tabilize-successes', rollsId: 'stabilize-roll-display', signed
          -: false, targetName: currentCharName}) +                      
      977 -        '<div id="stabilize-roll-display" class="math-detail" 
          -style="margin-top:4px;"></div>');                             
      974 +        postLuckOpen('stabilize-successes') +                 
      975 +          '<label>Successes: <input type="number" id="stabiliz
          +e-successes" min="0" value="0" style="width:50px;"></label>' +
      976 +          ' <button class="action-btn" onclick="showStabilizeS
          +ummary(\'' + spellName.replace(/'/g, "\\'") + '\', ' + spellTi
          +er + ', ' + targetId + ', ' + dice + ')">Next</button>' +     
      977 +          ' ' + rollButtonsHtml({dice: dice, tn: tn, inputId: 
          +'stabilize-successes', rollsId: 'stabilize-roll-display', sign
          +ed: false, targetName: currentCharName}) +                    
      978 +          '<div id="stabilize-roll-display" class="math-detail
          +" style="margin-top:4px;"></div>' +                           
      979 +        postLuckClose());                                     
      980      }
      981  
      982      function showStabilizeSummary(spellName, spellTier, target
           Id, dice) {

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 8 lines, removed 6 lines
      1214        var html =
      1215          '<div class="math-detail">Roll ' + p.dice + 'd at TN 
            ' + p.tn + ' <em>(' + tnDetail + ')</em></div>' +
      1216          luckPickerHtml('bi-net') +
      1217 -        '<br><label style="margin-top:4px;display:inline-bloc
           -k;">Net (successes − failures): ' +                          
      1218 -          '<input type="number" id="bi-net" value="0" style="
           -width:60px;">' +                                             
      1219 -        '</label>' +                                         
      1220 -        ' ' + rollButtonsHtml({dice: p.dice, tn: p.tn, inputI
           -d: 'bi-net', rollsId: 'bi-rolls', signed: true, targetName: c
           -urrentCharName}) +                                           
      1221 -        '<div id="bi-rolls" class="math-detail" style="margin
           --top:4px;"></div>' +                                         
      1222 -        '<br><button class="action-btn" onclick="submitBardic
           -Inspiration()" style="margin-top:8px;">Confirm Perform</butto
           -n>';                                                         
      1217 +        postLuckOpen('bi-net') +                             
      1218 +          '<label style="margin-top:4px;display:inline-block;
           +">Net (successes − failures): ' +                            
      1219 +            '<input type="number" id="bi-net" value="0" style
           +="width:60px;">' +                                           
      1220 +          '</label>' +                                       
      1221 +          ' ' + rollButtonsHtml({dice: p.dice, tn: p.tn, inpu
           +tId: 'bi-net', rollsId: 'bi-rolls', signed: true, targetName:
           + currentCharName}) +                                         
      1222 +          '<div id="bi-rolls" class="math-detail" style="marg
           +in-top:4px;"></div>' +                                       
      1223 +          '<br><button class="action-btn" onclick="submitBard
           +icInspiration()" style="margin-top:8px;">Confirm Perform</but
           +ton>' +                                                      
      1224 +        postLuckClose();                                     
      1225        document.getElementById('bi-roll-area').innerHTML = htm
            l;
      1226      }
      1227  

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 6 lines, removed 4 lines
      1626        var diceNote = attackState.attackDiceOverride ? ' (redu
            ced from ' + attackState.attackDice + ')' : '';
      1627        addStep('<strong>Attack Roll</strong>: ' + rollDice + '
             dice' + diceNote + ', TN ' + attackState.attackTn +
      1628          '<br>' + luckPickerHtml('attack-successes-input') +
      1629 -        '<br><label>Attack successes: <input type="number" id
           -="attack-successes-input" min="0" value="0" style="width:50px
           -;"></label>' +                                               
      1630 -        ' <button class="action-btn" onclick="confirmAttackSu
           -ccesses()">Confirm</button>' +                               
      1631 -        ' ' + rollButtonsHtml({dice: rollDice, tn: attackStat
           -e.attackTn, inputId: 'attack-successes-input', rollsId: 'atta
           -ck-roll-display', signed: false, targetName: currentCharName}
           -) +                                                          
      1632 -        '<div id="attack-roll-display" class="math-detail" st
           -yle="margin-top:4px;"></div>');                              
      1629 +        postLuckOpen('attack-successes-input') +             
      1630 +          '<label>Attack successes: <input type="number" id="
           +attack-successes-input" min="0" value="0" style="width:50px;"
           +></label>' +                                                 
      1631 +          ' <button class="action-btn" onclick="confirmAttack
           +Successes()">Confirm</button>' +                             
      1632 +          ' ' + rollButtonsHtml({dice: rollDice, tn: attackSt
           +ate.attackTn, inputId: 'attack-successes-input', rollsId: 'at
           +tack-roll-display', signed: false, targetName: currentCharNam
           +e}) +                                                        
      1633 +          '<div id="attack-roll-display" class="math-detail" 
           +style="margin-top:4px;"></div>' +                            
      1634 +        postLuckClose());                                    
      1635      }
      1636  
      1637      function confirmAttackSuccesses() {

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 18 lines, removed 12 lines
      1657      function showDodgeRoll() {
      1658        addStep('<strong>Dodge Roll</strong>: ' + attackState.d
            efenseDice + ' dice, TN ' + attackState.dodgeTn +
      1659          '<br>' + luckPickerHtml('defense-successes-input') +
      1660 -        '<br><label>Dodge successes: <input type="number" id=
           -"defense-successes-input" min="0" value="0" style="width:50px
           -;"></label>' +                                               
      1661 -        ' <button class="action-btn" onclick="confirmDefenseS
           -uccesses()">Confirm</button>' +                              
      1662 -        ' ' + rollButtonsHtml({dice: attackState.defenseDice,
           - tn: attackState.dodgeTn, inputId: 'defense-successes-input',
           - rollsId: 'defense-roll-display', signed: false, targetName: 
           -attackState.target.name}) +                                  
      1663 -        '<div id="defense-roll-display" class="math-detail" s
           -tyle="margin-top:4px;"></div>');                             
      1660 +        postLuckOpen('defense-successes-input') +            
      1661 +          '<label>Dodge successes: <input type="number" id="d
           +efense-successes-input" min="0" value="0" style="width:50px;"
           +></label>' +                                                 
      1662 +          ' <button class="action-btn" onclick="confirmDefens
           +eSuccesses()">Confirm</button>' +                            
      1663 +          ' ' + rollButtonsHtml({dice: attackState.defenseDic
           +e, tn: attackState.dodgeTn, inputId: 'defense-successes-input
           +', rollsId: 'defense-roll-display', signed: false, targetName
           +: attackState.target.name}) +                                
      1664 +          '<div id="defense-roll-display" class="math-detail"
           + style="margin-top:4px;"></div>' +                           
      1665 +        postLuckClose());                                    
      1666      }
      1667  
      1668      function showParryRoll() {
      1669        addStep('<strong>Parry Roll</strong>: ' + attackState.p
            arryDice + ' dice, TN ' + attackState.parryTn +
      1670          '<br>' + luckPickerHtml('defense-successes-input') +
      1669 -        '<br><label>Parry successes: <input type="number" id=
           -"defense-successes-input" min="0" value="0" style="width:50px
           -;"></label>' +                                               
      1670 -        ' <button class="action-btn" onclick="confirmDefenseS
           -uccesses()">Confirm</button>' +                              
      1671 -        ' ' + rollButtonsHtml({dice: attackState.parryDice, t
           -n: attackState.parryTn, inputId: 'defense-successes-input', r
           -ollsId: 'defense-roll-display', signed: false, targetName: at
           -tackState.target.name}) +                                    
      1672 -        '<div id="defense-roll-display" class="math-detail" s
           -tyle="margin-top:4px;"></div>');                             
      1671 +        postLuckOpen('defense-successes-input') +            
      1672 +          '<label>Parry successes: <input type="number" id="d
           +efense-successes-input" min="0" value="0" style="width:50px;"
           +></label>' +                                                 
      1673 +          ' <button class="action-btn" onclick="confirmDefens
           +eSuccesses()">Confirm</button>' +                            
      1674 +          ' ' + rollButtonsHtml({dice: attackState.parryDice,
           + tn: attackState.parryTn, inputId: 'defense-successes-input',
           + rollsId: 'defense-roll-display', signed: false, targetName: 
           +attackState.target.name}) +                                  
      1675 +          '<div id="defense-roll-display" class="math-detail"
           + style="margin-top:4px;"></div>' +                           
      1676 +        postLuckClose());                                    
      1677      }
      1678  
      1679      function showBlockRoll() {
      1680        addStep('<strong>Block Roll</strong>: ' + attackState.b
            lockDice + ' dice, TN ' + attackState.blockTn +
      1681          '<br>' + luckPickerHtml('defense-successes-input') +
      1678 -        '<br><label>Block successes: <input type="number" id=
           -"defense-successes-input" min="0" value="0" style="width:50px
           -;"></label>' +                                               
      1679 -        ' <button class="action-btn" onclick="confirmDefenseS
           -uccesses()">Confirm</button>' +                              
      1680 -        ' ' + rollButtonsHtml({dice: attackState.blockDice, t
           -n: attackState.blockTn, inputId: 'defense-successes-input', r
           -ollsId: 'defense-roll-display', signed: false, targetName: at
           -tackState.target.name}) +                                    
      1681 -        '<div id="defense-roll-display" class="math-detail" s
           -tyle="margin-top:4px;"></div>');                             
      1682 +        postLuckOpen('defense-successes-input') +            
      1683 +          '<label>Block successes: <input type="number" id="d
           +efense-successes-input" min="0" value="0" style="width:50px;"
           +></label>' +                                                 
      1684 +          ' <button class="action-btn" onclick="confirmDefens
           +eSuccesses()">Confirm</button>' +                            
      1685 +          ' ' + rollButtonsHtml({dice: attackState.blockDice,
           + tn: attackState.blockTn, inputId: 'defense-successes-input',
           + rollsId: 'defense-roll-display', signed: false, targetName: 
           +attackState.target.name}) +                                  
      1686 +          '<div id="defense-roll-display" class="math-detail"
           + style="margin-top:4px;"></div>' +                           
      1687 +        postLuckClose());                                    
      1688      }
      1689  
      1690      function confirmDefenseSuccesses() {

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 6 lines, removed 4 lines
      1721        addStep('<strong>' + (caster ? caster.name : 'Ally') + 
            ' blocks with Shield of Faith</strong>: ' + ally.dice + ' dic
            e' +
      1722          '<br><span class="math-detail">' + tnMath + '</span>'
             +
      1723          '<br>' + luckPickerHtml('ally-block-successes') +
      1724 -        '<br><label>Block successes: <input type="number" id=
           -"ally-block-successes" min="0" value="0" style="width:50px;">
           -</label>' +                                                  
      1725 -        ' <button class="action-btn" onclick="confirmAllyBloc
           -kSuccesses()">Confirm</button>' +                            
      1726 -        ' ' + rollButtonsHtml({dice: ally.dice, tn: blockTn, 
           -inputId: 'ally-block-successes', rollsId: 'ally-block-display
           -', signed: false, targetName: (caster ? caster.name : 'Ally')
           -}) +                                                         
      1727 -        '<div id="ally-block-display" class="math-detail" sty
           -le="margin-top:4px;"></div>');                               
      1724 +        postLuckOpen('ally-block-successes') +               
      1725 +          '<label>Block successes: <input type="number" id="a
           +lly-block-successes" min="0" value="0" style="width:50px;"></
           +label>' +                                                    
      1726 +          ' <button class="action-btn" onclick="confirmAllyBl
           +ockSuccesses()">Confirm</button>' +                          
      1727 +          ' ' + rollButtonsHtml({dice: ally.dice, tn: blockTn
           +, inputId: 'ally-block-successes', rollsId: 'ally-block-displ
           +ay', signed: false, targetName: (caster ? caster.name : 'Ally
           +')}) +                                                       
      1728 +          '<div id="ally-block-display" class="math-detail" s
           +tyle="margin-top:4px;"></div>' +                             
      1729 +        postLuckClose());                                    
      1730      }
      1731  
      1732      function confirmAllyBlockSuccesses() {

● Update(/home/user/crimson-steel/views/combat_tracker.erb)
  ⎿  Added 6 lines, removed 4 lines
      1857  
      1858        addStep('<strong>' + healer.name + ' rolls Healing Word
            </strong>: ' + dice + ' dice, TN ' + healTn +
      1859          '<br>' + luckPickerHtml('hw-successes') +
      1860 -        '<br><label>Successes (each reduces damage by 1): <in
           -put type="number" id="hw-successes" min="0" value="0" style="
           -width:50px;"></label>' +                                     
      1861 -        ' <button class="action-btn" onclick="confirmHealingW
           -ordSuccesses()">Confirm</button>' +                          
      1862 -        ' ' + rollButtonsHtml({dice: dice, tn: healTn, inputI
           -d: 'hw-successes', rollsId: 'hw-roll-display', signed: false,
           - targetName: healer.name}) +                                 
      1863 -        '<div id="hw-roll-display" class="math-detail" style=
           -"margin-top:4px;"></div>');                                  
      1860 +        postLuckOpen('hw-successes') +                       
      1861 +          '<label>Successes (each reduces damage by 1): <inpu
           +t type="number" id="hw-successes" min="0" value="0" style="wi
           +dth:50px;"></label>' +                                       
      1862 +          ' <button class="action-btn" onclick="confirmHealin
           +gWordSuccesses()">Confirm</button>' +                        
      1863 +          ' ' + rollButtonsHtml({dice: dice, tn: healTn, inpu
           +tId: 'hw-successes', rollsId: 'hw-roll-display', signed: fals
           +e, targetName: healer.name}) +                               
      1864 +          '<div id="hw-roll-display" class="math-detail" styl
           +e="margin-top:4px;"></div>' +                                
      1865 +        postLuckClose());                                    
      1866      }
      1867  
      1868      function confirmHealingWordSuccesses() {

● Bash(ruby -r erb -e 'ERB.new(File.read("views/combat_tracker.erb"), trim_mode:
       "-").src; puts "ERB OK"')
  ⎿  ERB OK

● Bash(git add views/combat_tracker.erb && git commit -m "$(cat <<'EOF'
      Gate successes UI behind Confirm Luck…)
  ⎿  [claude/bard-luck-reroll-mechanic-3DFmV f923f4a] Gate successes UI beh
     ind Confirm Luck
      1 file changed, 84 insertions(+), 37 deletions(-)
     … +3 lines (ctrl+o to expand)

● Pushed.

  What changed

  - luckPickerHtml now includes a Confirm Luck button next to the "(N
  available)" hint.
  - Two new helpers — postLuckOpen(inputId) and postLuckClose() — wrap each roll
   site's successes input, Confirm action button, Roll/Inspiration/Unsettling
  Words buttons, and roll display in a <div> that starts hidden when luck
  sources exist.
  - Clicking Confirm Luck reveals the wrapper and hides the button itself. All
  nine roll sites (saves, stabilize, perform, attack, dodge, parry, block, ally
  block, healing word) now share this gate.
  - When there's no luck to spend (no bard has a pool and DM pool is empty), the
   picker renders nothing and the wrapper starts visible — existing flow
  preserved.

  Worth a live check: on a save with Cottonballs active, confirm that the
  Successes/Roll section is hidden until you click Confirm Luck, and that a save
   with no luck sources still shows everything immediately.

● Session resumed
# Simple Combat — Four Common Orcs

The party (Ash, Lira, Thora, Garroth), each on a tablet, against four Common
Orcs the DM adds from the Sheets page. Test: `test/scenarios/simple_combat.rb`.
Outline in progress: combat, end of combat and loot are still to come.

## Starting data

`test/scenarios/data/no_monsters/`: no monsters in the encounter (the example
Wolf and Goblins are gone, their gear too), the party at full HP and mana with
no magic toxicity, phase Downtime. Everything else is the example campaign.

## Steps

1. The tablets connect; the DM assigns each its Character.
2. Check: no monsters; every PC at full HP and mana, magic toxicity 0.
3. DM goes to Sheets.
4. DM opens General Red Tier.
5. DM clicks Common Orc. General Red Tier stays expanded.
6. DM clicks the + next to Common Orc 4 times. General Red Tier stays expanded.
7. Check: four Common Orcs in the encounter, carrying exactly:

   | Orc | Melee | Ranged | Armor | Coins | Other |
   |---|---|---|---|---|---|
   | 1 | Falchion + Light metal shield | Longbow, 12 Arrows | Hide armor | 40 Copper, 25 Silver | Gem (5 gp), Necklace of animal fangs |
   | 2 | Great axe | Sling, 20 Stones | Leather armor | 30 Copper, 20 Gold | Gem (15 gp) |
   | 3 | Long sword + Light metal shield | Longbow, 10 Arrows | Breastplate | 50 Copper | Gem (25 gp) |
   | 4 | Spear | Sling, 25 Stones | — | 20 Copper | — |

   Weapons, armor and shields are equipped. Dagger and Short sword cannot
   also appear: each orc gets one melee weapon and the table has six.
8. DM goes to Encounter.
9. DM sets the phase to Combat.
10. DM clicks Start Combat.
11. Check: turn order Thora, Common Orc 1, Ash, Common Orc 2, Common Orc 3,
    Lira, Common Orc 4, Garroth; Thora is acting. Initiative dice:
    Thora `XXX9876543`, Orc 1 `XX98`, Ash `X99876543`, Orc 2 `X987`,
    Orc 3 `X986`, Lira `X9765432`, Orc 4 `9876`, Garroth `987543`.
12. Check: the orcs are numbered Common Orc 1–4 on the tablets and on the
    DM's Combat Tracker. *Fails until orc numbering lands (another thread).*
13. Thora's tablet: Cast Standard Shield on Garroth. It rolls nothing, so it
    does not hold up her next request.
14. Thora's tablet: Cast Spiritual Hammer on Common Orc 1 with 7 dice.
15. Check: both requests are on the DM's Player actions panel.
16. Check: every die was scripted.

*Next: the DM's approval and the rest of the fight.*

 ▐▛███▜▌   Claude Code v2.1.137
▝▜█████▛▘  Opus 4.6 · Claude Max
  ▘▘ ▝▝    ~/Claude/crimson-steel

❯ Let's add a magic tab. This will be two pages one will show a full list of    
  spells with the ability to filter based upon tier, skill, and spell school.   
  Then a second page for a specific spell description. Make a form on the spell 
   list page that  will let me add additional spells but only visible to the    
  DM. Players will  also be able to click on a spell on their character sheet   
  to get to the spell description page                                          
                                                                                
  We will need the ability to indicate which  spell school each spell has. If   
  the spell school is not indicated then it is part of the universal school.    
  Most of the spells we have are not, so we will  need to go through each of    
  them to indicate which school they are on.                                    
  Schools are: universal, necromancy, evocation, illusion, enchantment,         
  divination, abjuration, and conjuration. We will  at some point need to       
  revise this  list but it is a good starting spot                              

● Explore(Explore codebase structure)
  ⎿  Done (30 tool uses · 64.1k tokens · 1m 19s)
  (ctrl+o to expand)

● Let me read the key files I need to modify.

  Read 7 files (ctrl+o to expand)

● Now I have a complete picture. Let me start implementing.

● Before I assign schools, let me review each spell to determine the appropriate
   school:

  - Recharge - restores mana → universal (energy manipulation, doesn't fit a
  specific school)
  - Ward - temp HP, stops bleeding → abjuration (protective)
  - Cure - heals damage → necromancy (life force manipulation, traditional D&D
  convention)
  - Benign Transposition - swap positions → conjuration (teleportation)
  - Grease - area effect, slippery surface → conjuration (creates substance)
  - Disguise Self - alter appearance → illusion
  - Expeditious Retreat - speed boost → enchantment (enhancement)
  - Darkness - dims light → evocation (manipulates energy/light)
  - Invisibility - unseen → illusion
  - Web - creates sticky strands → conjuration (creates substance)
  - Disguise Other - alter target appearance → illusion
  - Create Pit - extradimensional hole → conjuration
  - Silence - stops sound → evocation (energy manipulation) or abjuration.
  Actually silence is traditionally abjuration-like but in many systems it's
  illusion (affects senses). I'll go with evocation since it manipulates sound
  energy.
  - Spiritual Weapon - force weapon → evocation (force damage)

  Let me update compendium.json with school fields:

● Update(/home/user/crimson-steel/data/compendium.json)
  ⎿  Added 2 lines, removed 1 line
       4    "range": {"0": "personal", "1": "touch", "2": "close", "3": "
          medium", "4": "long"},
       5    "item_costs": {"potion": "50*tier", "scroll": "25*tier", "oil
          ": "50*tier", "wand": "1000*tier*tier", "ammunition": [0, 20, 8
          0, 160, 320, 640]},
       6    "property_costs": {"Heartseeker": {"requirements": [{"type": 
          "ammunition", "tier": ">=3"}], "cost": 80, "description": "Adds
           4 additional dice that add their damage to physical damage. Da
          mage is increased by 1 for each success and 4 for each critical
          ."}},
       7 +  "spell_schools": ["universal", "necromancy", "evocation", "il
         +lusion", "enchantment", "divination", "abjuration", "conjuratio
         +n"],                                                           
       8    "spells": {
       8 -    "Recharge": {"tier": [0, 1, 2, 3, 4, 5], "save": "cha", "it
         -ems": ["potion", "scroll", "wand"], "range": 1, "duration": "in
         -stant", "casting_time": 0.5, "skill": ["arcana", "perform_"], "
         -properties": [], "effect_hash": {"mana": [2, 4, 8, 16, 32, 64],
         - "minimum_saturation": "tier*4", "saturation": "tier*10"}, "pre
         -fix": ["Faint", "Minor", "Basic", "Moderate", "Improved", "Grea
         -ter"], "description": "Restores {mana} points of mana. This can
         - be used to charge items or as an attack against creatures alre
         -ady saturated with magic."},                                   
       9 +    "Recharge": {"tier": [0, 1, 2, 3, 4, 5], "save": "cha", "sc
         +hool": "universal", "items": ["potion", "scroll", "wand"], "ran
         +ge": 1, "duration": "instant", "casting_time": 0.5, "skill": ["
         +arcana", "perform_"], "properties": [], "effect_hash": {"mana":
         + [2, 4, 8, 16, 32, 64], "minimum_saturation": "tier*4", "satura
         +tion": "tier*10"}, "prefix": ["Faint", "Minor", "Basic", "Moder
         +ate", "Improved", "Greater"], "description": "Restores {mana} p
         +oints of mana. This can be used to charge items or as an attack
         + against creatures already saturated with magic."},            
      10      "Ward": {"tier": [0, 1, 2, 3, 4, 5, 6], "save": 0, "items":
           ["potion", "scroll", "wand"], "range": 1, "duration": ["rank",
           "rank*10", "rank*100", "rank*600", "14400", "rank*14400", "525
          6000"], "casting_time": 0.5, "skill": ["healing", "nature", "pe
          rform_"], "properties": [], "effect_hash": {"temp_hp": "3+2.5*t
          ier", "bleeding": "-1*success", "resuscitate_timer": [0, 1, 2, 
          10, 20, 50, 14400]}, "prefix": ["Trivial", "Lesser", "Simple", 
          "Improved", "Advanced", "Superior", "Divine"], "description": "
          Target gains {temp_hp} temporary hit points, and any bleeding i
          s reduced based upon spell tier and success roll. Can resuscita
          te dying characters if cast within {resuscitate_timer} rounds."
          },
      11      "Cure": {"tier": [0, 1, 2, 3, 4, 5], "save": "cha", "items"
          : ["potion", "scroll", "wand"], "range": 1, "duration": "instan
          t", "casting_time": 0.5, "skill": ["healing", "nature", "perfor
          m_"], "properties": [], "effect_hash": {"minor_damage": [2, 4, 
          8, 16, 32, 64], "moderate_damage": [1, 2, 4, 8, 16, 32], "major
          _damage": [0, 0, 0, 1, 2, 4], "bleeding": "-1*success", "minimu
          m_saturation": "tier*2", "saturation": "tier*5"}, "suffix": ["P
          etty Wounds", "Lesser Wounds", "Simple Wounds", "Moderate Wound
          s", "Advanced Wounds", "Superior"], "description": "Cure target
           for {major_damage} points of major damage, {moderate_damage} p
          oints of moderate damage, and {minor_damage} points of minor da
          mage. Any bleeding is reduced based upon spell tier and success
           roll."},
      12      "Benign Transposition": {"tier": 1, "save": 0, "items": ["s
          croll", "wand"], "range": 3, "duration": "instant", "casting_ti
          me": 0.5, "skill": ["arcana"], "properties": [], "effect_hash":
           {}, "description": "Two target creatures, of which you can be 
          one, instantly swap positions. Both subjects must be within ran
          ge. Objects carried by the creatures (up to the creatures' maxi
          mum loads) go with them, but other creatures do not, even if th
          ey are carried. The movement is instantaneous and does not prov
          oke attacks of opportunity."},

● Update(/home/user/crimson-steel/data/compendium.json)
  ⎿  Added 1 line, removed 1 line
       7    "spell_schools": ["universal", "necromancy", "evocation", "il
          lusion", "enchantment", "divination", "abjuration", "conjuratio
          n"],
       8    "spells": {
       9      "Recharge": {"tier": [0, 1, 2, 3, 4, 5], "save": "cha", "sc
          hool": "universal", "items": ["potion", "scroll", "wand"], "ran
          ge": 1, "duration": "instant", "casting_time": 0.5, "skill": ["
          arcana", "perform_"], "properties": [], "effect_hash": {"mana":
           [2, 4, 8, 16, 32, 64], "minimum_saturation": "tier*4", "satura
          tion": "tier*10"}, "prefix": ["Faint", "Minor", "Basic", "Moder
          ate", "Improved", "Greater"], "description": "Restores {mana} p
          oints of mana. This can be used to charge items or as an attack
           against creatures already saturated with magic."},
      10 -    "Ward": {"tier": [0, 1, 2, 3, 4, 5, 6], "save": 0, "items":
         - ["potion", "scroll", "wand"], "range": 1, "duration": ["rank",
         - "rank*10", "rank*100", "rank*600", "14400", "rank*14400", "525
         -6000"], "casting_time": 0.5, "skill": ["healing", "nature", "pe
         -rform_"], "properties": [], "effect_hash": {"temp_hp": "3+2.5*t
         -ier", "bleeding": "-1*success", "resuscitate_timer": [0, 1, 2, 
         -10, 20, 50, 14400]}, "prefix": ["Trivial", "Lesser", "Simple", 
         -"Improved", "Advanced", "Superior", "Divine"], "description": "
         -Target gains {temp_hp} temporary hit points, and any bleeding i
         -s reduced based upon spell tier and success roll. Can resuscita
         -te dying characters if cast within {resuscitate_timer} rounds."
         -},                                                             
      10 +    "Ward": {"tier": [0, 1, 2, 3, 4, 5, 6], "save": 0, "school"
         +: "abjuration", "items": ["potion", "scroll", "wand"], "range":
         + 1, "duration": ["rank", "rank*10", "rank*100", "rank*600", "14
         +400", "rank*14400", "5256000"], "casting_time": 0.5, "skill": [
         +"healing", "nature", "perform_"], "properties": [], "effect_has
         +h": {"temp_hp": "3+2.5*tier", "bleeding": "-1*success", "resusc
         +itate_timer": [0, 1, 2, 10, 20, 50, 14400]}, "prefix": ["Trivia
         +l", "Lesser", "Simple", "Improved", "Advanced", "Superior", "Di
         +vine"], "description": "Target gains {temp_hp} temporary hit po
         +ints, and any bleeding is reduced based upon spell tier and suc
         +cess roll. Can resuscitate dying characters if cast within {res
         +uscitate_timer} rounds."},                                     
      11      "Cure": {"tier": [0, 1, 2, 3, 4, 5], "save": "cha", "items"
          : ["potion", "scroll", "wand"], "range": 1, "duration": "instan
          t", "casting_time": 0.5, "skill": ["healing", "nature", "perfor
          m_"], "properties": [], "effect_hash": {"minor_damage": [2, 4, 
          8, 16, 32, 64], "moderate_damage": [1, 2, 4, 8, 16, 32], "major
          _damage": [0, 0, 0, 1, 2, 4], "bleeding": "-1*success", "minimu
          m_saturation": "tier*2", "saturation": "tier*5"}, "suffix": ["P
          etty Wounds", "Lesser Wounds", "Simple Wounds", "Moderate Wound
          s", "Advanced Wounds", "Superior"], "description": "Cure target
           for {major_damage} points of major damage, {moderate_damage} p
          oints of moderate damage, and {minor_damage} points of minor da
          mage. Any bleeding is reduced based upon spell tier and success
           roll."},
      12      "Benign Transposition": {"tier": 1, "save": 0, "items": ["s
          croll", "wand"], "range": 3, "duration": "instant", "casting_ti
          me": 0.5, "skill": ["arcana"], "properties": [], "effect_hash":
           {}, "description": "Two target creatures, of which you can be 
          one, instantly swap positions. Both subjects must be within ran
          ge. Objects carried by the creatures (up to the creatures' maxi
          mum loads) go with them, but other creatures do not, even if th
          ey are carried. The movement is instantaneous and does not prov
          oke attacks of opportunity."},
      13      "Grease": {"tier": 1, "save": "dex", "items": ["scroll", "o
          il", "wand"], "range": 2, "duration": "rank", "casting_time": 0
          .5, "skill": ["arcana", "perform_"], "properties": [], "effect_
          hash": {}, "description": "One creature or 10 foot square becom
          es covered in grease. Covered creatures suffer a -2 situational
           penalty on athletics checks and gain a +2 situational bonus on
           escape artist checks. Creatures in the area when the spell is 
          cast, ending their turn in grease, or moving through grease mus
          t save or fall prone."},

● Update(/home/user/crimson-steel/data/compendium.json)
  ⎿  Added 1 line, removed 1 line
       8    "spells": {
       9      "Recharge": {"tier": [0, 1, 2, 3, 4, 5], "save": "cha", "sc
          hool": "universal", "items": ["potion", "scroll", "wand"], "ran
          ge": 1, "duration": "instant", "casting_time": 0.5, "skill": ["
          arcana", "perform_"], "properties": [], "effect_hash": {"mana":
           [2, 4, 8, 16, 32, 64], "minimum_saturation": "tier*4", "satura
          tion": "tier*10"}, "prefix": ["Faint", "Minor", "Basic", "Moder
          ate", "Improved", "Greater"], "description": "Restores {mana} p
          oints of mana. This can be used to charge items or as an attack
           against creatures already saturated with magic."},
      10      "Ward": {"tier": [0, 1, 2, 3, 4, 5, 6], "save": 0, "school"
          : "abjuration", "items": ["potion", "scroll", "wand"], "range":
           1, "duration": ["rank", "rank*10", "rank*100", "rank*600", "14
          400", "rank*14400", "5256000"], "casting_time": 0.5, "skill": [
          "healing", "nature", "perform_"], "properties": [], "effect_has
          h": {"temp_hp": "3+2.5*tier", "bleeding": "-1*success", "resusc
          itate_timer": [0, 1, 2, 10, 20, 50, 14400]}, "prefix": ["Trivia
          l", "Lesser", "Simple", "Improved", "Advanced", "Superior", "Di
          vine"], "description": "Target gains {temp_hp} temporary hit po
          ints, and any bleeding is reduced based upon spell tier and suc
          cess roll. Can resuscitate dying characters if cast within {res
          uscitate_timer} rounds."},
      11 -    "Cure": {"tier": [0, 1, 2, 3, 4, 5], "save": "cha", "items"
         -: ["potion", "scroll", "wand"], "range": 1, "duration": "instan
         -t", "casting_time": 0.5, "skill": ["healing", "nature", "perfor
         -m_"], "properties": [], "effect_hash": {"minor_damage": [2, 4, 
         -8, 16, 32, 64], "moderate_damage": [1, 2, 4, 8, 16, 32], "major
         -_damage": [0, 0, 0, 1, 2, 4], "bleeding": "-1*success", "minimu
         -m_saturation": "tier*2", "saturation": "tier*5"}, "suffix": ["P
         -etty Wounds", "Lesser Wounds", "Simple Wounds", "Moderate Wound
         -s", "Advanced Wounds", "Superior"], "description": "Cure target
         - for {major_damage} points of major damage, {moderate_damage} p
         -oints of moderate damage, and {minor_damage} points of minor da
         -mage. Any bleeding is reduced based upon spell tier and success
         - roll."},                                                      
      11 +    "Cure": {"tier": [0, 1, 2, 3, 4, 5], "save": "cha", "school
         +": "necromancy", "items": ["potion", "scroll", "wand"], "range"
         +: 1, "duration": "instant", "casting_time": 0.5, "skill": ["hea
         +ling", "nature", "perform_"], "properties": [], "effect_hash": 
         +{"minor_damage": [2, 4, 8, 16, 32, 64], "moderate_damage": [1, 
         +2, 4, 8, 16, 32], "major_damage": [0, 0, 0, 1, 2, 4], "bleeding
         +": "-1*success", "minimum_saturation": "tier*2", "saturation": 
         +"tier*5"}, "suffix": ["Petty Wounds", "Lesser Wounds", "Simple 
         +Wounds", "Moderate Wounds", "Advanced Wounds", "Superior"], "de
         +scription": "Cure target for {major_damage} points of major dam
         +age, {moderate_damage} points of moderate damage, and {minor_da
         +mage} points of minor damage. Any bleeding is reduced based upo
         +n spell tier and success roll."},                              
      12      "Benign Transposition": {"tier": 1, "save": 0, "items": ["s
          croll", "wand"], "range": 3, "duration": "instant", "casting_ti
          me": 0.5, "skill": ["arcana"], "properties": [], "effect_hash":
           {}, "description": "Two target creatures, of which you can be 
          one, instantly swap positions. Both subjects must be within ran
          ge. Objects carried by the creatures (up to the creatures' maxi
          mum loads) go with them, but other creatures do not, even if th
          ey are carried. The movement is instantaneous and does not prov
          oke attacks of opportunity."},
      13      "Grease": {"tier": 1, "save": "dex", "items": ["scroll", "o
          il", "wand"], "range": 2, "duration": "rank", "casting_time": 0
          .5, "skill": ["arcana", "perform_"], "properties": [], "effect_
          hash": {}, "description": "One creature or 10 foot square becom
          es covered in grease. Covered creatures suffer a -2 situational
           penalty on athletics checks and gain a +2 situational bonus on
           escape artist checks. Creatures in the area when the spell is 
          cast, ending their turn in grease, or moving through grease mus
          t save or fall prone."},
      14      "Disguise Self": {"tier": 1, "save": 0, "items": ["potion",
           "scroll", "wand"], "range": 0, "duration": "rank*100", "castin
          g_time": 0.5, "skill": ["arcana", "perform_"], "properties": []
          , "effect_hash": {"disguise": {"enhancement": 1}}, "description
          ": "You make yourself – including clothing, armor, weapons, and
           equipment – look different. You can seem 1 foot shorter or tal
          ler, thin, fat, or in between. You cannot change your creature 
          type (although you can appear as another subtype). Otherwise, t
          he extent of the apparent change is up to you. You could add or
           obscure a minor feature or look like an entirely different per
          son or gender."},

● Update(/home/user/crimson-steel/data/compendium.json)
  ⎿  Added 1 line, removed 1 line
       9      "Recharge": {"tier": [0, 1, 2, 3, 4, 5], "save": "cha", "sc
          hool": "universal", "items": ["potion", "scroll", "wand"], "ran
          ge": 1, "duration": "instant", "casting_time": 0.5, "skill": ["
          arcana", "perform_"], "properties": [], "effect_hash": {"mana":
           [2, 4, 8, 16, 32, 64], "minimum_saturation": "tier*4", "satura
          tion": "tier*10"}, "prefix": ["Faint", "Minor", "Basic", "Moder
          ate", "Improved", "Greater"], "description": "Restores {mana} p
          oints of mana. This can be used to charge items or as an attack
           against creatures already saturated with magic."},
      10      "Ward": {"tier": [0, 1, 2, 3, 4, 5, 6], "save": 0, "school"
          : "abjuration", "items": ["potion", "scroll", "wand"], "range":
           1, "duration": ["rank", "rank*10", "rank*100", "rank*600", "14
          400", "rank*14400", "5256000"], "casting_time": 0.5, "skill": [
          "healing", "nature", "perform_"], "properties": [], "effect_has
          h": {"temp_hp": "3+2.5*tier", "bleeding": "-1*success", "resusc
          itate_timer": [0, 1, 2, 10, 20, 50, 14400]}, "prefix": ["Trivia
          l", "Lesser", "Simple", "Improved", "Advanced", "Superior", "Di
          vine"], "description": "Target gains {temp_hp} temporary hit po
          ints, and any bleeding is reduced based upon spell tier and suc
          cess roll. Can resuscitate dying characters if cast within {res
          uscitate_timer} rounds."},
      11      "Cure": {"tier": [0, 1, 2, 3, 4, 5], "save": "cha", "school
          ": "necromancy", "items": ["potion", "scroll", "wand"], "range"
          : 1, "duration": "instant", "casting_time": 0.5, "skill": ["hea
          ling", "nature", "perform_"], "properties": [], "effect_hash": 
          {"minor_damage": [2, 4, 8, 16, 32, 64], "moderate_damage": [1, 
          2, 4, 8, 16, 32], "major_damage": [0, 0, 0, 1, 2, 4], "bleeding
          ": "-1*success", "minimum_saturation": "tier*2", "saturation": 
          "tier*5"}, "suffix": ["Petty Wounds", "Lesser Wounds", "Simple 
          Wounds", "Moderate Wounds", "Advanced Wounds", "Superior"], "de
          scription": "Cure target for {major_damage} points of major dam
          age, {moderate_damage} points of moderate damage, and {minor_da
          mage} points of minor damage. Any bleeding is reduced based upo
          n spell tier and success roll."},
      12 -    "Benign Transposition": {"tier": 1, "save": 0, "items": ["s
         -croll", "wand"], "range": 3, "duration": "instant", "casting_ti
         -me": 0.5, "skill": ["arcana"], "properties": [], "effect_hash":
         - {}, "description": "Two target creatures, of which you can be 
         -one, instantly swap positions. Both subjects must be within ran
         -ge. Objects carried by the creatures (up to the creatures' maxi
         -mum loads) go with them, but other creatures do not, even if th
         -ey are carried. The movement is instantaneous and does not prov
         -oke attacks of opportunity."},                                 
      12 +    "Benign Transposition": {"tier": 1, "save": 0, "school": "c
         +onjuration", "items": ["scroll", "wand"], "range": 3, "duration
         +": "instant", "casting_time": 0.5, "skill": ["arcana"], "proper
         +ties": [], "effect_hash": {}, "description": "Two target creatu
         +res, of which you can be one, instantly swap positions. Both su
         +bjects must be within range. Objects carried by the creatures (
         +up to the creatures' maximum loads) go with them, but other cre
         +atures do not, even if they are carried. The movement is instan
         +taneous and does not provoke attacks of opportunity."},        
      13      "Grease": {"tier": 1, "save": "dex", "items": ["scroll", "o
          il", "wand"], "range": 2, "duration": "rank", "casting_time": 0
          .5, "skill": ["arcana", "perform_"], "properties": [], "effect_
          hash": {}, "description": "One creature or 10 foot square becom
          es covered in grease. Covered creatures suffer a -2 situational
           penalty on athletics checks and gain a +2 situational bonus on
           escape artist checks. Creatures in the area when the spell is 
          cast, ending their turn in grease, or moving through grease mus
          t save or fall prone."},
      14      "Disguise Self": {"tier": 1, "save": 0, "items": ["potion",
           "scroll", "wand"], "range": 0, "duration": "rank*100", "castin
          g_time": 0.5, "skill": ["arcana", "perform_"], "properties": []
          , "effect_hash": {"disguise": {"enhancement": 1}}, "description
          ": "You make yourself – including clothing, armor, weapons, and
           equipment – look different. You can seem 1 foot shorter or tal
          ler, thin, fat, or in between. You cannot change your creature 
          type (although you can appear as another subtype). Otherwise, t
          he extent of the apparent change is up to you. You could add or
           obscure a minor feature or look like an entirely different per
          son or gender."},
      15      "Expeditious Retreat": {"tier": 1, "save": 0, "items": ["po
          tion", "scroll", "wand"], "range": 0, "duration": "rank*10", "c
          asting_time": 0.5, "skill": ["arcana", "perform_"], "properties
          ": [], "effect_hash": {"speed": {"enhancement": 30}}, "descript
          ion": "This spell increases your base land speed by 30 feet. Th
          is adjustment is treated as an enhancement bonus. There is no e
          ffect on other modes of movement, such as burrow, climb, fly, o
          r swim. As with any effect that increases your speed, this spel
          l affects your jumping distance (see the Acrobatics skill)."},

● Update(/home/user/crimson-steel/data/compendium.json)
  ⎿  Added 1 line, removed 1 line
      10      "Ward": {"tier": [0, 1, 2, 3, 4, 5, 6], "save": 0, "school"
          : "abjuration", "items": ["potion", "scroll", "wand"], "range":
           1, "duration": ["rank", "rank*10", "rank*100", "rank*600", "14
          400", "rank*14400", "5256000"], "casting_time": 0.5, "skill": [
          "healing", "nature", "perform_"], "properties": [], "effect_has
          h": {"temp_hp": "3+2.5*tier", "bleeding": "-1*success", "resusc
          itate_timer": [0, 1, 2, 10, 20, 50, 14400]}, "prefix": ["Trivia
          l", "Lesser", "Simple", "Improved", "Advanced", "Superior", "Di
          vine"], "description": "Target gains {temp_hp} temporary hit po
          ints, and any bleeding is reduced based upon spell tier and suc
          cess roll. Can resuscitate dying characters if cast within {res
          uscitate_timer} rounds."},
      11      "Cure": {"tier": [0, 1, 2, 3, 4, 5], "save": "cha", "school
          ": "necromancy", "items": ["potion", "scroll", "wand"], "range"
          : 1, "duration": "instant", "casting_time": 0.5, "skill": ["hea
          ling", "nature", "perform_"], "properties": [], "effect_hash": 
          {"minor_damage": [2, 4, 8, 16, 32, 64], "moderate_damage": [1, 
          2, 4, 8, 16, 32], "major_damage": [0, 0, 0, 1, 2, 4], "bleeding
          ": "-1*success", "minimum_saturation": "tier*2", "saturation": 
          "tier*5"}, "suffix": ["Petty Wounds", "Lesser Wounds", "Simple 
          Wounds", "Moderate Wounds", "Advanced Wounds", "Superior"], "de
          scription": "Cure target for {major_damage} points of major dam
          age, {moderate_damage} points of moderate damage, and {minor_da
          mage} points of minor damage. Any bleeding is reduced based upo
          n spell tier and success roll."},
      12      "Benign Transposition": {"tier": 1, "save": 0, "school": "c
          onjuration", "items": ["scroll", "wand"], "range": 3, "duration
          ": "instant", "casting_time": 0.5, "skill": ["arcana"], "proper
          ties": [], "effect_hash": {}, "description": "Two target creatu
          res, of which you can be one, instantly swap positions. Both su
          bjects must be within range. Objects carried by the creatures (
          up to the creatures' maximum loads) go with them, but other cre
          atures do not, even if they are carried. The movement is instan
          taneous and does not provoke attacks of opportunity."},
      13 -    "Grease": {"tier": 1, "save": "dex", "items": ["scroll", "o
         -il", "wand"], "range": 2, "duration": "rank", "casting_time": 0
         -.5, "skill": ["arcana", "perform_"], "properties": [], "effect_
         -hash": {}, "description": "One creature or 10 foot square becom
         -es covered in grease. Covered creatures suffer a -2 situational
         - penalty on athletics checks and gain a +2 situational bonus on
         - escape artist checks. Creatures in the area when the spell is 
         -cast, ending their turn in grease, or moving through grease mus
         -t save or fall prone."},                                       
      13 +    "Grease": {"tier": 1, "save": "dex", "school": "conjuration
         +", "items": ["scroll", "oil", "wand"], "range": 2, "duration": 
         +"rank", "casting_time": 0.5, "skill": ["arcana", "perform_"], "
         +properties": [], "effect_hash": {}, "description": "One creatur
         +e or 10 foot square becomes covered in grease. Covered creature
         +s suffer a -2 situational penalty on athletics checks and gain 
         +a +2 situational bonus on escape artist checks. Creatures in th
         +e area when the spell is cast, ending their turn in grease, or 
         +moving through grease must save or fall prone."},              
      14      "Disguise Self": {"tier": 1, "save": 0, "items": ["potion",
           "scroll", "wand"], "range": 0, "duration": "rank*100", "castin
          g_time": 0.5, "skill": ["arcana", "perform_"], "properties": []
          , "effect_hash": {"disguise": {"enhancement": 1}}, "description
          ": "You make yourself – including clothing, armor, weapons, and
           equipment – look different. You can seem 1 foot shorter or tal
          ler, thin, fat, or in between. You cannot change your creature 
          type (although you can appear as another subtype). Otherwise, t
          he extent of the apparent change is up to you. You could add or
           obscure a minor feature or look like an entirely different per
          son or gender."},
      15      "Expeditious Retreat": {"tier": 1, "save": 0, "items": ["po
          tion", "scroll", "wand"], "range": 0, "duration": "rank*10", "c
          asting_time": 0.5, "skill": ["arcana", "perform_"], "properties
          ": [], "effect_hash": {"speed": {"enhancement": 30}}, "descript
          ion": "This spell increases your base land speed by 30 feet. Th
          is adjustment is treated as an enhancement bonus. There is no e
          ffect on other modes of movement, such as burrow, climb, fly, o
          r swim. As with any effect that increases your speed, this spel
          l affects your jumping distance (see the Acrobatics skill)."},
      16      "Darkness": {"tier": 2, "save": 0, "items": ["scroll", "oil
          ", "wand"], "range": 1, "duration": "rank*10", "casting_time": 
          0.5, "skill": ["arcana", "healing"], "properties": [], "effect_
          hash": {}, "description": "This spell causes an object to radia
          te darkness out to a 20-foot radius. This darkness causes the i
          llumination level in the area to drop one step, from bright lig
          ht to normal light, from normal light to dim light, or from dim
           light to darkness. This spell has no effect in an area that is
           already dark. Creatures with light vulnerability or sensitivit
          y take no penalties in normal light. All creatures gain conceal
          ment in dim light. All creatures gain total concealment in dark
          ness. Creatures with darkvision can see in an area of dim light
           or darkness without penalty. Nonmagical sources of light, such
           as torches and lanterns, do not increase the light level in an
           area of darkness. Magical light sources only increase the ligh
          t level in an area if they are of a higher spell level than dar
          kness. If darkness is cast on a small object that is then place
          d inside or under a lightproof covering, the spell’s effect is 
          blocked until the covering is removed."},

● Update(/home/user/crimson-steel/data/compendium.json)
  ⎿  Added 1 line, removed 1 line
      11      "Cure": {"tier": [0, 1, 2, 3, 4, 5], "save": "cha", "school
          ": "necromancy", "items": ["potion", "scroll", "wand"], "range"
          : 1, "duration": "instant", "casting_time": 0.5, "skill": ["hea
          ling", "nature", "perform_"], "properties": [], "effect_hash": 
          {"minor_damage": [2, 4, 8, 16, 32, 64], "moderate_damage": [1, 
          2, 4, 8, 16, 32], "major_damage": [0, 0, 0, 1, 2, 4], "bleeding
          ": "-1*success", "minimum_saturation": "tier*2", "saturation": 
          "tier*5"}, "suffix": ["Petty Wounds", "Lesser Wounds", "Simple 
          Wounds", "Moderate Wounds", "Advanced Wounds", "Superior"], "de
          scription": "Cure target for {major_damage} points of major dam
          age, {moderate_damage} points of moderate damage, and {minor_da
          mage} points of minor damage. Any bleeding is reduced based upo
          n spell tier and success roll."},
      12      "Benign Transposition": {"tier": 1, "save": 0, "school": "c
          onjuration", "items": ["scroll", "wand"], "range": 3, "duration
          ": "instant", "casting_time": 0.5, "skill": ["arcana"], "proper
          ties": [], "effect_hash": {}, "description": "Two target creatu
          res, of which you can be one, instantly swap positions. Both su
          bjects must be within range. Objects carried by the creatures (
          up to the creatures' maximum loads) go with them, but other cre
          atures do not, even if they are carried. The movement is instan
          taneous and does not provoke attacks of opportunity."},
      13      "Grease": {"tier": 1, "save": "dex", "school": "conjuration
          ", "items": ["scroll", "oil", "wand"], "range": 2, "duration": 
          "rank", "casting_time": 0.5, "skill": ["arcana", "perform_"], "
          properties": [], "effect_hash": {}, "description": "One creatur
          e or 10 foot square becomes covered in grease. Covered creature
          s suffer a -2 situational penalty on athletics checks and gain 
          a +2 situational bonus on escape artist checks. Creatures in th
          e area when the spell is cast, ending their turn in grease, or 
          moving through grease must save or fall prone."},
      14 -    "Disguise Self": {"tier": 1, "save": 0, "items": ["potion",
         - "scroll", "wand"], "range": 0, "duration": "rank*100", "castin
         -g_time": 0.5, "skill": ["arcana", "perform_"], "properties": []
         -, "effect_hash": {"disguise": {"enhancement": 1}}, "description
         -": "You make yourself – including clothing, armor, weapons, and
         - equipment – look different. You can seem 1 foot shorter or tal
         -ler, thin, fat, or in between. You cannot change your creature 
         -type (although you can appear as another subtype). Otherwise, t
         -he extent of the apparent change is up to you. You could add or
         - obscure a minor feature or look like an entirely different per
         -son or gender."},                                              
      14 +    "Disguise Self": {"tier": 1, "save": 0, "school": "illusion
         +", "items": ["potion", "scroll", "wand"], "range": 0, "duration
         +": "rank*100", "casting_time": 0.5, "skill": ["arcana", "perfor
         +m_"], "properties": [], "effect_hash": {"disguise": {"enhanceme
         +nt": 1}}, "description": "You make yourself – including clothin
         +g, armor, weapons, and equipment – look different. You can seem
         + 1 foot shorter or taller, thin, fat, or in between. You cannot
         + change your creature type (although you can appear as another 
         +subtype). Otherwise, the extent of the apparent change is up to
         + you. You could add or obscure a minor feature or look like an 
         +entirely different person or gender."},                        
      15      "Expeditious Retreat": {"tier": 1, "save": 0, "items": ["po
          tion", "scroll", "wand"], "range": 0, "duration": "rank*10", "c
          asting_time": 0.5, "skill": ["arcana", "perform_"], "properties
          ": [], "effect_hash": {"speed": {"enhancement": 30}}, "descript
          ion": "This spell increases your base land speed by 30 feet. Th
          is adjustment is treated as an enhancement bonus. There is no e
          ffect on other modes of movement, such as burrow, climb, fly, o
          r swim. As with any effect that increases your speed, this spel
          l affects your jumping distance (see the Acrobatics skill)."},
      16      "Darkness": {"tier": 2, "save": 0, "items": ["scroll", "oil
          ", "wand"], "range": 1, "duration": "rank*10", "casting_time": 
          0.5, "skill": ["arcana", "healing"], "properties": [], "effect_
          hash": {}, "description": "This spell causes an object to radia
          te darkness out to a 20-foot radius. This darkness causes the i
          llumination level in the area to drop one step, from bright lig
          ht to normal light, from normal light to dim light, or from dim
           light to darkness. This spell has no effect in an area that is
           already dark. Creatures with light vulnerability or sensitivit
          y take no penalties in normal light. All creatures gain conceal
          ment in dim light. All creatures gain total concealment in dark
          ness. Creatures with darkvision can see in an area of dim light
           or darkness without penalty. Nonmagical sources of light, such
           as torches and lanterns, do not increase the light level in an
           area of darkness. Magical light sources only increase the ligh
          t level in an area if they are of a higher spell level than dar
          kness. If darkness is cast on a small object that is then place
          d inside or under a lightproof covering, the spell’s effect is 
          blocked until the covering is removed."},
      17      "Invisibility": {"tier": 2, "save": "will", "items": ["poti
          on", "scroll", "oil", "wand"], "range": 1, "duration": "rank*10
          ", "casting_time": 0.5, "skill": ["arcana", "perform_"], "prope
          rties": [], "effect_hash": {}, "description": "The creature or 
          object touched radiates an aura of unimportance preventing othe
          r creatures from noticing it or them. If any creature realizes,
           or suspects, the target creature or object are nearby then the
          y can make a wisdom save as a main action to overcome the spell
           for it's duration. There is a penalty on this save if they do 
          not know which square the creature or object is in, and a cumul
          ative penalty for every failed save. If an attack is made by th
          e target including any harmful spells cast then all creatures w
          ithin sight of the target immediatly gain the benefit of a succ
          essful save. Indirect actions, such as cutting a rope bridge, o
          r setting fire to a building do not grant an automatic save. Th
          is spell affects any objects carried by the target when the spe
          ll is cast but not objects dropped or picked up after. Any part
           of an item that the subject carries but that extends more than
           10 feet from can be observed. This spell does not prevent crea
          tures from noticing sounds or smells or other nonvisual clues t
          o the targets existance."},

● Update(/home/user/crimson-steel/data/compendium.json)
  ⎿  Added 1 line, removed 1 line
      12      "Benign Transposition": {"tier": 1, "save": 0, "school": "c
          onjuration", "items": ["scroll", "wand"], "range": 3, "duration
          ": "instant", "casting_time": 0.5, "skill": ["arcana"], "proper
          ties": [], "effect_hash": {}, "description": "Two target creatu
          res, of which you can be one, instantly swap positions. Both su
          bjects must be within range. Objects carried by the creatures (
          up to the creatures' maximum loads) go with them, but other cre
          atures do not, even if they are carried. The movement is instan
          taneous and does not provoke attacks of opportunity."},
      13      "Grease": {"tier": 1, "save": "dex", "school": "conjuration
          ", "items": ["scroll", "oil", "wand"], "range": 2, "duration": 
          "rank", "casting_time": 0.5, "skill": ["arcana", "perform_"], "
          properties": [], "effect_hash": {}, "description": "One creatur
          e or 10 foot square becomes covered in grease. Covered creature
          s suffer a -2 situational penalty on athletics checks and gain 
          a +2 situational bonus on escape artist checks. Creatures in th
          e area when the spell is cast, ending their turn in grease, or 
          moving through grease must save or fall prone."},
      14      "Disguise Self": {"tier": 1, "save": 0, "school": "illusion
          ", "items": ["potion", "scroll", "wand"], "range": 0, "duration
          ": "rank*100", "casting_time": 0.5, "skill": ["arcana", "perfor
          m_"], "properties": [], "effect_hash": {"disguise": {"enhanceme
          nt": 1}}, "description": "You make yourself – including clothin
          g, armor, weapons, and equipment – look different. You can seem
           1 foot shorter or taller, thin, fat, or in between. You cannot
           change your creature type (although you can appear as another 
          subtype). Otherwise, the extent of the apparent change is up to
           you. You could add or obscure a minor feature or look like an 
          entirely different person or gender."},
      15 -    "Expeditious Retreat": {"tier": 1, "save": 0, "items": ["po
         -tion", "scroll", "wand"], "range": 0, "duration": "rank*10", "c
         -asting_time": 0.5, "skill": ["arcana", "perform_"], "properties
         -": [], "effect_hash": {"speed": {"enhancement": 30}}, "descript
         -ion": "This spell increases your base land speed by 30 feet. Th
         -is adjustment is treated as an enhancement bonus. There is no e
         -ffect on other modes of movement, such as burrow, climb, fly, o
         -r swim. As with any effect that increases your speed, this spel
         -l affects your jumping distance (see the Acrobatics skill)."}, 
      15 +    "Expeditious Retreat": {"tier": 1, "save": 0, "school": "en
         +chantment", "items": ["potion", "scroll", "wand"], "range": 0, 
         +"duration": "rank*10", "casting_time": 0.5, "skill": ["arcana",
         + "perform_"], "properties": [], "effect_hash": {"speed": {"enha
         +ncement": 30}}, "description": "This spell increases your base 
         +land speed by 30 feet. This adjustment is treated as an enhance
         +ment bonus. There is no effect on other modes of movement, such
         + as burrow, climb, fly, or swim. As with any effect that increa
         +ses your speed, this spell affects your jumping distance (see t
         +he Acrobatics skill)."},                                       
      16      "Darkness": {"tier": 2, "save": 0, "items": ["scroll", "oil
          ", "wand"], "range": 1, "duration": "rank*10", "casting_time": 
          0.5, "skill": ["arcana", "healing"], "properties": [], "effect_
          hash": {}, "description": "This spell causes an object to radia
          te darkness out to a 20-foot radius. This darkness causes the i
          llumination level in the area to drop one step, from bright lig
          ht to normal light, from normal light to dim light, or from dim
           light to darkness. This spell has no effect in an area that is
           already dark. Creatures with light vulnerability or sensitivit
          y take no penalties in normal light. All creatures gain conceal
          ment in dim light. All creatures gain total concealment in dark
          ness. Creatures with darkvision can see in an area of dim light
           or darkness without penalty. Nonmagical sources of light, such
           as torches and lanterns, do not increase the light level in an
           area of darkness. Magical light sources only increase the ligh
          t level in an area if they are of a higher spell level than dar
          kness. If darkness is cast on a small object that is then place
          d inside or under a lightproof covering, the spell’s effect is 
          blocked until the covering is removed."},
      17      "Invisibility": {"tier": 2, "save": "will", "items": ["poti
          on", "scroll", "oil", "wand"], "range": 1, "duration": "rank*10
          ", "casting_time": 0.5, "skill": ["arcana", "perform_"], "prope
          rties": [], "effect_hash": {}, "description": "The creature or 
          object touched radiates an aura of unimportance preventing othe
          r creatures from noticing it or them. If any creature realizes,
           or suspects, the target creature or object are nearby then the
          y can make a wisdom save as a main action to overcome the spell
           for it's duration. There is a penalty on this save if they do 
          not know which square the creature or object is in, and a cumul
          ative penalty for every failed save. If an attack is made by th
          e target including any harmful spells cast then all creatures w
          ithin sight of the target immediatly gain the benefit of a succ
          essful save. Indirect actions, such as cutting a rope bridge, o
          r setting fire to a building do not grant an automatic save. Th
          is spell affects any objects carried by the target when the spe
          ll is cast but not objects dropped or picked up after. Any part
           of an item that the subject carries but that extends more than
           10 feet from can be observed. This spell does not prevent crea
          tures from noticing sounds or smells or other nonvisual clues t
          o the targets existance."},
      18      "Web": {"tier": 2, "save": "reflex", "items": ["scroll", "w
          and"], "range": 2, "duration": "rank*10", "casting_time": 0.5, 
          "skill": ["arcana"], "properties": [], "effect_hash": {}, "desc
          ription": "Web creates a many-layered mass of strong, sticky st
          rands. These strands trap those caught in them. The strands are
           similar to spiderwebs but far larger and tougher. These masses
           must be anchored to two or more solid and diametrically oppose
          d points or else the web collapses upon itself and disappears. 
          Creatures caught within a web become grappled by the sticky fib
          ers. Attacking a creature in a web doesn’t cause you to become 
          grappled. Anyone in the effect’s area when the spell is cast mu
          st make a Reflex save. If this save succeeds, the creature is i
          nside the web but is otherwise unaffected. If the save fails, t
          he creature gains the grappled condition, but can break free by
           making a combat maneuver check or Escape Artist check as a sta
          ndard action against the DC of this spell. The entire area of t
          he web is considered difficult terrain. Anyone moving through t
          he webs must make a combat maneuver check or Escape Artist chec
          k as part of their move action, with a DC equal to the spell’s 
          DC. Creatures that fail lose their movement and become grappled
           in the first square of webbing that they enter. If you have at
           least 5 feet of web between you and an opponent, it provides c
          over. If you have at least 20 feet of web between you, it provi
          des total cover. The strands of a web spell are flammable. A fl
          aming weapon can slash them away as easily as a hand brushes aw
          ay cobwebs. Any fire can set the webs alight and burn away one 
          5-foot square in 1 round. All creatures within flaming webs tak
          e fire damage from the flames."},

● Update(/home/user/crimson-steel/data/compendium.json)
  ⎿  Added 1 line, removed 1 line
      13      "Grease": {"tier": 1, "save": "dex", "school": "conjuration
          ", "items": ["scroll", "oil", "wand"], "range": 2, "duration": 
          "rank", "casting_time": 0.5, "skill": ["arcana", "perform_"], "
          properties": [], "effect_hash": {}, "description": "One creatur
          e or 10 foot square becomes covered in grease. Covered creature
          s suffer a -2 situational penalty on athletics checks and gain 
          a +2 situational bonus on escape artist checks. Creatures in th
          e area when the spell is cast, ending their turn in grease, or 
          moving through grease must save or fall prone."},
      14      "Disguise Self": {"tier": 1, "save": 0, "school": "illusion
          ", "items": ["potion", "scroll", "wand"], "range": 0, "duration
          ": "rank*100", "casting_time": 0.5, "skill": ["arcana", "perfor
          m_"], "properties": [], "effect_hash": {"disguise": {"enhanceme
          nt": 1}}, "description": "You make yourself – including clothin
          g, armor, weapons, and equipment – look different. You can seem
           1 foot shorter or taller, thin, fat, or in between. You cannot
           change your creature type (although you can appear as another 
          subtype). Otherwise, the extent of the apparent change is up to
           you. You could add or obscure a minor feature or look like an 
          entirely different person or gender."},
      15      "Expeditious Retreat": {"tier": 1, "save": 0, "school": "en
          chantment", "items": ["potion", "scroll", "wand"], "range": 0, 
          "duration": "rank*10", "casting_time": 0.5, "skill": ["arcana",
           "perform_"], "properties": [], "effect_hash": {"speed": {"enha
          ncement": 30}}, "description": "This spell increases your base 
          land speed by 30 feet. This adjustment is treated as an enhance
          ment bonus. There is no effect on other modes of movement, such
           as burrow, climb, fly, or swim. As with any effect that increa
          ses your speed, this spell affects your jumping distance (see t
          he Acrobatics skill)."},
      16 -    "Darkness": {"tier": 2, "save": 0, "items": ["scroll", "oil
         -", "wand"], "range": 1, "duration": "rank*10", "casting_time": 
         -0.5, "skill": ["arcana", "healing"], "properties": [], "effect_
         -hash": {}, "description": "This spell causes an object to radia
         -te darkness out to a 20-foot radius. This darkness causes the i
         -llumination level in the area to drop one step, from bright lig
         -ht to normal light, from normal light to dim light, or from dim
         - light to darkness. This spell has no effect in an area that is
         - already dark. Creatures with light vulnerability or sensitivit
         -y take no penalties in normal light. All creatures gain conceal
         -ment in dim light. All creatures gain total concealment in dark
         -ness. Creatures with darkvision can see in an area of dim light
         - or darkness without penalty. Nonmagical sources of light, such
         - as torches and lanterns, do not increase the light level in an
         - area of darkness. Magical light sources only increase the ligh
         -t level in an area if they are of a higher spell level than dar
         -kness. If darkness is cast on a small object that is then place
         -d inside or under a lightproof covering, the spell’s effect is 
         -blocked until the covering is removed."},                      
      16 +    "Darkness": {"tier": 2, "save": 0, "school": "evocation", "
         +items": ["scroll", "oil", "wand"], "range": 1, "duration": "ran
         +k*10", "casting_time": 0.5, "skill": ["arcana", "healing"], "pr
         +operties": [], "effect_hash": {}, "description": "This spell ca
         +uses an object to radiate darkness out to a 20-foot radius. Thi
         +s darkness causes the illumination level in the area to drop on
         +e step, from bright light to normal light, from normal light to
         + dim light, or from dim light to darkness. This spell has no ef
         +fect in an area that is already dark. Creatures with light vuln
         +erability or sensitivity take no penalties in normal light. All
         + creatures gain concealment in dim light. All creatures gain to
         +tal concealment in darkness. Creatures with darkvision can see 
         +in an area of dim light or darkness without penalty. Nonmagical
         + sources of light, such as torches and lanterns, do not increas
         +e the light level in an area of darkness. Magical light sources
         + only increase the light level in an area if they are of a high
         +er spell level than darkness. If darkness is cast on a small ob
         +ject that is then placed inside or under a lightproof covering,
         + the spell’s effect is blocked until the covering is removed."}
         +,                                                              
      17      "Invisibility": {"tier": 2, "save": "will", "items": ["poti
          on", "scroll", "oil", "wand"], "range": 1, "duration": "rank*10
          ", "casting_time": 0.5, "skill": ["arcana", "perform_"], "prope
          rties": [], "effect_hash": {}, "description": "The creature or 
          object touched radiates an aura of unimportance preventing othe
          r creatures from noticing it or them. If any creature realizes,
           or suspects, the target creature or object are nearby then the
          y can make a wisdom save as a main action to overcome the spell
           for it's duration. There is a penalty on this save if they do 
          not know which square the creature or object is in, and a cumul
          ative penalty for every failed save. If an attack is made by th
          e target including any harmful spells cast then all creatures w
          ithin sight of the target immediatly gain the benefit of a succ
          essful save. Indirect actions, such as cutting a rope bridge, o
          r setting fire to a building do not grant an automatic save. Th
          is spell affects any objects carried by the target when the spe
          ll is cast but not objects dropped or picked up after. Any part
           of an item that the subject carries but that extends more than
           10 feet from can be observed. This spell does not prevent crea
          tures from noticing sounds or smells or other nonvisual clues t
          o the targets existance."},
      18      "Web": {"tier": 2, "save": "reflex", "items": ["scroll", "w
          and"], "range": 2, "duration": "rank*10", "casting_time": 0.5, 
          "skill": ["arcana"], "properties": [], "effect_hash": {}, "desc
          ription": "Web creates a many-layered mass of strong, sticky st
          rands. These strands trap those caught in them. The strands are
           similar to spiderwebs but far larger and tougher. These masses
           must be anchored to two or more solid and diametrically oppose
          d points or else the web collapses upon itself and disappears. 
          Creatures caught within a web become grappled by the sticky fib
          ers. Attacking a creature in a web doesn’t cause you to become 
          grappled. Anyone in the effect’s area when the spell is cast mu
          st make a Reflex save. If this save succeeds, the creature is i
          nside the web but is otherwise unaffected. If the save fails, t
          he creature gains the grappled condition, but can break free by
           making a combat maneuver check or Escape Artist check as a sta
          ndard action against the DC of this spell. The entire area of t
          he web is considered difficult terrain. Anyone moving through t
          he webs must make a combat maneuver check or Escape Artist chec
          k as part of their move action, with a DC equal to the spell’s 
          DC. Creatures that fail lose their movement and become grappled
           in the first square of webbing that they enter. If you have at
           least 5 feet of web between you and an opponent, it provides c
          over. If you have at least 20 feet of web between you, it provi
          des total cover. The strands of a web spell are flammable. A fl
          aming weapon can slash them away as easily as a hand brushes aw
          ay cobwebs. Any fire can set the webs alight and burn away one 
          5-foot square in 1 round. All creatures within flaming webs tak
          e fire damage from the flames."},
      19      "Disguise Other": {"tier": 2, "save": "will", "items": ["po
          tion", "scroll", "oil", "wand"], "range": 1, "duration": "rank*
          100", "casting_time": 0.5, "skill": ["arcana", "perform_"], "pr
          operties": [], "effect_hash": {"disguise": {"enhancement": 1}},
           "description": "You make the target creature – including cloth
          ing, armor, weapons, and equipment – look different. They can s
          eem 1 foot shorter or taller, thin, fat, or in between. You can
          not change your creature type (although you can appear as anoth
          er subtype). Otherwise, the extent of the apparent change is up
           to you. You could add or obscure a minor feature or look like 
          an entirely different person or gender."},

● Update(/home/user/crimson-steel/data/compendium.json)
  ⎿  Added 1 line, removed 1 line
      14      "Disguise Self": {"tier": 1, "save": 0, "school": "illusion
          ", "items": ["potion", "scroll", "wand"], "range": 0, "duration
          ": "rank*100", "casting_time": 0.5, "skill": ["arcana", "perfor
          m_"], "properties": [], "effect_hash": {"disguise": {"enhanceme
          nt": 1}}, "description": "You make yourself – including clothin
          g, armor, weapons, and equipment – look different. You can seem
           1 foot shorter or taller, thin, fat, or in between. You cannot
           change your creature type (although you can appear as another 
          subtype). Otherwise, the extent of the apparent change is up to
           you. You could add or obscure a minor feature or look like an 
          entirely different person or gender."},
      15      "Expeditious Retreat": {"tier": 1, "save": 0, "school": "en
          chantment", "items": ["potion", "scroll", "wand"], "range": 0, 
          "duration": "rank*10", "casting_time": 0.5, "skill": ["arcana",
           "perform_"], "properties": [], "effect_hash": {"speed": {"enha
          ncement": 30}}, "description": "This spell increases your base 
          land speed by 30 feet. This adjustment is treated as an enhance
          ment bonus. There is no effect on other modes of movement, such
           as burrow, climb, fly, or swim. As with any effect that increa
          ses your speed, this spell affects your jumping distance (see t
          he Acrobatics skill)."},
      16      "Darkness": {"tier": 2, "save": 0, "school": "evocation", "
          items": ["scroll", "oil", "wand"], "range": 1, "duration": "ran
          k*10", "casting_time": 0.5, "skill": ["arcana", "healing"], "pr
          operties": [], "effect_hash": {}, "description": "This spell ca
          uses an object to radiate darkness out to a 20-foot radius. Thi
          s darkness causes the illumination level in the area to drop on
          e step, from bright light to normal light, from normal light to
           dim light, or from dim light to darkness. This spell has no ef
          fect in an area that is already dark. Creatures with light vuln
          erability or sensitivity take no penalties in normal light. All
           creatures gain concealment in dim light. All creatures gain to
          tal concealment in darkness. Creatures with darkvision can see 
          in an area of dim light or darkness without penalty. Nonmagical
           sources of light, such as torches and lanterns, do not increas
          e the light level in an area of darkness. Magical light sources
           only increase the light level in an area if they are of a high
          er spell level than darkness. If darkness is cast on a small ob
          ject that is then placed inside or under a lightproof covering,
           the spell’s effect is blocked until the covering is removed."}
          ,
      17 -    "Invisibility": {"tier": 2, "save": "will", "items": ["poti
         -on", "scroll", "oil", "wand"], "range": 1, "duration": "rank*10
         -", "casting_time": 0.5, "skill": ["arcana", "perform_"], "prope
         -rties": [], "effect_hash": {}, "description": "The creature or 
         -object touched radiates an aura of unimportance preventing othe
         -r creatures from noticing it or them. If any creature realizes,
         - or suspects, the target creature or object are nearby then the
         -y can make a wisdom save as a main action to overcome the spell
         - for it's duration. There is a penalty on this save if they do 
         -not know which square the creature or object is in, and a cumul
         -ative penalty for every failed save. If an attack is made by th
         -e target including any harmful spells cast then all creatures w
         -ithin sight of the target immediatly gain the benefit of a succ
         -essful save. Indirect actions, such as cutting a rope bridge, o
         -r setting fire to a building do not grant an automatic save. Th
         -is spell affects any objects carried by the target when the spe
         -ll is cast but not objects dropped or picked up after. Any part
         - of an item that the subject carries but that extends more than
         - 10 feet from can be observed. This spell does not prevent crea
         -tures from noticing sounds or smells or other nonvisual clues t
         -o the targets existance."},                                    
      17 +    "Invisibility": {"tier": 2, "save": "will", "school": "illu
         +sion", "items": ["potion", "scroll", "oil", "wand"], "range": 1
         +, "duration": "rank*10", "casting_time": 0.5, "skill": ["arcana
         +", "perform_"], "properties": [], "effect_hash": {}, "descripti
         +on": "The creature or object touched radiates an aura of unimpo
         +rtance preventing other creatures from noticing it or them. If 
         +any creature realizes, or suspects, the target creature or obje
         +ct are nearby then they can make a wisdom save as a main action
         + to overcome the spell for it's duration. There is a penalty on
         + this save if they do not know which square the creature or obj
         +ect is in, and a cumulative penalty for every failed save. If a
         +n attack is made by the target including any harmful spells cas
         +t then all creatures within sight of the target immediatly gain
         + the benefit of a successful save. Indirect actions, such as cu
         +tting a rope bridge, or setting fire to a building do not grant
         + an automatic save. This spell affects any objects carried by t
         +he target when the spell is cast but not objects dropped or pic
         +ked up after. Any part of an item that the subject carries but 
         +that extends more than 10 feet from can be observed. This spell
         + does not prevent creatures from noticing sounds or smells or o
         +ther nonvisual clues to the targets existance."},              
      18      "Web": {"tier": 2, "save": "reflex", "items": ["scroll", "w
          and"], "range": 2, "duration": "rank*10", "casting_time": 0.5, 
          "skill": ["arcana"], "properties": [], "effect_hash": {}, "desc
          ription": "Web creates a many-layered mass of strong, sticky st
          rands. These strands trap those caught in them. The strands are
           similar to spiderwebs but far larger and tougher. These masses
           must be anchored to two or more solid and diametrically oppose
          d points or else the web collapses upon itself and disappears. 
          Creatures caught within a web become grappled by the sticky fib
          ers. Attacking a creature in a web doesn’t cause you to become 
          grappled. Anyone in the effect’s area when the spell is cast mu
          st make a Reflex save. If this save succeeds, the creature is i
          nside the web but is otherwise unaffected. If the save fails, t
          he creature gains the grappled condition, but can break free by
           making a combat maneuver check or Escape Artist check as a sta
          ndard action against the DC of this spell. The entire area of t
          he web is considered difficult terrain. Anyone moving through t
          he webs must make a combat maneuver check or Escape Artist chec
          k as part of their move action, with a DC equal to the spell’s 
          DC. Creatures that fail lose their movement and become grappled
           in the first square of webbing that they enter. If you have at
           least 5 feet of web between you and an opponent, it provides c
          over. If you have at least 20 feet of web between you, it provi
          des total cover. The strands of a web spell are flammable. A fl
          aming weapon can slash them away as easily as a hand brushes aw
          ay cobwebs. Any fire can set the webs alight and burn away one 
          5-foot square in 1 round. All creatures within flaming webs tak
          e fire damage from the flames."},
      19      "Disguise Other": {"tier": 2, "save": "will", "items": ["po
          tion", "scroll", "oil", "wand"], "range": 1, "duration": "rank*
          100", "casting_time": 0.5, "skill": ["arcana", "perform_"], "pr
          operties": [], "effect_hash": {"disguise": {"enhancement": 1}},
           "description": "You make the target creature – including cloth
          ing, armor, weapons, and equipment – look different. They can s
          eem 1 foot shorter or taller, thin, fat, or in between. You can
          not change your creature type (although you can appear as anoth
          er subtype). Otherwise, the extent of the apparent change is up
           to you. You could add or obscure a minor feature or look like 
          an entirely different person or gender."},
      20      "Create Pit": {"tier": 2, "save": "reflex", "items": ["scro
          ll", "wand"], "range": 2, "duration": "rank", "casting_time": 0
          .5, "skill": ["arcana"], "properties": [], "effect_hash": {}, "
          description": "You create a 10-foot-by-10-foot extra-dimensiona
          l hole with a depth of 10 feet per two caster ranks (maximum 30
           feet). You must create the pit on a horizontal surface of suff
          icient size. Since it extends into another dimension, the pit h
          as no weight and does not otherwise displace the original under
          lying material. You can create the pit in the deck of a ship as
           easily as in a dungeon floor or the ground of a forest. Any cr
          eature standing in the area where you first conjured the pit mu
          st make a Reflex saving throw to jump to safety in the nearest 
          open space. In addition, the edges of the pit are sloped, and a
          ny creature ending its turn on a square adjacent to the pit mus
          t make a Reflex saving throw with a +1 bonus to avoid falling i
          nto it. Creatures subjected to an effect intended to push them 
          into the pit (such as bull rush) do not get a saving throw to a
          void falling in if they are affected by the pushing effect. Cre
          atures who fall into the pit take falling damage as normal. The
           pit’s coarse stone walls increase the Athletic check difficult
          y by 2. When the duration of the spell ends, creatures within t
          he hole rise up with the bottom of the pit until they are stand
          ing on the surface over the course of a single round."},

● Update(/home/user/crimson-steel/data/compendium.json)
  ⎿  Added 1 line, removed 1 line
      15      "Expeditious Retreat": {"tier": 1, "save": 0, "school": "en
          chantment", "items": ["potion", "scroll", "wand"], "range": 0, 
          "duration": "rank*10", "casting_time": 0.5, "skill": ["arcana",
           "perform_"], "properties": [], "effect_hash": {"speed": {"enha
          ncement": 30}}, "description": "This spell increases your base 
          land speed by 30 feet. This adjustment is treated as an enhance
          ment bonus. There is no effect on other modes of movement, such
           as burrow, climb, fly, or swim. As with any effect that increa
          ses your speed, this spell affects your jumping distance (see t
          he Acrobatics skill)."},
      16      "Darkness": {"tier": 2, "save": 0, "school": "evocation", "
          items": ["scroll", "oil", "wand"], "range": 1, "duration": "ran
          k*10", "casting_time": 0.5, "skill": ["arcana", "healing"], "pr
          operties": [], "effect_hash": {}, "description": "This spell ca
          uses an object to radiate darkness out to a 20-foot radius. Thi
          s darkness causes the illumination level in the area to drop on
          e step, from bright light to normal light, from normal light to
           dim light, or from dim light to darkness. This spell has no ef
          fect in an area that is already dark. Creatures with light vuln
          erability or sensitivity take no penalties in normal light. All
           creatures gain concealment in dim light. All creatures gain to
          tal concealment in darkness. Creatures with darkvision can see 
          in an area of dim light or darkness without penalty. Nonmagical
           sources of light, such as torches and lanterns, do not increas
          e the light level in an area of darkness. Magical light sources
           only increase the light level in an area if they are of a high
          er spell level than darkness. If darkness is cast on a small ob
          ject that is then placed inside or under a lightproof covering,
           the spell’s effect is blocked until the covering is removed."}
          ,
      17      "Invisibility": {"tier": 2, "save": "will", "school": "illu
          sion", "items": ["potion", "scroll", "oil", "wand"], "range": 1
          , "duration": "rank*10", "casting_time": 0.5, "skill": ["arcana
          ", "perform_"], "properties": [], "effect_hash": {}, "descripti
          on": "The creature or object touched radiates an aura of unimpo
          rtance preventing other creatures from noticing it or them. If 
          any creature realizes, or suspects, the target creature or obje
          ct are nearby then they can make a wisdom save as a main action
           to overcome the spell for it's duration. There is a penalty on
           this save if they do not know which square the creature or obj
          ect is in, and a cumulative penalty for every failed save. If a
          n attack is made by the target including any harmful spells cas
          t then all creatures within sight of the target immediatly gain
           the benefit of a successful save. Indirect actions, such as cu
          tting a rope bridge, or setting fire to a building do not grant
           an automatic save. This spell affects any objects carried by t
          he target when the spell is cast but not objects dropped or pic
          ked up after. Any part of an item that the subject carries but 
          that extends more than 10 feet from can be observed. This spell
           does not prevent creatures from noticing sounds or smells or o
          ther nonvisual clues to the targets existance."},
      18 -    "Web": {"tier": 2, "save": "reflex", "items": ["scroll", "w
         -and"], "range": 2, "duration": "rank*10", "casting_time": 0.5, 
         -"skill": ["arcana"], "properties": [], "effect_hash": {}, "desc
         -ription": "Web creates a many-layered mass of strong, sticky st
         -rands. These strands trap those caught in them. The strands are
         - similar to spiderwebs but far larger and tougher. These masses
         - must be anchored to two or more solid and diametrically oppose
         -d points or else the web collapses upon itself and disappears. 
         -Creatures caught within a web become grappled by the sticky fib
         -ers. Attacking a creature in a web doesn’t cause you to become 
         -grappled. Anyone in the effect’s area when the spell is cast mu
         -st make a Reflex save. If this save succeeds, the creature is i
         -nside the web but is otherwise unaffected. If the save fails, t
         -he creature gains the grappled condition, but can break free by
         - making a combat maneuver check or Escape Artist check as a sta
         -ndard action against the DC of this spell. The entire area of t
         -he web is considered difficult terrain. Anyone moving through t
         -he webs must make a combat maneuver check or Escape Artist chec
         -k as part of their move action, with a DC equal to the spell’s 
         -DC. Creatures that fail lose their movement and become grappled
         - in the first square of webbing that they enter. If you have at
         - least 5 feet of web between you and an opponent, it provides c
         -over. If you have at least 20 feet of web between you, it provi
         -des total cover. The strands of a web spell are flammable. A fl
         -aming weapon can slash them away as easily as a hand brushes aw
         -ay cobwebs. Any fire can set the webs alight and burn away one 
         -5-foot square in 1 round. All creatures within flaming webs tak
         -e fire damage from the flames."},                              
      18 +    "Web": {"tier": 2, "save": "reflex", "school": "conjuration
         +", "items": ["scroll", "wand"], "range": 2, "duration": "rank*1
         +0", "casting_time": 0.5, "skill": ["arcana"], "properties": [],
         + "effect_hash": {}, "description": "Web creates a many-layered 
         +mass of strong, sticky strands. These strands trap those caught
         + in them. The strands are similar to spiderwebs but far larger 
         +and tougher. These masses must be anchored to two or more solid
         + and diametrically opposed points or else the web collapses upo
         +n itself and disappears. Creatures caught within a web become g
         +rappled by the sticky fibers. Attacking a creature in a web doe
         +sn’t cause you to become grappled. Anyone in the effect’s area 
         +when the spell is cast must make a Reflex save. If this save su
         +cceeds, the creature is inside the web but is otherwise unaffec
         +ted. If the save fails, the creature gains the grappled conditi
         +on, but can break free by making a combat maneuver check or Esc
         +ape Artist check as a standard action against the DC of this sp
         +ell. The entire area of the web is considered difficult terrain
         +. Anyone moving through the webs must make a combat maneuver ch
         +eck or Escape Artist check as part of their move action, with a
         + DC equal to the spell’s DC. Creatures that fail lose their mov
         +ement and become grappled in the first square of webbing that t
         +hey enter. If you have at least 5 feet of web between you and a
         +n opponent, it provides cover. If you have at least 20 feet of 
         +web between you, it provides total cover. The strands of a web 
         +spell are flammable. A flaming weapon can slash them away as ea
         +sily as a hand brushes away cobwebs. Any fire can set the webs 
         +alight and burn away one 5-foot square in 1 round. All creature
         +s within flaming webs take fire damage from the flames."},     
      19      "Disguise Other": {"tier": 2, "save": "will", "items": ["po
          tion", "scroll", "oil", "wand"], "range": 1, "duration": "rank*
          100", "casting_time": 0.5, "skill": ["arcana", "perform_"], "pr
          operties": [], "effect_hash": {"disguise": {"enhancement": 1}},
           "description": "You make the target creature – including cloth
          ing, armor, weapons, and equipment – look different. They can s
          eem 1 foot shorter or taller, thin, fat, or in between. You can
          not change your creature type (although you can appear as anoth
          er subtype). Otherwise, the extent of the apparent change is up
           to you. You could add or obscure a minor feature or look like 
          an entirely different person or gender."},
      20      "Create Pit": {"tier": 2, "save": "reflex", "items": ["scro
          ll", "wand"], "range": 2, "duration": "rank", "casting_time": 0
          .5, "skill": ["arcana"], "properties": [], "effect_hash": {}, "
          description": "You create a 10-foot-by-10-foot extra-dimensiona
          l hole with a depth of 10 feet per two caster ranks (maximum 30
           feet). You must create the pit on a horizontal surface of suff
          icient size. Since it extends into another dimension, the pit h
          as no weight and does not otherwise displace the original under
          lying material. You can create the pit in the deck of a ship as
           easily as in a dungeon floor or the ground of a forest. Any cr
          eature standing in the area where you first conjured the pit mu
          st make a Reflex saving throw to jump to safety in the nearest 
          open space. In addition, the edges of the pit are sloped, and a
          ny creature ending its turn on a square adjacent to the pit mus
          t make a Reflex saving throw with a +1 bonus to avoid falling i
          nto it. Creatures subjected to an effect intended to push them 
          into the pit (such as bull rush) do not get a saving throw to a
          void falling in if they are affected by the pushing effect. Cre
          atures who fall into the pit take falling damage as normal. The
           pit’s coarse stone walls increase the Athletic check difficult
          y by 2. When the duration of the spell ends, creatures within t
          he hole rise up with the bottom of the pit until they are stand
          ing on the surface over the course of a single round."},
      21      "Silence": {"tier": 2, "save": "will", "items": ["scroll", 
          "wand"], "range": 3, "duration": "rank", "casting_time": 0.5, "
          skill": ["healing", "perform_"], "properties": [], "effect_hash
          ": {}, "description": "Upon the casting of this spell, complete
           silence prevails in the affected area. All sound is stopped: C
          onversation is impossible, spells with verbal components cannot
           be cast, and no noise whatsoever issues from, enters, or passe
          s through the area. The spell can be cast on a point in space, 
          but the effect is stationary unless cast on a mobile object. Th
          e spell can be centered on a creature, and the effect then radi
          ates from the creature and moves as it moves. An unwilling crea
          ture can attempt a Will save to negate the spell and can use Sp
          ell Resistance, if any. Items in a creature’s possession or mag
          ic items that emit sound receive the benefits of saves and Spel
          l Resistance, but unattended objects and points in space do not
          . Creatures in an area of a silence spell are immune to sonic o
          r language-based attacks, spells, and effects."},

● Update(/home/user/crimson-steel/data/compendium.json)
  ⎿  Added 1 line, removed 1 line
      16      "Darkness": {"tier": 2, "save": 0, "school": "evocation", "
          items": ["scroll", "oil", "wand"], "range": 1, "duration": "ran
          k*10", "casting_time": 0.5, "skill": ["arcana", "healing"], "pr
          operties": [], "effect_hash": {}, "description": "This spell ca
          uses an object to radiate darkness out to a 20-foot radius. Thi
          s darkness causes the illumination level in the area to drop on
          e step, from bright light to normal light, from normal light to
           dim light, or from dim light to darkness. This spell has no ef
          fect in an area that is already dark. Creatures with light vuln
          erability or sensitivity take no penalties in normal light. All
           creatures gain concealment in dim light. All creatures gain to
          tal concealment in darkness. Creatures with darkvision can see 
          in an area of dim light or darkness without penalty. Nonmagical
           sources of light, such as torches and lanterns, do not increas
          e the light level in an area of darkness. Magical light sources
           only increase the light level in an area if they are of a high
          er spell level than darkness. If darkness is cast on a small ob
          ject that is then placed inside or under a lightproof covering,
           the spell’s effect is blocked until the covering is removed."}
          ,
      17      "Invisibility": {"tier": 2, "save": "will", "school": "illu
          sion", "items": ["potion", "scroll", "oil", "wand"], "range": 1
          , "duration": "rank*10", "casting_time": 0.5, "skill": ["arcana
          ", "perform_"], "properties": [], "effect_hash": {}, "descripti
          on": "The creature or object touched radiates an aura of unimpo
          rtance preventing other creatures from noticing it or them. If 
          any creature realizes, or suspects, the target creature or obje
          ct are nearby then they can make a wisdom save as a main action
           to overcome the spell for it's duration. There is a penalty on
           this save if they do not know which square the creature or obj
          ect is in, and a cumulative penalty for every failed save. If a
          n attack is made by the target including any harmful spells cas
          t then all creatures within sight of the target immediatly gain
           the benefit of a successful save. Indirect actions, such as cu
          tting a rope bridge, or setting fire to a building do not grant
           an automatic save. This spell affects any objects carried by t
          he target when the spell is cast but not objects dropped or pic
          ked up after. Any part of an item that the subject carries but 
          that extends more than 10 feet from can be observed. This spell
           does not prevent creatures from noticing sounds or smells or o
          ther nonvisual clues to the targets existance."},
      18      "Web": {"tier": 2, "save": "reflex", "school": "conjuration
          ", "items": ["scroll", "wand"], "range": 2, "duration": "rank*1
          0", "casting_time": 0.5, "skill": ["arcana"], "properties": [],
           "effect_hash": {}, "description": "Web creates a many-layered 
          mass of strong, sticky strands. These strands trap those caught
           in them. The strands are similar to spiderwebs but far larger 
          and tougher. These masses must be anchored to two or more solid
           and diametrically opposed points or else the web collapses upo
          n itself and disappears. Creatures caught within a web become g
          rappled by the sticky fibers. Attacking a creature in a web doe
          sn’t cause you to become grappled. Anyone in the effect’s area 
          when the spell is cast must make a Reflex save. If this save su
          cceeds, the creature is inside the web but is otherwise unaffec
          ted. If the save fails, the creature gains the grappled conditi
          on, but can break free by making a combat maneuver check or Esc
          ape Artist check as a standard action against the DC of this sp
          ell. The entire area of the web is considered difficult terrain
          . Anyone moving through the webs must make a combat maneuver ch
          eck or Escape Artist check as part of their move action, with a
           DC equal to the spell’s DC. Creatures that fail lose their mov
          ement and become grappled in the first square of webbing that t
          hey enter. If you have at least 5 feet of web between you and a
          n opponent, it provides cover. If you have at least 20 feet of 
          web between you, it provides total cover. The strands of a web 
          spell are flammable. A flaming weapon can slash them away as ea
          sily as a hand brushes away cobwebs. Any fire can set the webs 
          alight and burn away one 5-foot square in 1 round. All creature
          s within flaming webs take fire damage from the flames."},
      19 -    "Disguise Other": {"tier": 2, "save": "will", "items": ["po
         -tion", "scroll", "oil", "wand"], "range": 1, "duration": "rank*
         -100", "casting_time": 0.5, "skill": ["arcana", "perform_"], "pr
         -operties": [], "effect_hash": {"disguise": {"enhancement": 1}},
         - "description": "You make the target creature – including cloth
         -ing, armor, weapons, and equipment – look different. They can s
         -eem 1 foot shorter or taller, thin, fat, or in between. You can
         -not change your creature type (although you can appear as anoth
         -er subtype). Otherwise, the extent of the apparent change is up
         - to you. You could add or obscure a minor feature or look like 
         -an entirely different person or gender."},                     
      19 +    "Disguise Other": {"tier": 2, "save": "will", "school": "il
         +lusion", "items": ["potion", "scroll", "oil", "wand"], "range":
         + 1, "duration": "rank*100", "casting_time": 0.5, "skill": ["arc
         +ana", "perform_"], "properties": [], "effect_hash": {"disguise"
         +: {"enhancement": 1}}, "description": "You make the target crea
         +ture – including clothing, armor, weapons, and equipment – look
         + different. They can seem 1 foot shorter or taller, thin, fat, 
         +or in between. You cannot change your creature type (although y
         +ou can appear as another subtype). Otherwise, the extent of the
         + apparent change is up to you. You could add or obscure a minor
         + feature or look like an entirely different person or gender."}
         +,                                                              
      20      "Create Pit": {"tier": 2, "save": "reflex", "items": ["scro
          ll", "wand"], "range": 2, "duration": "rank", "casting_time": 0
          .5, "skill": ["arcana"], "properties": [], "effect_hash": {}, "
          description": "You create a 10-foot-by-10-foot extra-dimensiona
          l hole with a depth of 10 feet per two caster ranks (maximum 30
           feet). You must create the pit on a horizontal surface of suff
          icient size. Since it extends into another dimension, the pit h
          as no weight and does not otherwise displace the original under
          lying material. You can create the pit in the deck of a ship as
           easily as in a dungeon floor or the ground of a forest. Any cr
          eature standing in the area where you first conjured the pit mu
          st make a Reflex saving throw to jump to safety in the nearest 
          open space. In addition, the edges of the pit are sloped, and a
          ny creature ending its turn on a square adjacent to the pit mus
          t make a Reflex saving throw with a +1 bonus to avoid falling i
          nto it. Creatures subjected to an effect intended to push them 
          into the pit (such as bull rush) do not get a saving throw to a
          void falling in if they are affected by the pushing effect. Cre
          atures who fall into the pit take falling damage as normal. The
           pit’s coarse stone walls increase the Athletic check difficult
          y by 2. When the duration of the spell ends, creatures within t
          he hole rise up with the bottom of the pit until they are stand
          ing on the surface over the course of a single round."},
      21      "Silence": {"tier": 2, "save": "will", "items": ["scroll", 
          "wand"], "range": 3, "duration": "rank", "casting_time": 0.5, "
          skill": ["healing", "perform_"], "properties": [], "effect_hash
          ": {}, "description": "Upon the casting of this spell, complete
           silence prevails in the affected area. All sound is stopped: C
          onversation is impossible, spells with verbal components cannot
           be cast, and no noise whatsoever issues from, enters, or passe
          s through the area. The spell can be cast on a point in space, 
          but the effect is stationary unless cast on a mobile object. Th
          e spell can be centered on a creature, and the effect then radi
          ates from the creature and moves as it moves. An unwilling crea
          ture can attempt a Will save to negate the spell and can use Sp
          ell Resistance, if any. Items in a creature’s possession or mag
          ic items that emit sound receive the benefits of saves and Spel
          l Resistance, but unattended objects and points in space do not
          . Creatures in an area of a silence spell are immune to sonic o
          r language-based attacks, spells, and effects."},
      22      "Spiritual Weapon": {"tier": 2, "save": 0, "items": ["scrol
          l", "wand"], "range": 0, "duration": "rank", "casting_time": 0.
          5, "skill": ["healing"], "properties": [], "effect_hash": {}, "
          description": "A weapon made of force appears and attacks foes 
          at a distance, as you direct it, dealing force damage. The weap
          on takes the shape of a weapon favored by your deity or a weapo
          n with some spiritual significance or symbolism to you and has 
          the same properties as a real weapon of its form. It strikes th
          e opponent you designate, starting with one attack in the round
           the spell is cast and continuing each round thereafter on your
           turn. It uses the casting bonus and number of dice used to cas
          t the spell for it's attacks.  As a force effect, it can strike
           incorporeal creatures without the reduction in damage associat
          ed with incorporeality. The weapon always strikes from your dir
          ection. If the weapon goes beyond the spell range, if it goes o
          ut of your sight, or if you are not directing it, the weapon re
          turns to you and hovers. Each round after the first, you can us
          e a main action to redirect the weapon to a new target. If you 
          do not, the weapon continues to attack the previous round’s tar
          get. The weapon gains one attack per round. Even if the spiritu
          al weapon is a ranged weapon, use the spell’s range, not the we
          apon’s normal range, and switching targets still is a main acti
          on."}},

● Update(/home/user/crimson-steel/data/compendium.json)
  ⎿  Added 1 line, removed 1 line
      17      "Invisibility": {"tier": 2, "save": "will", "school": "illu
          sion", "items": ["potion", "scroll", "oil", "wand"], "range": 1
          , "duration": "rank*10", "casting_time": 0.5, "skill": ["arcana
          ", "perform_"], "properties": [], "effect_hash": {}, "descripti
          on": "The creature or object touched radiates an aura of unimpo
          rtance preventing other creatures from noticing it or them. If 
          any creature realizes, or suspects, the target creature or obje
          ct are nearby then they can make a wisdom save as a main action
           to overcome the spell for it's duration. There is a penalty on
           this save if they do not know which square the creature or obj
          ect is in, and a cumulative penalty for every failed save. If a
          n attack is made by the target including any harmful spells cas
          t then all creatures within sight of the target immediatly gain
           the benefit of a successful save. Indirect actions, such as cu
          tting a rope bridge, or setting fire to a building do not grant
           an automatic save. This spell affects any objects carried by t
          he target when the spell is cast but not objects dropped or pic
          ked up after. Any part of an item that the subject carries but 
          that extends more than 10 feet from can be observed. This spell
           does not prevent creatures from noticing sounds or smells or o
          ther nonvisual clues to the targets existance."},
      18      "Web": {"tier": 2, "save": "reflex", "school": "conjuration
          ", "items": ["scroll", "wand"], "range": 2, "duration": "rank*1
          0", "casting_time": 0.5, "skill": ["arcana"], "properties": [],
           "effect_hash": {}, "description": "Web creates a many-layered 
          mass of strong, sticky strands. These strands trap those caught
           in them. The strands are similar to spiderwebs but far larger 
          and tougher. These masses must be anchored to two or more solid
           and diametrically opposed points or else the web collapses upo
          n itself and disappears. Creatures caught within a web become g
          rappled by the sticky fibers. Attacking a creature in a web doe
          sn’t cause you to become grappled. Anyone in the effect’s area 
          when the spell is cast must make a Reflex save. If this save su
          cceeds, the creature is inside the web but is otherwise unaffec
          ted. If the save fails, the creature gains the grappled conditi
          on, but can break free by making a combat maneuver check or Esc
          ape Artist check as a standard action against the DC of this sp
          ell. The entire area of the web is considered difficult terrain
          . Anyone moving through the webs must make a combat maneuver ch
          eck or Escape Artist check as part of their move action, with a
           DC equal to the spell’s DC. Creatures that fail lose their mov
          ement and become grappled in the first square of webbing that t
          hey enter. If you have at least 5 feet of web between you and a
          n opponent, it provides cover. If you have at least 20 feet of 
          web between you, it provides total cover. The strands of a web 
          spell are flammable. A flaming weapon can slash them away as ea
          sily as a hand brushes away cobwebs. Any fire can set the webs 
          alight and burn away one 5-foot square in 1 round. All creature
          s within flaming webs take fire damage from the flames."},
      19      "Disguise Other": {"tier": 2, "save": "will", "school": "il
          lusion", "items": ["potion", "scroll", "oil", "wand"], "range":
           1, "duration": "rank*100", "casting_time": 0.5, "skill": ["arc
          ana", "perform_"], "properties": [], "effect_hash": {"disguise"
          : {"enhancement": 1}}, "description": "You make the target crea
          ture – including clothing, armor, weapons, and equipment – look
           different. They can seem 1 foot shorter or taller, thin, fat, 
          or in between. You cannot change your creature type (although y
          ou can appear as another subtype). Otherwise, the extent of the
           apparent change is up to you. You could add or obscure a minor
           feature or look like an entirely different person or gender."}
          ,
      20 -    "Create Pit": {"tier": 2, "save": "reflex", "items": ["scro
         -ll", "wand"], "range": 2, "duration": "rank", "casting_time": 0
         -.5, "skill": ["arcana"], "properties": [], "effect_hash": {}, "
         -description": "You create a 10-foot-by-10-foot extra-dimensiona
         -l hole with a depth of 10 feet per two caster ranks (maximum 30
         - feet). You must create the pit on a horizontal surface of suff
         -icient size. Since it extends into another dimension, the pit h
         -as no weight and does not otherwise displace the original under
         -lying material. You can create the pit in the deck of a ship as
         - easily as in a dungeon floor or the ground of a forest. Any cr
         -eature standing in the area where you first conjured the pit mu
         -st make a Reflex saving throw to jump to safety in the nearest 
         -open space. In addition, the edges of the pit are sloped, and a
         -ny creature ending its turn on a square adjacent to the pit mus
         -t make a Reflex saving throw with a +1 bonus to avoid falling i
         -nto it. Creatures subjected to an effect intended to push them 
         -into the pit (such as bull rush) do not get a saving throw to a
         -void falling in if they are affected by the pushing effect. Cre
         -atures who fall into the pit take falling damage as normal. The
         - pit’s coarse stone walls increase the Athletic check difficult
         -y by 2. When the duration of the spell ends, creatures within t
         -he hole rise up with the bottom of the pit until they are stand
         -ing on the surface over the course of a single round."},       
      20 +    "Create Pit": {"tier": 2, "save": "reflex", "school": "conj
         +uration", "items": ["scroll", "wand"], "range": 2, "duration": 
         +"rank", "casting_time": 0.5, "skill": ["arcana"], "properties":
         + [], "effect_hash": {}, "description": "You create a 10-foot-by
         +-10-foot extra-dimensional hole with a depth of 10 feet per two
         + caster ranks (maximum 30 feet). You must create the pit on a h
         +orizontal surface of sufficient size. Since it extends into ano
         +ther dimension, the pit has no weight and does not otherwise di
         +splace the original underlying material. You can create the pit
         + in the deck of a ship as easily as in a dungeon floor or the g
         +round of a forest. Any creature standing in the area where you 
         +first conjured the pit must make a Reflex saving throw to jump 
         +to safety in the nearest open space. In addition, the edges of 
         +the pit are sloped, and any creature ending its turn on a squar
         +e adjacent to the pit must make a Reflex saving throw with a +1
         + bonus to avoid falling into it. Creatures subjected to an effe
         +ct intended to push them into the pit (such as bull rush) do no
         +t get a saving throw to avoid falling in if they are affected b
         +y the pushing effect. Creatures who fall into the pit take fall
         +ing damage as normal. The pit’s coarse stone walls increase the
         + Athletic check difficulty by 2. When the duration of the spell
         + ends, creatures within the hole rise up with the bottom of the
         + pit until they are standing on the surface over the course of 
         +a single round."},                                             
      21      "Silence": {"tier": 2, "save": "will", "items": ["scroll", 
          "wand"], "range": 3, "duration": "rank", "casting_time": 0.5, "
          skill": ["healing", "perform_"], "properties": [], "effect_hash
          ": {}, "description": "Upon the casting of this spell, complete
           silence prevails in the affected area. All sound is stopped: C
          onversation is impossible, spells with verbal components cannot
           be cast, and no noise whatsoever issues from, enters, or passe
          s through the area. The spell can be cast on a point in space, 
          but the effect is stationary unless cast on a mobile object. Th
          e spell can be centered on a creature, and the effect then radi
          ates from the creature and moves as it moves. An unwilling crea
          ture can attempt a Will save to negate the spell and can use Sp
          ell Resistance, if any. Items in a creature’s possession or mag
          ic items that emit sound receive the benefits of saves and Spel
          l Resistance, but unattended objects and points in space do not
          . Creatures in an area of a silence spell are immune to sonic o
          r language-based attacks, spells, and effects."},
      22      "Spiritual Weapon": {"tier": 2, "save": 0, "items": ["scrol
          l", "wand"], "range": 0, "duration": "rank", "casting_time": 0.
          5, "skill": ["healing"], "properties": [], "effect_hash": {}, "
          description": "A weapon made of force appears and attacks foes 
          at a distance, as you direct it, dealing force damage. The weap
          on takes the shape of a weapon favored by your deity or a weapo
          n with some spiritual significance or symbolism to you and has 
          the same properties as a real weapon of its form. It strikes th
          e opponent you designate, starting with one attack in the round
           the spell is cast and continuing each round thereafter on your
           turn. It uses the casting bonus and number of dice used to cas
          t the spell for it's attacks.  As a force effect, it can strike
           incorporeal creatures without the reduction in damage associat
          ed with incorporeality. The weapon always strikes from your dir
          ection. If the weapon goes beyond the spell range, if it goes o
          ut of your sight, or if you are not directing it, the weapon re
          turns to you and hovers. Each round after the first, you can us
          e a main action to redirect the weapon to a new target. If you 
          do not, the weapon continues to attack the previous round’s tar
          get. The weapon gains one attack per round. Even if the spiritu
          al weapon is a ranged weapon, use the spell’s range, not the we
          apon’s normal range, and switching targets still is a main acti
          on."}},
      23    "abilities": {

● Update(/home/user/crimson-steel/data/compendium.json)
  ⎿  Added 1 line, removed 1 line
      18      "Web": {"tier": 2, "save": "reflex", "school": "conjuration
          ", "items": ["scroll", "wand"], "range": 2, "duration": "rank*1
          0", "casting_time": 0.5, "skill": ["arcana"], "properties": [],
           "effect_hash": {}, "description": "Web creates a many-layered 
          mass of strong, sticky strands. These strands trap those caught
           in them. The strands are similar to spiderwebs but far larger 
          and tougher. These masses must be anchored to two or more solid
           and diametrically opposed points or else the web collapses upo
          n itself and disappears. Creatures caught within a web become g
          rappled by the sticky fibers. Attacking a creature in a web doe
          sn’t cause you to become grappled. Anyone in the effect’s area 
          when the spell is cast must make a Reflex save. If this save su
          cceeds, the creature is inside the web but is otherwise unaffec
          ted. If the save fails, the creature gains the grappled conditi
          on, but can break free by making a combat maneuver check or Esc
          ape Artist check as a standard action against the DC of this sp
          ell. The entire area of the web is considered difficult terrain
          . Anyone moving through the webs must make a combat maneuver ch
          eck or Escape Artist check as part of their move action, with a
           DC equal to the spell’s DC. Creatures that fail lose their mov
          ement and become grappled in the first square of webbing that t
          hey enter. If you have at least 5 feet of web between you and a
          n opponent, it provides cover. If you have at least 20 feet of 
          web between you, it provides total cover. The strands of a web 
          spell are flammable. A flaming weapon can slash them away as ea
          sily as a hand brushes away cobwebs. Any fire can set the webs 
          alight and burn away one 5-foot square in 1 round. All creature
          s within flaming webs take fire damage from the flames."},
      19      "Disguise Other": {"tier": 2, "save": "will", "school": "il
          lusion", "items": ["potion", "scroll", "oil", "wand"], "range":
           1, "duration": "rank*100", "casting_time": 0.5, "skill": ["arc
          ana", "perform_"], "properties": [], "effect_hash": {"disguise"
          : {"enhancement": 1}}, "description": "You make the target crea
          ture – including clothing, armor, weapons, and equipment – look
           different. They can seem 1 foot shorter or taller, thin, fat, 
          or in between. You cannot change your creature type (although y
          ou can appear as another subtype). Otherwise, the extent of the
           apparent change is up to you. You could add or obscure a minor
           feature or look like an entirely different person or gender."}
          ,
      20      "Create Pit": {"tier": 2, "save": "reflex", "school": "conj
          uration", "items": ["scroll", "wand"], "range": 2, "duration": 
          "rank", "casting_time": 0.5, "skill": ["arcana"], "properties":
           [], "effect_hash": {}, "description": "You create a 10-foot-by
          -10-foot extra-dimensional hole with a depth of 10 feet per two
           caster ranks (maximum 30 feet). You must create the pit on a h
          orizontal surface of sufficient size. Since it extends into ano
          ther dimension, the pit has no weight and does not otherwise di
          splace the original underlying material. You can create the pit
           in the deck of a ship as easily as in a dungeon floor or the g
          round of a forest. Any creature standing in the area where you 
          first conjured the pit must make a Reflex saving throw to jump 
          to safety in the nearest open space. In addition, the edges of 
          the pit are sloped, and any creature ending its turn on a squar
          e adjacent to the pit must make a Reflex saving throw with a +1
           bonus to avoid falling into it. Creatures subjected to an effe
          ct intended to push them into the pit (such as bull rush) do no
          t get a saving throw to avoid falling in if they are affected b
          y the pushing effect. Creatures who fall into the pit take fall
          ing damage as normal. The pit’s coarse stone walls increase the
           Athletic check difficulty by 2. When the duration of the spell
           ends, creatures within the hole rise up with the bottom of the
           pit until they are standing on the surface over the course of 
          a single round."},
      21 -    "Silence": {"tier": 2, "save": "will", "items": ["scroll", 
         -"wand"], "range": 3, "duration": "rank", "casting_time": 0.5, "
         -skill": ["healing", "perform_"], "properties": [], "effect_hash
         -": {}, "description": "Upon the casting of this spell, complete
         - silence prevails in the affected area. All sound is stopped: C
         -onversation is impossible, spells with verbal components cannot
         - be cast, and no noise whatsoever issues from, enters, or passe
         -s through the area. The spell can be cast on a point in space, 
         -but the effect is stationary unless cast on a mobile object. Th
         -e spell can be centered on a creature, and the effect then radi
         -ates from the creature and moves as it moves. An unwilling crea
         -ture can attempt a Will save to negate the spell and can use Sp
         -ell Resistance, if any. Items in a creature’s possession or mag
         -ic items that emit sound receive the benefits of saves and Spel
         -l Resistance, but unattended objects and points in space do not
         -. Creatures in an area of a silence spell are immune to sonic o
         -r language-based attacks, spells, and effects."},              
      21 +    "Silence": {"tier": 2, "save": "will", "school": "evocation
         +", "items": ["scroll", "wand"], "range": 3, "duration": "rank",
         + "casting_time": 0.5, "skill": ["healing", "perform_"], "proper
         +ties": [], "effect_hash": {}, "description": "Upon the casting 
         +of this spell, complete silence prevails in the affected area. 
         +All sound is stopped: Conversation is impossible, spells with v
         +erbal components cannot be cast, and no noise whatsoever issues
         + from, enters, or passes through the area. The spell can be cas
         +t on a point in space, but the effect is stationary unless cast
         + on a mobile object. The spell can be centered on a creature, a
         +nd the effect then radiates from the creature and moves as it m
         +oves. An unwilling creature can attempt a Will save to negate t
         +he spell and can use Spell Resistance, if any. Items in a creat
         +ure’s possession or magic items that emit sound receive the ben
         +efits of saves and Spell Resistance, but unattended objects and
         + points in space do not. Creatures in an area of a silence spel
         +l are immune to sonic or language-based attacks, spells, and ef
         +fects."},                                                      
      22      "Spiritual Weapon": {"tier": 2, "save": 0, "items": ["scrol
          l", "wand"], "range": 0, "duration": "rank", "casting_time": 0.
          5, "skill": ["healing"], "properties": [], "effect_hash": {}, "
          description": "A weapon made of force appears and attacks foes 
          at a distance, as you direct it, dealing force damage. The weap
          on takes the shape of a weapon favored by your deity or a weapo
          n with some spiritual significance or symbolism to you and has 
          the same properties as a real weapon of its form. It strikes th
          e opponent you designate, starting with one attack in the round
           the spell is cast and continuing each round thereafter on your
           turn. It uses the casting bonus and number of dice used to cas
          t the spell for it's attacks.  As a force effect, it can strike
           incorporeal creatures without the reduction in damage associat
          ed with incorporeality. The weapon always strikes from your dir
          ection. If the weapon goes beyond the spell range, if it goes o
          ut of your sight, or if you are not directing it, the weapon re
          turns to you and hovers. Each round after the first, you can us
          e a main action to redirect the weapon to a new target. If you 
          do not, the weapon continues to attack the previous round’s tar
          get. The weapon gains one attack per round. Even if the spiritu
          al weapon is a ranged weapon, use the spell’s range, not the we
          apon’s normal range, and switching targets still is a main acti
          on."}},
      23    "abilities": {
      24      "bardic_inspiration": "During your magical performance you 
          can use your performance to inspire your allies or distract you
          r enemies. This creates a pool of luck that can be spent by you
           or your team to reroll dice on any check your or they make. Ea
          ch point must be spent before the initial check is made, and ea
          ch point will allow a single reroll. Using this ability costs o
          ne point of mana and can only be used once per turn. This is a 
          main action that can be used as part of maintaining your perfor
          mance but only if that action is not used for any other purpose
           such as casting a spell. You gain one point of luck per succes
          s, and each point must be used before your next turn or it is l
          ost. Fumbling grants all failures to the DM to be used for the 
          enemy, or against the players.",
● Update(/home/user/crimson-steel/data/compendium.json)
  ⎿  Added 1 line, removed 1 line
      19      "Disguise Other": {"tier": 2, "save": "will", "school": "il
          lusion", "items": ["potion", "scroll", "oil", "wand"], "range":
           1, "duration": "rank*100", "casting_time": 0.5, "skill": ["arc
          ana", "perform_"], "properties": [], "effect_hash": {"disguise"
          : {"enhancement": 1}}, "description": "You make the target crea
          ture – including clothing, armor, weapons, and equipment – look
           different. They can seem 1 foot shorter or taller, thin, fat, 
          or in between. You cannot change your creature type (although y
          ou can appear as another subtype). Otherwise, the extent of the
           apparent change is up to you. You could add or obscure a minor
           feature or look like an entirely different person or gender."}
          ,
      20      "Create Pit": {"tier": 2, "save": "reflex", "school": "conj
          uration", "items": ["scroll", "wand"], "range": 2, "duration": 
          "rank", "casting_time": 0.5, "skill": ["arcana"], "properties":
           [], "effect_hash": {}, "description": "You create a 10-foot-by
          -10-foot extra-dimensional hole with a depth of 10 feet per two
           caster ranks (maximum 30 feet). You must create the pit on a h
          orizontal surface of sufficient size. Since it extends into ano
          ther dimension, the pit has no weight and does not otherwise di
          splace the original underlying material. You can create the pit
           in the deck of a ship as easily as in a dungeon floor or the g
          round of a forest. Any creature standing in the area where you 
          first conjured the pit must make a Reflex saving throw to jump 
          to safety in the nearest open space. In addition, the edges of 
          the pit are sloped, and any creature ending its turn on a squar
          e adjacent to the pit must make a Reflex saving throw with a +1
           bonus to avoid falling into it. Creatures subjected to an effe
          ct intended to push them into the pit (such as bull rush) do no
          t get a saving throw to avoid falling in if they are affected b
          y the pushing effect. Creatures who fall into the pit take fall
          ing damage as normal. The pit’s coarse stone walls increase the
           Athletic check difficulty by 2. When the duration of the spell
           ends, creatures within the hole rise up with the bottom of the
           pit until they are standing on the surface over the course of 
          a single round."},
      21      "Silence": {"tier": 2, "save": "will", "school": "evocation
          ", "items": ["scroll", "wand"], "range": 3, "duration": "rank",
           "casting_time": 0.5, "skill": ["healing", "perform_"], "proper
          ties": [], "effect_hash": {}, "description": "Upon the casting 
          of this spell, complete silence prevails in the affected area. 
          All sound is stopped: Conversation is impossible, spells with v
          erbal components cannot be cast, and no noise whatsoever issues
           from, enters, or passes through the area. The spell can be cas
          t on a point in space, but the effect is stationary unless cast
           on a mobile object. The spell can be centered on a creature, a
          nd the effect then radiates from the creature and moves as it m
          oves. An unwilling creature can attempt a Will save to negate t
          he spell and can use Spell Resistance, if any. Items in a creat
          ure’s possession or magic items that emit sound receive the ben
          efits of saves and Spell Resistance, but unattended objects and
           points in space do not. Creatures in an area of a silence spel
          l are immune to sonic or language-based attacks, spells, and ef
          fects."},
      22 -    "Spiritual Weapon": {"tier": 2, "save": 0, "items": ["scrol
         -l", "wand"], "range": 0, "duration": "rank", "casting_time": 0.
         -5, "skill": ["healing"], "properties": [], "effect_hash": {}, "
         -description": "A weapon made of force appears and attacks foes 
         -at a distance, as you direct it, dealing force damage. The weap
         -on takes the shape of a weapon favored by your deity or a weapo
         -n with some spiritual significance or symbolism to you and has 
         -the same properties as a real weapon of its form. It strikes th
         -e opponent you designate, starting with one attack in the round
         - the spell is cast and continuing each round thereafter on your
         - turn. It uses the casting bonus and number of dice used to cas
         -t the spell for it's attacks.  As a force effect, it can strike
         - incorporeal creatures without the reduction in damage associat
         -ed with incorporeality. The weapon always strikes from your dir
         -ection. If the weapon goes beyond the spell range, if it goes o
         -ut of your sight, or if you are not directing it, the weapon re
         -turns to you and hovers. Each round after the first, you can us
         -e a main action to redirect the weapon to a new target. If you 
         -do not, the weapon continues to attack the previous round’s tar
         -get. The weapon gains one attack per round. Even if the spiritu
         -al weapon is a ranged weapon, use the spell’s range, not the we
         -apon’s normal range, and switching targets still is a main acti
         -on."}},                                                        
      22 +    "Spiritual Weapon": {"tier": 2, "save": 0, "school": "evoca
         +tion", "items": ["scroll", "wand"], "range": 0, "duration": "ra
         +nk", "casting_time": 0.5, "skill": ["healing"], "properties": [
         +], "effect_hash": {}, "description": "A weapon made of force ap
         +pears and attacks foes at a distance, as you direct it, dealing
         + force damage. The weapon takes the shape of a weapon favored b
         +y your deity or a weapon with some spiritual significance or sy
         +mbolism to you and has the same properties as a real weapon of 
         +its form. It strikes the opponent you designate, starting with 
         +one attack in the round the spell is cast and continuing each r
         +ound thereafter on your turn. It uses the casting bonus and num
         +ber of dice used to cast the spell for it's attacks.  As a forc
         +e effect, it can strike incorporeal creatures without the reduc
         +tion in damage associated with incorporeality. The weapon alway
         +s strikes from your direction. If the weapon goes beyond the sp
         +ell range, if it goes out of your sight, or if you are not dire
         +cting it, the weapon returns to you and hovers. Each round afte
         +r the first, you can use a main action to redirect the weapon t
         +o a new target. If you do not, the weapon continues to attack t
         +he previous round’s target. The weapon gains one attack per rou
         +nd. Even if the spiritual weapon is a ranged weapon, use the sp
         +ell’s range, not the weapon’s normal range, and switching targe
         +ts still is a main action."}},                                 
      23    "abilities": {
      24      "bardic_inspiration": "During your magical performance you 
          can use your performance to inspire your allies or distract you
          r enemies. This creates a pool of luck that can be spent by you
           or your team to reroll dice on any check your or they make. Ea
          ch point must be spent before the initial check is made, and ea
          ch point will allow a single reroll. Using this ability costs o
          ne point of mana and can only be used once per turn. This is a 
          main action that can be used as part of maintaining your perfor
          mance but only if that action is not used for any other purpose
           such as casting a spell. You gain one point of luck per succes
          s, and each point must be used before your next turn or it is l
          ost. Fumbling grants all failures to the DM to be used for the 
          enemy, or against the players.",
      25      "better_lucky_than_good": "You may spend 3 mana during any 
          round that you are unable to act such as the surprise round. Al
          l attacks against you, including spells, are made with half as 
          many dice with a minimum of 3 dice. Enemies are unconsciously a
          ware of this penalty and may instead choose to target your alli
          es instead or use 3 dice on the attack.",

● Now let me create the spell list view and spell description view, add routes,
  update navigation, and CSS. I'll do the template files in parallel.

● Write(/home/user/crimson-steel/views/spell_list.erb)
  ⎿  Wrote 178 lines to ../../../user/crimson-steel/views/spell_list.erb
       1 <div class="sheet">
       2   <div class="header">
       3     <h1>Spell Compendium</h1>
       4   </div>
       5 
       6   <div class="spell-filters">
       7     <div class="filter-row">
       8       <div class="filter-field">
       9         <label for="filter-school">School</label>
      10         <select id="filter-school" onchange="filterSpells()">
     … +190 lines (ctrl+o to expand)

● Write(/home/user/crimson-steel/views/spell_detail.erb)
  ⎿  Wrote 113 lines to ../../../user/crimson-steel/views/spell_detail.erb
       2   <div class="header">
       3     <h1><%= @spell_name %></h1>
       4     <div class="subtitle">
       5       <span class="school-badge school-<%= @school %>"><%= @scho
         ol.capitalize %></span>
       7         Tier <%= @spell["tier"].first %> - <%= @spell["tier"].la
         st %>
       8       <% else %>
       9         Tier <%= @spell["tier"] %>
      10       <% end %>
     … +117 lines (ctrl+o to expand)

● Now add the routes to app.rb, the navigation link, helper method, character
  sheet links, and CSS — all in parallel:

● Update(/home/user/crimson-steel/app.rb)
  ⎿  Added 48 lines
      355    redirect "/notes/#{params[:owner_id]}"
      356  end
      357  
      358 +get '/spells' do                                              
      359 +  compendium = Compendium.new                                 
      360 +  @spells = compendium.data["spells"]                         
      361 +  @spell_schools = compendium.data["spell_schools"] || ["unive
          +rsal", "necromancy", "evocation", "illusion", "enchantment", "
          +divination", "abjuration", "conjuration"]                     
      362 +  @range_labels = compendium.data["range"]                    
      363 +  @all_skills = @spells.values.flat_map { |s| s["skill"] || []
          + }.uniq.sort                                                  
      364 +  erb :spell_list                                             
      365 +end                                                           
      366 +                                                              
      367 +get '/spell/:name' do                                         
      368 +  compendium = Compendium.new                                 
      369 +  @spell_name = params[:name]                                 
      370 +  @spell = compendium.data["spells"][@spell_name]             
      371 +  halt 404, "Spell not found" unless @spell                   
      372 +  @school = @spell["school"] || "universal"                   
      373 +  @range_labels = compendium.data["range"]                    
      374 +  erb :spell_detail                                           
      375 +end                                                           
      376 +                                                              
      377 +post '/spells/add' do                                         
      378 +  redirect '/spells' unless local_request?                    
      379 +  compendium_data = Tools.load_json('compendium.json')        
      380 +                                                              
      381 +  tiers = params[:tiers].split(',').map(&:strip).map(&:to_i)  
      382 +  tiers = tiers.length == 1 ? tiers.first : tiers             
      383 +                                                              
      384 +  save_val = params[:save] == "0" ? 0 : params[:save]         
      385 +  skills = params[:skills].to_s.split(',').map(&:strip).reject
          +(&:empty?)                                                    
      386 +  items = params[:items].to_s.split(',').map(&:strip).reject(&
          +:empty?)                                                      
      387 +                                                              
      388 +  compendium_data["spells"][params[:name]] = {                
      389 +    "tier" => tiers,                                          
      390 +    "save" => save_val,                                       
      391 +    "school" => params[:school] || "universal",               
      392 +    "items" => items.empty? ? [] : items,                     
      393 +    "range" => params[:range].to_i,                           
      394 +    "duration" => params[:duration] || "instant",             
      395 +    "casting_time" => params[:casting_time].to_f,             
      396 +    "skill" => skills,                                        
      397 +    "properties" => [],                                       
      398 +    "effect_hash" => {},                                      
      399 +    "description" => params[:description]                     
      400 +  }                                                           
      401 +                                                              
      402 +  Tools.save_json('compendium.json', compendium_data)         
      403 +  redirect '/spells'                                          
      404 +end                                                           
      405 +                                                              
      406  get '/store' do
      407    @store_items = Tools.load_json('store.json')
      408    @campaign = Tools.load_json('campaign.json')

● Now add the Magic tab to navigation:

● Update(/home/user/crimson-steel/views/layout.erb)
  ⎿  Added 1 line
       8    <div class="menu">
       9      <a href="/character/0">Character Sheets</a>
      10      <a href="/store">Store</a>
      11 +    <a href="/spells">Magic</a>                                
      12      <a href="/notes/<%= @viewer_id || 0 %>">Notes</a>
      13      <% if @is_local %>
      14        <a href="/enemies/0">Enemies</a>

● Now add the resolve_spell_description helper:

● Update(/home/user/crimson-steel/helpers.rb)
  ⎿  Added 15 lines
       8    def h(text)
       9      Rack::Utils.escape_html(text.to_s)
      10    end
      11 +                                                               
      12 +  def resolve_spell_description(spell, idx, tier_val)          
      13 +    spell["description"].gsub(/\{(\w+)\}/) do |match|          
      14 +      var = $1                                                 
      15 +      val = spell[var] || (spell["effect_hash"] && spell["effec
         +t_hash"][var])                                                 
      16 +      next match unless val                                    
      17 +      if val.is_a?(Array)                                      
      18 +        val[idx].to_s                                          
      19 +      elsif val.is_a?(String)                                  
      20 +        eval(val.gsub("tier", tier_val.to_s)).to_s rescue val  
      21 +      else                                                     
      22 +        val.to_s                                               
      23 +      end                                                      
      24 +    end                                                        
      25 +  end                                                          
      26  end

● Now make spells clickable on the character sheet:

● Update(/home/user/crimson-steel/views/character_sheet.erb)
  ⎿  Added 2 lines, removed 2 lines
      136          <h2>Spell List</h2>
      137  
      138          <% @character.spell_list.each.with_index do |spell_sub
           _list, index| %>
      139 -          <p><strong><%= index %>:</strong> <%= spell_sub_list
          -.join(', ') %></p>                                            
      139 +          <p><strong><%= index %>:</strong> <%= spell_sub_list
          +.map { |s| "<a href=\"/spell/#{ERB::Util.url_encode(s)}\" clas
          +s=\"spell-link\">#{h(s)}</a>" }.join(', ') %></p>             
      140          <% end %>
      141        <% end %>
      142  
     ...
      144          <h2>Item Spells</h2>
      145  
      146          <% @character.item_spell_list.each do |cat, spell_sub_
           list| %>
      147 -          <p><strong><%= cat %>:</strong> <%= spell_sub_list.j
          -oin(', ') %></p>                                              
      147 +          <p><strong><%= cat %>:</strong> <%= spell_sub_list.m
          +ap { |s| "<a href=\"/spell/#{ERB::Util.url_encode(s)}\" class=
          +\"spell-link\">#{h(s)}</a>" }.join(', ') %></p>               
      148          <% end %>
      149        <% end %>
      150      </div>

● Now add CSS for the magic pages:

● Update(/home/user/crimson-steel/public/style.css)
  ⎿  Added 52 lines
      336  .enemy-clear-btn:hover { background: #b71c1c; }
      337  .enemy-sheet { min-width: 0; }
      338  
      339 +/* Spell list page */                                         
      340 +.spell-filters { margin-bottom: 15px; padding: 10px; backgroun
          +d: #f5f5f5; border-radius: 5px; }                             
      341 +.spell-filters .filter-row { display: flex; gap: 15px; align-i
          +tems: flex-end; }                                             
      342 +.spell-filters .filter-field { flex: 1; }                     
      343 +.spell-filters .filter-field label { display: block; font-weig
          +ht: bold; margin-bottom: 4px; font-size: 12px; }              
      344 +.spell-filters .filter-field select { width: 100%; padding: 6p
          +x; font-size: 13px; }                                         
      345 +                                                              
      346 +.spell-table { width: 100%; border-collapse: collapse; }      
      347 +.spell-table th { background: #333; color: white; padding: 6px
          + 8px; text-align: left; font-size: 11px; }                    
      348 +.spell-table td { padding: 5px 8px; border-bottom: 1px solid #
          +ddd; font-size: 11px; }                                       
      349 +.spell-table tr:hover { background: #f0f7ff; }                
      350 +.spell-table a { color: #1976d2; text-decoration: none; font-w
          +eight: bold; }                                                
      351 +.spell-table a:hover { text-decoration: underline; }          
      352 +                                                              
      353 +.school-badge { display: inline-block; padding: 1px 6px; borde
          +r-radius: 3px; font-size: 10px; font-weight: bold; color: whit
          +e; }                                                          
      354 +.school-universal { background: #757575; }                    
      355 +.school-necromancy { background: #4a148c; }                   
      356 +.school-evocation { background: #c62828; }                    
      357 +.school-illusion { background: #6a1b9a; }                     
      358 +.school-enchantment { background: #ad1457; }                  
      359 +.school-divination { background: #0277bd; }                   
      360 +.school-abjuration { background: #00695c; }                   
      361 +.school-conjuration { background: #ef6c00; }                  
      362 +                                                              
      363 +/* Spell detail page */                                       
      364 +.spell-detail-stats { display: flex; justify-content: space-be
          +tween; margin: 15px 0; border-top: 1px solid #000; border-bott
          +om: 1px solid #000; padding: 8px 0; }                         
      365 +.spell-stat { flex: 1; display: flex; flex-direction: column; 
          +align-items: center; }                                        
      366 +.spell-stat .label { font-weight: bold; font-size: 10px; text-
          +transform: uppercase; color: #666; }                          
      367 +.spell-stat .value { font-size: 13px; margin-top: 2px; }      
      368 +                                                              
      369 +.spell-detail-section { margin-bottom: 15px; }                
      370 +.spell-detail-section p { font-size: 12px; line-height: 1.6; m
          +argin-bottom: 8px; }                                          
      371 +                                                              
      372 +.spell-effects-table { width: 100%; border-collapse: collapse;
          + font-size: 11px; }                                           
      373 +.spell-effects-table th { background: #f0f0f0; padding: 4px 8p
          +x; border: 1px solid #ccc; text-align: center; }              
      374 +.spell-effects-table td { padding: 4px 8px; border: 1px solid 
          +#ccc; text-align: center; }                                   
      375 +.spell-effects-table td:first-child { text-align: left; }     
      376 +                                                              
      377 +/* DM add spell form */                                       
      378 +.dm-section { margin-top: 20px; padding: 15px; background: #ff
          +f3e0; border: 1px solid #ffcc80; border-radius: 5px; }        
      379 +.add-spell-form { display: grid; gap: 12px; }                 
      380 +.add-spell-form .form-row { display: grid; grid-template-colum
          +ns: repeat(auto-fit, minmax(150px, 1fr)); gap: 12px; }        
      381 +.add-spell-form .full-width { grid-column: 1 / -1; }          
      382 +.add-spell-form label { display: block; font-weight: bold; mar
          +gin-bottom: 4px; font-size: 12px; }                           
      383 +.add-spell-form input, .add-spell-form select, .add-spell-form
          + textarea { width: 100%; padding: 6px; font-size: 13px; box-si
          +zing: border-box; }                                           
      384 +.add-spell-form button { padding: 8px 20px; background: #4CAF5
          +0; color: white; border: none; cursor: pointer; font-size: 14p
          +x; }                                                          
      385 +.add-spell-form button:hover { background: #45a049; }         
      386 +                                                              
      387 +/* Spell links on character sheet */                          
      388 +.spell-link { color: #1976d2; text-decoration: none; }        
      389 +.spell-link:hover { text-decoration: underline; }             
      390 +                                                              
      391  @media print {
      392    body {
      393      padding: 0;

● Let me verify the app starts correctly before committing.

● Bash(ruby -c app.rb && ruby -c character.rb && ruby -c helpers.rb)
  ⎿  Syntax OK
     Syntax OK
     Syntax OK

● Bash(ruby -e "require 'json'; JSON.parse(File.read('data/compendium.json'))"
      && echo "JSON valid")
  ⎿  JSON valid

● Now commit and push.

● Bash(git checkout -b claude/add-magic-tab-gx56h 2>/dev/null || git checkout
      claude/add-magic-tab-gx56h)
  ⎿  Already on 'claude/add-magic-tab-gx56h'
     M  app.rb
     M  data/compendium.json
     … +4 lines (ctrl+o to expand)

● Bash(git status)
  ⎿  On branch claude/add-magic-tab-gx56h
     Changes not staged for commit:
       (use "git add <file>..." to update what will be committed)
     … +15 lines (ctrl+o to expand)

● Bash(git log --oneline -3)
  ⎿  5107dc2 Fix NoMethodError when combat participant references missing c
     haracter
     72b006e Implement attack resolution for Nothing and Dodge defenses
     60f47f0 Usage data changed
● Bash(git add app.rb data/compendium.json helpers.rb public/style.css
      views/character_sheet.erb views/layout.erb views/spell_detail.erb
      views/spell_list.erb)
  ⎿  (No output)

● Bash(git commit -m "$(cat <<'EOF'
      Add Magic tab with spell list, spell detail pages, and spell schools…)
  ⎿  [claude/add-magic-tab-gx56h 258dddd] Add Magic tab with spell list, sp
     ell detail pages, and spell schools
      8 files changed, 424 insertions(+), 16 deletions(-)
     … +2 lines (ctrl+o to expand)

● Bash(git push -u origin claude/add-magic-tab-gx56h)
  ⎿  remote:
     remote: Create a pull request for 'claude/add-magic-tab-gx56h' on GitH
     ub by visiting:
     … +8 lines (ctrl+o to expand)

● All done. Here's what was implemented:

  Magic Tab - Summary

  Two new pages:

  1. Spell List (/spells) - Full compendium table with columns for name, school,
   tier, skills, save, range, duration, and casting time. Includes client-side
  filtering by school, tier, and skill. DM-only add spell form at the bottom.
  2. Spell Detail (/spell/:name) - Shows full spell info: school badge,
  range/duration/cast time/save stats, skills, description resolved per tier
  with effect values substituted, effects-by-tier table, and duration-by-tier
  table when applicable.

  Spell Schools added to compendium.json:
  - spell_schools array defined for future editing
  - Each spell tagged: Ward→abjuration, Cure→necromancy, Benign
  Transposition/Grease/Web/Create Pit→conjuration, Disguise
  Self/Invisibility/Disguise Other→illusion, Expeditious Retreat→enchantment,
  Darkness/Silence/Spiritual Weapon→evocation, Recharge→universal

  Character sheet integration:
  - Spell names in both the Spell List and Item Spells sections are now
  clickable links to the spell detail page

  Navigation:
  - "Magic" link added to the top menu bar, visible to all users

  The school assignments are my best guesses based on traditional RPG
  conventions — you mentioned wanting to go through each spell to assign
  schools, so feel free to adjust any of them. You can also update the
  spell_schools array in compendium.json when you want to revise the list of
  schools.

❯ I forgot transmutation. Expeditious Retreat is transmutation. Invisibility is 
   enchantment                                                                  

● Update(/home/user/crimson-steel/data/compendium.json)
  ⎿  File must be read first

  Searched for 1 pattern, read 1 file (ctrl+o to expand)

● Update(/home/user/crimson-steel/data/compendium.json)
  ⎿  Added 1 line, removed 1 line
       4    "range": {"0": "personal", "1": "touch", "2": "close", "3": "
          medium", "4": "long"},
       5    "item_costs": {"potion": "50*tier", "scroll": "25*tier", "oil
          ": "50*tier", "wand": "1000*tier*tier", "ammunition": [0, 20, 8
          0, 160, 320, 640]},
       6    "property_costs": {"Heartseeker": {"requirements": [{"type": 
          "ammunition", "tier": ">=3"}], "cost": 80, "description": "Adds
           4 additional dice that add their damage to physical damage. Da
          mage is increased by 1 for each success and 4 for each critical
          ."}},
       7 -  "spell_schools": ["universal", "necromancy", "evocation", "il
         -lusion", "enchantment", "divination", "abjuration", "conjuratio
         -n"],                                                           
       7 +  "spell_schools": ["universal", "necromancy", "evocation", "il
         +lusion", "enchantment", "divination", "abjuration", "conjuratio
         +n", "transmutation"],                                          
       8    "spells": {
       9      "Recharge": {"tier": [0, 1, 2, 3, 4, 5], "save": "cha", "sc
          hool": "universal", "items": ["potion", "scroll", "wand"], "ran
          ge": 1, "duration": "instant", "casting_time": 0.5, "skill": ["
          arcana", "perform_"], "properties": [], "effect_hash": {"mana":
           [2, 4, 8, 16, 32, 64], "minimum_saturation": "tier*4", "satura
          tion": "tier*10"}, "prefix": ["Faint", "Minor", "Basic", "Moder
          ate", "Improved", "Greater"], "description": "Restores {mana} p
          oints of mana. This can be used to charge items or as an attack
           against creatures already saturated with magic."},
      10      "Ward": {"tier": [0, 1, 2, 3, 4, 5, 6], "save": 0, "school"
          : "abjuration", "items": ["potion", "scroll", "wand"], "range":
           1, "duration": ["rank", "rank*10", "rank*100", "rank*600", "14
          400", "rank*14400", "5256000"], "casting_time": 0.5, "skill": [
          "healing", "nature", "perform_"], "properties": [], "effect_has
          h": {"temp_hp": "3+2.5*tier", "bleeding": "-1*success", "resusc
          itate_timer": [0, 1, 2, 10, 20, 50, 14400]}, "prefix": ["Trivia
          l", "Lesser", "Simple", "Improved", "Advanced", "Superior", "Di
          vine"], "description": "Target gains {temp_hp} temporary hit po
          ints, and any bleeding is reduced based upon spell tier and suc
          cess roll. Can resuscitate dying characters if cast within {res
          uscitate_timer} rounds."},

● Update(/home/user/crimson-steel/data/compendium.json)
  ⎿  Added 1 line, removed 1 line
      12      "Benign Transposition": {"tier": 1, "save": 0, "school": "c
          onjuration", "items": ["scroll", "wand"], "range": 3, "duration
          ": "instant", "casting_time": 0.5, "skill": ["arcana"], "proper
          ties": [], "effect_hash": {}, "description": "Two target creatu
          res, of which you can be one, instantly swap positions. Both su
          bjects must be within range. Objects carried by the creatures (
          up to the creatures' maximum loads) go with them, but other cre
          atures do not, even if they are carried. The movement is instan
          taneous and does not provoke attacks of opportunity."},
      13      "Grease": {"tier": 1, "save": "dex", "school": "conjuration
          ", "items": ["scroll", "oil", "wand"], "range": 2, "duration": 
          "rank", "casting_time": 0.5, "skill": ["arcana", "perform_"], "
          properties": [], "effect_hash": {}, "description": "One creatur
          e or 10 foot square becomes covered in grease. Covered creature
          s suffer a -2 situational penalty on athletics checks and gain 
          a +2 situational bonus on escape artist checks. Creatures in th
          e area when the spell is cast, ending their turn in grease, or 
          moving through grease must save or fall prone."},
      14      "Disguise Self": {"tier": 1, "save": 0, "school": "illusion
          ", "items": ["potion", "scroll", "wand"], "range": 0, "duration
          ": "rank*100", "casting_time": 0.5, "skill": ["arcana", "perfor
          m_"], "properties": [], "effect_hash": {"disguise": {"enhanceme
          nt": 1}}, "description": "You make yourself – including clothin
          g, armor, weapons, and equipment – look different. You can seem
           1 foot shorter or taller, thin, fat, or in between. You cannot
           change your creature type (although you can appear as another 
          subtype). Otherwise, the extent of the apparent change is up to
           you. You could add or obscure a minor feature or look like an 
          entirely different person or gender."},
      15 -    "Expeditious Retreat": {"tier": 1, "save": 0, "school": "en
         -chantment", "items": ["potion", "scroll", "wand"], "range": 0, 
         -"duration": "rank*10", "casting_time": 0.5, "skill": ["arcana",
         - "perform_"], "properties": [], "effect_hash": {"speed": {"enha
         -ncement": 30}}, "description": "This spell increases your base 
         -land speed by 30 feet. This adjustment is treated as an enhance
         -ment bonus. There is no effect on other modes of movement, such
         - as burrow, climb, fly, or swim. As with any effect that increa
         -ses your speed, this spell affects your jumping distance (see t
         -he Acrobatics skill)."},                                       
      15 +    "Expeditious Retreat": {"tier": 1, "save": 0, "school": "tr
         +ansmutation", "items": ["potion", "scroll", "wand"], "range": 0
         +, "duration": "rank*10", "casting_time": 0.5, "skill": ["arcana
         +", "perform_"], "properties": [], "effect_hash": {"speed": {"en
         +hancement": 30}}, "description": "This spell increases your bas
         +e land speed by 30 feet. This adjustment is treated as an enhan
         +cement bonus. There is no effect on other modes of movement, su
         +ch as burrow, climb, fly, or swim. As with any effect that incr
         +eases your speed, this spell affects your jumping distance (see
         + the Acrobatics skill)."},                                     
      16      "Darkness": {"tier": 2, "save": 0, "school": "evocation", "
          items": ["scroll", "oil", "wand"], "range": 1, "duration": "ran
          k*10", "casting_time": 0.5, "skill": ["arcana", "healing"], "pr
          operties": [], "effect_hash": {}, "description": "This spell ca
          uses an object to radiate darkness out to a 20-foot radius. Thi
          s darkness causes the illumination level in the area to drop on
          e step, from bright light to normal light, from normal light to
           dim light, or from dim light to darkness. This spell has no ef
          fect in an area that is already dark. Creatures with light vuln
          erability or sensitivity take no penalties in normal light. All
           creatures gain concealment in dim light. All creatures gain to
          tal concealment in darkness. Creatures with darkvision can see 
          in an area of dim light or darkness without penalty. Nonmagical
           sources of light, such as torches and lanterns, do not increas
          e the light level in an area of darkness. Magical light sources
           only increase the light level in an area if they are of a high
          er spell level than darkness. If darkness is cast on a small ob
          ject that is then placed inside or under a lightproof covering,
           the spell’s effect is blocked until the covering is removed."}
          ,
      17      "Invisibility": {"tier": 2, "save": "will", "school": "illu
          sion", "items": ["potion", "scroll", "oil", "wand"], "range": 1
          , "duration": "rank*10", "casting_time": 0.5, "skill": ["arcana
          ", "perform_"], "properties": [], "effect_hash": {}, "descripti
          on": "The creature or object touched radiates an aura of unimpo
          rtance preventing other creatures from noticing it or them. If 
          any creature realizes, or suspects, the target creature or obje
          ct are nearby then they can make a wisdom save as a main action
           to overcome the spell for it's duration. There is a penalty on
           this save if they do not know which square the creature or obj
          ect is in, and a cumulative penalty for every failed save. If a
          n attack is made by the target including any harmful spells cas
          t then all creatures within sight of the target immediatly gain
           the benefit of a successful save. Indirect actions, such as cu
          tting a rope bridge, or setting fire to a building do not grant
           an automatic save. This spell affects any objects carried by t
          he target when the spell is cast but not objects dropped or pic
          ked up after. Any part of an item that the subject carries but 
          that extends more than 10 feet from can be observed. This spell
           does not prevent creatures from noticing sounds or smells or o
          ther nonvisual clues to the targets existance."},
      18      "Web": {"tier": 2, "save": "reflex", "school": "conjuration
          ", "items": ["scroll", "wand"], "range": 2, "duration": "rank*1
          0", "casting_time": 0.5, "skill": ["arcana"], "properties": [],
           "effect_hash": {}, "description": "Web creates a many-layered 
          mass of strong, sticky strands. These strands trap those caught
           in them. The strands are similar to spiderwebs but far larger 
          and tougher. These masses must be anchored to two or more solid
           and diametrically opposed points or else the web collapses upo
          n itself and disappears. Creatures caught within a web become g
          rappled by the sticky fibers. Attacking a creature in a web doe
          sn’t cause you to become grappled. Anyone in the effect’s area 
          when the spell is cast must make a Reflex save. If this save su
          cceeds, the creature is inside the web but is otherwise unaffec
          ted. If the save fails, the creature gains the grappled conditi
          on, but can break free by making a combat maneuver check or Esc
          ape Artist check as a standard action against the DC of this sp
          ell. The entire area of the web is considered difficult terrain
          . Anyone moving through the webs must make a combat maneuver ch
          eck or Escape Artist check as part of their move action, with a
           DC equal to the spell’s DC. Creatures that fail lose their mov
          ement and become grappled in the first square of webbing that t
          hey enter. If you have at least 5 feet of web between you and a
          n opponent, it provides cover. If you have at least 20 feet of 
          web between you, it provides total cover. The strands of a web 
          spell are flammable. A flaming weapon can slash them away as ea
          sily as a hand brushes away cobwebs. Any fire can set the webs 
          alight and burn away one 5-foot square in 1 round. All creature
          s within flaming webs take fire damage from the flames."},

● Update(/home/user/crimson-steel/data/compendium.json)
  ⎿  Added 1 line, removed 1 line
      14      "Disguise Self": {"tier": 1, "save": 0, "school": "illusion
          ", "items": ["potion", "scroll", "wand"], "range": 0, "duration
          ": "rank*100", "casting_time": 0.5, "skill": ["arcana", "perfor
          m_"], "properties": [], "effect_hash": {"disguise": {"enhanceme
          nt": 1}}, "description": "You make yourself – including clothin
          g, armor, weapons, and equipment – look different. You can seem
           1 foot shorter or taller, thin, fat, or in between. You cannot
           change your creature type (although you can appear as another 
          subtype). Otherwise, the extent of the apparent change is up to
           you. You could add or obscure a minor feature or look like an 
          entirely different person or gender."},
      15      "Expeditious Retreat": {"tier": 1, "save": 0, "school": "tr
          ansmutation", "items": ["potion", "scroll", "wand"], "range": 0
          , "duration": "rank*10", "casting_time": 0.5, "skill": ["arcana
          ", "perform_"], "properties": [], "effect_hash": {"speed": {"en
          hancement": 30}}, "description": "This spell increases your bas
          e land speed by 30 feet. This adjustment is treated as an enhan
          cement bonus. There is no effect on other modes of movement, su
          ch as burrow, climb, fly, or swim. As with any effect that incr
          eases your speed, this spell affects your jumping distance (see
           the Acrobatics skill)."},
      16      "Darkness": {"tier": 2, "save": 0, "school": "evocation", "
          items": ["scroll", "oil", "wand"], "range": 1, "duration": "ran
          k*10", "casting_time": 0.5, "skill": ["arcana", "healing"], "pr
          operties": [], "effect_hash": {}, "description": "This spell ca
          uses an object to radiate darkness out to a 20-foot radius. Thi
          s darkness causes the illumination level in the area to drop on
          e step, from bright light to normal light, from normal light to
           dim light, or from dim light to darkness. This spell has no ef
          fect in an area that is already dark. Creatures with light vuln
          erability or sensitivity take no penalties in normal light. All
           creatures gain concealment in dim light. All creatures gain to
          tal concealment in darkness. Creatures with darkvision can see 
          in an area of dim light or darkness without penalty. Nonmagical
           sources of light, such as torches and lanterns, do not increas
          e the light level in an area of darkness. Magical light sources
           only increase the light level in an area if they are of a high
          er spell level than darkness. If darkness is cast on a small ob
          ject that is then placed inside or under a lightproof covering,
           the spell’s effect is blocked until the covering is removed."}
          ,
      17 -    "Invisibility": {"tier": 2, "save": "will", "school": "illu
         -sion", "items": ["potion", "scroll", "oil", "wand"], "range": 1
         -, "duration": "rank*10", "casting_time": 0.5, "skill": ["arcana
         -", "perform_"], "properties": [], "effect_hash": {}, "descripti
         -on": "The creature or object touched radiates an aura of unimpo
         -rtance preventing other creatures from noticing it or them. If 
         -any creature realizes, or suspects, the target creature or obje
         -ct are nearby then they can make a wisdom save as a main action
         - to overcome the spell for it's duration. There is a penalty on
         - this save if they do not know which square the creature or obj
         -ect is in, and a cumulative penalty for every failed save. If a
         -n attack is made by the target including any harmful spells cas
         -t then all creatures within sight of the target immediatly gain
         - the benefit of a successful save. Indirect actions, such as cu
         -tting a rope bridge, or setting fire to a building do not grant
         - an automatic save. This spell affects any objects carried by t
         -he target when the spell is cast but not objects dropped or pic
         -ked up after. Any part of an item that the subject carries but 
         -that extends more than 10 feet from can be observed. This spell
         - does not prevent creatures from noticing sounds or smells or o
         -ther nonvisual clues to the targets existance."},              
      17 +    "Invisibility": {"tier": 2, "save": "will", "school": "ench
         +antment", "items": ["potion", "scroll", "oil", "wand"], "range"
         +: 1, "duration": "rank*10", "casting_time": 0.5, "skill": ["arc
         +ana", "perform_"], "properties": [], "effect_hash": {}, "descri
         +ption": "The creature or object touched radiates an aura of uni
         +mportance preventing other creatures from noticing it or them. 
         +If any creature realizes, or suspects, the target creature or o
         +bject are nearby then they can make a wisdom save as a main act
         +ion to overcome the spell for it's duration. There is a penalty
         + on this save if they do not know which square the creature or 
         +object is in, and a cumulative penalty for every failed save. I
         +f an attack is made by the target including any harmful spells 
         +cast then all creatures within sight of the target immediatly g
         +ain the benefit of a successful save. Indirect actions, such as
         + cutting a rope bridge, or setting fire to a building do not gr
         +ant an automatic save. This spell affects any objects carried b
         +y the target when the spell is cast but not objects dropped or 
         +picked up after. Any part of an item that the subject carries b
         +ut that extends more than 10 feet from can be observed. This sp
         +ell does not prevent creatures from noticing sounds or smells o
         +r other nonvisual clues to the targets existance."},           
      18      "Web": {"tier": 2, "save": "reflex", "school": "conjuration
          ", "items": ["scroll", "wand"], "range": 2, "duration": "rank*1
          0", "casting_time": 0.5, "skill": ["arcana"], "properties": [],
           "effect_hash": {}, "description": "Web creates a many-layered 
          mass of strong, sticky strands. These strands trap those caught
           in them. The strands are similar to spiderwebs but far larger 
          and tougher. These masses must be anchored to two or more solid
           and diametrically opposed points or else the web collapses upo
          n itself and disappears. Creatures caught within a web become g
          rappled by the sticky fibers. Attacking a creature in a web doe
          sn’t cause you to become grappled. Anyone in the effect’s area 
          when the spell is cast must make a Reflex save. If this save su
          cceeds, the creature is inside the web but is otherwise unaffec
          ted. If the save fails, the creature gains the grappled conditi
          on, but can break free by making a combat maneuver check or Esc
          ape Artist check as a standard action against the DC of this sp
          ell. The entire area of the web is considered difficult terrain
          . Anyone moving through the webs must make a combat maneuver ch
          eck or Escape Artist check as part of their move action, with a
           DC equal to the spell’s DC. Creatures that fail lose their mov
          ement and become grappled in the first square of webbing that t
          hey enter. If you have at least 5 feet of web between you and a
          n opponent, it provides cover. If you have at least 20 feet of 
          web between you, it provides total cover. The strands of a web 
          spell are flammable. A flaming weapon can slash them away as ea
          sily as a hand brushes away cobwebs. Any fire can set the webs 
          alight and burn away one 5-foot square in 1 round. All creature
          s within flaming webs take fire damage from the flames."},
      19      "Disguise Other": {"tier": 2, "save": "will", "school": "il
          lusion", "items": ["potion", "scroll", "oil", "wand"], "range":
           1, "duration": "rank*100", "casting_time": 0.5, "skill": ["arc
          ana", "perform_"], "properties": [], "effect_hash": {"disguise"
          : {"enhancement": 1}}, "description": "You make the target crea
          ture – including clothing, armor, weapons, and equipment – look
           different. They can seem 1 foot shorter or taller, thin, fat, 
          or in between. You cannot change your creature type (although y
          ou can appear as another subtype). Otherwise, the extent of the
           apparent change is up to you. You could add or obscure a minor
           feature or look like an entirely different person or gender."}
          ,
      20      "Create Pit": {"tier": 2, "save": "reflex", "school": "conj
          uration", "items": ["scroll", "wand"], "range": 2, "duration": 
          "rank", "casting_time": 0.5, "skill": ["arcana"], "properties":
           [], "effect_hash": {}, "description": "You create a 10-foot-by
          -10-foot extra-dimensional hole with a depth of 10 feet per two
           caster ranks (maximum 30 feet). You must create the pit on a h
          orizontal surface of sufficient size. Since it extends into ano
          ther dimension, the pit has no weight and does not otherwise di
          splace the original underlying material. You can create the pit
           in the deck of a ship as easily as in a dungeon floor or the g
          round of a forest. Any creature standing in the area where you 
          first conjured the pit must make a Reflex saving throw to jump 
          to safety in the nearest open space. In addition, the edges of 
          the pit are sloped, and any creature ending its turn on a squar
          e adjacent to the pit must make a Reflex saving throw with a +1
           bonus to avoid falling into it. Creatures subjected to an effe
          ct intended to push them into the pit (such as bull rush) do no
          t get a saving throw to avoid falling in if they are affected b
          y the pushing effect. Creatures who fall into the pit take fall
          ing damage as normal. The pit’s coarse stone walls increase the
           Athletic check difficulty by 2. When the duration of the spell
           ends, creatures within the hole rise up with the bottom of the
           pit until they are standing on the surface over the course of 
          a single round."},

● Now add CSS for the transmutation school badge.

  Read 1 file (ctrl+o to expand)

● Update(/home/user/crimson-steel/public/style.css)
  ⎿  Added 1 line
      359  .school-divination { background: #0277bd; }
      360  .school-abjuration { background: #00695c; }
      361  .school-conjuration { background: #ef6c00; }
      362 +.school-transmutation { background: #558b2f; }                
      363  
      364  /* Spell detail page */
      365  .spell-detail-stats { display: flex; justify-content: space-be
           tween; margin: 15px 0; border-top: 1px solid #000; border-bott
           om: 1px solid #000; padding: 8px 0; }

● Bash(git add data/compendium.json public/style.css && git commit -m "$(cat
      <<'EOF'
      Add transmutation school, fix Expeditious Retreat and Invisibility
      schools…)
  ⎿  [claude/add-magic-tab-gx56h 19ec5df] Add transmutation school, fix Exp
     editious Retreat and Invisibility schools
      2 files changed, 4 insertions(+), 3 deletions(-)

● Bash(git push -u origin claude/add-magic-tab-gx56h)
  ⎿  To http://127.0.0.1:37499/git/dividetask/crimson-steel
        258dddd..19ec5df  claude/add-magic-tab-gx56h -> claude/add-magic-ta
     b-gx56h
     … +2 lines (ctrl+o to expand)

● Done. Updated:
  - Added transmutation to the spell_schools list
  - Expeditious Retreat → transmutation
  - Invisibility → enchantment
  - Added green CSS badge for transmutation

❯ Actually I want to change them again                                          
  Final School List                                                             
                                                                                
  Pneumancy: Soul/spirit — undead, binding, communing (Formerly necromancy)     
  Augury: Fate reading, detection, foresight (Formerly Divination)              
  Convergence - Dimensional pulling — summoning + translocation, temporary by   
  nature (Formerly conjuration)                                                 
  Enchantment - Mind-affecting, will saves (unchanged)                          
  Resonance - Force, energy, light, sound, warding (Formerly evocation,         
  illusion, and abjuration)                                                     
  Transmutation - Physical transformation                                       
  Universal -Cross-school utility                                               

● Here's the mapping I'll apply to existing spells:

  ┌──────────────────────┬───────────────┬───────────────┐
  │        Spell         │  Old School   │  New School   │
  ├──────────────────────┼───────────────┼───────────────┤
  │ Recharge             │ universal     │ universal     │
  ├──────────────────────┼───────────────┼───────────────┤
  │ Ward                 │ abjuration    │ resonance     │
  ├──────────────────────┼───────────────┼───────────────┤
  │ Cure                 │ necromancy    │ pneumancy     │
  ├──────────────────────┼───────────────┼───────────────┤
  │ Benign Transposition │ conjuration   │ convergence   │
  ├──────────────────────┼───────────────┼───────────────┤
  │ Grease               │ conjuration   │ convergence   │
  ├──────────────────────┼───────────────┼───────────────┤
  │ Disguise Self        │ illusion      │ resonance     │
  ├──────────────────────┼───────────────┼───────────────┤
  │ Expeditious Retreat  │ transmutation │ transmutation │
  ├──────────────────────┼───────────────┼───────────────┤
  │ Darkness             │ evocation     │ resonance     │
  ├──────────────────────┼───────────────┼───────────────┤
  │ Invisibility         │ enchantment   │ enchantment   │
  ├──────────────────────┼───────────────┼───────────────┤
  │ Web                  │ conjuration   │ convergence   │
  ├──────────────────────┼───────────────┼───────────────┤
  │ Disguise Other       │ illusion      │ resonance     │
  ├──────────────────────┼───────────────┼───────────────┤
  │ Create Pit           │ conjuration   │ convergence   │
  ├──────────────────────┼───────────────┼───────────────┤
  │ Silence              │ evocation     │ resonance     │
  ├──────────────────────┼───────────────┼───────────────┤
  │ Spiritual Weapon     │ evocation     │ resonance     │
  └──────────────────────┴───────────────┴───────────────┘

  Read 1 file (ctrl+o to expand)

● Now I'll update all the schools:

● Update(/home/user/crimson-steel/data/compendium.json)
  ⎿  Added 1 line, removed 1 line
       4    "range": {"0": "personal", "1": "touch", "2": "close", "3": "
          medium", "4": "long"},
       5    "item_costs": {"potion": "50*tier", "scroll": "25*tier", "oil
          ": "50*tier", "wand": "1000*tier*tier", "ammunition": [0, 20, 8
          0, 160, 320, 640]},
       6    "property_costs": {"Heartseeker": {"requirements": [{"type": 
          "ammunition", "tier": ">=3"}], "cost": 80, "description": "Adds
           4 additional dice that add their damage to physical damage. Da
          mage is increased by 1 for each success and 4 for each critical
          ."}},
       7 -  "spell_schools": ["universal", "necromancy", "evocation", "il
         -lusion", "enchantment", "divination", "abjuration", "conjuratio
         -n", "transmutation"],                                          
       7 +  "spell_schools": ["universal", "pneumancy", "resonance", "enc
         +hantment", "augury", "convergence", "transmutation"],          
       8    "spells": {
       9      "Recharge": {"tier": [0, 1, 2, 3, 4, 5], "save": "cha", "sc
          hool": "universal", "items": ["potion", "scroll", "wand"], "ran
          ge": 1, "duration": "instant", "casting_time": 0.5, "skill": ["
          arcana", "perform_"], "properties": [], "effect_hash": {"mana":
           [2, 4, 8, 16, 32, 64], "minimum_saturation": "tier*4", "satura
          tion": "tier*10"}, "prefix": ["Faint", "Minor", "Basic", "Moder
          ate", "Improved", "Greater"], "description": "Restores {mana} p
          oints of mana. This can be used to charge items or as an attack
           against creatures already saturated with magic."},
      10      "Ward": {"tier": [0, 1, 2, 3, 4, 5, 6], "save": 0, "school"
          : "abjuration", "items": ["potion", "scroll", "wand"], "range":
           1, "duration": ["rank", "rank*10", "rank*100", "rank*600", "14
          400", "rank*14400", "5256000"], "casting_time": 0.5, "skill": [
          "healing", "nature", "perform_"], "properties": [], "effect_has
          h": {"temp_hp": "3+2.5*tier", "bleeding": "-1*success", "resusc
          itate_timer": [0, 1, 2, 10, 20, 50, 14400]}, "prefix": ["Trivia
          l", "Lesser", "Simple", "Improved", "Advanced", "Superior", "Di
          vine"], "description": "Target gains {temp_hp} temporary hit po
          ints, and any bleeding is reduced based upon spell tier and suc
          cess roll. Can resuscitate dying characters if cast within {res
          uscitate_timer} rounds."},

● Update(/home/user/crimson-steel/data/compendium.json)
  ⎿  Added 1 line, removed 1 line
       7    "spell_schools": ["universal", "pneumancy", "resonance", "enc
          hantment", "augury", "convergence", "transmutation"],
       8    "spells": {
       9      "Recharge": {"tier": [0, 1, 2, 3, 4, 5], "save": "cha", "sc
          hool": "universal", "items": ["potion", "scroll", "wand"], "ran
          ge": 1, "duration": "instant", "casting_time": 0.5, "skill": ["
          arcana", "perform_"], "properties": [], "effect_hash": {"mana":
           [2, 4, 8, 16, 32, 64], "minimum_saturation": "tier*4", "satura
          tion": "tier*10"}, "prefix": ["Faint", "Minor", "Basic", "Moder
          ate", "Improved", "Greater"], "description": "Restores {mana} p
          oints of mana. This can be used to charge items or as an attack
           against creatures already saturated with magic."},
      10 -    "Ward": {"tier": [0, 1, 2, 3, 4, 5, 6], "save": 0, "school"
         -: "abjuration", "items": ["potion", "scroll", "wand"], "range":
         - 1, "duration": ["rank", "rank*10", "rank*100", "rank*600", "14
         -400", "rank*14400", "5256000"], "casting_time": 0.5, "skill": [
         -"healing", "nature", "perform_"], "properties": [], "effect_has
         -h": {"temp_hp": "3+2.5*tier", "bleeding": "-1*success", "resusc
         -itate_timer": [0, 1, 2, 10, 20, 50, 14400]}, "prefix": ["Trivia
         -l", "Lesser", "Simple", "Improved", "Advanced", "Superior", "Di
         -vine"], "description": "Target gains {temp_hp} temporary hit po
         -ints, and any bleeding is reduced based upon spell tier and suc
         -cess roll. Can resuscitate dying characters if cast within {res
         -uscitate_timer} rounds."},                                     
      10 +    "Ward": {"tier": [0, 1, 2, 3, 4, 5, 6], "save": 0, "school"
         +: "resonance", "items": ["potion", "scroll", "wand"], "range": 
         +1, "duration": ["rank", "rank*10", "rank*100", "rank*600", "144
         +00", "rank*14400", "5256000"], "casting_time": 0.5, "skill": ["
         +healing", "nature", "perform_"], "properties": [], "effect_hash
         +": {"temp_hp": "3+2.5*tier", "bleeding": "-1*success", "resusci
         +tate_timer": [0, 1, 2, 10, 20, 50, 14400]}, "prefix": ["Trivial
         +", "Lesser", "Simple", "Improved", "Advanced", "Superior", "Div
         +ine"], "description": "Target gains {temp_hp} temporary hit poi
         +nts, and any bleeding is reduced based upon spell tier and succ
         +ess roll. Can resuscitate dying characters if cast within {resu
         +scitate_timer} rounds."},                                      
      11      "Cure": {"tier": [0, 1, 2, 3, 4, 5], "save": "cha", "school
          ": "necromancy", "items": ["potion", "scroll", "wand"], "range"
          : 1, "duration": "instant", "casting_time": 0.5, "skill": ["hea
          ling", "nature", "perform_"], "properties": [], "effect_hash": 
          {"minor_damage": [2, 4, 8, 16, 32, 64], "moderate_damage": [1, 
          2, 4, 8, 16, 32], "major_damage": [0, 0, 0, 1, 2, 4], "bleeding
          ": "-1*success", "minimum_saturation": "tier*2", "saturation": 
          "tier*5"}, "suffix": ["Petty Wounds", "Lesser Wounds", "Simple 
          Wounds", "Moderate Wounds", "Advanced Wounds", "Superior"], "de
          scription": "Cure target for {major_damage} points of major dam
          age, {moderate_damage} points of moderate damage, and {minor_da
          mage} points of minor damage. Any bleeding is reduced based upo
          n spell tier and success roll."},
      12      "Benign Transposition": {"tier": 1, "save": 0, "school": "c
          onjuration", "items": ["scroll", "wand"], "range": 3, "duration
          ": "instant", "casting_time": 0.5, "skill": ["arcana"], "proper
          ties": [], "effect_hash": {}, "description": "Two target creatu
          res, of which you can be one, instantly swap positions. Both su
          bjects must be within range. Objects carried by the creatures (
          up to the creatures' maximum loads) go with them, but other cre
          atures do not, even if they are carried. The movement is instan
          taneous and does not provoke attacks of opportunity."},
      13      "Grease": {"tier": 1, "save": "dex", "school": "conjuration
          ", "items": ["scroll", "oil", "wand"], "range": 2, "duration": 
          "rank", "casting_time": 0.5, "skill": ["arcana", "perform_"], "
          properties": [], "effect_hash": {}, "description": "One creatur
          e or 10 foot square becomes covered in grease. Covered creature
          s suffer a -2 situational penalty on athletics checks and gain 
          a +2 situational bonus on escape artist checks. Creatures in th
          e area when the spell is cast, ending their turn in grease, or 
          moving through grease must save or fall prone."},

● Update(/home/user/crimson-steel/data/compendium.json)  ⎿  Added 1 line, removed 1 line
       8    "spells": {
       9      "Recharge": {"tier": [0, 1, 2, 3, 4, 5], "save": "cha", "sc
          hool": "universal", "items": ["potion", "scroll", "wand"], "ran
          ge": 1, "duration": "instant", "casting_time": 0.5, "skill": ["
          arcana", "perform_"], "properties": [], "effect_hash": {"mana":
           [2, 4, 8, 16, 32, 64], "minimum_saturation": "tier*4", "satura
          tion": "tier*10"}, "prefix": ["Faint", "Minor", "Basic", "Moder
          ate", "Improved", "Greater"], "description": "Restores {mana} p
          oints of mana. This can be used to charge items or as an attack
           against creatures already saturated with magic."},
      10      "Ward": {"tier": [0, 1, 2, 3, 4, 5, 6], "save": 0, "school"
          : "resonance", "items": ["potion", "scroll", "wand"], "range": 
          1, "duration": ["rank", "rank*10", "rank*100", "rank*600", "144
          00", "rank*14400", "5256000"], "casting_time": 0.5, "skill": ["
          healing", "nature", "perform_"], "properties": [], "effect_hash
          ": {"temp_hp": "3+2.5*tier", "bleeding": "-1*success", "resusci
          tate_timer": [0, 1, 2, 10, 20, 50, 14400]}, "prefix": ["Trivial
          ", "Lesser", "Simple", "Improved", "Advanced", "Superior", "Div
          ine"], "description": "Target gains {temp_hp} temporary hit poi
          nts, and any bleeding is reduced based upon spell tier and succ
          ess roll. Can resuscitate dying characters if cast within {resu
          scitate_timer} rounds."},
      11 -    "Cure": {"tier": [0, 1, 2, 3, 4, 5], "save": "cha", "school
         -": "necromancy", "items": ["potion", "scroll", "wand"], "range"
         -: 1, "duration": "instant", "casting_time": 0.5, "skill": ["hea
         -ling", "nature", "perform_"], "properties": [], "effect_hash": 
         -{"minor_damage": [2, 4, 8, 16, 32, 64], "moderate_damage": [1, 
         -2, 4, 8, 16, 32], "major_damage": [0, 0, 0, 1, 2, 4], "bleeding
         -": "-1*success", "minimum_saturation": "tier*2", "saturation": 
         -"tier*5"}, "suffix": ["Petty Wounds", "Lesser Wounds", "Simple 
         -Wounds", "Moderate Wounds", "Advanced Wounds", "Superior"], "de
         -scription": "Cure target for {major_damage} points of major dam
         -age, {moderate_damage} points of moderate damage, and {minor_da
         -mage} points of minor damage. Any bleeding is reduced based upo
         -n spell tier and success roll."},                              
      11 +    "Cure": {"tier": [0, 1, 2, 3, 4, 5], "save": "cha", "school
         +": "pneumancy", "items": ["potion", "scroll", "wand"], "range":
         + 1, "duration": "instant", "casting_time": 0.5, "skill": ["heal
         +ing", "nature", "perform_"], "properties": [], "effect_hash": {
         +"minor_damage": [2, 4, 8, 16, 32, 64], "moderate_damage": [1, 2
         +, 4, 8, 16, 32], "major_damage": [0, 0, 0, 1, 2, 4], "bleeding"
         +: "-1*success", "minimum_saturation": "tier*2", "saturation": "
         +tier*5"}, "suffix": ["Petty Wounds", "Lesser Wounds", "Simple W
         +ounds", "Moderate Wounds", "Advanced Wounds", "Superior"], "des
         +cription": "Cure target for {major_damage} points of major dama
         +ge, {moderate_damage} points of moderate damage, and {minor_dam
         +age} points of minor damage. Any bleeding is reduced based upon
         + spell tier and success roll."},                               
      12      "Benign Transposition": {"tier": 1, "save": 0, "school": "c
          onjuration", "items": ["scroll", "wand"], "range": 3, "duration
          ": "instant", "casting_time": 0.5, "skill": ["arcana"], "proper
          ties": [], "effect_hash": {}, "description": "Two target creatu
          res, of which you can be one, instantly swap positions. Both su
          bjects must be within range. Objects carried by the creatures (
          up to the creatures' maximum loads) go with them, but other cre
          atures do not, even if they are carried. The movement is instan
          taneous and does not provoke attacks of opportunity."},
      13      "Grease": {"tier": 1, "save": "dex", "school": "conjuration
          ", "items": ["scroll", "oil", "wand"], "range": 2, "duration": 
          "rank", "casting_time": 0.5, "skill": ["arcana", "perform_"], "
          properties": [], "effect_hash": {}, "description": "One creatur
          e or 10 foot square becomes covered in grease. Covered creature
          s suffer a -2 situational penalty on athletics checks and gain 
          a +2 situational bonus on escape artist checks. Creatures in th
          e area when the spell is cast, ending their turn in grease, or 
          moving through grease must save or fall prone."},
      14      "Disguise Self": {"tier": 1, "save": 0, "school": "illusion
          ", "items": ["potion", "scroll", "wand"], "range": 0, "duration
          ": "rank*100", "casting_time": 0.5, "skill": ["arcana", "perfor
          m_"], "properties": [], "effect_hash": {"disguise": {"enhanceme
          nt": 1}}, "description": "You make yourself – including clothin
          g, armor, weapons, and equipment – look different. You can seem
           1 foot shorter or taller, thin, fat, or in between. You cannot
           change your creature type (although you can appear as another 
          subtype). Otherwise, the extent of the apparent change is up to
           you. You could add or obscure a minor feature or look like an 
          entirely different person or gender."},

● Update(/home/user/crimson-steel/data/compendium.json)
  ⎿  Added 4 lines, removed 4 lines
       9      "Recharge": {"tier": [0, 1, 2, 3, 4, 5], "save": "cha", "sc
          hool": "universal", "items": ["potion", "scroll", "wand"], "ran
          ge": 1, "duration": "instant", "casting_time": 0.5, "skill": ["
          arcana", "perform_"], "properties": [], "effect_hash": {"mana":
           [2, 4, 8, 16, 32, 64], "minimum_saturation": "tier*4", "satura
          tion": "tier*10"}, "prefix": ["Faint", "Minor", "Basic", "Moder
          ate", "Improved", "Greater"], "description": "Restores {mana} p
          oints of mana. This can be used to charge items or as an attack
           against creatures already saturated with magic."},
      10      "Ward": {"tier": [0, 1, 2, 3, 4, 5, 6], "save": 0, "school"
          : "resonance", "items": ["potion", "scroll", "wand"], "range": 
          1, "duration": ["rank", "rank*10", "rank*100", "rank*600", "144
          00", "rank*14400", "5256000"], "casting_time": 0.5, "skill": ["
          healing", "nature", "perform_"], "properties": [], "effect_hash
          ": {"temp_hp": "3+2.5*tier", "bleeding": "-1*success", "resusci
          tate_timer": [0, 1, 2, 10, 20, 50, 14400]}, "prefix": ["Trivial
          ", "Lesser", "Simple", "Improved", "Advanced", "Superior", "Div
          ine"], "description": "Target gains {temp_hp} temporary hit poi
          nts, and any bleeding is reduced based upon spell tier and succ
          ess roll. Can resuscitate dying characters if cast within {resu
          scitate_timer} rounds."},
      11      "Cure": {"tier": [0, 1, 2, 3, 4, 5], "save": "cha", "school
          ": "pneumancy", "items": ["potion", "scroll", "wand"], "range":
           1, "duration": "instant", "casting_time": 0.5, "skill": ["heal
          ing", "nature", "perform_"], "properties": [], "effect_hash": {
          "minor_damage": [2, 4, 8, 16, 32, 64], "moderate_damage": [1, 2
          , 4, 8, 16, 32], "major_damage": [0, 0, 0, 1, 2, 4], "bleeding"
          : "-1*success", "minimum_saturation": "tier*2", "saturation": "
          tier*5"}, "suffix": ["Petty Wounds", "Lesser Wounds", "Simple W
          ounds", "Moderate Wounds", "Advanced Wounds", "Superior"], "des
          cription": "Cure target for {major_damage} points of major dama
          ge, {moderate_damage} points of moderate damage, and {minor_dam
          age} points of minor damage. Any bleeding is reduced based upon
           spell tier and success roll."},
      12 -    "Benign Transposition": {"tier": 1, "save": 0, "school": "c
         -onjuration", "items": ["scroll", "wand"], "range": 3, "duration
         -": "instant", "casting_time": 0.5, "skill": ["arcana"], "proper
         -ties": [], "effect_hash": {}, "description": "Two target creatu
         -res, of which you can be one, instantly swap positions. Both su
         -bjects must be within range. Objects carried by the creatures (
         -up to the creatures' maximum loads) go with them, but other cre
         -atures do not, even if they are carried. The movement is instan
         -taneous and does not provoke attacks of opportunity."},        
      13 -    "Grease": {"tier": 1, "save": "dex", "school": "conjuration
         -", "items": ["scroll", "oil", "wand"], "range": 2, "duration": 
         -"rank", "casting_time": 0.5, "skill": ["arcana", "perform_"], "
         -properties": [], "effect_hash": {}, "description": "One creatur
         -e or 10 foot square becomes covered in grease. Covered creature
         -s suffer a -2 situational penalty on athletics checks and gain 
         -a +2 situational bonus on escape artist checks. Creatures in th
         -e area when the spell is cast, ending their turn in grease, or 
         -moving through grease must save or fall prone."},              
      12 +    "Benign Transposition": {"tier": 1, "save": 0, "school": "c
         +onvergence", "items": ["scroll", "wand"], "range": 3, "duration
         +": "instant", "casting_time": 0.5, "skill": ["arcana"], "proper
         +ties": [], "effect_hash": {}, "description": "Two target creatu
         +res, of which you can be one, instantly swap positions. Both su
         +bjects must be within range. Objects carried by the creatures (
         +up to the creatures' maximum loads) go with them, but other cre
         +atures do not, even if they are carried. The movement is instan
         +taneous and does not provoke attacks of opportunity."},        
      13 +    "Grease": {"tier": 1, "save": "dex", "school": "convergence
         +", "items": ["scroll", "oil", "wand"], "range": 2, "duration": 
         +"rank", "casting_time": 0.5, "skill": ["arcana", "perform_"], "
         +properties": [], "effect_hash": {}, "description": "One creatur
         +e or 10 foot square becomes covered in grease. Covered creature
         +s suffer a -2 situational penalty on athletics checks and gain 
         +a +2 situational bonus on escape artist checks. Creatures in th
         +e area when the spell is cast, ending their turn in grease, or 
         +moving through grease must save or fall prone."},              
      14      "Disguise Self": {"tier": 1, "save": 0, "school": "illusion
          ", "items": ["potion", "scroll", "wand"], "range": 0, "duration
          ": "rank*100", "casting_time": 0.5, "skill": ["arcana", "perfor
          m_"], "properties": [], "effect_hash": {"disguise": {"enhanceme
          nt": 1}}, "description": "You make yourself – including clothin
          g, armor, weapons, and equipment – look different. You can seem
           1 foot shorter or taller, thin, fat, or in between. You cannot
           change your creature type (although you can appear as another 
          subtype). Otherwise, the extent of the apparent change is up to
           you. You could add or obscure a minor feature or look like an 
          entirely different person or gender."},
      15      "Expeditious Retreat": {"tier": 1, "save": 0, "school": "tr
          ansmutation", "items": ["potion", "scroll", "wand"], "range": 0
          , "duration": "rank*10", "casting_time": 0.5, "skill": ["arcana
          ", "perform_"], "properties": [], "effect_hash": {"speed": {"en
          hancement": 30}}, "description": "This spell increases your bas
          e land speed by 30 feet. This adjustment is treated as an enhan
          cement bonus. There is no effect on other modes of movement, su
          ch as burrow, climb, fly, or swim. As with any effect that incr
          eases your speed, this spell affects your jumping distance (see
           the Acrobatics skill)."},
      16      "Darkness": {"tier": 2, "save": 0, "school": "evocation", "
          items": ["scroll", "oil", "wand"], "range": 1, "duration": "ran
          k*10", "casting_time": 0.5, "skill": ["arcana", "healing"], "pr
          operties": [], "effect_hash": {}, "description": "This spell ca
          uses an object to radiate darkness out to a 20-foot radius. Thi
          s darkness causes the illumination level in the area to drop on
          e step, from bright light to normal light, from normal light to
           dim light, or from dim light to darkness. This spell has no ef
          fect in an area that is already dark. Creatures with light vuln
          erability or sensitivity take no penalties in normal light. All
           creatures gain concealment in dim light. All creatures gain to
          tal concealment in darkness. Creatures with darkvision can see 
          in an area of dim light or darkness without penalty. Nonmagical
           sources of light, such as torches and lanterns, do not increas
          e the light level in an area of darkness. Magical light sources
           only increase the light level in an area if they are of a high
          er spell level than darkness. If darkness is cast on a small ob
          ject that is then placed inside or under a lightproof covering,
           the spell’s effect is blocked until the covering is removed."}
          ,
      17      "Invisibility": {"tier": 2, "save": "will", "school": "ench
          antment", "items": ["potion", "scroll", "oil", "wand"], "range"
          : 1, "duration": "rank*10", "casting_time": 0.5, "skill": ["arc
          ana", "perform_"], "properties": [], "effect_hash": {}, "descri
          ption": "The creature or object touched radiates an aura of uni
          mportance preventing other creatures from noticing it or them. 
          If any creature realizes, or suspects, the target creature or o
          bject are nearby then they can make a wisdom save as a main act
          ion to overcome the spell for it's duration. There is a penalty
           on this save if they do not know which square the creature or 
          object is in, and a cumulative penalty for every failed save. I
          f an attack is made by the target including any harmful spells 
          cast then all creatures within sight of the target immediatly g
          ain the benefit of a successful save. Indirect actions, such as
           cutting a rope bridge, or setting fire to a building do not gr
          ant an automatic save. This spell affects any objects carried b
          y the target when the spell is cast but not objects dropped or 
          picked up after. Any part of an item that the subject carries b
          ut that extends more than 10 feet from can be observed. This sp
          ell does not prevent creatures from noticing sounds or smells o
          r other nonvisual clues to the targets existance."},
      18 -    "Web": {"tier": 2, "save": "reflex", "school": "conjuration
         -", "items": ["scroll", "wand"], "range": 2, "duration": "rank*1
         -0", "casting_time": 0.5, "skill": ["arcana"], "properties": [],
         - "effect_hash": {}, "description": "Web creates a many-layered 
         -mass of strong, sticky strands. These strands trap those caught
         - in them. The strands are similar to spiderwebs but far larger 
         -and tougher. These masses must be anchored to two or more solid
         - and diametrically opposed points or else the web collapses upo
         -n itself and disappears. Creatures caught within a web become g
         -rappled by the sticky fibers. Attacking a creature in a web doe
         -sn’t cause you to become grappled. Anyone in the effect’s area 
         -when the spell is cast must make a Reflex save. If this save su
         -cceeds, the creature is inside the web but is otherwise unaffec
         -ted. If the save fails, the creature gains the grappled conditi
         -on, but can break free by making a combat maneuver check or Esc
         -ape Artist check as a standard action against the DC of this sp
         -ell. The entire area of the web is considered difficult terrain
         -. Anyone moving through the webs must make a combat maneuver ch
         -eck or Escape Artist check as part of their move action, with a
         - DC equal to the spell’s DC. Creatures that fail lose their mov
         -ement and become grappled in the first square of webbing that t
         -hey enter. If you have at least 5 feet of web between you and a
         -n opponent, it provides cover. If you have at least 20 feet of 
         -web between you, it provides total cover. The strands of a web 
         -spell are flammable. A flaming weapon can slash them away as ea
         -sily as a hand brushes away cobwebs. Any fire can set the webs 
         -alight and burn away one 5-foot square in 1 round. All creature
         -s within flaming webs take fire damage from the flames."},     
      18 +    "Web": {"tier": 2, "save": "reflex", "school": "convergence
         +", "items": ["scroll", "wand"], "range": 2, "duration": "rank*1
         +0", "casting_time": 0.5, "skill": ["arcana"], "properties": [],
         + "effect_hash": {}, "description": "Web creates a many-layered 
         +mass of strong, sticky strands. These strands trap those caught
         + in them. The strands are similar to spiderwebs but far larger 
         +and tougher. These masses must be anchored to two or more solid
         + and diametrically opposed points or else the web collapses upo
         +n itself and disappears. Creatures caught within a web become g
         +rappled by the sticky fibers. Attacking a creature in a web doe
         +sn’t cause you to become grappled. Anyone in the effect’s area 
         +when the spell is cast must make a Reflex save. If this save su
         +cceeds, the creature is inside the web but is otherwise unaffec
         +ted. If the save fails, the creature gains the grappled conditi
         +on, but can break free by making a combat maneuver check or Esc
         +ape Artist check as a standard action against the DC of this sp
         +ell. The entire area of the web is considered difficult terrain
         +. Anyone moving through the webs must make a combat maneuver ch
         +eck or Escape Artist check as part of their move action, with a
         + DC equal to the spell’s DC. Creatures that fail lose their mov
         +ement and become grappled in the first square of webbing that t
         +hey enter. If you have at least 5 feet of web between you and a
         +n opponent, it provides cover. If you have at least 20 feet of 
         +web between you, it provides total cover. The strands of a web 
         +spell are flammable. A flaming weapon can slash them away as ea
         +sily as a hand brushes away cobwebs. Any fire can set the webs 
         +alight and burn away one 5-foot square in 1 round. All creature
         +s within flaming webs take fire damage from the flames."},     
      19      "Disguise Other": {"tier": 2, "save": "will", "school": "il
          lusion", "items": ["potion", "scroll", "oil", "wand"], "range":
           1, "duration": "rank*100", "casting_time": 0.5, "skill": ["arc
          ana", "perform_"], "properties": [], "effect_hash": {"disguise"
          : {"enhancement": 1}}, "description": "You make the target crea
          ture – including clothing, armor, weapons, and equipment – look
           different. They can seem 1 foot shorter or taller, thin, fat, 
          or in between. You cannot change your creature type (although y
          ou can appear as another subtype). Otherwise, the extent of the
           apparent change is up to you. You could add or obscure a minor
           feature or look like an entirely different person or gender."}
          ,
      20 -    "Create Pit": {"tier": 2, "save": "reflex", "school": "conj
         -uration", "items": ["scroll", "wand"], "range": 2, "duration": 
         -"rank", "casting_time": 0.5, "skill": ["arcana"], "properties":
         - [], "effect_hash": {}, "description": "You create a 10-foot-by
         --10-foot extra-dimensional hole with a depth of 10 feet per two
         - caster ranks (maximum 30 feet). You must create the pit on a h
         -orizontal surface of sufficient size. Since it extends into ano
         -ther dimension, the pit has no weight and does not otherwise di
         -splace the original underlying material. You can create the pit
         - in the deck of a ship as easily as in a dungeon floor or the g
         -round of a forest. Any creature standing in the area where you 
         -first conjured the pit must make a Reflex saving throw to jump 
         -to safety in the nearest open space. In addition, the edges of 
         -the pit are sloped, and any creature ending its turn on a squar
         -e adjacent to the pit must make a Reflex saving throw with a +1
         - bonus to avoid falling into it. Creatures subjected to an effe
         -ct intended to push them into the pit (such as bull rush) do no
         -t get a saving throw to avoid falling in if they are affected b
         -y the pushing effect. Creatures who fall into the pit take fall
         -ing damage as normal. The pit’s coarse stone walls increase the
         - Athletic check difficulty by 2. When the duration of the spell
         - ends, creatures within the hole rise up with the bottom of the
         - pit until they are standing on the surface over the course of 
         -a single round."},                                             
      20 +    "Create Pit": {"tier": 2, "save": "reflex", "school": "conv
         +ergence", "items": ["scroll", "wand"], "range": 2, "duration": 
         +"rank", "casting_time": 0.5, "skill": ["arcana"], "properties":
         + [], "effect_hash": {}, "description": "You create a 10-foot-by
         +-10-foot extra-dimensional hole with a depth of 10 feet per two
         + caster ranks (maximum 30 feet). You must create the pit on a h
         +orizontal surface of sufficient size. Since it extends into ano
         +ther dimension, the pit has no weight and does not otherwise di
         +splace the original underlying material. You can create the pit
         + in the deck of a ship as easily as in a dungeon floor or the g
         +round of a forest. Any creature standing in the area where you 
         +first conjured the pit must make a Reflex saving throw to jump 
         +to safety in the nearest open space. In addition, the edges of 
         +the pit are sloped, and any creature ending its turn on a squar
         +e adjacent to the pit must make a Reflex saving throw with a +1
         + bonus to avoid falling into it. Creatures subjected to an effe
         +ct intended to push them into the pit (such as bull rush) do no
         +t get a saving throw to avoid falling in if they are affected b
         +y the pushing effect. Creatures who fall into the pit take fall
         +ing damage as normal. The pit’s coarse stone walls increase the
         + Athletic check difficulty by 2. When the duration of the spell
         + ends, creatures within the hole rise up with the bottom of the
         + pit until they are standing on the surface over the course of 
         +a single round."},                                             
      21      "Silence": {"tier": 2, "save": "will", "school": "evocation
          ", "items": ["scroll", "wand"], "range": 3, "duration": "rank",
           "casting_time": 0.5, "skill": ["healing", "perform_"], "proper
          ties": [], "effect_hash": {}, "description": "Upon the casting 
          of this spell, complete silence prevails in the affected area. 
          All sound is stopped: Conversation is impossible, spells with v
          erbal components cannot be cast, and no noise whatsoever issues
           from, enters, or passes through the area. The spell can be cas
          t on a point in space, but the effect is stationary unless cast
           on a mobile object. The spell can be centered on a creature, a
          nd the effect then radiates from the creature and moves as it m
          oves. An unwilling creature can attempt a Will save to negate t
          he spell and can use Spell Resistance, if any. Items in a creat
          ure’s possession or magic items that emit sound receive the ben
          efits of saves and Spell Resistance, but unattended objects and
           points in space do not. Creatures in an area of a silence spel
          l are immune to sonic or language-based attacks, spells, and ef
          fects."},
      22      "Spiritual Weapon": {"tier": 2, "save": 0, "school": "evoca
          tion", "items": ["scroll", "wand"], "range": 0, "duration": "ra
          nk", "casting_time": 0.5, "skill": ["healing"], "properties": [
          ], "effect_hash": {}, "description": "A weapon made of force ap
          pears and attacks foes at a distance, as you direct it, dealing
           force damage. The weapon takes the shape of a weapon favored b
          y your deity or a weapon with some spiritual significance or sy
          mbolism to you and has the same properties as a real weapon of 
          its form. It strikes the opponent you designate, starting with 
          one attack in the round the spell is cast and continuing each r
          ound thereafter on your turn. It uses the casting bonus and num
          ber of dice used to cast the spell for it's attacks.  As a forc
          e effect, it can strike incorporeal creatures without the reduc
          tion in damage associated with incorporeality. The weapon alway
          s strikes from your direction. If the weapon goes beyond the sp
          ell range, if it goes out of your sight, or if you are not dire
          cting it, the weapon returns to you and hovers. Each round afte
          r the first, you can use a main action to redirect the weapon t
          o a new target. If you do not, the weapon continues to attack t
          he previous round’s target. The weapon gains one attack per rou
          nd. Even if the spiritual weapon is a ranged weapon, use the sp
          ell’s range, not the weapon’s normal range, and switching targe
          ts still is a main action."}},
      23    "abilities": {

● Update(/home/user/crimson-steel/data/compendium.json)
  ⎿  Added 2 lines, removed 2 lines
      11      "Cure": {"tier": [0, 1, 2, 3, 4, 5], "save": "cha", "school
          ": "pneumancy", "items": ["potion", "scroll", "wand"], "range":
           1, "duration": "instant", "casting_time": 0.5, "skill": ["heal
          ing", "nature", "perform_"], "properties": [], "effect_hash": {
          "minor_damage": [2, 4, 8, 16, 32, 64], "moderate_damage": [1, 2
          , 4, 8, 16, 32], "major_damage": [0, 0, 0, 1, 2, 4], "bleeding"
          : "-1*success", "minimum_saturation": "tier*2", "saturation": "
          tier*5"}, "suffix": ["Petty Wounds", "Lesser Wounds", "Simple W
          ounds", "Moderate Wounds", "Advanced Wounds", "Superior"], "des
          cription": "Cure target for {major_damage} points of major dama
          ge, {moderate_damage} points of moderate damage, and {minor_dam
          age} points of minor damage. Any bleeding is reduced based upon
           spell tier and success roll."},
      12      "Benign Transposition": {"tier": 1, "save": 0, "school": "c
          onvergence", "items": ["scroll", "wand"], "range": 3, "duration
          ": "instant", "casting_time": 0.5, "skill": ["arcana"], "proper
          ties": [], "effect_hash": {}, "description": "Two target creatu
          res, of which you can be one, instantly swap positions. Both su
          bjects must be within range. Objects carried by the creatures (
          up to the creatures' maximum loads) go with them, but other cre
          atures do not, even if they are carried. The movement is instan
          taneous and does not provoke attacks of opportunity."},
      13      "Grease": {"tier": 1, "save": "dex", "school": "convergence
          ", "items": ["scroll", "oil", "wand"], "range": 2, "duration": 
          "rank", "casting_time": 0.5, "skill": ["arcana", "perform_"], "
          properties": [], "effect_hash": {}, "description": "One creatur
          e or 10 foot square becomes covered in grease. Covered creature
          s suffer a -2 situational penalty on athletics checks and gain 
          a +2 situational bonus on escape artist checks. Creatures in th
          e area when the spell is cast, ending their turn in grease, or 
          moving through grease must save or fall prone."},
      14 -    "Disguise Self": {"tier": 1, "save": 0, "school": "illusion
         -", "items": ["potion", "scroll", "wand"], "range": 0, "duration
         -": "rank*100", "casting_time": 0.5, "skill": ["arcana", "perfor
         -m_"], "properties": [], "effect_hash": {"disguise": {"enhanceme
         -nt": 1}}, "description": "You make yourself – including clothin
         -g, armor, weapons, and equipment – look different. You can seem
         - 1 foot shorter or taller, thin, fat, or in between. You cannot
         - change your creature type (although you can appear as another 
         -subtype). Otherwise, the extent of the apparent change is up to
         - you. You could add or obscure a minor feature or look like an 
         -entirely different person or gender."},                        
      14 +    "Disguise Self": {"tier": 1, "save": 0, "school": "resonanc
         +e", "items": ["potion", "scroll", "wand"], "range": 0, "duratio
         +n": "rank*100", "casting_time": 0.5, "skill": ["arcana", "perfo
         +rm_"], "properties": [], "effect_hash": {"disguise": {"enhancem
         +ent": 1}}, "description": "You make yourself – including clothi
         +ng, armor, weapons, and equipment – look different. You can see
         +m 1 foot shorter or taller, thin, fat, or in between. You canno
         +t change your creature type (although you can appear as another
         + subtype). Otherwise, the extent of the apparent change is up t
         +o you. You could add or obscure a minor feature or look like an
         + entirely different person or gender."},                       
      15      "Expeditious Retreat": {"tier": 1, "save": 0, "school": "tr
          ansmutation", "items": ["potion", "scroll", "wand"], "range": 0
          , "duration": "rank*10", "casting_time": 0.5, "skill": ["arcana
          ", "perform_"], "properties": [], "effect_hash": {"speed": {"en
          hancement": 30}}, "description": "This spell increases your bas
          e land speed by 30 feet. This adjustment is treated as an enhan
          cement bonus. There is no effect on other modes of movement, su
          ch as burrow, climb, fly, or swim. As with any effect that incr
          eases your speed, this spell affects your jumping distance (see
           the Acrobatics skill)."},
      16      "Darkness": {"tier": 2, "save": 0, "school": "evocation", "
          items": ["scroll", "oil", "wand"], "range": 1, "duration": "ran
          k*10", "casting_time": 0.5, "skill": ["arcana", "healing"], "pr
          operties": [], "effect_hash": {}, "description": "This spell ca
          uses an object to radiate darkness out to a 20-foot radius. Thi
          s darkness causes the illumination level in the area to drop on
          e step, from bright light to normal light, from normal light to
           dim light, or from dim light to darkness. This spell has no ef
          fect in an area that is already dark. Creatures with light vuln
          erability or sensitivity take no penalties in normal light. All
           creatures gain concealment in dim light. All creatures gain to
          tal concealment in darkness. Creatures with darkvision can see 
          in an area of dim light or darkness without penalty. Nonmagical
           sources of light, such as torches and lanterns, do not increas
          e the light level in an area of darkness. Magical light sources
           only increase the light level in an area if they are of a high
          er spell level than darkness. If darkness is cast on a small ob
          ject that is then placed inside or under a lightproof covering,
           the spell’s effect is blocked until the covering is removed."}
          ,
      17      "Invisibility": {"tier": 2, "save": "will", "school": "ench
          antment", "items": ["potion", "scroll", "oil", "wand"], "range"
          : 1, "duration": "rank*10", "casting_time": 0.5, "skill": ["arc
          ana", "perform_"], "properties": [], "effect_hash": {}, "descri
          ption": "The creature or object touched radiates an aura of uni
          mportance preventing other creatures from noticing it or them. 
          If any creature realizes, or suspects, the target creature or o
          bject are nearby then they can make a wisdom save as a main act
          ion to overcome the spell for it's duration. There is a penalty
           on this save if they do not know which square the creature or 
          object is in, and a cumulative penalty for every failed save. I
          f an attack is made by the target including any harmful spells 
          cast then all creatures within sight of the target immediatly g
          ain the benefit of a successful save. Indirect actions, such as
           cutting a rope bridge, or setting fire to a building do not gr
          ant an automatic save. This spell affects any objects carried b
          y the target when the spell is cast but not objects dropped or 
          picked up after. Any part of an item that the subject carries b
          ut that extends more than 10 feet from can be observed. This sp
          ell does not prevent creatures from noticing sounds or smells o
          r other nonvisual clues to the targets existance."},
      18      "Web": {"tier": 2, "save": "reflex", "school": "convergence
          ", "items": ["scroll", "wand"], "range": 2, "duration": "rank*1
          0", "casting_time": 0.5, "skill": ["arcana"], "properties": [],
           "effect_hash": {}, "description": "Web creates a many-layered 
          mass of strong, sticky strands. These strands trap those caught
           in them. The strands are similar to spiderwebs but far larger 
          and tougher. These masses must be anchored to two or more solid
           and diametrically opposed points or else the web collapses upo
          n itself and disappears. Creatures caught within a web become g
          rappled by the sticky fibers. Attacking a creature in a web doe
          sn’t cause you to become grappled. Anyone in the effect’s area 
          when the spell is cast must make a Reflex save. If this save su
          cceeds, the creature is inside the web but is otherwise unaffec
          ted. If the save fails, the creature gains the grappled conditi
          on, but can break free by making a combat maneuver check or Esc
          ape Artist check as a standard action against the DC of this sp
          ell. The entire area of the web is considered difficult terrain
          . Anyone moving through the webs must make a combat maneuver ch
          eck or Escape Artist check as part of their move action, with a
           DC equal to the spell’s DC. Creatures that fail lose their mov
          ement and become grappled in the first square of webbing that t
          hey enter. If you have at least 5 feet of web between you and a
          n opponent, it provides cover. If you have at least 20 feet of 
          web between you, it provides total cover. The strands of a web 
          spell are flammable. A flaming weapon can slash them away as ea
          sily as a hand brushes away cobwebs. Any fire can set the webs 
          alight and burn away one 5-foot square in 1 round. All creature
          s within flaming webs take fire damage from the flames."},
      19 -    "Disguise Other": {"tier": 2, "save": "will", "school": "il
         -lusion", "items": ["potion", "scroll", "oil", "wand"], "range":
         - 1, "duration": "rank*100", "casting_time": 0.5, "skill": ["arc
         -ana", "perform_"], "properties": [], "effect_hash": {"disguise"
         -: {"enhancement": 1}}, "description": "You make the target crea
         -ture – including clothing, armor, weapons, and equipment – look
         - different. They can seem 1 foot shorter or taller, thin, fat, 
         -or in between. You cannot change your creature type (although y
         -ou can appear as another subtype). Otherwise, the extent of the
         - apparent change is up to you. You could add or obscure a minor
         - feature or look like an entirely different person or gender."}
         -,                                                              
      19 +    "Disguise Other": {"tier": 2, "save": "will", "school": "re
         +sonance", "items": ["potion", "scroll", "oil", "wand"], "range"
         +: 1, "duration": "rank*100", "casting_time": 0.5, "skill": ["ar
         +cana", "perform_"], "properties": [], "effect_hash": {"disguise
         +": {"enhancement": 1}}, "description": "You make the target cre
         +ature – including clothing, armor, weapons, and equipment – loo
         +k different. They can seem 1 foot shorter or taller, thin, fat,
         + or in between. You cannot change your creature type (although 
         +you can appear as another subtype). Otherwise, the extent of th
         +e apparent change is up to you. You could add or obscure a mino
         +r feature or look like an entirely different person or gender."
         +},                                                             
      20      "Create Pit": {"tier": 2, "save": "reflex", "school": "conv
          ergence", "items": ["scroll", "wand"], "range": 2, "duration": 
          "rank", "casting_time": 0.5, "skill": ["arcana"], "properties":
           [], "effect_hash": {}, "description": "You create a 10-foot-by
          -10-foot extra-dimensional hole with a depth of 10 feet per two
           caster ranks (maximum 30 feet). You must create the pit on a h
          orizontal surface of sufficient size. Since it extends into ano
          ther dimension, the pit has no weight and does not otherwise di
          splace the original underlying material. You can create the pit
           in the deck of a ship as easily as in a dungeon floor or the g
          round of a forest. Any creature standing in the area where you 
          first conjured the pit must make a Reflex saving throw to jump 
          to safety in the nearest open space. In addition, the edges of 
          the pit are sloped, and any creature ending its turn on a squar
          e adjacent to the pit must make a Reflex saving throw with a +1
           bonus to avoid falling into it. Creatures subjected to an effe
          ct intended to push them into the pit (such as bull rush) do no
          t get a saving throw to avoid falling in if they are affected b
          y the pushing effect. Creatures who fall into the pit take fall
          ing damage as normal. The pit’s coarse stone walls increase the
           Athletic check difficulty by 2. When the duration of the spell
           ends, creatures within the hole rise up with the bottom of the
           pit until they are standing on the surface over the course of 
          a single round."},
      21      "Silence": {"tier": 2, "save": "will", "school": "evocation
          ", "items": ["scroll", "wand"], "range": 3, "duration": "rank",
           "casting_time": 0.5, "skill": ["healing", "perform_"], "proper
          ties": [], "effect_hash": {}, "description": "Upon the casting 
          of this spell, complete silence prevails in the affected area. 
          All sound is stopped: Conversation is impossible, spells with v
          erbal components cannot be cast, and no noise whatsoever issues
           from, enters, or passes through the area. The spell can be cas
          t on a point in space, but the effect is stationary unless cast
           on a mobile object. The spell can be centered on a creature, a
          nd the effect then radiates from the creature and moves as it m
          oves. An unwilling creature can attempt a Will save to negate t
          he spell and can use Spell Resistance, if any. Items in a creat
          ure’s possession or magic items that emit sound receive the ben
          efits of saves and Spell Resistance, but unattended objects and
           points in space do not. Creatures in an area of a silence spel
          l are immune to sonic or language-based attacks, spells, and ef
          fects."},
      22      "Spiritual Weapon": {"tier": 2, "save": 0, "school": "evoca
          tion", "items": ["scroll", "wand"], "range": 0, "duration": "ra
          nk", "casting_time": 0.5, "skill": ["healing"], "properties": [
          ], "effect_hash": {}, "description": "A weapon made of force ap
          pears and attacks foes at a distance, as you direct it, dealing
           force damage. The weapon takes the shape of a weapon favored b
          y your deity or a weapon with some spiritual significance or sy
          mbolism to you and has the same properties as a real weapon of 
          its form. It strikes the opponent you designate, starting with 
          one attack in the round the spell is cast and continuing each r
          ound thereafter on your turn. It uses the casting bonus and num
          ber of dice used to cast the spell for it's attacks.  As a forc
          e effect, it can strike incorporeal creatures without the reduc
          tion in damage associated with incorporeality. The weapon alway
          s strikes from your direction. If the weapon goes beyond the sp
          ell range, if it goes out of your sight, or if you are not dire
          cting it, the weapon returns to you and hovers. Each round afte
          r the first, you can use a main action to redirect the weapon t
          o a new target. If you do not, the weapon continues to attack t
          he previous round’s target. The weapon gains one attack per rou
          nd. Even if the spiritual weapon is a ranged weapon, use the sp
          ell’s range, not the weapon’s normal range, and switching targe
          ts still is a main action."}},

● Update(/home/user/crimson-steel/data/compendium.json)
  ⎿  Added 3 lines, removed 3 lines
      13      "Grease": {"tier": 1, "save": "dex", "school": "convergence
          ", "items": ["scroll", "oil", "wand"], "range": 2, "duration": 
          "rank", "casting_time": 0.5, "skill": ["arcana", "perform_"], "
          properties": [], "effect_hash": {}, "description": "One creatur
          e or 10 foot square becomes covered in grease. Covered creature
          s suffer a -2 situational penalty on athletics checks and gain 
          a +2 situational bonus on escape artist checks. Creatures in th
          e area when the spell is cast, ending their turn in grease, or 
          moving through grease must save or fall prone."},
      14      "Disguise Self": {"tier": 1, "save": 0, "school": "resonanc
          e", "items": ["potion", "scroll", "wand"], "range": 0, "duratio
          n": "rank*100", "casting_time": 0.5, "skill": ["arcana", "perfo
          rm_"], "properties": [], "effect_hash": {"disguise": {"enhancem
          ent": 1}}, "description": "You make yourself – including clothi
          ng, armor, weapons, and equipment – look different. You can see
          m 1 foot shorter or taller, thin, fat, or in between. You canno
          t change your creature type (although you can appear as another
           subtype). Otherwise, the extent of the apparent change is up t
          o you. You could add or obscure a minor feature or look like an
           entirely different person or gender."},
      15      "Expeditious Retreat": {"tier": 1, "save": 0, "school": "tr
          ansmutation", "items": ["potion", "scroll", "wand"], "range": 0
          , "duration": "rank*10", "casting_time": 0.5, "skill": ["arcana
          ", "perform_"], "properties": [], "effect_hash": {"speed": {"en
          hancement": 30}}, "description": "This spell increases your bas
          e land speed by 30 feet. This adjustment is treated as an enhan
          cement bonus. There is no effect on other modes of movement, su
          ch as burrow, climb, fly, or swim. As with any effect that incr
          eases your speed, this spell affects your jumping distance (see
           the Acrobatics skill)."},
      16 -    "Darkness": {"tier": 2, "save": 0, "school": "evocation", "
         -items": ["scroll", "oil", "wand"], "range": 1, "duration": "ran
         -k*10", "casting_time": 0.5, "skill": ["arcana", "healing"], "pr
         -operties": [], "effect_hash": {}, "description": "This spell ca
         -uses an object to radiate darkness out to a 20-foot radius. Thi
         -s darkness causes the illumination level in the area to drop on
         -e step, from bright light to normal light, from normal light to
         - dim light, or from dim light to darkness. This spell has no ef
         -fect in an area that is already dark. Creatures with light vuln
         -erability or sensitivity take no penalties in normal light. All
         - creatures gain concealment in dim light. All creatures gain to
         -tal concealment in darkness. Creatures with darkvision can see 
         -in an area of dim light or darkness without penalty. Nonmagical
         - sources of light, such as torches and lanterns, do not increas
         -e the light level in an area of darkness. Magical light sources
         - only increase the light level in an area if they are of a high
         -er spell level than darkness. If darkness is cast on a small ob
         -ject that is then placed inside or under a lightproof covering,
         - the spell’s effect is blocked until the covering is removed."}
         -,                                                              
      16 +    "Darkness": {"tier": 2, "save": 0, "school": "resonance", "
         +items": ["scroll", "oil", "wand"], "range": 1, "duration": "ran
         +k*10", "casting_time": 0.5, "skill": ["arcana", "healing"], "pr
         +operties": [], "effect_hash": {}, "description": "This spell ca
         +uses an object to radiate darkness out to a 20-foot radius. Thi
         +s darkness causes the illumination level in the area to drop on
         +e step, from bright light to normal light, from normal light to
         + dim light, or from dim light to darkness. This spell has no ef
         +fect in an area that is already dark. Creatures with light vuln
         +erability or sensitivity take no penalties in normal light. All
         + creatures gain concealment in dim light. All creatures gain to
         +tal concealment in darkness. Creatures with darkvision can see 
         +in an area of dim light or darkness without penalty. Nonmagical
         + sources of light, such as torches and lanterns, do not increas
         +e the light level in an area of darkness. Magical light sources
         + only increase the light level in an area if they are of a high
         +er spell level than darkness. If darkness is cast on a small ob
         +ject that is then placed inside or under a lightproof covering,
         + the spell’s effect is blocked until the covering is removed."}
         +,                                                              
      17      "Invisibility": {"tier": 2, "save": "will", "school": "ench
          antment", "items": ["potion", "scroll", "oil", "wand"], "range"
          : 1, "duration": "rank*10", "casting_time": 0.5, "skill": ["arc
          ana", "perform_"], "properties": [], "effect_hash": {}, "descri
          ption": "The creature or object touched radiates an aura of uni
          mportance preventing other creatures from noticing it or them. 
          If any creature realizes, or suspects, the target creature or o
          bject are nearby then they can make a wisdom save as a main act
          ion to overcome the spell for it's duration. There is a penalty
           on this save if they do not know which square the creature or 
          object is in, and a cumulative penalty for every failed save. I
          f an attack is made by the target including any harmful spells 
          cast then all creatures within sight of the target immediatly g
          ain the benefit of a successful save. Indirect actions, such as
           cutting a rope bridge, or setting fire to a building do not gr
          ant an automatic save. This spell affects any objects carried b
          y the target when the spell is cast but not objects dropped or 
          picked up after. Any part of an item that the subject carries b
          ut that extends more than 10 feet from can be observed. This sp
          ell does not prevent creatures from noticing sounds or smells o
          r other nonvisual clues to the targets existance."},
      18      "Web": {"tier": 2, "save": "reflex", "school": "convergence
          ", "items": ["scroll", "wand"], "range": 2, "duration": "rank*1
          0", "casting_time": 0.5, "skill": ["arcana"], "properties": [],
           "effect_hash": {}, "description": "Web creates a many-layered 
          mass of strong, sticky strands. These strands trap those caught
           in them. The strands are similar to spiderwebs but far larger 
          and tougher. These masses must be anchored to two or more solid
           and diametrically opposed points or else the web collapses upo
          n itself and disappears. Creatures caught within a web become g
          rappled by the sticky fibers. Attacking a creature in a web doe
          sn’t cause you to become grappled. Anyone in the effect’s area 
          when the spell is cast must make a Reflex save. If this save su
          cceeds, the creature is inside the web but is otherwise unaffec
          ted. If the save fails, the creature gains the grappled conditi
          on, but can break free by making a combat maneuver check or Esc
          ape Artist check as a standard action against the DC of this sp
          ell. The entire area of the web is considered difficult terrain
          . Anyone moving through the webs must make a combat maneuver ch
          eck or Escape Artist check as part of their move action, with a
           DC equal to the spell’s DC. Creatures that fail lose their mov
          ement and become grappled in the first square of webbing that t
          hey enter. If you have at least 5 feet of web between you and a
          n opponent, it provides cover. If you have at least 20 feet of 
          web between you, it provides total cover. The strands of a web 
          spell are flammable. A flaming weapon can slash them away as ea
          sily as a hand brushes away cobwebs. Any fire can set the webs 
          alight and burn away one 5-foot square in 1 round. All creature
          s within flaming webs take fire damage from the flames."},
      19      "Disguise Other": {"tier": 2, "save": "will", "school": "re
          sonance", "items": ["potion", "scroll", "oil", "wand"], "range"
          : 1, "duration": "rank*100", "casting_time": 0.5, "skill": ["ar
          cana", "perform_"], "properties": [], "effect_hash": {"disguise
          ": {"enhancement": 1}}, "description": "You make the target cre
          ature – including clothing, armor, weapons, and equipment – loo
          k different. They can seem 1 foot shorter or taller, thin, fat,
           or in between. You cannot change your creature type (although 
          you can appear as another subtype). Otherwise, the extent of th
          e apparent change is up to you. You could add or obscure a mino
          r feature or look like an entirely different person or gender."
          },
      20      "Create Pit": {"tier": 2, "save": "reflex", "school": "conv
          ergence", "items": ["scroll", "wand"], "range": 2, "duration": 
          "rank", "casting_time": 0.5, "skill": ["arcana"], "properties":
           [], "effect_hash": {}, "description": "You create a 10-foot-by
          -10-foot extra-dimensional hole with a depth of 10 feet per two
           caster ranks (maximum 30 feet). You must create the pit on a h
          orizontal surface of sufficient size. Since it extends into ano
          ther dimension, the pit has no weight and does not otherwise di
          splace the original underlying material. You can create the pit
           in the deck of a ship as easily as in a dungeon floor or the g
          round of a forest. Any creature standing in the area where you 
          first conjured the pit must make a Reflex saving throw to jump 
          to safety in the nearest open space. In addition, the edges of 
          the pit are sloped, and any creature ending its turn on a squar
          e adjacent to the pit must make a Reflex saving throw with a +1
           bonus to avoid falling into it. Creatures subjected to an effe
          ct intended to push them into the pit (such as bull rush) do no
          t get a saving throw to avoid falling in if they are affected b
          y the pushing effect. Creatures who fall into the pit take fall
          ing damage as normal. The pit’s coarse stone walls increase the
           Athletic check difficulty by 2. When the duration of the spell
           ends, creatures within the hole rise up with the bottom of the
           pit until they are standing on the surface over the course of 
          a single round."},
      21 -    "Silence": {"tier": 2, "save": "will", "school": "evocation
         -", "items": ["scroll", "wand"], "range": 3, "duration": "rank",
         - "casting_time": 0.5, "skill": ["healing", "perform_"], "proper
         -ties": [], "effect_hash": {}, "description": "Upon the casting 
         -of this spell, complete silence prevails in the affected area. 
         -All sound is stopped: Conversation is impossible, spells with v
         -erbal components cannot be cast, and no noise whatsoever issues
         - from, enters, or passes through the area. The spell can be cas
         -t on a point in space, but the effect is stationary unless cast
         - on a mobile object. The spell can be centered on a creature, a
         -nd the effect then radiates from the creature and moves as it m
         -oves. An unwilling creature can attempt a Will save to negate t
         -he spell and can use Spell Resistance, if any. Items in a creat
         -ure’s possession or magic items that emit sound receive the ben
         -efits of saves and Spell Resistance, but unattended objects and
         - points in space do not. Creatures in an area of a silence spel
         -l are immune to sonic or language-based attacks, spells, and ef
         -fects."},                                                      
      22 -    "Spiritual Weapon": {"tier": 2, "save": 0, "school": "evoca
         -tion", "items": ["scroll", "wand"], "range": 0, "duration": "ra
         -nk", "casting_time": 0.5, "skill": ["healing"], "properties": [
         -], "effect_hash": {}, "description": "A weapon made of force ap
         -pears and attacks foes at a distance, as you direct it, dealing
         - force damage. The weapon takes the shape of a weapon favored b
         -y your deity or a weapon with some spiritual significance or sy
         -mbolism to you and has the same properties as a real weapon of 
         -its form. It strikes the opponent you designate, starting with 
         -one attack in the round the spell is cast and continuing each r
         -ound thereafter on your turn. It uses the casting bonus and num
         -ber of dice used to cast the spell for it's attacks.  As a forc
         -e effect, it can strike incorporeal creatures without the reduc
         -tion in damage associated with incorporeality. The weapon alway
         -s strikes from your direction. If the weapon goes beyond the sp
         -ell range, if it goes out of your sight, or if you are not dire
         -cting it, the weapon returns to you and hovers. Each round afte
         -r the first, you can use a main action to redirect the weapon t
         -o a new target. If you do not, the weapon continues to attack t
         -he previous round’s target. The weapon gains one attack per rou
         -nd. Even if the spiritual weapon is a ranged weapon, use the sp
         -ell’s range, not the weapon’s normal range, and switching targe
         -ts still is a main action."}},                                 
      21 +    "Silence": {"tier": 2, "save": "will", "school": "resonance
         +", "items": ["scroll", "wand"], "range": 3, "duration": "rank",
         + "casting_time": 0.5, "skill": ["healing", "perform_"], "proper
         +ties": [], "effect_hash": {}, "description": "Upon the casting 
         +of this spell, complete silence prevails in the affected area. 
         +All sound is stopped: Conversation is impossible, spells with v
         +erbal components cannot be cast, and no noise whatsoever issues
         + from, enters, or passes through the area. The spell can be cas
         +t on a point in space, but the effect is stationary unless cast
         + on a mobile object. The spell can be centered on a creature, a
         +nd the effect then radiates from the creature and moves as it m
         +oves. An unwilling creature can attempt a Will save to negate t
         +he spell and can use Spell Resistance, if any. Items in a creat
         +ure’s possession or magic items that emit sound receive the ben
         +efits of saves and Spell Resistance, but unattended objects and
         + points in space do not. Creatures in an area of a silence spel
         +l are immune to sonic or language-based attacks, spells, and ef
         +fects."},                                                      
      22 +    "Spiritual Weapon": {"tier": 2, "save": 0, "school": "reson
         +ance", "items": ["scroll", "wand"], "range": 0, "duration": "ra
         +nk", "casting_time": 0.5, "skill": ["healing"], "properties": [
         +], "effect_hash": {}, "description": "A weapon made of force ap
         +pears and attacks foes at a distance, as you direct it, dealing
         + force damage. The weapon takes the shape of a weapon favored b
         +y your deity or a weapon with some spiritual significance or sy
         +mbolism to you and has the same properties as a real weapon of 
         +its form. It strikes the opponent you designate, starting with 
         +one attack in the round the spell is cast and continuing each r
         +ound thereafter on your turn. It uses the casting bonus and num
         +ber of dice used to cast the spell for it's attacks.  As a forc
         +e effect, it can strike incorporeal creatures without the reduc
         +tion in damage associated with incorporeality. The weapon alway
         +s strikes from your direction. If the weapon goes beyond the sp
         +ell range, if it goes out of your sight, or if you are not dire
         +cting it, the weapon returns to you and hovers. Each round afte
         +r the first, you can use a main action to redirect the weapon t
         +o a new target. If you do not, the weapon continues to attack t
         +he previous round’s target. The weapon gains one attack per rou
         +nd. Even if the spiritual weapon is a ranged weapon, use the sp
         +ell’s range, not the weapon’s normal range, and switching targe
         +ts still is a main action."}},                                 
      23    "abilities": {
      24      "bardic_inspiration": "During your magical performance you 
          can use your performance to inspire your allies or distract you
          r enemies. This creates a pool of luck that can be spent by you
           or your team to reroll dice on any check your or they make. Ea
          ch point must be spent before the initial check is made, and ea
          ch point will allow a single reroll. Using this ability costs o
          ne point of mana and can only be used once per turn. This is a 
          main action that can be used as part of maintaining your perfor
          mance but only if that action is not used for any other purpose
           such as casting a spell. You gain one point of luck per succes
          s, and each point must be used before your next turn or it is l
          ost. Fumbling grants all failures to the DM to be used for the 
          enemy, or against the players.",
      25      "better_lucky_than_good": "You may spend 3 mana during any 
          round that you are unable to act such as the surprise round. Al
          l attacks against you, including spells, are made with half as 
          many dice with a minimum of 3 dice. Enemies are unconsciously a
          ware of this penalty and may instead choose to target your alli
          es instead or use 3 dice on the attack.",

● Now update the CSS — replace old school badges with new ones:

  Read 1 file (ctrl+o to expand)

● Update(/home/user/crimson-steel/public/style.css)
  ⎿  Added 4 lines, removed 6 lines
      352  
      353  .school-badge { display: inline-block; padding: 1px 6px; borde
           r-radius: 3px; font-size: 10px; font-weight: bold; color: whit
           e; }
      354  .school-universal { background: #757575; }
      355 -.school-necromancy { background: #4a148c; }                   
      356 -.school-evocation { background: #c62828; }                    
      357 -.school-illusion { background: #6a1b9a; }                     
      355 +.school-pneumancy { background: #4a148c; }                    
      356 +.school-resonance { background: #c62828; }                    
      357  .school-enchantment { background: #ad1457; }
      359 -.school-divination { background: #0277bd; }                   
      360 -.school-abjuration { background: #00695c; }                   
      361 -.school-conjuration { background: #ef6c00; }                  
      358 +.school-augury { background: #0277bd; }                       
      359 +.school-convergence { background: #ef6c00; }                  
      360  .school-transmutation { background: #558b2f; }
      361  
      362  /* Spell detail page */

● Bash(ruby -e "require 'json'; JSON.parse(File.read('data/compendium.json'))"
      && echo "JSON valid")
  ⎿  JSON valid

● Bash(git add data/compendium.json public/style.css && git commit -m "$(cat
      <<'EOF'
      Replace spell schools with custom system…)
  ⎿  [claude/add-magic-tab-gx56h 222c1e6] Replace spell schools with custom
      system
      2 files changed, 16 insertions(+), 18 deletions(-)

● Bash(git push -u origin claude/add-magic-tab-gx56h)
  ⎿  To http://127.0.0.1:36437/git/dividetask/crimson-steel
        19ec5df..222c1e6  claude/add-magic-tab-gx56h -> claude/add-magic-ta
     b-gx56h
     … +2 lines (ctrl+o to expand)

● Done. The school system is now:

  ┌───────────────┬───────────────────────────────────────────────┬────────┐
  │    School     │                     Theme                     │ Color  │
  ├───────────────┼───────────────────────────────────────────────┼────────┤
  │ Universal     │ Cross-school utility                          │ Gray   │
  ├───────────────┼───────────────────────────────────────────────┼────────┤
  │ Pneumancy     │ Soul/spirit, undead, binding, communing       │ Purple │
  ├───────────────┼───────────────────────────────────────────────┼────────┤
  │ Resonance     │ Force, energy, light, sound, warding          │ Red    │
  ├───────────────┼───────────────────────────────────────────────┼────────┤
  │ Enchantment   │ Mind-affecting, will saves                    │ Pink   │
  ├───────────────┼───────────────────────────────────────────────┼────────┤
  │ Augury        │ Fate reading, detection, foresight            │ Blue   │
  ├───────────────┼───────────────────────────────────────────────┼────────┤
  │ Convergence   │ Dimensional pulling, summoning, translocation │ Orange │
  ├───────────────┼───────────────────────────────────────────────┼────────┤
  │ Transmutation │ Physical transformation                       │ Green  │
  └───────────────┴───────────────────────────────────────────────┴────────┘

  Current spell assignments:
  - Universal: Recharge
  - Pneumancy: Cure
  - Resonance: Ward, Disguise Self, Disguise Other, Darkness, Silence, Spiritual
   Weapon
  - Enchantment: Invisibility
  - Convergence: Benign Transposition, Grease, Web, Create Pit
  - Transmutation: Expeditious Retreat

❯ The spell Cure on the character sheet isn't linking to the spell, and instead 
   I am getting an error saying spell not found. Please make a list of  every   
  spell that needs to be added                                                  

  Read 1 file (ctrl+o to expand)

● Here are all the spells referenced on character sheets that don't exist in
  compendium.json:

  Stumpy (Cleric):
  1. Stabilize
  2. Sacred Flame
  3. Magic Vestments
  4. Cure Lesser Wounds
  5. Healing Word
  6. Command
  7. Lesser Ward
  8. Divine Favor
  9. Shield of Faith
  10. Magic Weapon
  11. Hold Person
  12. Blindness/Deafness
  13. Augury (note: this is also the name of your new spell school)
  14. Cure Simple Wounds
  15. Standard Ward
  16. Locate Object
  17. Protection from Poison
  18. Standard Surgery

  Lysander (Arcane Trickster):
  19. Fire Bolt
  20. Message
  21. Silent Portal
  22. Ghost Sound
  23. Mage Hand
  24. Hideous Laughter
  25. Illusion of Calm
  26. Auditory Hallucination

  Cottonballs (Bard):
  27. Detect Magic
  28. Friends
  29. Sift
  30. Vacuous Vessel
  31. Vicious Mockery
  32. Biting Words
  33. Ears of the City
  34. Silent Image
  35. Timely Inspiration

  That's 35 spells on character sheets that aren't in the compendium yet. The
  only character sheet spells that already exist are Spiritual Weapon and
  Silence (on Stumpy) and Ghost Sound and Stabilize appear on both Lysander and
  Cottonballs but none of them are in the compendium either.

  Want me to add stub entries for all of these so the links work? I'd set them
  up with the name, a placeholder description, and "universal" school — then you
   can fill in the real details and assign schools as you go.

❯ The issue is Cure Lesser Wounds links here                                    
  http://localhost:4567/spell/Cure%20Lesser%20Wounds                            
  Instead of  Cure. I assume this problem exists for the other spells like Ward 

● Right, the character sheet spells use the prefixed/suffixed names (like "Cure
  Lesser Wounds", "Lesser Ward", "Standard Ward") but the compendium stores them
   as base spells ("Cure", "Ward") with tier variants defined by the
  prefix/suffix arrays.

  The link needs to map the display name back to the base spell. Let me check
  what prefixes/suffixes exist.

  Read 1 file (ctrl+o to expand)

● I need to add a helper method that resolves a display spell name (like "Cure
  Lesser Wounds") back to its base compendium spell name ("Cure"). I'll build a
  lookup from all prefix/suffix + base name combinations in the spell/:name
  route.

  Read 1 file (ctrl+o to expand)

● I'll update the /spell/:name route to fall back to a prefix/suffix lookup when
   the exact name isn't found, and also set @tier_index so the detail page can
  highlight which tier variant was clicked.

● Update(/home/user/crimson-steel/app.rb)
  ⎿  Added 20 lines
      368    compendium = Compendium.new
      369    @spell_name = params[:name]
      370    @spell = compendium.data["spells"][@spell_name]
      371 +  @tier_index = nil                                           
      372 +                                                              
      373 +  unless @spell                                               
      374 +    compendium.data["spells"].each do |base_name, spell_data| 
      375 +      tiers = spell_data["tier"].is_a?(Array) ? spell_data["ti
          +er"] : [spell_data["tier"]]                                   
      376 +      tiers.each_with_index do |tier_val, idx|                
      377 +        variant_names = []                                    
      378 +        variant_names << "#{spell_data["prefix"][idx]} #{base_
          +name}" if spell_data["prefix"] && spell_data["prefix"][idx]   
      379 +        variant_names << "#{base_name} #{spell_data["suffix"][
          +idx]}" if spell_data["suffix"] && spell_data["suffix"][idx]   
      380 +        if variant_names.any? { |v| v == @spell_name }        
      381 +          @spell = spell_data                                 
      382 +          @spell_name = base_name                             
      383 +          @tier_index = idx                                   
      384 +          break                                               
      385 +        end                                                   
      386 +      end                                                     
      387 +      break if @spell                                         
      388 +    end                                                       
      389 +  end                                                         
      390 +                                                              
      391    halt 404, "Spell not found" unless @spell
      392    @school = @spell["school"] || "universal"
      393    @range_labels = compendium.data["range"]

● Now let me verify: "Cure Lesser Wounds" — Cure has suffix ["Petty Wounds", 
  "Lesser Wounds", ...], so tier 1 variant = "Cure Lesser Wounds". That matches.
   "Lesser Ward" — Ward has prefix ["Trivial", "Lesser", ...], so tier 1 =
  "Lesser Ward". Also matches. "Standard Ward" — prefix index 2 is "Simple", not
   "Standard". That one won't match automatically — but that's a data issue for
  later, not a code issue.

  Let me also verify "Cure Simple Wounds" — suffix index 2 is "Simple Wounds",
  so "Cure Simple Wounds". That works.

● Bash(ruby -c app.rb)
  ⎿  Syntax OK

● Bash(git add app.rb && git commit -m "$(cat <<'EOF'
      Resolve prefixed/suffixed spell names to base spell on detail page…)
  ⎿  [claude/add-magic-tab-gx56h 6c0159f] Resolve prefixed/suffixed spell n
     ames to base spell on detail page
      1 file changed, 20 insertions(+)
● Bash(git push -u origin claude/add-magic-tab-gx56h)
  ⎿  To http://127.0.0.1:43037/git/dividetask/crimson-steel
        222c1e6..6c0159f  claude/add-magic-tab-gx56h -> claude/add-magic-ta
     b-gx56h
     … +2 lines (ctrl+o to expand)

● Done. The /spell/:name route now tries an exact match first, and if that
  fails, it searches all spells for a prefix/suffix variant match. So "Cure
  Lesser Wounds" resolves to the "Cure" spell (tier 1), "Lesser Ward" resolves
  to "Ward" (tier 1), "Cure Simple Wounds" to "Cure" (tier 2), etc.

  One thing to note: Stumpy's sheet has "Standard Ward" but Ward's prefix array
  uses "Simple" for tier 2, not "Standard" — so that one won't match. Either the
   character data or the Ward prefix array may need a tweak. Same thing to watch
   for with any other mismatches between the character sheet names and the
  compendium prefix/suffix arrays.

❯ Here is the spell information. Let's change the name of the spell Augury to   
  Commune                                                                       
  Note (M) means it is a main action, (B) means it is a bonus action, and (F)   
  means it is a free action                                                     
                                                                                
  Tier 2 Spells                                                                 
                                                                                
  Biting Words                                                                  
  (M) (conc), close, SMotive reduces                                            
  [enchantment, lang dependent]                                                 
  Perform                                                                       
  You can make verbal assaults on targets within range dealing emotional        
  damage. This is treated as two handed weapon attacks using your charisma      
  instead of strength.                                                          
                                                                                
  Ears of the City                                                              
  (B), touch, 1 round                                                           
  Arcane, Perform                                                               
  The target of this spell sees and hears a stream of past scenes and pieces of 
   conversations from lower tier creatures within the building the caster       
  occupies maximum 100 feet. The target gains the benefit of a ‘gather          
  information’ check in a single round rather than hours using the casters      
  spell check instead of persuasion.                                            
                                                                                
  Silent Image                                                                  
  (M) (conc), long, Int discerns                                                
  Arcane, Heal, Perform, Trickery                                               
  This spell creates a visual figment that cannot extend beyond 4+ranks 10-ft.  
  cubes.This illusion can be of an object, creature, or force, as visualized by 
   you. The illusion does not create sound, smell, texture, or temperature. You 
   can move the image within the limits of the size of the effect. All          
  creatures noticing the illusion gain a save.                                  
                                                                                
  Timely Inspiration                                                            
  (B), close                                                                    
  Perform                                                                       
  Boost an ally attack or skill check                                           
                                                                                
                                                                                
                                                                                
  Locate Object                                                                 
  (M) 1000 feet + 100 feet per rank                                             
  Object must have previously been seen up close, or this can be used to search 
   for any item of the kind                                                     
                                                                                
  Magic Weapon                                                                  
  (M) touch                                                                     
  Increases the enchantment bonus on a a single weapon by +1 for 1 round per    
  rank.                                                                         
                                                                                
  Augury                                                                        
  (M) 1 minutes, touch                                                          
  Commune with your god and learn if an action will be good or bad for them.    
                                                                                
                                                                                
  Hold Person                                                                   
  (M), close, Wis Save                                                          
  Paralyzes a single creature. They gain a wisdom save each round to negate the 
   effect.                                                                      
                                                                                
  Blindness/Deafness                                                            
  (M), close, Con Save                                                          
  Permanently blinds or deafens a single target.                                
                                                                                
  Admonishing Ray                                                               
  (M), close                                                                    
  Fires 2 rays dealing non lethal dmg.                                          
                                                                                
  Silence                                                                       
  (M), long                                                                     
  No sound can pass between a 20’ radius sphere. This prevents spell casting    
  with verbal components.                                                       
                                                                                
  Greater Detect Magic                                                          
  (M), 60 feet                                                                  
  As detect magic, but learn more information including caster signature.       
                                                                                
                                                                                
  Spiritual Weapon                                                              
  (M), close                                                                    
  Conjures a floating +2 magical weapon under your control. This weapon attacks 
   your enemies using the dice you spent summoning it.                          
                                                                                
  Protection from Poison                                                        
  (M), touch, 1 hour                                                            
  Neutralize a single non magical poison affecting a target. For the duration   
  all poison taken is halved.                                                   
                                                                                
  Calm Emotions                                                                 
  (M), medium, Will Save                                                        
  This spell calms agitated creatures. Creatures cannot take violent actions.   
  Any aggressive action against affected targets breaks the spell               
                                                                                
                                                                                
                                                                                
                                                                                
                                                                                
  Tier 1 Spells                                                                 
                                                                                
  Healing Word                                                                  
  (B), close, Healing and Performance                                           
  Reduce damage taken by target by success count. Requires a concentration      
  check if used on self.                                                        
                                                                                
  Lesser Ward                                                                   
  (M) touch, Healing and Performance                                            
  Grants 5 temporary hit points and reduces bleeding by 10. Can save a dying    
  creature if cast within 1 round of being downed.                              
                                                                                
  Command                                                                       
  Enchantment, (M), close, Wis Save, Healing and Performance                    
  You can give the target a simple command: Approach, Drop, Fall, Flee, or      
  Halt, This is language dependent.                                             
                                                                                
  Vicious Mockery                                                               
  [enchantment, lang dependent]                                                 
  (M) (conc), close, wis negates                                                
  Hiders the next attack or spell check made by the target, penalizing their    
  roll by 1. It also deals 3 emotional damage for each critical rolled. Save    
  does not negate damage.                                                       
                                                                                
  Vacuous Vessel                                                                
  [enchantment]                                                                 
  (B), touch, 1 r/rank, wis negates, Arcana and Performance                     
  This spell makes a single bag, chest, sack, or other container look and feel  
  empty. It cannot be larger than 1 cubic foot per rank. Anyone examining it    
  gets a wisdom save to resist this enchantment.                                
                                                                                
  Minor Disguise                                                                
  (M), self, 10 m/rank, int discerns, Arcana and Performance                    
  You can make minor changes to your appearance. The spell does not change the  
  actual structure of either your features or body. It can add color to hair,   
  paint wrinkles upon your face, give you a scar, or darken your teeth. This    
  spell removes the need for a disguise kit.                                    
                                                                                
                                                                                
                                                                                
  Shield of Faith                                                               
  (B) (conc), close, Healing                                                    
  Conjures a floating +1 magical shield under your control that floats around   
  target ally within range. Can be redirected to a different ally as a move     
  action.                                                                       
                                                                                
  Divine Favor                                                                  
  (F), personal, Healing                                                        
  Your weapon gains 4d radiant damage until end of turn. This can stack with    
  existing bonus damage from the weapon’s magical properties.                   
                                                                                
  Liberating Comand                                                             
  (B), close, Healing, Arcana, and Performance                                  
  Target can make an escape artist check as a free action assisted by your      
  spell check. Target spends no dice on their check.                            
                                                                                
  Standard Surgery                                                              
  1 hour casting time, touch, Healing and Performance                           
  Target helpless or willing creature immediatly loses all temporary hitpoints  
  and takes an amount of moderate damage equal to double it’s major damage. Any 
   attempt to prevent this damage causes the spell to fail. At the end of       
  casting a spell check is rolled and each success cures 1 point of major       
  damage. This spell causes ten points of magic saturation per major point      
  cured, with a minimum of 5 points of magical saturation per point cured.      
                                                                                
  Hideous Laughter                                                              
  (M), close, wis negates                                                       
  Target creature falls prone in gales of laughter. They can spend full round   
  actions to gain additional saves.                                             
                                                                                
  Illusion of Calm                                                              
  (M) (conc), int discerns                                                      
  Create an illusion of yourself that hides your real actions. You can control  
  the apparent actions of your illusion but it must remain exactly where you    
  are. Can be used as a reaction in combat to evade attacks.                    
                                                                                
  Speak with Plants                                                             
  At will, (M), close                                                           
  Surrounding vegetation gains temporary sentience and can recall the events of 
   the last 24 hours. They still retain any other limitations such as lack of   
  sight, but can remember touch, temperature, and the feeling of light As       
  sentient plants they can make small movements of their leaves and branches    
  but are not compelled to.                                                     
                                                                                
  Auditory Hallucination                                                        
  (M) (conc), long, wis discerns, Enchantment                                   
  Targets will hear any sound you can imagine. The sounds the creature hears    
  will be based upon their knowledge not yours such as the sound of their       
  chieftan’s voice. All targets hear the same hallucination.                    
                                                                                
  Entangle                                                                      
  (M), long, 1 m/rank, str negates                                              
  Plant life grows and animates creating difficult terrain in a 40’ spread.     
  Spent dice are used each round on your turn to make athletics checks against  
  targets in effect.                                                            
                                                                                
                                                                                
                                                                                
                                                                                
  Tier 0 Spells                                                                 
                                                                                
  Fire Bolt                                                                     
  (M) (conc), close                                                             
  Make a ranged attack that does fire damage to the target. You must spend at   
  least 4 dice each turn.                                                       
                                                                                
  Message                                                                       
  (M), medium, 10min/rank                                                       
  You can whisper messages and hear whispered replies while targets are within  
  range                                                                         
                                                                                
  Silent Portal                                                                 
  (M), close                                                                    
  Target door or window makes no sound when opened or closed. This does not     
  prevent other sounds such as objects falling from the door frame.             
                                                                                
                                                                                
                                                                                
  Stabilize                                                                     
  (M) (conc), close, Healing and Performance                                    
  Reduce bleeding by 3 for each success                                         
                                                                                
  Magic Vestments                                                               
  (B) close , Healing and Performance                                           
  Increase target’s damage reduction and damage resilience by 3 for 1 round     
                                                                                
  Sacred Flame                                                                  
  (M) (conc), close, Healing                                                    
  Make a ranged attack that does radiant damage to the target                   
                                                                                
  Light                                                                         
  (M) touch , Healing, Arcana, and Performance                                  
  Target object, or point on the object, glows shedding light similar to a      
  torch.                                                                        
                                                                                
  Daze                                                                          
  Enchantment, (M), 1 round, wis negates, Arcana and Performance                
  Cloud the mind of a creature of a lower tier than you causing them to skip    
  their turn. They still refill their combat pool. Once affected they are       
  immune to this spell for one minute.                                          
                                                                                
  Ghost Sound                                                                   
  (M) (conc), close, int discerns, Arcana and Performance                       
  You can create various real sounds within range. You can create as much       
  volume as 1 human per magic skill rank. This can be virtually any sound you   
  can imagine but is limited by your own knowledge.                             
                                                                                
  Resistance                                                                    
  (M), 1m/rank , Healing, Arcana and Performance                                
  Grants +1 enhancement bonus to saving throws.                                 
                                                                                
                                                                                
   Sift                                                                         
  (M) (conc), close, Arcana and Performance                                     
  Instantly search a 10’ cubic area                                             
                                                                                
  Grasp                                                                         
  (B) (conc), close, Performance                                                
  Boost target’s climb check. This can be cast after the climb check has been   
  rolled.                                                                       
                                                                                
  Friends (Spell Like)                                                          
  (M) (conc), close, wis discerns, Arcana and Performance                       
  All allies gain a +1 bonus to all charisma based skill checks against anyone  
  failing their save. Identifying the spell automatically counts as making      
  their save.                                                                   
                                                                                
  Flare                                                                         
  (M) (conc), close, con negates, , Healing, Arcana and Performance             
  Creates a burst of light which can be used to dazzle a creature penalizing    
  their attacks and perception by 1.                                            
                                                                                
  Detect Magic                                                                  
  (M) (conc), Healing, Arcana, and Performance                                  
  Detect magical auras within 60 feet. It takes 3 rounds to pinpoint and        
  examine the aura. There are many ways to fool this spell.                     

● This is a big update. Let me parse all the spell data and add everything.

● I'll add all the spells after the existing Spiritual Weapon entry. Here's my
  school assignment plan:

  School: Pneumancy
  Spells: Stabilize, Healing Word, Standard Surgery, Protection from Poison,
    Blindness/Deafness
  ────────────────────────────────────────
  School: Resonance
  Spells: Fire Bolt, Sacred Flame, Magic Vestments, Light, Ghost Sound, Silent
    Portal, Flare, Minor Disguise, Shield of Faith, Divine Favor, Illusion of
    Calm, Silent Image, Admonishing Ray
  ────────────────────────────────────────
  School: Enchantment
  Spells: Daze, Friends, Vicious Mockery, Vacuous Vessel, Command, Hideous
    Laughter, Auditory Hallucination, Biting Words, Hold Person, Calm Emotions
  ────────────────────────────────────────
  School: Augury
  Spells: Detect Magic, Sift, Speak with Plants, Ears of the City, Locate
  Object,
    Commune, Greater Detect Magic
  ────────────────────────────────────────
  School: Convergence
  Spells: Entangle
  ────────────────────────────────────────
  School: Transmutation
  Spells: Grasp, Magic Weapon
  ────────────────────────────────────────
  School: Universal
  Spells: Message, Resistance, Liberating Command, Timely Inspiration

● Update(/home/user/crimson-steel/data/compendium.json)
  ⎿  Added 44 lines, removed 1 line
      19      "Disguise Other": {"tier": 2, "save": "will", "school": "re
          sonance", "items": ["potion", "scroll", "oil", "wand"], "range"
          : 1, "duration": "rank*100", "casting_time": 0.5, "skill": ["ar
          cana", "perform_"], "properties": [], "effect_hash": {"disguise
          ": {"enhancement": 1}}, "description": "You make the target cre
          ature – including clothing, armor, weapons, and equipment – loo
          k different. They can seem 1 foot shorter or taller, thin, fat,
           or in between. You cannot change your creature type (although 
          you can appear as another subtype). Otherwise, the extent of th
          e apparent change is up to you. You could add or obscure a mino
          r feature or look like an entirely different person or gender."
          },
      20      "Create Pit": {"tier": 2, "save": "reflex", "school": "conv
          ergence", "items": ["scroll", "wand"], "range": 2, "duration": 
          "rank", "casting_time": 0.5, "skill": ["arcana"], "properties":
           [], "effect_hash": {}, "description": "You create a 10-foot-by
          -10-foot extra-dimensional hole with a depth of 10 feet per two
           caster ranks (maximum 30 feet). You must create the pit on a h
          orizontal surface of sufficient size. Since it extends into ano
          ther dimension, the pit has no weight and does not otherwise di
          splace the original underlying material. You can create the pit
           in the deck of a ship as easily as in a dungeon floor or the g
          round of a forest. Any creature standing in the area where you 
          first conjured the pit must make a Reflex saving throw to jump 
          to safety in the nearest open space. In addition, the edges of 
          the pit are sloped, and any creature ending its turn on a squar
          e adjacent to the pit must make a Reflex saving throw with a +1
           bonus to avoid falling into it. Creatures subjected to an effe
          ct intended to push them into the pit (such as bull rush) do no
          t get a saving throw to avoid falling in if they are affected b
          y the pushing effect. Creatures who fall into the pit take fall
          ing damage as normal. The pit’s coarse stone walls increase the
           Athletic check difficulty by 2. When the duration of the spell
           ends, creatures within the hole rise up with the bottom of the
           pit until they are standing on the surface over the course of 
          a single round."},
      21      "Silence": {"tier": 2, "save": "will", "school": "resonance
          ", "items": ["scroll", "wand"], "range": 3, "duration": "rank",
           "casting_time": 0.5, "skill": ["healing", "perform_"], "proper
          ties": [], "effect_hash": {}, "description": "Upon the casting 
          of this spell, complete silence prevails in the affected area. 
          All sound is stopped: Conversation is impossible, spells with v
          erbal components cannot be cast, and no noise whatsoever issues
           from, enters, or passes through the area. The spell can be cas
          t on a point in space, but the effect is stationary unless cast
           on a mobile object. The spell can be centered on a creature, a
          nd the effect then radiates from the creature and moves as it m
          oves. An unwilling creature can attempt a Will save to negate t
          he spell and can use Spell Resistance, if any. Items in a creat
          ure’s possession or magic items that emit sound receive the ben
          efits of saves and Spell Resistance, but unattended objects and
           points in space do not. Creatures in an area of a silence spel
          l are immune to sonic or language-based attacks, spells, and ef
          fects."},
      22 -    "Spiritual Weapon": {"tier": 2, "save": 0, "school": "reson
         -ance", "items": ["scroll", "wand"], "range": 0, "duration": "ra
         -nk", "casting_time": 0.5, "skill": ["healing"], "properties": [
         -], "effect_hash": {}, "description": "A weapon made of force ap
         -pears and attacks foes at a distance, as you direct it, dealing
         - force damage. The weapon takes the shape of a weapon favored b
         -y your deity or a weapon with some spiritual significance or sy
         -mbolism to you and has the same properties as a real weapon of 
         -its form. It strikes the opponent you designate, starting with 
         -one attack in the round the spell is cast and continuing each r
         -ound thereafter on your turn. It uses the casting bonus and num
         -ber of dice used to cast the spell for it's attacks.  As a forc
         -e effect, it can strike incorporeal creatures without the reduc
         -tion in damage associated with incorporeality. The weapon alway
         -s strikes from your direction. If the weapon goes beyond the sp
         -ell range, if it goes out of your sight, or if you are not dire
         -cting it, the weapon returns to you and hovers. Each round afte
         -r the first, you can use a main action to redirect the weapon t
         -o a new target. If you do not, the weapon continues to attack t
         -he previous round’s target. The weapon gains one attack per rou
         -nd. Even if the spiritual weapon is a ranged weapon, use the sp
         -ell’s range, not the weapon’s normal range, and switching targe
         -ts still is a main action."}},                                 
      22 +    "Spiritual Weapon": {"tier": 2, "save": 0, "school": "reson
         +ance", "items": ["scroll", "wand"], "range": 0, "duration": "ra
         +nk", "casting_time": 0.5, "skill": ["healing"], "properties": [
         +], "effect_hash": {}, "description": "A weapon made of force ap
         +pears and attacks foes at a distance, as you direct it, dealing
         + force damage. The weapon takes the shape of a weapon favored b
         +y your deity or a weapon with some spiritual significance or sy
         +mbolism to you and has the same properties as a real weapon of 
         +its form. It strikes the opponent you designate, starting with 
         +one attack in the round the spell is cast and continuing each r
         +ound thereafter on your turn. It uses the casting bonus and num
         +ber of dice used to cast the spell for it’s attacks.  As a forc
         +e effect, it can strike incorporeal creatures without the reduc
         +tion in damage associated with incorporeality. The weapon alway
         +s strikes from your direction. If the weapon goes beyond the sp
         +ell range, if it goes out of your sight, or if you are not dire
         +cting it, the weapon returns to you and hovers. Each round afte
         +r the first, you can use a main action to redirect the weapon t
         +o a new target. If you do not, the weapon continues to attack t
         +he previous round’s target. The weapon gains one attack per rou
         +nd. Even if the spiritual weapon is a ranged weapon, use the sp
         +ell’s range, not the weapon’s normal range, and switching targe
         +ts still is a main action."},                                  
      23 +    "Fire Bolt": {"tier": 0, "save": 0, "school": "resonance", 
         +"items": [], "range": 2, "duration": "concentration", "casting_
         +time": 1, "skill": ["arcana"], "properties": ["concentration"],
         + "effect_hash": {}, "description": "Make a ranged attack that d
         +oes fire damage to the target. You must spend at least 4 dice e
         +ach turn."},                                                   
      24 +    "Message": {"tier": 0, "save": 0, "school": "universal", "i
         +tems": [], "range": 3, "duration": "rank*100", "casting_time": 
         +1, "skill": ["arcana"], "properties": [], "effect_hash": {}, "d
         +escription": "You can whisper messages and hear whispered repli
         +es while targets are within range."},                          
      25 +    "Silent Portal": {"tier": 0, "save": 0, "school": "resonanc
         +e", "items": [], "range": 2, "duration": "instant", "casting_ti
         +me": 1, "skill": ["arcana"], "properties": [], "effect_hash": {
         +}, "description": "Target door or window makes no sound when op
         +ened or closed. This does not prevent other sounds such as obje
         +cts falling from the door frame."},                            
      26 +    "Stabilize": {"tier": 0, "save": 0, "school": "pneumancy", 
         +"items": [], "range": 2, "duration": "concentration", "casting_
         +time": 1, "skill": ["healing", "perform_"], "properties": ["con
         +centration"], "effect_hash": {}, "description": "Reduce bleedin
         +g by 3 for each success."},                                    
      27 +    "Magic Vestments": {"tier": 0, "save": 0, "school": "resona
         +nce", "items": [], "range": 2, "duration": "1 round", "casting_
         +time": 0.5, "skill": ["healing", "perform_"], "properties": [],
         + "effect_hash": {}, "description": "Increase target’s damage re
         +duction and damage resilience by 3 for 1 round."},             
      28 +    "Sacred Flame": {"tier": 0, "save": 0, "school": "resonance
         +", "items": [], "range": 2, "duration": "concentration", "casti
         +ng_time": 1, "skill": ["healing"], "properties": ["concentratio
         +n"], "effect_hash": {}, "description": "Make a ranged attack th
         +at does radiant damage to the target."},                       
      29 +    "Light": {"tier": 0, "save": 0, "school": "resonance", "ite
         +ms": [], "range": 1, "duration": "rank*100", "casting_time": 1,
         + "skill": ["healing", "arcana", "perform_"], "properties": [], 
         +"effect_hash": {}, "description": "Target object, or point on t
         +he object, glows shedding light similar to a torch."},         
      30 +    "Daze": {"tier": 0, "save": "wis", "school": "enchantment",
         + "items": [], "range": 2, "duration": "1 round", "casting_time"
         +: 1, "skill": ["arcana", "perform_"], "properties": [], "effect
         +_hash": {}, "description": "Cloud the mind of a creature of a l
         +ower tier than you causing them to skip their turn. They still 
         +refill their combat pool. Once affected they are immune to this
         + spell for one minute."},                                      
      31 +    "Ghost Sound": {"tier": 0, "save": "int", "school": "resona
         +nce", "items": [], "range": 2, "duration": "concentration", "ca
         +sting_time": 1, "skill": ["arcana", "perform_"], "properties": 
         +["concentration"], "effect_hash": {}, "description": "You can c
         +reate various real sounds within range. You can create as much 
         +volume as 1 human per magic skill rank. This can be virtually a
         +ny sound you can imagine but is limited by your own knowledge."
         +},                                                             
      32 +    "Resistance": {"tier": 0, "save": 0, "school": "universal",
         + "items": [], "range": 1, "duration": "rank*10", "casting_time"
         +: 1, "skill": ["healing", "arcana", "perform_"], "properties": 
         +[], "effect_hash": {}, "description": "Grants +1 enhancement bo
         +nus to saving throws."},                                       
      33 +    "Sift": {"tier": 0, "save": 0, "school": "augury", "items":
         + [], "range": 2, "duration": "concentration", "casting_time": 1
         +, "skill": ["arcana", "perform_"], "properties": ["concentratio
         +n"], "effect_hash": {}, "description": "Instantly search a 10’ 
         +cubic area."},                                                 
      34 +    "Grasp": {"tier": 0, "save": 0, "school": "transmutation", 
         +"items": [], "range": 2, "duration": "concentration", "casting_
         +time": 0.5, "skill": ["perform_"], "properties": ["concentratio
         +n"], "effect_hash": {}, "description": "Boost target’s climb ch
         +eck. This can be cast after the climb check has been rolled."},
      35 +    "Friends": {"tier": 0, "save": "wis", "school": "enchantmen
         +t", "items": [], "range": 2, "duration": "concentration", "cast
         +ing_time": 1, "skill": ["arcana", "perform_"], "properties": ["
         +concentration"], "effect_hash": {}, "description": "All allies 
         +gain a +1 bonus to all charisma based skill checks against anyo
         +ne failing their save. Identifying the spell automatically coun
         +ts as making their save."},                                    
      36 +    "Flare": {"tier": 0, "save": "con", "school": "resonance", 
         +"items": [], "range": 2, "duration": "concentration", "casting_
         +time": 1, "skill": ["healing", "arcana", "perform_"], "properti
         +es": ["concentration"], "effect_hash": {}, "description": "Crea
         +tes a burst of light which can be used to dazzle a creature pen
         +alizing their attacks and perception by 1."},                  
      37 +    "Detect Magic": {"tier": 0, "save": 0, "school": "augury", 
         +"items": [], "range": 2, "duration": "concentration", "casting_
         +time": 1, "skill": ["healing", "arcana", "perform_"], "properti
         +es": ["concentration"], "effect_hash": {}, "description": "Dete
         +ct magical auras within 60 feet. It takes 3 rounds to pinpoint 
         +and examine the aura. There are many ways to fool this spell."}
         +,                                                              
      38 +    "Healing Word": {"tier": 1, "save": 0, "school": "pneumancy
         +", "items": [], "range": 2, "duration": "instant", "casting_tim
         +e": 0.5, "skill": ["healing", "perform_"], "properties": [], "e
         +ffect_hash": {}, "description": "Reduce damage taken by target 
         +by success count. Requires a concentration check if used on sel
         +f."},                                                          
      39 +    "Command": {"tier": 1, "save": "wis", "school": "enchantmen
         +t", "items": [], "range": 2, "duration": "1 round", "casting_ti
         +me": 1, "skill": ["healing", "perform_"], "properties": ["langu
         +age_dependent"], "effect_hash": {}, "description": "You can giv
         +e the target a simple command: Approach, Drop, Fall, Flee, or H
         +alt. This is language dependent."},                            
      40 +    "Vicious Mockery": {"tier": 1, "save": "wis", "school": "en
         +chantment", "items": [], "range": 2, "duration": "concentration
         +", "casting_time": 1, "skill": ["perform_"], "properties": ["co
         +ncentration", "language_dependent"], "effect_hash": {}, "descri
         +ption": "Hinders the next attack or spell check made by the tar
         +get, penalizing their roll by 1. It also deals 3 emotional dama
         +ge for each critical rolled. Save does not negate damage."},   
      41 +    "Vacuous Vessel": {"tier": 1, "save": "wis", "school": "enc
         +hantment", "items": [], "range": 1, "duration": "rank", "castin
         +g_time": 0.5, "skill": ["arcana", "perform_"], "properties": []
         +, "effect_hash": {}, "description": "This spell makes a single 
         +bag, chest, sack, or other container look and feel empty. It ca
         +nnot be larger than 1 cubic foot per rank. Anyone examining it 
         +gets a wisdom save to resist this enchantment."},              
      42 +    "Minor Disguise": {"tier": 1, "save": "int", "school": "res
         +onance", "items": [], "range": 0, "duration": "rank*100", "cast
         +ing_time": 1, "skill": ["arcana", "perform_"], "properties": []
         +, "effect_hash": {}, "description": "You can make minor changes
         + to your appearance. The spell does not change the actual struc
         +ture of either your features or body. It can add color to hair,
         + paint wrinkles upon your face, give you a scar, or darken your
         + teeth. This spell removes the need for a disguise kit."},     
      43 +    "Shield of Faith": {"tier": 1, "save": 0, "school": "resona
         +nce", "items": [], "range": 2, "duration": "concentration", "ca
         +sting_time": 0.5, "skill": ["healing"], "properties": ["concent
         +ration"], "effect_hash": {}, "description": "Conjures a floatin
         +g +1 magical shield under your control that floats around targe
         +t ally within range. Can be redirected to a different ally as a
         + move action."},                                               
      44 +    "Divine Favor": {"tier": 1, "save": 0, "school": "resonance
         +", "items": [], "range": 0, "duration": "end of turn", "casting
         +_time": 0, "skill": ["healing"], "properties": [], "effect_hash
         +": {}, "description": "Your weapon gains 4d radiant damage unti
         +l end of turn. This can stack with existing bonus damage from t
         +he weapon’s magical properties."},                             
      45 +    "Liberating Command": {"tier": 1, "save": 0, "school": "uni
         +versal", "items": [], "range": 2, "duration": "instant", "casti
         +ng_time": 0.5, "skill": ["healing", "arcana", "perform_"], "pro
         +perties": [], "effect_hash": {}, "description": "Target can mak
         +e an escape artist check as a free action assisted by your spel
         +l check. Target spends no dice on their check."},              
      46 +    "Standard Surgery": {"tier": 1, "save": 0, "school": "pneum
         +ancy", "items": [], "range": 1, "duration": "instant", "casting
         +_time": 3600, "skill": ["healing", "perform_"], "properties": [
         +], "effect_hash": {}, "description": "Target helpless or willin
         +g creature immediately loses all temporary hitpoints and takes 
         +an amount of moderate damage equal to double its major damage. 
         +Any attempt to prevent this damage causes the spell to fail. At
         + the end of casting a spell check is rolled and each success cu
         +res 1 point of major damage. This spell causes ten points of ma
         +gic toxicity per major point cured, with a minimum of 5 points 
         +of magic toxicity per point cured."},                          
      47 +    "Hideous Laughter": {"tier": 1, "save": "wis", "school": "e
         +nchantment", "items": [], "range": 2, "duration": "rank", "cast
         +ing_time": 1, "skill": ["arcana"], "properties": [], "effect_ha
         +sh": {}, "description": "Target creature falls prone in gales o
         +f laughter. They can spend full round actions to gain additiona
         +l saves."},                                                    
      48 +    "Illusion of Calm": {"tier": 1, "save": "int", "school": "r
         +esonance", "items": [], "range": 0, "duration": "concentration"
         +, "casting_time": 1, "skill": ["arcana"], "properties": ["conce
         +ntration"], "effect_hash": {}, "description": "Create an illusi
         +on of yourself that hides your real actions. You can control th
         +e apparent actions of your illusion but it must remain exactly 
         +where you are. Can be used as a reaction in combat to evade att
         +acks."},                                                       
      49 +    "Speak with Plants": {"tier": 1, "save": 0, "school": "augu
         +ry", "items": [], "range": 2, "duration": "instant", "casting_t
         +ime": 1, "skill": ["nature"], "properties": [], "effect_hash": 
         +{}, "description": "Surrounding vegetation gains temporary sent
         +ience and can recall the events of the last 24 hours. They stil
         +l retain any other limitations such as lack of sight, but can r
         +emember touch, temperature, and the feeling of light. As sentie
         +nt plants they can make small movements of their leaves and bra
         +nches but are not compelled to."},                             
      50 +    "Auditory Hallucination": {"tier": 1, "save": "wis", "schoo
         +l": "enchantment", "items": [], "range": 4, "duration": "concen
         +tration", "casting_time": 1, "skill": ["arcana", "perform_"], "
         +properties": ["concentration"], "effect_hash": {}, "description
         +": "Targets will hear any sound you can imagine. The sounds the
         + creature hears will be based upon their knowledge not yours su
         +ch as the sound of their chieftain’s voice. All targets hear th
         +e same hallucination."},                                       
      51 +    "Entangle": {"tier": 1, "save": "str", "school": "convergen
         +ce", "items": [], "range": 4, "duration": "rank*10", "casting_t
         +ime": 1, "skill": ["nature"], "properties": [], "effect_hash": 
         +{}, "description": "Plant life grows and animates creating diff
         +icult terrain in a 40’ spread. Spent dice are used each round o
         +n your turn to make athletics checks against targets in effect.
         +"},                                                            
      52 +    "Biting Words": {"tier": 2, "save": "wis", "school": "encha
         +ntment", "items": [], "range": 2, "duration": "concentration", 
         +"casting_time": 1, "skill": ["perform_"], "properties": ["conce
         +ntration", "language_dependent"], "effect_hash": {}, "descripti
         +on": "You can make verbal assaults on targets within range deal
         +ing emotional damage. This is treated as two handed weapon atta
         +cks using your charisma instead of strength."},                
      53 +    "Ears of the City": {"tier": 2, "save": 0, "school": "augur
         +y", "items": [], "range": 1, "duration": "1 round", "casting_ti
         +me": 0.5, "skill": ["arcana", "perform_"], "properties": [], "e
         +ffect_hash": {}, "description": "The target of this spell sees 
         +and hears a stream of past scenes and pieces of conversations f
         +rom lower tier creatures within the building the caster occupie
         +s maximum 100 feet. The target gains the benefit of a ‘gather i
         +nformation’ check in a single round rather than hours using the
         + casters spell check instead of persuasion."},                 
      54 +    "Silent Image": {"tier": 2, "save": "int", "school": "reson
         +ance", "items": [], "range": 4, "duration": "concentration", "c
         +asting_time": 1, "skill": ["arcana", "healing", "perform_"], "p
         +roperties": ["concentration"], "effect_hash": {}, "description"
         +: "This spell creates a visual figment that cannot extend beyon
         +d 4+ranks 10-ft. cubes. This illusion can be of an object, crea
         +ture, or force, as visualized by you. The illusion does not cre
         +ate sound, smell, texture, or temperature. You can move the ima
         +ge within the limits of the size of the effect. All creatures n
         +oticing the illusion gain a save."},                           
      55 +    "Timely Inspiration": {"tier": 2, "save": 0, "school": "uni
         +versal", "items": [], "range": 2, "duration": "instant", "casti
         +ng_time": 0.5, "skill": ["perform_"], "properties": [], "effect
         +_hash": {}, "description": "Boost an ally attack or skill check
         +."},                                                           
      56 +    "Locate Object": {"tier": 2, "save": 0, "school": "augury",
         + "items": [], "range": 4, "duration": "rank*10", "casting_time"
         +: 1, "skill": ["healing", "arcana"], "properties": ["concentrat
         +ion"], "effect_hash": {}, "description": "Object must have prev
         +iously been seen up close, or this can be used to search for an
         +y item of the kind. Range is 1000 feet + 100 feet per rank."}, 
      57 +    "Magic Weapon": {"tier": 2, "save": 0, "school": "transmuta
         +tion", "items": [], "range": 1, "duration": "rank", "casting_ti
         +me": 1, "skill": ["healing", "arcana"], "properties": [], "effe
         +ct_hash": {}, "description": "Increases the enchantment bonus o
         +n a single weapon by +1 for 1 round per rank."},               
      58 +    "Commune": {"tier": 2, "save": 0, "school": "augury", "item
         +s": [], "range": 1, "duration": "instant", "casting_time": 60, 
         +"skill": ["healing"], "properties": [], "effect_hash": {}, "des
         +cription": "Commune with your god and learn if an action will b
         +e good or bad for them."},                                     
      59 +    "Hold Person": {"tier": 2, "save": "wis", "school": "enchan
         +tment", "items": [], "range": 2, "duration": "rank", "casting_t
         +ime": 1, "skill": ["healing", "arcana"], "properties": [], "eff
         +ect_hash": {}, "description": "Paralyzes a single creature. The
         +y gain a wisdom save each round to negate the effect."},       
      60 +    "Blindness/Deafness": {"tier": 2, "save": "con", "school": 
         +"pneumancy", "items": [], "range": 2, "duration": "permanent", 
         +"casting_time": 1, "skill": ["healing", "arcana"], "properties"
         +: [], "effect_hash": {}, "description": "Permanently blinds or 
         +deafens a single target."},                                    
      61 +    "Admonishing Ray": {"tier": 2, "save": 0, "school": "resona
         +nce", "items": [], "range": 2, "duration": "instant", "casting_
         +time": 1, "skill": ["arcana"], "properties": [], "effect_hash":
         + {}, "description": "Fires 2 rays dealing non lethal damage."},
      62 +    "Greater Detect Magic": {"tier": 2, "save": 0, "school": "a
         +ugury", "items": [], "range": 2, "duration": "concentration", "
         +casting_time": 1, "skill": ["healing", "arcana", "perform_"], "
         +properties": ["concentration"], "effect_hash": {}, "description
         +": "As detect magic, but learn more information including caste
         +r signature."},                                                
      63 +    "Protection from Poison": {"tier": 2, "save": 0, "school": 
         +"pneumancy", "items": [], "range": 1, "duration": "600", "casti
         +ng_time": 1, "skill": ["healing", "nature"], "properties": [], 
         +"effect_hash": {}, "description": "Neutralize a single non magi
         +cal poison affecting a target. For the duration all poison take
         +n is halved."},                                                
      64 +    "Calm Emotions": {"tier": 2, "save": "wis", "school": "ench
         +antment", "items": [], "range": 3, "duration": "concentration",
         + "casting_time": 1, "skill": ["healing", "perform_"], "properti
         +es": ["concentration"], "effect_hash": {}, "description": "This
         + spell calms agitated creatures. Creatures cannot take violent 
         +actions. Any aggressive action against affected targets breaks 
         +the spell."},                                                  
      65 +    "Mage Hand": {"tier": 0, "save": 0, "school": "convergence"
         +, "items": [], "range": 2, "duration": "concentration", "castin
         +g_time": 1, "skill": ["arcana"], "properties": ["concentration"
         +], "effect_hash": {}, "description": "You point your finger at 
         +an object and can lift it and move it at will from a distance. 
         +As a move action, you can propel the object as far as 15 feet i
         +n any direction, though the spell ends if the distance between 
         +you and the object ever exceeds the spell’s range."}},         
      66    "abilities": {
      67      "bardic_inspiration": "During your magical performance you 
          can use your performance to inspire your allies or distract you
          r enemies. This creates a pool of luck that can be spent by you
           or your team to reroll dice on any check your or they make. Ea
          ch point must be spent before the initial check is made, and ea
          ch point will allow a single reroll. Using this ability costs o
          ne point of mana and can only be used once per turn. This is a 
          main action that can be used as part of maintaining your perfor
          mance but only if that action is not used for any other purpose
           such as casting a spell. You gain one point of luck per succes
          s, and each point must be used before your next turn or it is l
          ost. Fumbling grants all failures to the DM to be used for the 
          enemy, or against the players.",
      68      "better_lucky_than_good": "You may spend 3 mana during any 
          round that you are unable to act such as the surprise round. Al
          l attacks against you, including spells, are made with half as 
          many dice with a minimum of 3 dice. Enemies are unconsciously a
          ware of this penalty and may instead choose to target your alli
          es instead or use 3 dice on the attack.",

● Bash(ruby -e "require 'json'; data =
      JSON.parse(File.read('data/compendium.json')); puts
      data['spells'].keys.length.to_s + ' spells'" )
  ⎿  57 spells

● Now fix the character data.

  Read 1 file (ctrl+o to expand)

● Update(/home/user/crimson-steel/data/characters.json)
  ⎿  Added 2 lines, removed 2 lines
      18      "feats": { "race": ["armor_training"]},
      19      "spells": [ 
      20        ["Stabilize", "Sacred Flame", "Magic Vestments"],
      21 -      ["Cure Lesser Wounds", "Healing Word", "Command", "Lesser
         - Ward", "Divine Favor", "Shield of Faith "],                   
      22 -      ["Magic Weapon", "Spiritual Weapon", "Hold Person", "Sile
         -nce", "Blindness/Deafness", "Augury", "Cure Simple Wounds", "St
         -andard Ward", "Locate Object", "Augury", "Protection from Poiso
         -n", "Standard Surgery"]]                                       
      21 +      ["Cure Lesser Wounds", "Healing Word", "Command", "Lesser
         + Ward", "Divine Favor", "Shield of Faith"],                    
      22 +      ["Magic Weapon", "Spiritual Weapon", "Hold Person", "Sile
         +nce", "Blindness/Deafness", "Commune", "Cure Simple Wounds", "S
         +imple Ward", "Locate Object", "Commune", "Protection from Poiso
         +n", "Standard Surgery"]]                                       
      23    },
      24    {
      25      "id": 2,

● Bash(ruby -e "require 'json'; JSON.parse(File.read('data/characters.json'))"
      && echo "characters.json valid")
  ⎿  characters.json valid

● Bash(git add data/compendium.json data/characters.json && git commit -m "$(cat
       <<'EOF'
      Add 42 spells to compendium, rename Augury spell to Commune…)
  ⎿  [claude/add-magic-tab-gx56h 3bf2986] Add 42 spells to compendium, rena
     me Augury spell to Commune
      2 files changed, 46 insertions(+), 3 deletions(-)

● Bash(git push -u origin claude/add-magic-tab-gx56h)
  ⎿  To http://127.0.0.1:33021/git/dividetask/crimson-steel
        6c0159f..3bf2986  claude/add-magic-tab-gx56h -> claude/add-magic-ta
     b-gx56h
     … +2 lines (ctrl+o to expand)

● Done. Here's a summary of everything:

  57 spells now in the compendium (15 existing + 42 new).

  Character data fixes for Stumpy:
  - "Augury" renamed to "Commune" (both instances)
  - "Standard Ward" changed to "Simple Ward" (matches Ward's tier 2 prefix)
  - "Shield of Faith " trailing space removed

  Casting time encoding: (M)=1, (B)=0.5, (F)=0, 1 minute=60, 1 hour=3600.
  Concentration spells have "concentration" in their properties array.

  A couple things to note:
  - Cottonballs' character data lists Vicious Mockery and Vacuous Vessel at tier
   0, but your spell descriptions put them at tier 1. You may want to adjust
  either the character data or the spell tiers.
  - Stumpy has "Commune" listed twice in tier 2 (carried over from the duplicate
   "Augury" entries). You may want to remove the duplicate.
  - I added Mage Hand (tier 0, convergence) since Lysander has it but it wasn't
  in your spell list.

❯ All spells should be automatically sorted by name                             

  Read 1 file (ctrl+o to expand)

● The spell list iterates @spells which is a hash — it comes out in insertion
  order. I'll sort it in the route.

  Read 1 file (ctrl+o to expand)

● Update(/home/user/crimson-steel/app.rb)
  ⎿  Added 1 line, removed 1 line
      357  
      358  get '/spells' do
      359    compendium = Compendium.new
      360 -  @spells = compendium.data["spells"]                         
      360 +  @spells = compendium.data["spells"].sort_by { |name, _| name
          +.downcase }.to_h                                              
      361    @spell_schools = compendium.data["spell_schools"] || ["unive
           rsal", "necromancy", "evocation", "illusion", "enchantment", "
           divination", "abjuration", "conjuration"]
      362    @range_labels = compendium.data["range"]
      363    @all_skills = @spells.values.flat_map { |s| s["skill"] || []
            }.uniq.sort

● Bash(ruby -c app.rb && git add app.rb && git commit -m "$(cat <<'EOF'
      Sort spell list alphabetically by name…)
  ⎿  Syntax OK
     [claude/add-magic-tab-gx56h 3d0e826] Sort spell list alphabetically by
      name
     … +6 lines (ctrl+o to expand)

● Done. The spell list is now sorted alphabetically by name (case-insensitive).

❯ Can we prevent people from going forward or back using the webbrowsers        
  navigation?                                                                   
  Read 1 file (ctrl+o to expand)

● Update(/home/user/crimson-steel/views/layout.erb)
  ⎿  Added 5 lines
      30    </div>
      31    <%= yield %>
      32  <script>
      33 +history.pushState(null, '', location.href);                    
      34 +window.addEventListener('popstate', function() {               
      35 +  history.pushState(null, '', location.href);                  
      36 +});                                                            
      37 +                                                               
      38  function toggleNote(btn) {
      39    var text = btn.previousElementSibling;
      40    if (text.classList.contains('collapsed')) {

● Bash(git add views/layout.erb && git commit -m "$(cat <<'EOF'
      Disable browser back/forward navigation…)
  ⎿  [claude/add-magic-tab-gx56h a006f3d] Disable browser back/forward navi
     gation
      1 file changed, 5 insertions(+)
     … +5 lines (ctrl+o to expand)

● Done. On every page load it pushes a history state, and if the user hits
  back/forward it immediately pushes again, keeping them on the current page.
  All navigation still works through the in-page links and menu.

❯ Great. Cast time should show main action, bonus action, free, X rounds, X     
  minutes, or X hours depending on how long it tasks to cast. We can assume     
  that it will always be multiples of  hours when it is greater then an hour,   
  or multiples of minutes when greater then a minute                            

  Read 1 file (ctrl+o to expand)

● I'll add a helper for formatting casting time, then use it in both the spell
  list and spell detail templates.

  Read 1 file (ctrl+o to expand)

● Update(/home/user/crimson-steel/helpers.rb)
  ⎿  Added 10 lines
       9      Rack::Utils.escape_html(text.to_s)
      10    end
      11  
      12 +  def format_casting_time(val)                                 
      13 +    v = val.to_f                                               
      14 +    return "Free" if v == 0                                    
      15 +    return "Bonus Action" if v == 0.5                          
      16 +    return "Main Action" if v == 1                             
      17 +    return "#{(v / 3600).to_i} hour#{'s' if v >= 7200}" if v >=
         + 3600                                                          
      18 +    return "#{(v / 60).to_i} minute#{'s' if v >= 120}" if v >= 
         +60                                                             
      19 +    return "#{v.to_i} round#{'s' if v > 1}"                    
      20 +  end                                                          
      21 +                                                               
      22    def resolve_spell_description(spell, idx, tier_val)
      23      spell["description"].gsub(/\{(\w+)\}/) do |match|
      24        var = $1

● Now update the spell list and spell detail templates to use the helper.

● Update(/home/user/crimson-steel/views/spell_list.erb)
  ⎿  Added 1 line, removed 1 line
      62          <td><%= spell["save"] == 0 ? "None" : spell["save"].to_
          s.capitalize %></td>
      63          <td><%= @range_labels[spell["range"].to_s] || spell["ra
          nge"] %></td>
      64          <td><%= spell["duration"].is_a?(Array) ? "varies" : spe
          ll["duration"] %></td>
      65 -        <td><%= spell["casting_time"] %></td>                  
      65 +        <td><%= format_casting_time(spell["casting_time"]) %></
         +td>                                                            
      66        </tr>
      67      <% end %>
      68    </table>

  Read 1 file (ctrl+o to expand)

● Update(/home/user/crimson-steel/views/spell_detail.erb)
  ⎿  Added 1 line, removed 1 line
      22      </div>
      23      <div class="spell-stat">
      24        <span class="label">Casting Time</span>
      25 -      <span class="value"><%= @spell["casting_time"] %></span> 
      25 +      <span class="value"><%= format_casting_time(@spell["casti
         +ng_time"]) %></span>                                           
      26      </div>
      27      <div class="spell-stat">
      28        <span class="label">Save</span>

● Bash(ruby -c helpers.rb && git add helpers.rb views/spell_list.erb
      views/spell_detail.erb && git commit -m "$(cat <<'EOF'
      Format casting time as human-readable label…)
  ⎿  Syntax OK
     [claude/add-magic-tab-gx56h 27aa70f] Format casting time as human-read
     able labels
     … +6 lines (ctrl+o to expand)

● Done. Casting time now displays as:

  ┌─────────┬──────────────────┐
  │  Value  │     Display      │
  ├─────────┼──────────────────┤
  │ 0       │ Free             │
  ├─────────┼──────────────────┤
  │ 0.5     │ Bonus Action     │
  ├─────────┼──────────────────┤
  │ 1       │ Main Action      │
  ├─────────┼──────────────────┤
  │ 2-59    │ X rounds         │
  ├─────────┼──────────────────┤
  │ 60-3599 │ X minute/minutes │
  ├─────────┼──────────────────┤
  │ 3600+   │ X hour/hours     │
  └─────────┴──────────────────┘

  So Standard Surgery shows "1 hour", Commune shows "1 minute", and most spells
  show "Main Action" or "Bonus Action".

● Session resumed
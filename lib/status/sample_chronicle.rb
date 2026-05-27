module Status
  # Sample Chronicle Entries for the Chronicle sub-view of the Status
  # page. Intentionally divorced from the live example Campaign in
  # chronicle_data.example.json so reviewers don't confuse the two.
  # The Status sub-view renders the same five Entries twice — once
  # under the DM viewer role, once under a player viewer (Bryn,
  # Creature id 2) — so the role differences are easy to compare.
  module SampleChronicle
    module_function

    def chronicle_examples
      hollow_glade = {
        id: 9001, entry_type: 'note', chapter: 1,
        notes_position: 1, scene_position: 1,
        title: 'Briefing — The Hollow Glade',
        public_description: "Three travelers vanished from the Hollow Glade trail this month. The ranger station marked the trees with white chalk where each disappearance happened — the chalk is gone now, but you can still feel where the bark was scraped. Local hunters refuse to cross the glade after dark and the lumber camp has stopped sending crews past the second bridge.\n\nThe rangers found two of the packs intact and untouched in clearings several leagues apart. The third pack has not been found; the traveler in question, a tinker from a coastal town to the south, was carrying a brass ledger he claimed had been promised to a man in the next valley. The ledger has not turned up either.\n\nA child from the nearby farm holding swears she saw a tall figure with no face walking among the trees the morning after the third disappearance. Adults dismiss the story. The party may want to talk to her before her parents decide otherwise.",
        dm_description: 'The vanishings line up with new-moon nights. The Lantern is hunting at the edge of the glade and dragging the bodies into the cliffs.',
        image: '/example_images/saltmere_lighthouse.svg',
        shared: true, hidden_from: [], owner_id: nil, active: true
      }
      dm_secret = {
        id: 9002, entry_type: 'note', chapter: 1,
        notes_position: 2, scene_position: 2,
        title: 'GM — Behind the Curtain',
        public_description: '',
        dm_description: "The Pale Lantern was not always pale. In life it was a keeper named Iren Halverlight, drowned in 4691 trying to reach a foundering ship he had inadvertently lured onto the rocks with a beacon he had been told to keep dark. The oath that binds him to the spire is the one he never finished — to confess to the harbormaster what had happened. Daven Korr already knows the story; the merchants' guild does not.\n\nPlot pivots:\n- If the party releases the Lantern by completing the oath on his behalf (a Diplomacy check vs Daven), the beacon goes out permanently and the coast stays vulnerable. Daven offers them the keeper's salary anyway.\n- If the party binds the Lantern to the new beacon stone (an Arcana check at the watchroom), the beacon relights and the haunting eases but the Lantern persists, only quieter.\n- If the party destroys the Lantern outright, the beacon lights and stays lit, but every keeper who tries to live in the spire from then on dies inside a month. This is a story consequence; the party will not learn of it until much later.\n\nDaven will not lie about the Lantern's identity if asked directly. He will not volunteer it.",
        image: nil, shared: false, hidden_from: [], owner_id: nil, active: false
      }
      spiral_stair = {
        id: 9003, entry_type: 'note', chapter: 3,
        notes_position: 3, scene_position: 3,
        title: 'The Spiral Stair',
        public_description: "The lighthouse spire has 247 iron steps and not one of them is level. Halfway up, the wall is scored with seven long parallel grooves at shoulder height. Cold air pours from above, even at midday.\n\nTana counted the steps twice on the way up and got a different total each time — 247 the first count, 251 the second. She blamed the wind. Bryn counted them on the way back down and got 247 twice in a row, but he insisted the landings had moved between counts. Selka refused to count and stared at the wall instead.\n\nThe grooves run for about thirty paces along the inner wall, then stop in clean iron, as if something had hit the metal and decided to leave through it instead of around it. The air on the upper side of the grooves is roughly a fingerwidth colder than the air on the lower side. You can feel the difference if you sit very still with one hand above the line and one below.\n\nThe keeper's logbook, recovered at the watchroom landing on Day Four, records two earlier incidents in the same place. Both entries end mid-sentence. Both have the same word scratched into the margin in a different hand than the rest: \"wait\".\n\nThe party did not wait.",
        dm_description: "The grooves are claw marks, but not from any beast the players will recognize. Strictly speaking, they are not claw marks at all — they are a record of motion preserved in iron, like a stonemason's mark of an animal that wasn't yet born. The Pale Lantern leaves them whenever it descends; the temperature differential is its trail.\n\nIf the party rests on the steps between the grooves and the watchroom, run the long-rest table with one column shifted toward Cold instead of Quiet.",
        image: nil, shared: true, hidden_from: [], owner_id: nil, active: true
      }
      pale_lantern = {
        id: 9004, entry_type: 'creature', chapter: 4,
        notes_position: 4, scene_position: 4,
        title: '',
        public_description: 'A figure of cold blue light glimpsed at the top of the spire. Where it walks the lamps gutter and the iron rusts. It does not speak.',
        dm_description: '',
        image: '/example_images/pale_lantern.svg',
        shared: true, hidden_from: [], owner_id: nil, active: true,
        creature_id: 2002, creature_token: nil, tier: 4
      }
      bryn_journal = {
        id: 9005, entry_type: 'note', chapter: 1,
        notes_position: 5, scene_position: 5,
        title: "Bryn's Field Journal",
        public_description: "Day Seven on the coast. The wind off the water tastes like iron and old kelp. I have started counting my own pulses while I sleep — Tana's idea. She says it keeps the cold from getting inside you. I cannot tell if she is right or if I am just sleeping badly.\n\nWisp has been quieter than usual. She watched the watchroom door for two hours last night without speaking, then asked me whether I trust the harbormaster. I told her the truth, which is that I do not, but I trust the work. She nodded and went back to looking at the door.\n\nSelka's water-skin froze on the stair on Day Four. She has not let any of us touch it since. I think she is keeping it as a reminder, but a reminder of what I cannot say.\n\nTomorrow we climb again. I have written this in case I do not come back, and I have left it in the dry-box at the foot of the stair. If you are reading it and I am not present, tell Daven I asked after his daughter.",
        dm_description: '',
        image: nil, shared: true, hidden_from: [], owner_id: 2, active: false
      }

      [
        { label: 'Shared note (long public)',         entry: hollow_glade },
        { label: 'Private GM note (long DM only)',    entry: dm_secret },
        { label: 'Shared note (long public + GM)',    entry: spiral_stair },
        { label: 'Creature reference',                entry: pale_lantern },
        { label: "Player-owned note (Bryn, shared)",  entry: bryn_journal }
      ]
    end
  end
end

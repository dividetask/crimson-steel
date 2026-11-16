package com.dividetask.crimsonsteel.data

import com.dividetask.crimsonsteel.dice.ActionCategory
import com.dividetask.crimsonsteel.dice.CombatRules
import com.dividetask.crimsonsteel.dice.DiceRules
import com.dividetask.crimsonsteel.dice.RollInputs
import com.dividetask.crimsonsteel.dice.RollRequest

/*
 * Offline placeholder data. Every screen reads from here until the app can
 * fetch the same information from the Crimson Steel server.
 */

enum class Attribute(val key: String, val label: String, val abbr: String) {
    STR("str", "Strength", "STR"),
    DEX("dex", "Dexterity", "DEX"),
    CON("con", "Constitution", "CON"),
    INT("int", "Intelligence", "INT"),
    WIS("wis", "Wisdom", "WIS"),
    CHA("cha", "Charisma", "CHA"),
}

data class Skill(val key: String, val name: String, val attribute: Attribute, val ranks: Int)

data class Ability(val name: String, val description: String)

/** An equipped weapon. Speed is the weapon category's flat Combat Pool surcharge. */
data class Weapon(val name: String, val category: String, val speed: Int)

/** A known Spell. [skillKey] is the casting skill whose Dice Cap bounds the dice. */
data class Spell(val name: String, val tier: Int, val skillKey: String, val category: ActionCategory = ActionCategory.MAIN)

/** An Ability usable on your turn (has a free / bonus / main activation), e.g. Rage. */
data class ActiveAbility(val name: String, val category: ActionCategory, val manaCost: Int, val summary: String)

data class Vitals(
    val hp: Int, val hpMax: Int,
    val mana: Int, val manaMax: Int,
    val toxicity: Int, val toxicityThreshold: Int,
    val damageReduction: Int, val damageResilience: Int,
)

data class Character(
    val name: String,
    val player: String,
    val summary: String,
    val tier: Int,
    val attributes: Map<Attribute, Int>,
    val saveRanks: Map<Attribute, Int>,
    val skills: List<Skill>,
    val vitals: Vitals,
    val speed: Int,
    val abilities: List<Ability>,
    val weapons: List<Weapon> = emptyList(),
    val spells: List<Spell> = emptyList(),
    val activeAbilities: List<ActiveAbility> = emptyList(),
) {
    fun skill(key: String): Skill? = skills.find { it.key == key }

    /** Dice Cap + bonus for a skill key (untrained if the character has no entry). */
    fun skillInputs(key: String): RollInputs {
        val s = skill(key) ?: return DiceRules.skill(0, attributes.getValue(Attribute.DEX))
        return DiceRules.skill(s.ranks, attributes.getValue(s.attribute))
    }

    /** Combat Pool size (Combat Pool Attribute is Wisdom). */
    val combatPool: Int
        get() = CombatRules.combatPool(skill("martial")?.ranks ?: 0, attributes.getValue(Attribute.WIS), tier)

    fun attributeCheck(a: Attribute) =
        RollRequest("${a.label} check", DiceRules.attributeCheck(attributes.getValue(a)))

    fun save(a: Attribute) =
        RollRequest("${a.label} save", DiceRules.save(saveRanks[a] ?: 0, attributes.getValue(a)))

    fun skillRoll(s: Skill) =
        RollRequest(s.name, DiceRules.skill(s.ranks, attributes.getValue(s.attribute)))
}

data class InitiativeEntry(
    val name: String,
    val isPlayerCharacter: Boolean,
    val diceResult: String,
    val isYou: Boolean = false,
)

data class Initiative(
    val round: Int,
    val currentIndex: Int,
    val order: List<InitiativeEntry>,
)

data class Note(val title: String, val date: String, val body: String)

data class Scene(
    val title: String,
    val location: String,
    val time: String,
    val description: String,
    val present: List<String>,
)

object DummyData {

    private fun skill(key: String, name: String, a: Attribute, ranks: Int = 0) = Skill(key, name, a, ranks)

    val character = Character(
        name = "Seren Ashvale",
        player = "Player",
        summary = "Human Ranger 2 / Barbarian 1",
        tier = 1,
        attributes = mapOf(
            Attribute.STR to 14, Attribute.DEX to 18, Attribute.CON to 13,
            Attribute.INT to 12, Attribute.WIS to 15, Attribute.CHA to 10,
        ),
        saveRanks = mapOf(
            Attribute.STR to 1, Attribute.DEX to 3, Attribute.CON to 2,
            Attribute.INT to 1, Attribute.WIS to 2, Attribute.CHA to 1,
        ),
        // Skill catalog from docs/common/proficiencies/skills.yaml (Set Skills
        // shown as one example instance each). Ranks are dummy values.
        skills = listOf(
            skill("athletics", "Athletics", Attribute.STR, 2),
            skill("acrobatics", "Acrobatics", Attribute.DEX, 1),
            skill("escape_artist", "Escape Artist", Attribute.DEX),
            skill("larceny", "Larceny", Attribute.DEX),
            skill("martial", "Martial", Attribute.DEX, 3),
            skill("ride", "Ride", Attribute.DEX, 1),
            skill("sleight_of_hand", "Sleight of Hand", Attribute.DEX),
            skill("stealth", "Stealth", Attribute.DEX, 4),
            skill("appraisal", "Appraisal", Attribute.INT),
            skill("arcana", "Arcana", Attribute.INT),
            skill("craft_bows", "Craft (Bows)", Attribute.INT, 2),
            skill("dungeoneering", "Dungeoneering", Attribute.INT),
            skill("game_dice", "Game (Dice)", Attribute.INT),
            skill("history", "History", Attribute.INT),
            skill("investigation", "Investigation", Attribute.INT, 1),
            skill("linguistics", "Linguistics", Attribute.INT),
            skill("nobility", "Nobility", Attribute.INT),
            skill("planes", "Planes", Attribute.INT),
            skill("religion", "Religion", Attribute.INT),
            skill("local_lore", "Local Lore", Attribute.INT, 1),
            skill("healing", "Healing", Attribute.WIS, 1),
            skill("invocation", "Invocation", Attribute.WIS),
            skill("nature", "Nature", Attribute.WIS, 3),
            skill("perception", "Perception", Attribute.WIS, 4),
            skill("profession_hunter", "Profession (Hunter)", Attribute.WIS, 2),
            skill("sense_motive", "Sense Motive", Attribute.WIS),
            skill("survival", "Survival", Attribute.WIS, 4),
            skill("animal_handling", "Animal Handling", Attribute.CHA, 2),
            skill("deception", "Deception", Attribute.CHA),
            skill("disguise", "Disguise", Attribute.CHA),
            skill("intimidate", "Intimidate", Attribute.CHA),
            skill("perform_sing", "Perform (Sing)", Attribute.CHA),
            skill("persuasion", "Persuasion", Attribute.CHA),
            skill("evocation", "Evocation", Attribute.CHA),
        ),
        vitals = Vitals(
            hp = 17, hpMax = 24,
            mana = 6, manaMax = 9,
            toxicity = 1, toxicityThreshold = 7,
            damageReduction = 2, damageResilience = 4,
        ),
        speed = 30,
        abilities = listOf(
            Ability("Favored Terrain (Forest)", "Placeholder: bonus to Stealth, Survival and Perception in forests."),
            Ability("Hunter's Mark", "Placeholder: mark one creature you can see; your attacks against it gain a bonus."),
            Ability("Wild Empathy", "Placeholder: improve the attitude of an animal, as Persuasion for people."),
            Ability("Rage", "Spend 1 mana to enter a rage for 10 turns plus 1 per class level (free action)."),
        ),
        // Weapon Speeds from equipment_config.yaml Weapon Categories (Ranged 2, One Handed 2); Unarmed is 0.
        weapons = listOf(
            Weapon("Longbow", "Ranged", 2),
            Weapon("Short sword", "One Handed", 2),
            Weapon("Unarmed", "Unarmed", 0),
        ),
        // Spells from docs/common/abilities/spells.yaml, cast with Nature.
        spells = listOf(
            Spell("Spark Shower", 0, "nature"),
            Spell("Heal Petty Wounds", 0, "nature"),
            Spell("Entangle", 1, "nature"),
        ),
        activeAbilities = listOf(
            ActiveAbility("Rage", ActionCategory.FREE, 1, "Spend 1 mana, gain the rage condition."),
        ),
    )

    val initiative = Initiative(
        round = 2,
        currentIndex = 1,
        order = listOf(
            InitiativeEntry("Goblin Skirmisher", false, "XX9875"),
            InitiativeEntry("Seren Ashvale", true, "X998743", isYou = true),
            InitiativeEntry("Bryn Ironvein", true, "X97765"),
            InitiativeEntry("Goblin Archer", false, "988642"),
            InitiativeEntry("Tamsin Reed", true, "877531"),
            InitiativeEntry("Hobgoblin Captain", false, "766421"),
        ),
    )

    val notes = listOf(
        Note(
            "Arrival at Dunmere", "3rd of Highsun",
            "The party reached the village of Dunmere at dusk. The innkeeper, Oswin, mentioned " +
                "livestock going missing from the eastern farms over the past week.",
        ),
        Note(
            "Tracks by the river", "4th of Highsun",
            "Seren found small booted footprints and drag marks leading north along the river. " +
                "At least five creatures, possibly goblins.",
        ),
        Note(
            "Reward", "4th of Highsun",
            "Reeve Hallam offered 40 silver for each missing animal returned, and 100 silver to " +
                "whoever ends the raids.",
        ),
    )

    val scene = Scene(
        title = "Ambush at the Old Mill",
        location = "Abandoned mill, north bank of the Dun river",
        time = "4th of Highsun, late afternoon",
        description = "The waterwheel creaks in the current. Broken fencing surrounds a muddy yard " +
            "littered with sheep bones. Smoke drifts from a gap in the mill's roof, and something " +
            "moves behind the shuttered upper window.",
        present = listOf("Seren Ashvale", "Bryn Ironvein", "Tamsin Reed", "Goblins (number unknown)"),
    )
}

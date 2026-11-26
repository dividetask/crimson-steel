package com.dividetask.crimsonsteel.data

import com.dividetask.crimsonsteel.dice.RollSpec
import org.json.JSONArray
import org.json.JSONObject

/*
 * What the server sends (lib/routes/api.rb). Each type parses itself from the
 * API's JSON; missing optional fields fall back to empty values so a newer or
 * older server never crashes the app.
 */

private inline fun <T> JSONArray?.mapObjects(f: (JSONObject) -> T): List<T> =
    if (this == null) emptyList() else (0 until length()).mapNotNull { optJSONObject(it) }.map(f)

private fun JSONObject.optIntOrNull(key: String): Int? = if (has(key) && !isNull(key)) optInt(key) else null

private fun JSONObject.optStringOrNull(key: String): String? =
    if (has(key) && !isNull(key)) optString(key).takeIf { it.isNotEmpty() } else null

data class CharacterRef(val id: Int, val name: String)

/** The newest app build on the server: its version ("v0.040") and the commit it was built from. */
data class AppRelease(val version: String, val commit: String?)

data class Hello(val campaign: String, val device: String, val character: CharacterRef?, val diceColor: Int? = null,
                 val app: AppRelease? = null) {
    companion object {
        fun from(j: JSONObject) = Hello(
            campaign = j.optString("campaign"),
            device = j.optString("device"),
            character = j.optJSONObject("character")?.let { CharacterRef(it.optInt("id"), it.optString("name")) },
            diceColor = com.dividetask.crimsonsteel.ui.Ui.parseHex(j.optStringOrNull("dice_color")),
            app = j.optJSONObject("app")?.let { a ->
                a.optStringOrNull("version")?.let { AppRelease(it, a.optStringOrNull("commit")) }
            },
        )
    }
}

/** A dice colour on offer in Settings; [takenBy] names whoever else has it. */
data class DiceColorOption(val key: String, val name: String, val color: Int, val takenBy: String?)
data class DiceColors(val mine: String, val options: List<DiceColorOption>) {
    companion object {
        fun from(j: JSONObject) = DiceColors(
            mine = j.optString("color"),
            options = j.optJSONArray("options").mapObjects {
                DiceColorOption(it.optString("key"), it.optString("name"),
                    com.dividetask.crimsonsteel.ui.Ui.parseHex(it.optString("hex")) ?: com.dividetask.crimsonsteel.ui.Ui.DICE_DEFAULT,
                    it.optStringOrNull("taken_by"))
            },
        )
    }
}

fun rollSpecFrom(j: JSONObject?): RollSpec? {
    if (j == null) return null
    val bpl = j.optJSONArray("bonus_penalty_list")
    val mods = if (bpl == null) emptyList() else (0 until bpl.length()).mapNotNull { i ->
        bpl.optJSONArray(i)?.let { Pair(it.optString(0), it.optInt(1)) }
    }
    return RollSpec(
        name = j.optString("name"),
        diceCount = j.optInt("dice_count"),
        tn = j.optInt("tn"),
        startingValue = j.optInt("starting_value"),
        baseTn = j.optInt("base_tn"),
        bonusPenaltyList = mods,
        ranks = j.optInt("ranks"),
    )
}

data class Meter(val current: Int, val max: Int) {
    companion object {
        fun from(j: JSONObject?, maxKey: String = "max") =
            j?.let { Meter(it.optInt("current"), it.optInt(maxKey)) }
    }
}

/** A table inside a [StatMath]: every cell is text. */
data class MathTable(val head: List<String>, val rows: List<List<String>>, val foot: List<String>)

/**
 * The math behind one number on the sheet (the "?" on the Sheet tab). The
 * server writes every line (lib/sheet_math.rb); the app shows it as it comes.
 */
data class StatMath(val title: String, val lines: List<String>, val table: MathTable?, val note: String?) {
    companion object {
        fun from(j: JSONObject?): StatMath? {
            if (j == null) return null
            return StatMath(
                title = j.optString("title"),
                lines = strings(j.optJSONArray("lines")),
                table = j.optJSONObject("table")?.let { t ->
                    val rows = t.optJSONArray("rows")
                    MathTable(
                        head = strings(t.optJSONArray("head")),
                        rows = if (rows == null) emptyList() else (0 until rows.length()).map { strings(rows.optJSONArray(it)) },
                        foot = strings(t.optJSONArray("foot")),
                    )
                },
                note = j.optStringOrNull("note"),
            )
        }

        /** Keyed as the server keys them: "hp", "mana", "combat_pool"… */
        fun mapFrom(j: JSONObject?): Map<String, StatMath> {
            if (j == null) return emptyMap()
            val out = mutableMapOf<String, StatMath>()
            for (key in j.keys()) from(j.optJSONObject(key))?.let { out[key] = it }
            return out
        }

        private fun strings(a: JSONArray?): List<String> =
            if (a == null) emptyList() else (0 until a.length()).map { a.optString(it) }
    }
}

data class SheetAttribute(
    val key: String, val label: String, val score: Int, val check: RollSpec?, val save: RollSpec?,
    val math: StatMath? = null, val checkMath: StatMath? = null, val saveMath: StatMath? = null,
)

data class SheetSkill(
    val key: String, val name: String, val attribute: String, val ranks: Int,
    val trained: Boolean, val dice: Int, val bonus: Int, val roll: RollSpec?,
    val math: StatMath? = null,
)

data class Ability(val name: String, val description: String)

data class Sheet(
    val id: Int,
    val name: String,
    val player: String,
    val summary: String,
    val tier: Int?,
    val hp: Meter?,
    val tempHp: Int,
    val mana: Meter?,
    val toxicity: Meter?,
    val damageReduction: Int,
    val damageResilience: Int,
    val speed: Int,
    val attributes: List<SheetAttribute>,
    val skills: List<SheetSkill>,
    val abilities: List<Ability>,
    val combatPool: Int? = null,
    /** The math behind each vital, by the server's key ("hp", "mana", "combat_pool"…). */
    val math: Map<String, StatMath> = emptyMap(),
) {
    /** Whether the server sent any math: without it there is nothing for "?" to show. */
    val hasMath: Boolean
        get() = math.isNotEmpty() || attributes.any { it.math != null } || skills.any { it.math != null }

    companion object {
        fun from(j: JSONObject): Sheet {
            val v = j.optJSONObject("vitals") ?: JSONObject()
            return Sheet(
                id = j.optInt("id"),
                name = j.optString("name"),
                player = j.optString("player"),
                summary = j.optString("summary"),
                tier = j.optIntOrNull("tier"),
                hp = Meter.from(v.optJSONObject("hp")),
                tempHp = v.optInt("temp_hp"),
                mana = Meter.from(v.optJSONObject("mana")),
                toxicity = Meter.from(v.optJSONObject("toxicity"), maxKey = "threshold"),
                damageReduction = v.optInt("damage_reduction"),
                damageResilience = v.optInt("damage_resilience"),
                speed = j.optInt("speed"),
                attributes = j.optJSONArray("attributes").mapObjects {
                    SheetAttribute(it.optString("key"), it.optString("label"), it.optInt("score"),
                        rollSpecFrom(it.optJSONObject("check")), rollSpecFrom(it.optJSONObject("save")),
                        StatMath.from(it.optJSONObject("math")), StatMath.from(it.optJSONObject("check_math")),
                        StatMath.from(it.optJSONObject("save_math")))
                },
                skills = j.optJSONArray("skills").mapObjects {
                    SheetSkill(it.optString("key"), it.optString("name"), it.optString("attribute"),
                        it.optInt("ranks"), it.optBoolean("trained"), it.optInt("dice"), it.optInt("bonus"),
                        rollSpecFrom(it.optJSONObject("roll")), StatMath.from(it.optJSONObject("math")))
                },
                abilities = j.optJSONArray("abilities").mapObjects { Ability(it.optString("name"), it.optString("description")) },
                combatPool = v.optIntOrNull("combat_pool"),
                math = StatMath.mapFrom(v.optJSONObject("math")),
            )
        }
    }
}

// --- Inventory -----------------------------------------------------------------

data class InventoryRow(
    val index: Int, val name: String, val category: String, val quantity: Int,
    val equipped: Boolean, val equippable: Boolean,
)

data class Inventory(
    val creatureId: Int,
    val manageable: Boolean,
    val equipped: List<InventoryRow>,
    val carried: List<InventoryRow>,
    val sellPile: List<InventoryRow>,
) {
    companion object {
        private fun rows(a: JSONArray?) = a.mapObjects {
            InventoryRow(it.optInt("index"), it.optString("name"), it.optString("category"),
                it.optInt("quantity", 1), it.optBoolean("equipped"), it.optBoolean("equippable"))
        }

        fun from(j: JSONObject) = Inventory(
            creatureId = j.optInt("creature_id"),
            manageable = j.optBoolean("manageable", true),
            equipped = rows(j.optJSONArray("equipped")),
            carried = rows(j.optJSONArray("inventory")),
            sellPile = rows(j.optJSONArray("sell")),
        )
    }
}

// --- Initiative and turn ---------------------------------------------------------

enum class ActionCategory(val key: String, val label: String) {
    MAIN("main", "Main Action"),
    BONUS("bonus", "Bonus Action"),
    FREE("free", "Free Action"),
    MINUTE("minute", "1 minute");

    companion object {
        fun of(key: String) = entries.find { it.key == key } ?: MAIN
    }
}

data class DiceChoice(val dice: Int, val poolCost: Int, val affordable: Boolean)

/** The skill a turn option rolls: e.g. Nature, 6 dice, +2. */
data class SkillView(val name: String, val dice: Int, val bonus: Int)

data class TurnOption(
    val key: String,
    val label: String,
    /** The action's own name without a verb (e.g. "Fire Dart", "Longbow"). */
    val name: String,
    /** Spell Tier for casts and items (the name is coloured by it); null otherwise. */
    val tier: Int?,
    val skill: SkillView?,
    /** Flat Combat Pool surcharge on top of one die per die (a weapon's Speed). */
    val speed: Int,
    /** Spells and Items: what it is pointed at — "creature", "self", "object" or "area". Null otherwise. */
    val target: String? = null,
    val kind: String,
    val category: ActionCategory,
    val detail: String,
    val dice: List<DiceChoice>,
    val poolCost: Int?,
    val manaCost: Int,
    val disabledReason: String?,
    /** Attacks: a ranged weapon (listed under Ranged, not Melee). */
    val ranged: Boolean = false,
    /** A sound tied to the action (e.g. "/sounds/RAGE_AGAIN.mp3"), played on the device by a button. */
    val sound: String? = null,
    /** Magic toxicity it adds to the user (a potion); 0 when none. */
    val toxicity: Int = 0,
    /** Spells: the catalog description, shown on the card. */
    val description: String = "",
) {
    val isEndTurn: Boolean get() = kind == "end_turn"

    /** Needs a creature picked in the app: an Attack, or a Spell / Item aimed at someone. */
    val needsTarget: Boolean get() = kind == "attack" || target == "creature"

    /** What the confirm button says: "Cast Fire Dart", "Attack with Longbow", "Move"… */
    val actionText: String
        get() = when (kind) {
            "cast" -> "Cast $name"
            "attack" -> "Attack with $name"
            "item", "special" -> "Use $name"
            "end_turn" -> "End my turn"
            else -> name
        }
}

data class TurnRequest(
    val id: String, val label: String, val category: ActionCategory,
    val dice: Int?, val poolCost: Int, val manaCost: Int,
) {
    val summary: String
        get() = buildString {
            append(label)
            if (dice != null) append(" — $dice dice")
            append(" (pool $poolCost")
            if (manaCost > 0) append(", mana $manaCost")
            append(")")
        }

    companion object {
        fun list(a: JSONArray?) = a.mapObjects {
            TurnRequest(it.optString("id"), it.optString("label"), ActionCategory.of(it.optString("category")),
                it.optIntOrNull("dice"), it.optInt("pool_cost"), it.optInt("mana_cost"))
        }
    }
}

/** Someone an attack can target (enemies first). */
data class TargetChoice(val combatantId: Int, val name: String, val enemy: Boolean, val dying: Boolean, val self: Boolean = false)

/** One answer a prompt offers. Options sharing a [group] with a [dice] count form one dice picker. */
data class PromptOption(
    val value: String, val label: String, val summary: String,
    val group: String, val groupLabel: String, val dice: Int?, val disabled: Boolean,
    /** Luck: "help" (a reroll for them) or "hinder" (against them); null otherwise. */
    val tone: String? = null,
)

/** The dice a roll prompt asks for, already worked out by the server (TN after both sides' bonuses). */
data class PromptRoll(
    val name: String, val diceCount: Int, val tn: Int, val startingValue: Int,
    val positiveReroll: Int, val negativeReroll: Int,
    /** The DM's fudge (never shown): the dice are landed in that band before Luck. */
    val fudge: String? = null,
)

/** One Roll of an action, for the overview on a roll prompt: who rolls what, how many dice, at what TN. */
data class RollLine(
    val taskId: String, val owner: String, val name: String, val diceCount: Int, val tn: Int,
    val startingValue: Int, val positiveReroll: Int, val negativeReroll: Int, val status: String, val summary: String?,
    /** What is rolled in words ("Arcana", "Dodging", "Wisdom save") and its own bonus. */
    val what: String = "", val bonus: Int = 0,
    /** Once rolled: the dice as thrown, any Luck rerolls (null where unchanged), the final dice and Successes. */
    val dice: List<Int>? = null, val rerolled: List<Int?>? = null, val final: List<Int>? = null, val successes: Int? = null,
    /** The roller's dice colour, the same on every phone (null from an older server). */
    val color: Int? = null,
    /** What a 1 counts for: −1, or 0 for a Damage Rider. */
    val failureModifier: Int = -1,
    /** A weapon's Damage Rider (e.g. Vicious), rolled after the attack lands. */
    val rider: Boolean = false,
) {
    val rolled: Boolean get() = final != null
}

private fun JSONArray?.ints(): List<Int>? = this?.let { a -> (0 until a.length()).map { a.optInt(it) } }
private fun JSONArray?.intsOrNull(): List<Int?>? = this?.let { a -> (0 until a.length()).map { if (a.isNull(it)) null else a.optInt(it) } }

/** One Roll of an action as the server sends it (a roll prompt's all_rolls, or a shared action). */
fun rollLine(it: JSONObject) = RollLine(it.optString("task_id"), it.optString("owner"), it.optString("name"), it.optInt("dice_count"),
    it.optInt("tn"), it.optInt("starting_value"), it.optInt("positive_reroll"), it.optInt("negative_reroll"),
    it.optString("status"), it.optStringOrNull("summary"),
    what = it.optString("what"), bonus = it.optInt("bonus"),
    dice = it.optJSONArray("dice").ints(), rerolled = it.optJSONArray("rerolled").intsOrNull(),
    final = it.optJSONArray("final").ints(), successes = it.optIntOrNull("successes"),
    color = com.dividetask.crimsonsteel.ui.Ui.parseHex(it.optStringOrNull("color")),
    failureModifier = if (it.has("failure_modifier") && !it.isNull("failure_modifier")) it.optInt("failure_modifier") else -1,
    rider = it.optBoolean("rider"))

/** What a committed action did ("Garroth Vask hit Wolf…"); [yours] when this player took it. */
data class NewsItem(val flowId: String, val text: String, val yours: Boolean) {
    companion object {
        fun list(a: JSONArray?) = a.mapObjects { NewsItem(it.optString("flow_id"), it.optString("text"), it.optBoolean("yours")) }
    }
}

/**
 * An action whose Rolls the DM just shared (Confirm): every phone in combat
 * throws them once. [version] goes up each time the DM shares again.
 */
data class SharedAction(val flowId: String, val version: Int, val actionLine: String, val rolls: List<RollLine>,
                        val headline: String? = null)

/**
 * A step of an attack waiting on this player (docs/project/action_flow.md):
 * choose a defense, shield an ally, use Luck, or roll. [status] is "waiting"
 * (answer it) or "submitted" (sent; waiting for the DM to approve).
 */
data class Prompt(
    val flowId: String, val taskId: String, val kind: String, val step: String,
    val title: String, val body: String, val status: String, val summary: String?,
    val options: List<PromptOption>, val roll: PromptRoll?,
    /** Every Roll of the action (roll prompts only), the player's own included. */
    val allRolls: List<RollLine> = emptyList(),
    /** Roll prompts: the action from this player's side, e.g. "Casting Fire Dart at Wolf". */
    val headline: String? = null,
    /** The prompt's heading: "Garroth Vask Attacks Wolf with Great Sword". */
    val actionLine: String? = null,
    /** Luck prompts: how much Luck the player has. */
    val luckRemaining: Int? = null,
) {
    val waiting: Boolean get() = status == "waiting"

    companion object {
        fun list(a: JSONArray?) = a.mapObjects { p ->
            Prompt(
                flowId = p.optString("flow_id"), taskId = p.optString("task_id"), kind = p.optString("kind"),
                step = p.optString("step"), title = p.optString("title"), body = p.optString("body"),
                status = p.optString("status"), summary = p.optStringOrNull("summary"),
                options = p.optJSONArray("options").mapObjects {
                    PromptOption(it.optString("value"), it.optString("label"), it.optString("summary"),
                        it.optString("group"), it.optString("group_label"), it.optIntOrNull("dice"), it.optBoolean("disabled"),
                        it.optStringOrNull("tone"))
                },
                roll = p.optJSONObject("roll")?.let {
                    PromptRoll(it.optString("name"), it.optInt("dice_count"), it.optInt("tn"), it.optInt("starting_value"),
                        it.optInt("positive_reroll"), it.optInt("negative_reroll"), it.optStringOrNull("fudge"))
                },
                allRolls = p.optJSONArray("all_rolls").mapObjects { rollLine(it) },
                headline = p.optStringOrNull("headline"),
                actionLine = p.optStringOrNull("action_line"),
                luckRemaining = p.optIntOrNull("luck_remaining"),
            )
        }
    }
}

/** One of this player's own attacks in progress, for the status lines. */
data class FlowStatus(val flowId: String, val stage: String, val summary: String, val poolCost: Int, val steps: List<FlowStep>,
                      val kind: String = "", val category: String? = null) {
    /** A Main Action that is not a weapon attack: ends a full round attack. */
    val breaksFullRound: Boolean get() = kind != "attack" && category in setOf("main", "minute")
    val isMainAction: Boolean get() = category == "main" || category == "minute"
}
data class FlowStep(
    val step: String, val owner: String, val status: String, val summary: String?,
    /** A roll's dice once it is in (drawn coloured by result). */
    val dice: List<Int>? = null, val rerolled: List<Int?>? = null, val final: List<Int>? = null,
    val successes: Int? = null, val tn: Int = 0, val startingValue: Int = 0,
)

data class InitiativeEntry(
    val combatantId: Int, val name: String, val isPc: Boolean,
    val acting: Boolean, val isYou: Boolean, val initiative: String?,
    /** Player Characters' Tier, for the name's colour (null for others). */
    val tier: Int? = null,
    /** Their turn is over this Round. */
    val acted: Boolean = false,
    val pool: Stat? = null, val hp: Stat? = null, val mana: Stat? = null,
    /** Conditions, or null when they are hidden from players. */
    val conditions: List<String>? = null,
)

/** A value on a Status row; [hidden] when players may not see it (shown as "?"). */
data class Stat(val current: Int, val max: Int, val hidden: Boolean = false) {
    companion object {
        fun from(j: JSONObject?): Stat? = j?.let {
            if (it.optBoolean("hidden")) Stat(0, 0, true)
            else Stat(if (it.has("current")) it.optInt("current") else it.optInt("remaining"), it.optInt("max"))
        }
    }
}

/** A rectangle or ellipse between two corners, in grid squares. */
data class MapShape(val ellipse: Boolean, val x0: Float, val y0: Float, val x1: Float, val y1: Float, val texture: String? = null) {
    companion object {
        fun from(j: JSONObject): MapShape? {
            val p = j.optJSONArray("points") ?: return null
            if (p.length() < 2) return null
            val a = p.optJSONArray(0) ?: return null
            val b = p.optJSONArray(1) ?: return null
            return MapShape(j.optString("shape") == "ellipse",
                minOf(a.optDouble(0), b.optDouble(0)).toFloat(), minOf(a.optDouble(1), b.optDouble(1)).toFloat(),
                maxOf(a.optDouble(0), b.optDouble(0)).toFloat(), maxOf(a.optDouble(1), b.optDouble(1)).toFloat(),
                j.optStringOrNull("texture"))
        }
    }
}

/** [color]: the ring — the owning player's dice colour, or the DM's. */
data class MapToken(val x: Float, val y: Float, val size: Float, val label: String, val image: String?, val combatantId: Int?,
                    val color: Int? = null, val tier: Int? = null)

/** The Active Map as a player sees it (GET /api/initiative → map). Units are grid squares. */
data class MapSnapshot(
    val width: Int, val height: Int, val image: String?,
    val tokens: List<MapToken>, val terrain: List<MapShape>, val fog: List<MapShape>,
) {
    companion object {
        fun from(j: JSONObject) = MapSnapshot(
            width = j.optInt("width").coerceAtLeast(1), height = j.optInt("height").coerceAtLeast(1),
            image = j.optStringOrNull("image"),
            tokens = j.optJSONArray("tokens").mapObjects {
                MapToken(it.optDouble("x").toFloat(), it.optDouble("y").toFloat(), it.optDouble("size", 1.0).toFloat(),
                    it.optString("label"), it.optStringOrNull("image"), it.optIntOrNull("combatant_id"),
                    com.dividetask.crimsonsteel.ui.Ui.parseHex(it.optStringOrNull("color")), it.optIntOrNull("tier"))
            },
            terrain = j.optJSONArray("terrain").mapObjects { MapShape.from(it) }.filterNotNull(),
            fog = j.optJSONArray("fog").mapObjects { MapShape.from(it) }.filterNotNull(),
        )
    }
}

data class Initiative(
    val combatActive: Boolean,
    val roundLabel: String,
    val myTurn: Boolean,
    val pool: Meter?,
    val mainActionsRemaining: Int?,
    /** Full round attack: only weapon attacks so far this turn, so they need no Main Action left. */
    val weaponAttacksOnly: Boolean = false,
    val mana: Meter?,
    /** The player's magic toxicity now, against their threshold (max). */
    val toxicity: Meter? = null,
    /** The Active Map, to pick targets on; null when there is none. */
    val map: MapSnapshot? = null,
    val order: List<InitiativeEntry>,
    val options: List<TurnOption>,
    val requests: List<TurnRequest>,
    val targets: List<TargetChoice> = emptyList(),
    val prompts: List<Prompt> = emptyList(),
    val flows: List<FlowStatus> = emptyList(),
    /** One of the player's actions waits on other players or dice: hide the action list until it is finished. */
    val busy: Boolean = false,
    /** Actions the DM just shared the Rolls of: thrown on the dice table once each. */
    val shared: List<SharedAction> = emptyList(),
    /** Every action with Rolls on the table, whether or not this player rolls in it. */
    val actions: List<SharedAction> = emptyList(),
    /** What the DM committed lately. */
    val news: List<NewsItem> = emptyList(),
    /** How many creatures act before the player's next turn; null when the server cannot say. */
    val creaturesBefore: Int? = null,
) {
    companion object {
        fun from(j: JSONObject): Initiative {
            val me = j.optJSONObject("me")
            val pool = me?.optJSONObject("pool")?.let { Meter(it.optInt("remaining"), it.optInt("max")) }
            return Initiative(
                combatActive = j.optBoolean("combat_active"),
                roundLabel = j.optString("round_label"),
                myTurn = j.optBoolean("my_turn"),
                pool = pool,
                mainActionsRemaining = me?.optIntOrNull("main_actions_remaining"),
                weaponAttacksOnly = me?.optBoolean("weapon_attacks_only") ?: false,
                mana = Meter.from(me?.optJSONObject("mana")),
                toxicity = Meter.from(me?.optJSONObject("toxicity"), maxKey = "threshold"),
                map = j.optJSONObject("map")?.let { MapSnapshot.from(it) },
                order = j.optJSONArray("order").mapObjects {
                    InitiativeEntry(it.optInt("combatant_id"), it.optString("name"), it.optBoolean("is_pc"),
                        it.optBoolean("acting"), it.optBoolean("is_you"), it.optStringOrNull("initiative"),
                        tier = it.optIntOrNull("tier"), acted = it.optBoolean("acted"),
                        pool = Stat.from(it.optJSONObject("pool")), hp = Stat.from(it.optJSONObject("hp")),
                        mana = Stat.from(it.optJSONObject("mana")),
                        conditions = it.optJSONArray("conditions")?.let { a -> (0 until a.length()).map { i -> a.optString(i) } })
                },
                options = j.optJSONArray("options").mapObjects { o ->
                    TurnOption(
                        key = o.optString("key"),
                        label = o.optString("label"),
                        name = o.optStringOrNull("name") ?: o.optString("label"),
                        tier = o.optIntOrNull("tier"),
                        skill = o.optJSONObject("skill")?.let {
                            SkillView(it.optString("name"), it.optInt("dice"), it.optInt("bonus"))
                        },
                        speed = o.optInt("speed"),
                        target = o.optStringOrNull("target"),
                        kind = o.optString("kind"),
                        category = ActionCategory.of(o.optString("category")),
                        detail = o.optString("detail"),
                        dice = o.optJSONArray("dice").mapObjects {
                            DiceChoice(it.optInt("dice"), it.optInt("pool_cost"), it.optBoolean("affordable"))
                        },
                        poolCost = o.optIntOrNull("pool_cost"),
                        manaCost = o.optInt("mana_cost"),
                        disabledReason = o.optStringOrNull("disabled_reason"),
                        ranged = o.optBoolean("ranged"),
                        sound = o.optStringOrNull("sound"),
                        toxicity = o.optInt("toxicity"),
                        description = o.optStringOrNull("description") ?: "",
                    )
                },
                requests = TurnRequest.list(j.optJSONArray("requests")),
                targets = j.optJSONArray("targets").mapObjects {
                    TargetChoice(it.optInt("combatant_id"), it.optString("name"), it.optBoolean("enemy"), it.optBoolean("dying"), it.optBoolean("self"))
                },
                prompts = Prompt.list(j.optJSONArray("prompts")),
                busy = j.optBoolean("busy"),
                creaturesBefore = me?.optIntOrNull("creatures_before"),
                news = NewsItem.list(j.optJSONArray("news")),
                actions = j.optJSONArray("actions").mapObjects { a ->
                    SharedAction(a.optString("flow_id"), 0, a.optString("action_line"),
                        a.optJSONArray("rolls").mapObjects { rollLine(it) }, a.optStringOrNull("headline"))
                },
                shared = j.optJSONArray("shared").mapObjects { a ->
                    SharedAction(a.optString("flow_id"), a.optInt("version"), a.optString("action_line"),
                        a.optJSONArray("rolls").mapObjects { rollLine(it) })
                },
                flows = j.optJSONArray("flows").mapObjects { f ->
                    FlowStatus(f.optString("flow_id"), f.optString("stage"), f.optString("summary"), f.optInt("pool_cost"),
                        f.optJSONArray("tasks").mapObjects {
                            FlowStep(it.optString("step"), it.optString("owner"), it.optString("status"), it.optStringOrNull("summary"),
                                dice = it.optJSONArray("dice").ints(), rerolled = it.optJSONArray("rerolled").intsOrNull(),
                                final = it.optJSONArray("final").ints(), successes = it.optIntOrNull("successes"),
                                tn = it.optInt("tn"), startingValue = it.optInt("starting_value"))
                        }, kind = f.optString("kind"), category = f.optStringOrNull("category"))
                },
            )
        }
    }
}

// --- Notes and scene ---------------------------------------------------------------

data class Note(val id: Int, val type: String, val chapter: Int?, val chapterName: String?, val title: String, val body: String)

data class Notes(val currentChapter: Int?, val notes: List<Note>) {
    companion object {
        fun from(j: JSONObject) = Notes(
            currentChapter = j.optIntOrNull("current_chapter"),
            notes = j.optJSONArray("notes").mapObjects {
                Note(it.optInt("id"), it.optString("type"), it.optIntOrNull("chapter"),
                    it.optStringOrNull("chapter_name"), it.optString("title"), it.optString("body"))
            },
        )
    }
}

data class SceneEntry(val id: Int, val type: String, val title: String, val body: String)

data class Scene(
    val campaign: String?, val chapter: String?, val time: String?,
    val combatActive: Boolean, val entries: List<SceneEntry>,
) {
    companion object {
        fun from(j: JSONObject) = Scene(
            campaign = j.optStringOrNull("campaign"),
            chapter = j.optStringOrNull("chapter"),
            time = j.optStringOrNull("time"),
            combatActive = j.optBoolean("combat_active"),
            entries = j.optJSONArray("entries").mapObjects {
                SceneEntry(it.optInt("id"), it.optString("type"), it.optString("title"), it.optString("body"))
            },
        )
    }
}

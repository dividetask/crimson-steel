package com.dividetask.crimsonsteel.net

import com.dividetask.crimsonsteel.data.Initiative
import com.dividetask.crimsonsteel.data.Sheet
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NetTest {

    @Test fun parsesDiscoveryReply() {
        val s = ServerLocator.parseReply(
            """{"service":"crimson-steel","version":1,"http_port":4567,"name":"The Shattered Beacon"}""", "192.168.1.10")
        assertEquals(ServerInfo("192.168.1.10", 4567, "The Shattered Beacon"), s)
        assertEquals("http://192.168.1.10:4567", s!!.baseUrl)
    }

    @Test fun ignoresOtherReplies() {
        assertNull(ServerLocator.parseReply("""{"service":"something-else","http_port":80}""", "1.2.3.4"))
        assertNull(ServerLocator.parseReply("not json", "1.2.3.4"))
        assertNull(ServerLocator.parseReply("""{"service":"crimson-steel","http_port":0}""", "1.2.3.4"))
    }

    @Test fun readsDeviceCookieOnly() {
        assertEquals("abc-123", Api.parseDeviceCookie("crimson_device_id=abc-123; path=/; HttpOnly"))
        assertNull(Api.parseDeviceCookie("rack.session=xyz; path=/"))
    }

    @Test fun parsesSheetFromApiJson() {
        val j = JSONObject("""
            {"ok":true,"id":1,"name":"Ash Windmere","player":"Sam","summary":"Human Bard 3","tier":1,
             "vitals":{"hp":{"current":8,"max":14},"temp_hp":0,"mana":{"current":8,"max":13,"regen":3},
                       "toxicity":{"current":3,"threshold":22},"damage_reduction":1,"damage_resilience":1},
             "speed":30,
             "attributes":[{"key":"str","label":"Strength","score":12,
               "check":{"name":"Strength check","dice_count":7,"tn":7,"starting_value":0,"base_tn":8,
                        "bonus_penalty_list":[["Competency",1]],"ranks":0},
               "save":{"name":"Strength save","dice_count":9,"tn":6,"starting_value":0,"base_tn":8,
                        "bonus_penalty_list":[["Competency",1],["Guidance",1]],"ranks":2}}],
             "skills":[{"key":"acrobatics","name":"Acrobatics","attribute":"dex","ranks":0,"dice":10,"bonus":1,
               "trained":false,"roll":null}],
             "abilities":[{"name":"Bardic Spellcasting","description":"..."}]}
        """.trimIndent())
        val s = Sheet.from(j)
        assertEquals("Ash Windmere", s.name)
        assertEquals(22, s.toxicity!!.max)
        assertEquals(6, s.attributes[0].save!!.tn)
        assertEquals(listOf("Competency" to 1, "Guidance" to 1), s.attributes[0].save!!.bonusPenaltyList)
        assertNull(s.skills[0].roll)
    }

    @Test fun parsesInitiativeOptions() {
        val j = JSONObject("""
            {"ok":true,"combat_active":true,"round_label":"Round 2","my_turn":true,
             "me":{"combatant_id":4,"pool":{"remaining":12,"max":16},"main_actions_remaining":2,
                   "mana":{"current":8,"max":13}},
             "order":[{"combatant_id":4,"name":"Ash","is_pc":true,"acting":true,"is_you":true,"initiative":"X865"}],
             "options":[
               {"key":"attack:Rapier","label":"Attack: Rapier","kind":"attack","category":"main","detail":"",
                "dice":[{"dice":2,"pool_cost":4,"affordable":true}],"pool_cost":null,"mana_cost":0,"disabled":false},
               {"key":"end_turn","label":"End Turn","kind":"end_turn","category":"free","detail":"","dice":[],
                "pool_cost":0,"mana_cost":0,"disabled":false}],
             "requests":[{"id":"ab12","key":"move","label":"Move","category":"main","dice":null,"pool_cost":4,"mana_cost":0}]}
        """.trimIndent())
        val i = Initiative.from(j)
        assertTrue(i.myTurn)
        assertEquals(12, i.pool!!.current)
        assertNull(i.options[0].poolCost)
        assertTrue(i.options[1].isEndTurn)
        assertEquals("Move (pool 4)", i.requests[0].summary)
    }
}

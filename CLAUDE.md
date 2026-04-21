# CLAUDE.md — Project Guidelines for Crimson Steel DM Tools

## Project Overview

Crimson Steel DM Tools is a local server that allows other players to connect to in order to view their character sheets, game notes, inventory, items for sale, current statuses, and view information relevant to their current choices. It also allows the DM to manage this information, add monsters, manage combat, manage hit points, and other useful tools.

- **Design documents** (`.md` files in `docs/`) — Game rules, pseudocode, spells, skills, classes, creatures, weapons, display
- **Configuration templates** (`.yaml.example` files in `docs/`) — Contains default rule data, and example campaign data
- **Configuration files** (`.json` in `data/`) — Contains rule data, and campaign data

## Critical Rules

### Do not loop on errors — stop and explain

- If an approach fails twice, stop immediately. Do not retry the same strategy.
- Explain what went wrong, what was attempted, and suggest alternatives — let me decide how to proceed.
- Do not silently retry file operations, compilations, or code execution hoping for a different result.
- If a tool call or code execution returns an error, analyze the error before taking any further action.
- When stuck on a problem, present the situation clearly rather than burning through tokens on repeated attempts.

### Ask questions often

- Ask questions often especially when there is ambiguity or you believe I have made a mistake

### Stop after asking questions

- Whenever you have a question, or multiple questions, stop immediatly after asking them.

### Design document conventions

- All formulas use `floor()` for division (round down) unless explicitly stated otherwise.
- Use "Wisdom save" and "Dexterity save" — never "will save" or "reflex save".
- Use "magic toxicity" — not "mana saturation".
- Tier 0 is treated as 0.5 in all formulas.
- Cross-reference between documents using relative markdown links: `[SPELLS.md](SPELLS.md)`.

### Configuration file architecture

| File | Purpose | Scope |
|------|---------|-------|

## File Structure

```
```

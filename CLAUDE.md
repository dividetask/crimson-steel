# CLAUDE.md — Project Guidelines for Crimson Steel DM Tools

## Project Overview

Crimson Steel DM Tools is a local server that allows other players to connect to in order to view their character sheets, game notes, inventory, items for sale, current statuses, and view information relevant to their current choices. It also allows the DM to manage this information, add monsters, manage combat, manage hit points, and other useful tools.

- **Common design documents** (`.md` files in `docs/common/`) — General, project-agnostic rules: dice/check resolution, shared UI conventions, glossary terms.
- **Project design documents** (`.md` files in `docs/project/`) — Crimson Steel–specific rules: menu layout, page access, server behavior, anything that customizes the common rules for this project.
- **Configuration templates** (`.yaml.example` files in `docs/`) — Contains default rule data, and example campaign data
- **Configuration files** (`.json` in `data/`) — Contains rule data, and campaign data

### Documentation precedence

When a rule in `docs/project/` conflicts with a rule in `docs/common/`, the `docs/project/` rule wins. Treat `docs/common/` as the default behavior and `docs/project/` as the Crimson Steel override.

### DM vs. player identification

The website identifies viewers by where their HTTP request originates:

- A request whose remote address is the same machine as the server (loopback addresses such as `127.0.0.1` and `::1`) is treated as the **DM**.
- Every other request — anyone connecting from another device on the LAN — is treated as a **player**.

There is no login, password, or account selection. Identity is purely based on whether the request comes from the server host. The DM may temporarily view the site as a player would (see `docs/project/menu_layout.md`); that toggle is a UI convenience and does not change the underlying identification rule.

## Critical Rules

### Do not loop on errors — stop and explain

- If an approach fails twice, stop immediately. Do not retry the same strategy.
- Explain what went wrong, what was attempted, and suggest alternatives — let me decide how to proceed.
- Do not silently retry file operations, compilations, or code execution hoping for a different result.
- If a tool call or code execution returns an error, analyze the error before taking any further action.
- When stuck on a problem, present the situation clearly rather than burning through tokens on repeated attempts.

### Ask questions often

- Ask questions often especially when there is ambiguity or you believe I have made a mistake
- Ask questions in plain chat text, not via the `AskUserQuestion` / multiple-choice prompt tool. Do not use that tool in this project — write the question(s) as normal prose and wait for a reply.

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

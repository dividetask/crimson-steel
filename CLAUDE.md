# CLAUDE.md — Project Guidelines

## Critical Rules

### Do not loop on errors — stop and explain

- If an approach fails twice, stop immediately. Do not retry the same strategy.
- Explain what went wrong, what was attempted, and suggest alternatives — let me decide how to proceed.
- Do not silently retry file operations, compilations, or code execution hoping for a different result.
- If a tool call or code execution returns an error, analyze the error before taking any further action.
- When stuck on a problem, present the situation clearly rather than burning through tokens on repeated attempts.

### Ask questions often

- Ask questions often especially when there is ambiguity or you believe I have made a mistake

### When a referenced thing is missing, stop and ask

- If the user references a branch, file, function, document, or anything else
  that I can't find, do not silently proceed against the closest match — stop
  and tell them what I looked for and where, and ask for clarification.
- The same applies if I find something with a similar name but I'm not sure
  it's the right thing.

### Stop after asking questions

- Whenever you have a question, or multiple questions, stop immediatly after asking them.

### Never use question prompts

- Never use the `AskUserQuestion` tool or any other interactive question/choice prompt. Ask your questions in plain text, then stop until you get a response.

---
name: export-session-log
description: Hand off this Claude Code session's own raw transcript (the local JSONL conversation log, including every tool_use/tool_result — not a written-up summary) so it can be analyzed elsewhere, e.g. in another Claude session or a script. Use this whenever the user asks for "the session log", "this chat's log/transcript", "the jsonl", "raw conversation data", says they want to analyze "this incident/investigation" in another session, or asks for tool usage / MCP tool call history to be exported. Trigger even if they don't say "jsonl" explicitly — "I want to hand this whole conversation to another session to dig into" or "give me the data behind this debugging session" both mean the same thing. Do NOT use this for a human-readable recap or write-up of what happened — that's a normal summary, not this skill.
license: MIT
---

# Export Session Log

The user wants the *raw* record of this conversation — the actual JSONL
transcript Claude Code writes to disk, not a prose summary. This is because
transcripts carry structure (tool calls, tool results, timestamps, event
types) that only another Claude session or a script can make full use of.
Prose summaries lose that structure; don't substitute one for the other.

## Step 1: Find the transcript file

Claude Code sessions are logged one line of JSON per event under
`~/.claude/projects/<project-slug>/<session-id>.jsonl`. The project slug is
the current working directory with `/` replaced by `-`. Find the current
session's file:

```bash
ls -t ~/.claude/projects/*/*.jsonl 2>/dev/null | head -5
```

If more than one file is plausible (e.g. multiple sessions in the same
project), disambiguate by matching the `sessionId` field inside the file
against the session ID visible in this conversation's context (it also
appears in any `claude.ai/code/session_...` URL you've been given, and as
`"sessionId"` on nearly every line of the file itself). When genuinely
unsure which file is the current session, ask rather than guess — handing
over the wrong session's data is worse than a clarifying question.

## Step 2: Size it up before deciding how to deliver it

```bash
wc -l <file>; wc -c <file>
```

A raw JSONL transcript is usually large — every turn re-injects full system
reminders, tool schemas, and MCP instructions, so line count and byte size
both run high fast. As a rule of thumb: if it's small enough that pasting it
verbatim into the chat would still be a readable, single message (a rough
guide: well under ~200KB / a few thousand lines), inline it. Above that,
don't paste it — dumping a multi-megabyte blob as chat text is not more
"raw" or more useful, it just becomes unreadable and risks silent truncation
by the terminal. Send it as an actual file instead (`SendUserFile` if
available, otherwise whatever file-delivery tool this harness provides) —
a real file is what a downstream analysis session can actually ingest
without you having had to reformat it.

## Step 3: Give a MECE breakdown, always

Whichever way you deliver the transcript, also summarize it in the chat so
the user (and whoever picks up the file later) knows what's in it without
having to open and parse it themselves. At minimum, count events by their
`type` field:

```bash
python3 -c "
import json, collections
c = collections.Counter()
with open('<file>') as f:
    for line in f:
        try:
            c[json.loads(line).get('type', 'unknown')] += 1
        except Exception:
            pass
for k, v in c.most_common():
    print(f'{k}: {v}')
"
```

Report line count, byte/MB size, and the type breakdown together — that's
the MECE view: every event in the file falls into exactly one type, and the
counts add up to the total.

## Step 4: Respect what the user actually asked for

Default to handing over everything (don't pre-filter or summarize away
tool calls "to save space" — that's exactly the structure the user wants
preserved). Only narrow the scope if the user says so explicitly (e.g. "just
the tool_use events" or "only from when the RCA started"). If they ask for
something narrower, filter with the same `type`-counting script pattern
above rather than hand-editing the file, so the subset stays valid JSONL.

## What not to do

- Don't convert the transcript into a narrative write-up instead of handing
  over the raw data — that defeats the purpose of a separate analysis
  session, which wants the structure (exact tool inputs/outputs, timestamps)
  a summary throws away.
- Don't paste a multi-megabyte file into chat just because the user said
  "output it directly here" — explain the size problem and send the file
  instead; note this reasoning briefly rather than silently doing something
  different from what was asked.

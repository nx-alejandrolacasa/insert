# Diagnosing a freeze

What to do when Insert beachballs, and why the agent can't do it for you.

## The one rule

**Sample it before you quit it.** A beachballed app holds the whole answer in its
stack, and force-quitting throws it away. macOS usually writes *nothing* on its
own — hang reports in `/Library/Logs/DiagnosticReports/*.hang` only appear when
hangtracer happens to notice the spin and decides to sample it, and a freeze you
quit out of typically leaves no report at all. So the 5 seconds you spend on the
command below is the difference between a fixed bug and a shrug.

```
sample Insert 5 -file /tmp/insert-hang.txt
```

For the dev build the process name has a space, so quote it:

```
sample "Insert Dev" 5 -file /tmp/insert-dev-hang.txt
```

That's it. Now force-quit and get on with your day; the file keeps.

`sample` attaches to an unresponsive app fine — it doesn't need the app to be
answering events, which is the whole point. No `sudo`, no entitlements.

If you'd rather click: **Activity Monitor** → select Insert → the **⋯** button in
the toolbar → **Sample Process** → **Save**. Same artifact.

## Why you have to run it, not the agent

Claude Code runs in a sandbox on this machine, and the three tools that would
answer this question are all blocked by it:

- `log` — refuses outright: `log: Cannot run while sandboxed`.
- `sample`, `spindump` — need to attach to another process.
- `ps`, `pgrep` — blocked the same way.

Reading files is fine, which is why the handoff is a **path**: run the command,
paste `/tmp/insert-hang.txt` into the chat, and the agent reads it from disk.
Prefixing a command with `!` in the Claude Code prompt runs it in your shell and
drops the output straight into the conversation, so that works too for anything
short.

## Reading the sample

You're looking for the main thread — it's the first one listed, and it's labelled
`Thread_… DispatchQueue_1: com.apple.main-thread`. Everything under it is the
call stack, outermost frame first, with a count of how many of the samples each
frame was present in. The deepest frame with a count near the total is where the
app is stuck.

Two shapes come up:

- **Stuck in one place** — some frame holds ~500/500 samples. That's a blocking
  call: a synchronous file read, a lock, a formatter being built. Read the frames
  above it back to Insert's own code.
- **Spinning** — the counts fan out across many different frames under one of
  ours. That's work being done over and over, usually per layout pass or per
  keystroke.

`spindump` is the heavier alternative and is worth it when you suspect the app is
waiting on *another* process (the spell checker daemon, `cfprefsd`, a network
mount), because it samples everything at once and shows the wait chains:

```
sudo spindump Insert 5 -file /tmp/insert-spin.txt
```

## The unified log, after the fact

The unified log retains days of history, so it survives the restart — this is the
one thing you can still collect *after* the freeze is over.

```
/usr/bin/log show --last 30m --predicate 'process == "Insert"' --info --style compact
```

Narrow it to the window you care about with explicit bounds:

```
/usr/bin/log show --start "2026-07-31 13:20:00" --end "2026-07-31 13:40:00" \
    --predicate 'process == "Insert"' --info --style compact
```

Use `/usr/bin/log` — plain `log` collides with a shell function in some setups.

Temper your expectations: **Insert barely logs.** The whole app has two `Logger`
instances, both under subsystem `com.alejandrolacasa.insert` — category
`Library` (failed moves, failed writes, a duplicate id being trashed, the
retention purge) and `Reminder` (notification authorization and post failures).
Everything but the purge line is `.error`, and the purge is `.info`, which is why
`--info` is on the command. Nothing traces the UI, so the app's own log will not
tell you why a card stopped drawing.

What *is* worth grepping is the system's view of Insert — hangtracer,
WindowServer marking it unresponsive, the spell checker, `cfprefsd`:

```
/usr/bin/log show --last 30m --predicate 'eventMessage CONTAINS "Insert"' --style compact
```

## Also worth a look

```
ls -lat /Library/Logs/DiagnosticReports ~/Library/Logs/DiagnosticReports
```

Crashes land as `.ips`, spins as `.hang`, and both directories rotate old entries
into `Retired/`. Empty of anything named Insert is the normal case for a freeze —
don't read it as "nothing happened".

## What to hand back

Paste the path, plus what you were doing when it went — the pane you were on, the
field you were typing in, whether Settings was open. The stack names the frame;
you name the gesture, and it usually takes both.

## A worked example

The one freeze this app has actually had, so you know what the payoff looks like.
Settings → Tasks locked up for seconds at a time on a real library. A `sample` of
the hung app named two costs on the AppKit date picker: SwiftUI re-applying
`setLocale:`/`setCalendar:`/`setTimeZone:` on every graph update, each one
rebuilding an ICU `SimpleDateFormat` and its symbols, and
`GroupedFormRowLayout.Cache.updateAlignment()` asking that control for
`_baselineOffsetsAtSize:` from five separate measurement sites in a single layout
pass. Neither was guessable from reading the code — the fix (a `Picker` over a
fixed list of `Int` minutes) followed directly from the frame names. See the
"Daily morning reminder" bullet in `CLAUDE.md`.

The near-miss on the other side: a stale `~/Library/Logs/Insert-spelling.log`
sitting in the log directory from an earlier instrumentation session, which reads
like live evidence and is nothing of the kind. If you find a hand-rolled log file
in there, check the source still writes it before you believe a word of it.

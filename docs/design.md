# dot-profiler design

## What it answers

A frame over budget is logged with the system that caused it and what that system was doing, and a cause that repeats on a beat is named with its period ("`navigation.rebuild` repeats every 0.50 s"). The engine's own profiler shows a timeline you have to read; this names the culprit in a log line an operator or a nightly run can act on.

## The pieces

| Piece | Where | Job |
| --- | --- | --- |
| `DotFrameCost` | dot-core `profile/` | Systems report their own per-frame cost: `var t := DotFrameCost.now()` ... `DotFrameCost.add(&"system", t, "what")`. Off and free by default; `now()` returns 0 while off and `add` ignores 0. |
| `DotHitchLog` | dot-core `profile/` | Measures each frame's phases (physics, script, render, wait), counter deltas, marks and new nodes; while enabled it drains `DotFrameCost.take()` once per frame and puts the costs on each hitch as `systems`. |
| `DotProfiler` | `runtime/` | The node a game places. Owns a `DotHitchLog`, attributes each spike, tracks periods, keeps running averages for the overlay, records to `user://profiles`. |
| `DotProfilerPeriod` | `core/` | Finds the beat in a list of spike times: the median gap, and how many gaps fall within `period_tolerance` of it. |
| `DotProfilerReport` | `core/` | Builds the JSON report and its text form from a recording. |
| `DotProfilerOverlay` | `ui/` | The top costs, frame time against budget and the last spike, drawn in a corner. |
| `DotProfilerPanel` | `ui/` | Record / Stop with elapsed time, the saved path, Open folder and Copy path (Download on the web), the recent recordings. |
| `dot_profiler_run` | `tools/` | The headless runner for the nightly perf budget ([runner.md](runner.md)). |

## Attribution

A spike is charged to the system that took at least a quarter (`CAUSE_SHARE`) of the frame. When no reported system did, it is charged to `engine.<phase>`, the largest of physics, script, render and wait, so unreported work still lands somewhere. Hints come from the hitch record: shader compiles, new nodes and resources, static memory growth, log lines and marks.

A spike is logged at WARN at most once per `profiler_warn_every_s` per cause; the rest are counted and the count is reported on the next line for that cause.

## Configuration

Exported defaults < JSON file (`config_file`) < environment (`DOT_PROFILER_*`) < command line (`--profiler-*`), then the console variables at run time.

| cvar | Default | Meaning |
| --- | --- | --- |
| `profiler_enabled` | 0 | Watch every frame and log spikes. |
| `profiler_budget_ms` | 33 | A frame longer than this is a spike. |
| `profiler_overlay` | 0 | Draw the overlay (turns watching on). |
| `profiler_overlay_top` | 6 | Rows on the overlay. |
| `profiler_period_tolerance` | 0.12 | How far a gap may stray from the median and still count as the beat. |
| `profiler_period_min_spikes` | 4 | Spikes needed before a beat is named. |
| `profiler_warn_every_s` | 5 | Throttle per cause for the WARN line. |
| `profiler_record_seconds` | 30 | Default recording length. |
| `profiler_record_dir` | user://profiles | Where reports go: under `user://` or an absolute path. On a server left at the default, `<log_directory>/profiles`. |
| `profiler_keep_recordings` | 20 | Older reports are deleted. |
| `profiler_sample_hz` | 1 | Metric samples per second written into a recording's `samples` (memory and counts; on a server also bytes, players and bots); 0 takes none. Every frame is recorded regardless. |
| `profiler_query` | 0 | Publish `profiler_ms`, `profiler_spikes`, `profiler_period`, `profiler_static_mb` and `profiler_nodes` in the server query's game section. Off because the query is public. |

Console commands (via `bind_console(local)` on a dot-console `DotConsoleLocal`): `record [seconds]` (alias `profiler_record`), `profiler_stop`, `profiler_report`. A dedicated server uses `DotProfilerServer` instead ([server.md](server.md)).

## Instrumenting a system

Wrap the work that might be slow, name the system with a dotted `StringName` and say what ran:

```gdscript
var t := DotFrameCost.now()
_rebuild_paths()
DotFrameCost.add(&"navigation.rebuild", t, "%d paths" % n)
```

Exactly one reader drains `DotFrameCost` per frame (`DotHitchLog` while enabled). A second reader would see half the frame.

## Existing frame clocks

`DotHitchLog` keeps its old behaviour and fields; `systems` is an addition. dot-menu's `DotMenuFrameClock` and game-arena's frame probe keep working and can be retired in favour of a `DotProfiler` once each consumer moves.

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
| `DotProfilerReport` | `core/` | Builds the JSON report and its text form from a recording; writes the `.json`, `.txt` and `.folded` files ([report-format.md](report-format.md)). |
| `DotProfilerSession` | `core/` | The version 2 half of a recording: frame statistics, physics ticks per frame, engine monitors, physics queries, the worst frames whole and the profiler's own cost. |
| `DotProfilerTree` | `core/` | The call tree with inclusive and exclusive ms, rebuilt each frame from traced `DotFrameCost` spans under the roots frame > process, render, wait, physics > scripts, step. |
| `DotProfilerTicks` | `runtime/` | A child node of the recorder that stamps each physics tick's start and the end of its scripts, so the tree can split scripts from the engine step. |
| `DotProfilerReportText` | `core/` | The text sections of a version 2 report. |
| `DotProfilerCompare` | `core/` | Two reports side by side in ms per frame, B minus A. |
| `DotProfilerDeep` | `runtime/` | Optional native samples with Linux perf next to a recording ([deep-mode.md](deep-mode.md)). |
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
| `profiler_trace` | 1 | While recording, time each `DotFrameCost` span so the report has a call tree. |
| `profiler_monitors` | 1 | While recording, read the engine monitors every frame. |
| `profiler_worst_frames` | 5 | Slowest frames kept whole, with their tree (0 to 50). |
| `profiler_capture_seconds` | 10 | Length of a capture started by the capture key or `profiler_capture`. |
| `profiler_deep` | 0 | Also sample native stacks with perf while recording. |
| `profiler_timeline` | 0 | While recording, keep each frame's ms and flag frames at 2x the running average (and 2 ms above it) or over budget, with their top self spans, systems and phases. |
| `profiler_render_detail` | 0 | While recording, also read texture and buffer memory, resources, the viewport's draw calls, primitives and objects split by visible, shadow and canvas, and render cpu and gpu ms. |
| `profiler_groups` | "" | Comma-separated `group` or `group:system-prefix`, counted every frame while recording: a SceneTree group, or a counter the game registers with `DotProfiler.add_counter(group, callable, prefix)`, which is only read when its group is listed here. With a prefix, the report gives each matching system's us per unit. |
| `profiler_census` | 0 | Count nodes by class (or script `class_name`) when a recording starts and stops; the report lists the classes that changed most. |
| `profiler_script_top` | 0 | GDScript functions listed by self time, with total time and calls (0 to 500). Needs the game started with `-d`, because the engine's script profiler only runs under its local debugger; without it the report says so. Costs a lot while on. |
| `profiler_script_buckets` | "" | Sums script functions into named buckets: comma-separated `name=part|part`, matched against script paths and function names; the rest is `other`. |
| `profiler_query` | 0 | Publish `profiler_ms`, `profiler_spikes`, `profiler_period`, `profiler_static_mb` and `profiler_nodes` in the server query's game section. Off because the query is public. |

Console commands (via `bind_console(local)` on a dot-console `DotConsoleLocal`): `record [seconds]` (alias `profiler_record`), `profiler_stop`, `profiler_report`, `profiler_capture` (start a capture of `profiler_capture_seconds`, or stop the running one) and `profiler_compare [a.json b.json]` (the two newest recordings when no paths are given). `enable_capture_key(KEY_F10)` binds the `profiler_capture` input action to a key when the project has not bound it, so one key starts and stops a capture. A dedicated server uses `DotProfilerServer` instead ([server.md](server.md)).

## Instrumenting a system

Wrap the work that might be slow, name the system with a dotted `StringName` and say what ran:

```gdscript
var t := DotFrameCost.now()
_rebuild_paths()
DotFrameCost.add(&"navigation.rebuild", t, "%d paths" % n)
```

Physics queries go through dot-core's `DotSpaceQuery`, which counts and times each one by kind for the system named, for example `DotSpaceQuery.cast_motion(space, params, &"p_controller")`. A query made without it can be reported with `DotFrameCost.add_query(system, kind, t)`.

Exactly one reader drains `DotFrameCost` per frame (`DotHitchLog` while enabled). A second reader would see half the frame.

## Existing frame clocks

`DotHitchLog` keeps its old behaviour and fields; `systems` is an addition. dot-menu's `DotMenuFrameClock` and game-arena's frame probe keep working and can be retired in favour of a `DotProfiler` once each consumer moves.

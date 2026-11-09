# Report format

A recording writes three files next to each other in `profiler_record_dir`: `profile-<stamp>.json`, `profile-<stamp>.txt` and `profile-<stamp>.folded`. The JSON is the contract; the text is for people and its section headings stay stable for tools that grep it. Keys are only ever added; a key that changes meaning bumps `version`.

## Version 1 keys (unchanged)

| Key | Meaning |
| --- | --- |
| `version` | 2 since the call tree; 1 before. |
| `made` | UTC time the report was written. |
| `frames`, `wall_s` | Frames recorded and their total length in seconds. |
| `p50_ms`, `p95_ms`, `p99_ms`, `worst_ms` | Frame time percentiles. |
| `spike_count`, `spikes`, `causes` | Frames over `budget_ms` and who they were charged to. |
| `systems` | Rows `{system, ms, calls, worst_ms, what, ms_per_frame}` from `DotFrameCost.add`, costliest first. |
| `phases` | Total ms per engine phase: `physics`, `script`, `render`, `wait`. |
| `budget_ms`, `seconds`, `scene`, `period`, `sample_hz`, `samples` | The recording's settings and metric samples. |

## Version 2 keys

| Key | Meaning |
| --- | --- |
| `frame_stats` | `{frame, physics, script, render, wait}`, each `{min, avg, p50, p95, p99, max}` in ms per frame. |
| `tree` | The call tree in depth-first order, costliest child first: rows `{path, name, depth, ms, self_ms, calls, p95_ms, max_ms, frames}`. `ms` (inclusive), `self_ms` (exclusive) and `calls` are per frame averaged over every frame; `p95_ms` counts frames the node missed as 0; `max_ms` is its worst single frame; `frames` is how many frames it ran in. |
| `worst_frames` | The `profiler_worst_frames` slowest frames whole: `{t, ms, ticks, physics, script, render, wait, tree, queries, monitors}`, `tree` rows `{path, ms, self_ms, calls}` for that frame only. |
| `monitors` | Engine monitors read every frame, each `{min, avg, p50, p95, p99, max}`: `time_process_ms`, `time_physics_ms`, `time_navigation_ms`, `physics_3d_active`, `physics_3d_pairs`, `physics_3d_islands`, `draw_calls`, `objects_drawn`, `primitives`, `objects`, `nodes`, `orphan_nodes`, `static_mb`, `video_mb`. |
| `queries` | Physics queries by caller and kind, costliest first: `{system, kind, ms, calls, worst_ms, ms_per_frame, calls_per_frame, calls_per_tick, us_per_call}`. Kinds are `cast_motion`, `rest_info`, `intersect_ray`, `intersect_shape`, `intersect_point`, `collide_shape`, `move_and_collide`, `body_test_motion` and whatever a system passes to `DotFrameCost.add_query`. Unnamed callers are `unattributed`. |
| `traced_queries` | `{caller: {kind: {ms, calls}}}` from the tree: the span each `q.<kind>` ran inside, which can be finer than the `system` passed in. |
| `physics_ticks` | `{ticks, per_second, max_per_frame, per_frame, histogram, catch_up_frames, spiral_frames, wall_s, ticks_per_sec, dropped_ticks}`. `dropped_ticks` is the ticks the wall time called for (`wall_s` x `per_second`) minus the ticks that ran. `histogram` maps ticks-in-a-frame (as a string) to frames. A catch-up frame ran 2 or more ticks; a spiral frame hit `max_physics_steps_per_frame`. |
| `overhead` | `{on_frame_avg_ms, on_frame_max_ms, spans_per_frame, trace}`: the profiler's own per-frame cost while recording, measured around its frame handler. |
| `deep` | Empty unless `profiler_deep` is on: `{ok, file, pid, command}` or `{ok: false, reason}` ([deep-mode.md](deep-mode.md)). |

## Context keys

| Key | Meaning |
| --- | --- |
| `context` | `{machine, <game keys>}`. `machine` is `{os, cpu, cores, ram_mb, gpu, gpu_vendor, driver, renderer, godot, debug_build, tick_rate, max_fps, window, vsync, display}`; a game adds keys with `DotProfiler.add_context(key, provider)` (build, map, bots, natives loaded, cvar overrides). Read when the recording starts. |
| `extras` | `{<key>: Dictionary}` from `DotProfiler.add_recording_hook(key, begin, end)`: what `end` returned when the recording stopped (a game's native timers). A hook returning an empty Dictionary is left out. |

The capture key and `profiler_capture` turn `render_detail` on for that capture, so `render_cpu_ms` and `render_gpu_ms` are there; `profiler_reference` (a JSON path) diffs every written report against that file and saves `<report>.diff.txt`.

## Detail keys

These come from the options in [design.md](design.md#configuration); all are off by default except `growth`, which is computed when the report is built from the frames already kept.

| Key | Meaning |
| --- | --- |
| `growth` | Per monitor that grows (`objects`, `nodes`, `orphan_nodes`, `static_mb`, `video_mb`, `resources`, `texture_mb`, `buffer_mb`): `{first, last, delta, per_min, max}`. Empty when monitors are off. |
| `monitors` (render_detail) | Adds `texture_mb`, `buffer_mb`, `resources`, `draws_visible`, `draws_shadow`, `draws_canvas`, `primitives_visible`, `primitives_shadow`, `objects_visible`, `objects_shadow`, `render_cpu_ms` and `render_gpu_ms`, even with `profiler_monitors` off. |
| `timeline` | `{t0, frame_ms, seconds, flagged}`. `frame_ms` is every frame's time; `seconds` rows `{s, frames, avg_ms, max_ms, flagged, physics, script, render, wait}` (phases in ms per frame); `flagged` (at most 200, the worst kept) `{t, ms, avg_ms, top, systems, physics, script, render, wait}`, with `top` the 5 largest self spans `{path, self_ms, ms}` and `systems` the 5 costliest `{system, ms}`. |
| `groups` | Per `profiler_groups` entry `{group, prefix, count, systems}`: `count` is `{min, avg, p50, p95, p99, max}` per frame, `systems` rows `{system, ms_per_frame, calls_per_frame, us_per_unit}` for systems starting with `prefix`. |
| `script_functions` | `{ok, functions, scripts, buckets, self_ms, function_count}` or `{ok: false, reason}`. `functions` (the top `profiler_script_top` by self time) are `{function, script, line, calls_per_frame, self_ms, total_ms, us_per_call}`, ms per frame; `scripts` sums them per file; `buckets` per `profiler_script_buckets` entry plus `other`. Times are the engine's script profiler, which inflates small functions; the profiler's own script functions are left out. |
| `census` | `{start_nodes, end_nodes, classes}` with `classes` rows `{class, start, end, delta}`, largest change first. |

## The tree

Every frame's tree hangs under fixed roots, taken from `DotHitchLog`'s stamps and a tail node that runs after every other `_physics_process`:

```
frame
  process        idle callbacks of the previous frame (_process, signals, deferred calls)
  render         the previous frame's draw
  wait           the gap before this frame's first physics tick (vsync, frame cap)
  physics        this frame's physics ticks
    scripts      _physics_process callbacks, once per tick
    step         the engine's physics step and sync after the scripts, once per tick
```

Spans reported through `DotFrameCost` nest under the root that contains them and under each other by time, so `frame;physics;scripts;arena.bots;q.intersect_ray` is a ray cast by bots inside a physics tick. Work no span covers is the parent's `self_ms`. Tracing is on only while recording with `profiler_trace` 1.

## Folded stacks

`profile-<stamp>.folded` has one line per tree node, `path exclusive_microseconds`, summed over the recording:

```
frame;physics;step 581234
frame;physics;scripts;p_controller;q.cast_motion 120455
```

flamegraph.pl, inferno and speedscope read it as it is.

## Text sections

After the version 1 text come, in this order: `Frames (ms):`, `Physics ticks:` (with `ticks per frame:` and per-tick ms of the scripts and the engine step), `Engine monitors (per frame):`, `Growth over the recording`, `Groups (count per frame; ...)`, `Call tree (ms per frame; ...)`, `Script functions ...`, `Physics queries (...)` with `by caller span (traced):`, `Timeline (per second; ...)` with the flagged frames, `Worst frames (whole tree, ms incl / self):`, `Node census:`, `Profiler overhead:` and `Deep mode:`. Sections with no data are left out.

## Compare

`DotProfilerCompare.compare(a, b)`, the `profiler_compare [a.json b.json]` console command and `tools/profile_compare.py a.json b.json` print the same thing: B minus A in ms per frame, in sections `frame` (p50, p95, p99, worst), `phase`, `system`, `tree` and `query`, each sorted by the size of the change, then `group` (count and us per unit), `script` (self ms per function and bucket) and `monitor` (averages, in their own unit) when both reports have them. Version 1 reports compare on what they have.

`--diff` treats A as the saved baseline and prints only rows that moved by at least `--noise-pct` (5 by default, the run-to-run noise of a pinned box) percent of A, or that are new in B; `--min-abs` also drops changes smaller than that. In GDScript the same filter is `DotProfilerCompare.changed(rows, noise_pct, min_abs)`.

```
python3 tools/profile_compare.py before.json after.json --min-ms 0.1 --top 20
python3 tools/profile_compare.py baseline.json after.json --diff
python3 tools/profile_compare_test.py
```

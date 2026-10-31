# The headless runner

`res://addons/dot_profiler/tools/dot_profiler_run.tscn` loads a scene beside itself, waits out a warm-up, records it with a `DotProfiler` and prints:

- `PERF {json}`: `p50_ms`, `p95_ms`, `p99_ms`, `stall_ms` (worst frame), `spikes`, `frames`, `load_s`, `rss_mb`, `gpu`, `resolution`, `source`. This is the line the nightly perf budget already parses, so a game's `tools/perf_budget.sh --post` sends it to the `/qa` board's `perf` kind unchanged.
- `PROFILER {json}`: the report path, the scene, the budget, the spike count, spikes per cause with their period, and the top eight systems.
- The text report.

```bash
heavy -- timeout 120 godot --headless --path . res://addons/dot_profiler/tools/dot_profiler_run.tscn -- \
    --profile-scene res://tools/client_bench.tscn --profile-warmup 10 --profile-seconds 20 --profile-budget 16.7 \
    <the scene's own arguments>
```

| Argument | Default | Meaning |
| --- | --- | --- |
| `--profile-scene` | (required) | The scene to profile. |
| `--profile-warmup` | 5 | Seconds before recording starts. |
| `--profile-seconds` | 20 | Recording length. |
| `--profile-budget` | 33 | Spike threshold in ms. |
| `--profile-out` | user://profiles | Report directory. |
| `--profile-stay` | off | Do not quit when done. |

The scene's own arguments pass through untouched. Exit 0 when the report is written, 1 when it is not, 2 on bad arguments.

The scene is added beside the runner and made `current_scene` by hand; `change_scene_to_*` would free the runner with the old scene.

Headless, `gpu` is empty and `resolution` is `0x0`: frame times there measure scripts and physics only. Render cost needs a real GPU (the GPU boxes, through a game's `gpu.sh`).

`examples/spiky.tscn` is the CI target: one system costing 30 ms every half second, which the runner must name with its 0.50 s beat.

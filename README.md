# dot-profiler

Finds the cause of frame spikes. When a frame runs over budget it logs the system that took the time and what that system was doing, names a cause that repeats on a beat with its period, draws an overlay of the top costs, records a session to JSON and text reports, and runs headless for a nightly performance budget.

Part of the TMC Godot addon family. Depends on dot-core only (`DotFrameCost`, `DotHitchLog`, `DotSpaceQuery`, API level 30 or later). dot-console, dot-menu, dot-server and dot-server-query are reached by duck typing when present.

## Use

```gdscript
var prof := DotProfiler.new()
prof.config = DotProfilerConfig.new()
add_child(prof)
prof.bind_console(console_local)   # profiler_* cvars, record 30, profiler_stop, profiler_report
```

Systems report their cost:

```gdscript
var t := DotFrameCost.now()
_rebuild_paths()
DotFrameCost.add(&"navigation.rebuild", t, "%d paths" % n)
```

A spike then logs at WARN as, for example, `frame 41.2 ms over 33.0 ms budget: t=12.50s 41.2 ms  navigation.rebuild (52 paths)  [phys 1.0 script 38.1 render 1.5 wait 0.6] repeats every 0.50 s (7 of 7 gaps)`.

Everything is off by default: `profiler_enabled 1` watches, `profiler_overlay 1` draws, `record 30` writes `user://profiles/<stamp>.json`, `.txt` and `.folded`. `prof.enable_capture_key()` makes F10 start and stop a capture with the call tree, physics ticks and queries, engine monitors and the worst frames; `profiler_compare` diffs the two newest.

More detail when asked for, each off by default: `profiler_timeline 1` (every frame, spikes flagged with what ran in them), `profiler_render_detail 1` (texture and buffer memory, draw split, render cpu/gpu ms), `profiler_groups bots:arena.bot` (unit counts per frame and each system's cost per unit), `profiler_census 1` (node classes that grew), `profiler_script_top 30` (GDScript functions by self time with calls; run with `-d`) and `tools/profile_compare.py baseline.json new.json --diff` (only changes past the 5% noise floor). [docs/design.md](docs/design.md#configuration) lists them.

On a dedicated server, `DotProfilerServer.new().install(prof)` adds admin-only `sv_profiler_record`, `sv_profiler_stop`, `sv_profiler_status` and metric commands (frame, hitches, systems, memory, net, and all of them as one JSON line) to dot-server's console and RCON, the `profiler_*` cvars, and optional query keys. Recordings go to `<log_directory>/profiles`.

## Docs

- [docs/design.md](docs/design.md): the pieces, attribution, configuration and cvars, instrumenting a system.
- [docs/report-format.md](docs/report-format.md): the report's JSON keys, call tree, folded stacks, text sections and compare.
- [docs/deep-mode.md](docs/deep-mode.md): native samples with perf, and why perf over the alternatives.
- [docs/runner.md](docs/runner.md): the headless runner and its `PERF` line.
- [docs/menu.md](docs/menu.md): the settings menu's Performance section.
- [docs/server.md](docs/server.md): the dedicated server's commands, cvars and query keys.

## Testing

```bash
godot --headless --path . --import
godot --headless --path . res://examples/profiler_selftest.tscn
godot --headless --path . res://examples/profiler_detail_selftest.tscn
python3 tools/profile_compare_test.py
godot --headless --path . res://addons/dot_profiler/tools/dot_profiler_run.tscn -- --profile-scene res://examples/spiky.tscn --profile-seconds 4 --profile-budget 20
tools/screenshot.sh screenshots/demo.png
tools/screenshot.sh screenshots/menu_tab.png menu   # dot-menu's Advanced page with a profiler placed
```

## Licence

MIT, see [LICENSE](LICENSE).

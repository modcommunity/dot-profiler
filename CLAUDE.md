# dot-profiler

Names the system behind a frame spike, its period when it repeats, an overlay of top costs, recordings to `user://profiles`, and a headless runner for the perf budget.

**The distributable is `addons/dot_profiler/`.** It depends on dot-core only; dot-console (`bind_console`), dot-menu (`make_menu_panel(kit)`), dot-server and dot-server-query (`DotProfilerServer`) are duck-typed; the suite links dot-server and dot-server-query to run against a real console. Read the family [CLAUDE.md](../../CLAUDE.md) first.

## Read before

| Read | Before |
| --- | --- |
| [docs/design.md](docs/design.md) | changing attribution, periods, cvars or the report |
| [docs/runner.md](docs/runner.md) | changing the `PERF` / `PROFILER` lines (the nightly perf budget parses `PERF`) |
| [docs/menu.md](docs/menu.md) | changing the panel or how a menu finds it |
| [docs/server.md](docs/server.md) | changing `sv_profiler_*`, the server cvars or the query keys |

## Layout

| Path | What |
| --- | --- |
| `addons/dot_profiler/core/` | `dot_profiler_config.gd` (cvars, layers), `_period.gd` (the beat), `_report.gd` (JSON, text, list, prune), `dot_profiler_catalog.gd` (every recorded option as a toggleable row: label, group, cost; `strip` drops switched-off sections from a report), `dot_profiler_net.gd` (smoothed KB/s from the metered peer, for the merged graph) |
| `addons/dot_profiler/runtime/dot_profiler.gd` | the node: owns a `DotHitchLog`, attributes spikes, records, registers `&"dot_profiler"` |
| `addons/dot_profiler/runtime/dot_profiler_scripts.gd` | `profiler_script_top`: the engine's script profiler (needs `-d`), its accumulated table caught by a `Logger` and parsed into functions, scripts and buckets |
| `addons/dot_profiler/runtime/dot_profiler_server.gd` | `sv_profiler_*` on dot-server's console and RCON, server samples, the query provider |
| `addons/dot_profiler/core/dot_profiler_metrics.gd` | engine monitors (frame, memory) and network bytes (a `DotMeteredPeer`, or ENet host statistics) |
| `addons/dot_profiler/ui/` | `dot_profiler_overlay.gd`, `dot_profiler_panel.gd`, `dot_profiler_graph.gd` (solid stacked area chart by band, Y legend of band start ms; cvars profiler_graph, _graph_height, _graph_scale_ms, _graph_frames, _graph_legend; data ring in core/dot_profiler_graph_data.gd), `dot_profiler_catalog_view.gd` (the list of everything it records), `dot_profiler_window.gd` (the panel over the game on Shift+F10, a dot_pointer_modal); look cvars `profiler_overlay_*`, `profiler_graph_col_px`, `profiler_overlay_merge_net` (net lines drawn in the profiler graph, dot-menu's NetStat text hidden meanwhile); prefs saved to user://profiler_ui.cfg |
| `addons/dot_profiler/tools/dot_profiler_run.*` | the headless runner |
| `examples/` | `profiler_selftest` (the suite), `profiler_ui_selftest` (menu, catalog, look options, merge, prefs), `profiler_trace_selftest`, `profiler_detail_selftest` (timeline, groups, census, script functions, compare --diff), `profiler_demo` (what the screenshot renders), `spiky` (the runner's CI target) |
| `tools/profile_compare.py` | compare two report JSONs; `--diff` for changes above the noise floor; tested by `tools/profile_compare_test.py` |
| `tools/screenshot.sh`, `tools/menu_tab_shot.gd` | render the demo, or (`menu`) dot-menu's Advanced page with a profiler placed, under Xvfb |

## Rules that bite

- **Exactly one reader drains `DotFrameCost` per frame.** `DotHitchLog` does while enabled; never call `take()` elsewhere while a profiler runs.
- **`DotWeb.available()` is true on desktop** (the JavaScriptBridge singleton exists everywhere). Choose browser UI with `DotPlatform.is_web()`.
- **The runner adds the scene beside itself**; `change_scene_to_*` would free it.
- **`DotProfilerMetrics.net` drains ENet's host statistics** (`pop_statistic` resets them). Nothing else may pop them, and one `DotProfilerMetrics` per peer.
- Never name a dot-server or dot-server-query class in `addons/`; only the suite may.
- Headless frame times have no render cost; profile rendering on a GPU box.
- Every Godot run goes through `heavy -- timeout N`.

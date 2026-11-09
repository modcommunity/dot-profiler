# Deep mode

The call tree stops where the game's own spans stop. When the time is inside the engine (the physics step, a query, the renderer) and the tree's `step` or `self_ms` is not enough, deep mode samples native stacks for the length of the recording.

## The choice

| Option | Gives | Cost | Verdict |
| --- | --- | --- | --- |
| Godot's built-in profiler | Script functions and the engine's frame phases, in the editor | Needs the editor's debugger attached; a custom `EngineProfiler` only runs with it | Not for players' or servers' builds, so not used. |
| Linux `perf` | Native stacks of every thread, engine and driver included, at a fixed rate | Nothing inside the game; needs perf installed and `kernel.perf_event_paranoid` 2 or less | Chosen: no engine change, attaches to any running build. |
| Tracy | Exact zones with a live viewer | A custom engine build with Tracy compiled in, and a viewer | Worth it only for a long engine investigation; the same symbols build below is the starting point. |

## Turning it on

Set `profiler_deep 1` (or `--profiler-deep=1`). Each recording then runs

```
perf record -g -F 999 -p <game pid> -o <record_dir>/perf-<time>.data -- sleep <seconds>
```

and perf stops on its own. The report's `deep` key and the `Deep mode:` text line name the file, or say why it could not start (not Linux, perf not installed, paranoid level too high).

Read the samples with:

```
perf report -i perf-<time>.data --no-children
perf script -i perf-<time>.data | inferno-collapse-perf | inferno-flamegraph > engine.svg
```

## Symbols

The official engine binary is stripped, so its frames show as addresses. For named engine frames build the engine with symbols on the build VM, not a developer machine:

```
scons platform=linuxbsd target=template_release debug_symbols=yes production=yes
```

and run the game with that binary for the deep recording. The same source tree is where a Tracy build would start.

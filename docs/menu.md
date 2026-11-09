# Settings menu integration

dot-profiler does not depend on dot-menu, and dot-menu does not depend on dot-profiler. A `DotProfiler` registers itself in `DotRegistry` as `&"dot_profiler"` (`register_as_service`, on by default). A menu that finds that service and sees `make_menu_panel` on it adds a Performance section built by `make_menu_panel(kit)`, passing its `DotMenuKit` so the panel matches the menu's theme. With no profiler placed, the section is not shown.

The panel holds:

- the overlay toggle;
- Record / Stop, with the elapsed time while recording;
- "Saved to <path>" once a report is written;
- on desktop, Open folder and Copy path; in the browser, Download report (every write and prune already calls `DotWeb.sync_filesystem()`, so the file survives a reload);
- the recent recordings, newest first.

Reports are a JSON file and a text file per recording in `profiler_record_dir` (`user://profiles`), the oldest deleted beyond `profiler_keep_recordings`.

Any other menu can do the same: look the service up, call `make_menu_panel(kit_or_null)`, and add the returned `Control`.

## Recording and look options

The Performance panel has a seconds box (any value, default 30), a "What does it record" button that opens the catalog of every recorded item with its cost, and a switch per item (frame stats, spikes, systems, phases, physics ticks, queries, growth, overhead); "Cheap set" and "All on" are presets. Switched-off sections are left out of the report. The detail options (groups, spikes, timeline, render detail, node census, script functions, --diff) stay in the runner and the report tools.

"Overlay and graph look" sets text, text size, scale, corner, offset, opacity, background opacity and graph column width. "Merge net graph" draws the in and out KB/s of the metered peer inside the profiler graph and hides dot-menu's net readout while both are shown. The defaults are small and translucent. Look settings persist in `user://profiler_ui.cfg`. The profiler stays off by default, and the net sampler only runs when overlay, graph and merge are all on.

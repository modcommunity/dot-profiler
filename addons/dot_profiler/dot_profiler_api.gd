extends RefCounted

## dot-profiler's API level. The rule for bumping it is on [DotAddonApi].

# 1: DotProfiler, DotProfilerConfig, DotProfilerPeriod, DotProfilerReport, DotProfilerOverlay, DotProfilerPanel.
# 2: DotProfilerTree, DotProfilerSession, DotProfilerTicks, DotProfilerCompare, DotProfilerDeep, DotProfilerReportText, report v2, capture key, profiler_capture/compare.
const LEVEL := 2
const OLDEST := 1

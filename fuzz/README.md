# Fuzzers and brute-force oracles

Long-running randomized and exhaustive checks that compare VirtualTime's
arithmetic and materialization against brute-force ground truth. They are too
slow for `crystal spec`, so they live here and are meant for release checks or
a nightly CI job.

Run all of them with:

```sh
fuzz/run.sh
```

or one at a time with `crystal run --release fuzz/<name>.cr`.

| File | What it checks |
|------|----------------|
| `fuzz1.cr` | Earliest-match materialization (`to_time`) vs minute-level `matches?` scans across day/month/week/dow/doy/hour/minute rules incl. negatives |
| `fuzz2.cr` | Same, with StepIterators, Procs and mixed-sign values at second granularity |
| `fuzz3.cr` | `strict: false`, past-pinned years, fixed-offset locations |
| `fuzz4.cr` | DST-transition-biased invariants (Europe/Berlin) and millisecond rules |
| `fuzz_succ.cr` | `succ`/`step` chains: no skipped matches, `by:` consistency |
| `rangehelper_brute.cr` | `RangeHelper` step arithmetic vs `StepIterator#to_a` (~119k cases) |
| `range_last_intersect_brute.cr` | `RangeHelper.last`/`intersect?` vs `Range#to_a` (~115k cases) |
| `rangehelper_random_big.cr` | Randomized large-magnitude bounds (overflow hunting, ~123k cases) |
| `search_bounds.cr` | `Search.shift_from_base`/`shifted_from_base?` bound semantics |

# Performance and resource checks

BinSchema separates deterministic correctness checks from environment-sensitive performance
records. Unit tests enforce exact results and configured resource limits on every backend. Native
resource probes exercise larger workloads and record elapsed time plus peak resident memory.

## CI resource smoke

Run the Ubuntu smoke suite from the repository root:

```bash
bash scripts/resource-smoke.sh
```

The suite builds release-mode Native executables and covers four resource-sensitive paths:

| Scenario | Workload | Stable gate |
| --- | --- | --- |
| `large-input` | Decode a borrowed 32 MiB byte region | Exact consumed size and successful decode |
| `elf-repeated-names` | 4,096 sections reference one 8 KiB ELF name | Section/name consistency and bounded cached expansion |
| `short-frames` | Drain 50,000 two-byte frames from one buffered append | Frame order, count, and empty final buffer |
| `many-traces` | Decode 80,000 named fields and retain 160,000 trace entries | Exact value and trace counts |
| `cli-input-limit` | Read a sparse 64 MiB + 1 byte file | Rejection with the documented data-error exit code |

Each probe prints one JSON workload record. The wrapper prints a second JSON record containing
`elapsed_seconds`, `max_rss_kib`, and `exit_code`. Elapsed time is evidence only: the smoke suite
does not compare it with a threshold because shared CI runners are noisy. Peak RSS has a deliberately
broad 768 MiB default ceiling intended only to catch catastrophic allocation regressions. Override it
with `RESOURCE_MAX_RSS_KIB`; set `RESOURCE_ENFORCE_RSS=0` when collecting unrestricted local data.

The CLI case uses a sparse file, but the bounded reader still observes 64 MiB + 1 byte through the
normal read path. A file-size metadata check alone therefore cannot make this test pass.

The main CI workflow runs this smoke suite on every change. The weekly
`continuous-verification.yml` workflow also runs fixed regression seeds plus a reproducible seed
derived from the workflow run id, then uploads the raw JSONL measurements together with the commit,
toolchain, operating system, and CPU description.

## Benchmark records

The existing zero-copy microbenchmark remains available with:

```bash
moon bench --target native --release
```

For an auditable resource record without an RSS gate, use:

```bash
RESOURCE_ENFORCE_RSS=0 bash scripts/resource-smoke.sh | tee resource-results.jsonl
```

Record the MoonBit version (`moon version --all`), operating system, CPU, commit SHA, and raw JSONL
alongside any published result. Compare repeated runs on the same machine and toolchain; do not turn
single-run elapsed times into correctness claims.

On Windows, build `benchmarks/resource_probe` and run its four scenario arguments directly. Windows
PowerShell does not provide GNU `/usr/bin/time`, so peak RSS collection should use an equivalent
process monitor and retain the same JSON field names.

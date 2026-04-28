# revive-bench

Benchmark harness for [revive](https://github.com/mgechev/revive), inspired by [ldez/golangci-lint-bench](https://github.com/ldez/golangci-lint-bench).

This repository uses [Hyperfine](https://github.com/sharkdp/hyperfine) for local benchmark runs.

## What this bench measures

For each repository listed in a targets file, the bench runs:

```bash
revive -config configs/revive-bench.toml ./...
```

You can run:

- single-binary timing (candidate only)
- A/B comparison timing (baseline vs candidate)

Results are written to:

- `results/*.json` (raw Hyperfine data)
- `results/*.md` (ready-to-read markdown tables)

## Local usage

### 1) Prerequisites

- Go installed
- Hyperfine installed

On macOS:

```bash
make install-hyperfine
```

### 2) Prepare benchmark targets

```bash
make setup-targets
```

Target profiles:

- fast: [targets/repos-fast.txt](targets/repos-fast.txt)
- all: [targets/repos-all.txt](targets/repos-all.txt)

`make setup-targets` uses the fast profile by default.

### 3) Build revive binaries

Build baseline from an upstream tag/ref:

```bash
make install-base BASE_REF=v1.15.0
```

Build candidate from local HEAD (requires revive repository checked out):

```bash
make install-candidate CANDIDATE_REF=HEAD
```

Build candidate from upstream ref (branch or tag):

```bash
make install-candidate CANDIDATE_REF=master
```

Install from a custom revive repository (module path or GitHub URL):

```bash
make install-base REVIVE_MODULE=https://github.com/alexandear/revive BASE_REF=v1.15.0
make install-candidate REVIVE_MODULE=https://github.com/alexandear/revive CANDIDATE_REF=master
```

Equivalent module-path form:

```bash
make install-candidate REVIVE_MODULE=github.com/alexandear/revive CANDIDATE_REF=master
```

If a fork keeps `module github.com/mgechev/revive` in `go.mod`, `go install <fork>@<sha>` may fail with a module-path mismatch.
In that case, the Makefile automatically falls back to cloning the repository at the requested ref and running `go install .`.

Build candidate from a PR commit SHA:

```bash
# Copy the commit SHA from the PR's commit list
make install-candidate CANDIDATE_REF=f749dc6dc45c77f72c79cb9c7dea0e57a6507a84
```

This works for any git ref: tags, branches, or full/short commit SHAs that are available to `go install`.

### Quick start: Complete workflows

**Fastest run (fast profile, compare v1.7.0 vs master):**

```bash
make install-hyperfine
make setup-targets
make install-base BASE_REF=v1.15.0
make install-candidate CANDIDATE_REF=master
make bench-compare
```

**Benchmark your local revive changes against v1.7.0:**

```bash
# From your revive repository root:
make setup-targets -C /path/to/revive-bench
make install-base BASE_REF=v1.15.0 -C /path/to/revive-bench
make install-candidate CANDIDATE_REF=HEAD -C /path/to/revive-bench
make bench-compare-fast -C /path/to/revive-bench
```

**Using custom revive binaries:**

```bash
./scripts/bench.sh \
  --base-bin /path/to/revive-base \
  --candidate-bin /path/to/revive-candidate \
  --targets-file targets/repos-fast.txt
```

### 4) Run benchmark

**Fast profile (default, quicker set):**

```bash
make bench
```

Compare baseline vs candidate:

```bash
make bench-compare
```

**Full profile (all repositories, takes longer locally):**

```bash
make setup-targets-all
make bench-all
```

Compare with full profile:

```bash
make bench-compare-all
```

**Explicit profile control:**

```bash
make bench-fast
make bench-compare-fast
```

### 5) Check for regression: count issues

To ensure your changes don't introduce or remove linting issues, count issues in target repositories:

Count issues with candidate binary (fast profile):

```bash
make issues
```

Count issues with candidate binary (all profile):

```bash
make issues-all
```

Compare issue counts between baseline and candidate (tracks regressions):

```bash
make issues-compare
```

Full profile comparison:

```bash
make issues-compare-all
```

The output shows a table with issue counts per repository and a total. This helps detect if your changes make revive stricter or looser.

Each run also writes per-repo issue details to text files so you can diff exact findings:

- fast baseline: [results/issues/fast/baseline](results/issues/fast/baseline)
- fast candidate: [results/issues/fast/candidate](results/issues/fast/candidate)
- all baseline: [results/issues/all/baseline](results/issues/all/baseline)
- all candidate: [results/issues/all/candidate](results/issues/all/candidate)

Example comparison:

```bash
diff -u results/issues/fast/baseline/revive.txt results/issues/fast/candidate/revive.txt
```

## Tips for comparing results

**Performance:** `make bench-compare` gives execution time deltas.
**Correctness:** `make issues-compare` shows if issue counts changed (possible regression).
**Both:** Run both to understand if your changes improved performance without changing linting behavior.

## Customize targets

Edit [targets/repos-fast.txt](targets/repos-fast.txt) and/or [targets/repos-all.txt](targets/repos-all.txt) with:

```text
# name repository ref
name https://github.com/org/repo.git branch-or-tag
```

Keep the list manageable for local runtime. Start with 3-5 repositories of different sizes.

## Tips for stable measurements

- Run on idle machines.
- Keep CPU power mode consistent.
- Use the same target repository refs.
- Use enough runs (10+ locally when possible).

# Release process

Use this checklist for every published BinSchema release.

## 1. Prepare

1. Choose the next Semantic Versioning version.
2. Move relevant `CHANGELOG.md` entries from **Unreleased** into a dated release section.
3. Update `version` in `moon.mod`.
4. Review `docs/COMPATIBILITY.md` and add migration notes for intentional compatibility changes.

## 2. Verify

Run the same gates used by CI:

```bash
moon update
moon info
git diff --exit-code
moon doc
moon package --list
moon check --target all --deny-warn
moon test --target all --deny-warn
moon test README.mbt.md --target native --deny-warn
moon bench --build-only --target native --deny-warn
moon test --target native --enable-coverage --deny-warn
moon coverage analyze
moon fmt --check
cmp README.md README.mbt.md
moon build --target native cmd/main --release
moon build --target native examples/custom_packet --release
moon build --target wasm-gc web/bridge --release
```

If `moon coverage analyze` exits with an internal reporter assertion on Windows after the
coverage-enabled tests pass, verify the instrumented library packages separately:

```bash
moon coverage analyze -p prowk/binschema
moon coverage analyze -p prowk/binschema/formats
```

The aggregate coverage run in the Ubuntu GitHub Actions job remains the release gate.

Inspect `moon package --list` before publishing. The root `.moonignore` is the source of truth
for repository-only files that must not enter the release archive.

`web/binschema.wasm` is a generated artifact: build it from `web/bridge` for local use or Pages
deployment, but do not commit it to source control.

For performance-sensitive releases, also run:

```bash
moon bench --target native --release
```

Benchmark numbers are evidence for the machine/toolchain where they were measured, not a
cross-machine performance guarantee.

## 3. Publish

1. Merge the release PR only after the required GitHub Actions `test` check is green.
2. Create an annotated tag matching the release version (for example, `v0.3.0` for version `0.3.0`) on the release commit.
3. Publish the MoonBit module using the normal registry release flow.
4. Create a GitHub Release from the same tag and copy the relevant changelog section.
5. Verify a clean consumer project can install the released version and compile a minimal codec.

## 4. After release

- Confirm the GitHub Pages playground deployment succeeded.
- Keep **Unreleased** at the top of `CHANGELOG.md` for the next development cycle.
- If a regression is discovered, add a focused corpus/property test before shipping the fix.

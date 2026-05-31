# Build Notes

Platform/toolchain gotchas and their workarounds. Loaded on demand.

## `path_provider_foundation` + `objective_c` breaks Windows builds

**Symptom:** `flutter build windows` fails while compiling a native asset hook.

**Cause:** Flutter compiles native asset hooks for *all* platforms when building for one. `path_provider_foundation >=2.4.3` depends on `objective_c >=9.0.0`, whose `hook/build.dart` uses macOS-only API (`OS.iOS`, `OS.macOS`) that fails to compile on Windows.

**Bug report:** [dart-lang/native#2480](https://github.com/dart-lang/native/issues/2480) — "[hooks] Exclude a platform from being built by dependency's build hook". Open, milestone: Native Assets v1.x.

**Workaround (active):** `pubspec.yaml` pins via `dependency_overrides`:

```yaml
dependency_overrides:
  path_provider: 2.1.5
  path_provider_foundation: 2.4.2
```

`path_provider_foundation 2.4.2` uses MethodChannel instead of FFI, so it doesn't pull in `objective_c`.

**Periodic check (every few weeks):**
1. Remove the `dependency_overrides` block from `pubspec.yaml`.
2. `flutter pub upgrade path_provider path_provider_foundation`
3. `flutter build windows`
4. If it passes — drop the override and delete this section.
5. If it fails — restore the override and run `flutter pub get`.

**Checked 2026-05-31 (Flutter 3.44.0):** `path_provider_foundation 2.6.0` — still broken.
Hook folder is gone from the repo, but `objective_c`/`hooks` transitively still
triggers "Building native assets failed" on Windows. Override stays.

---
name: upgrade-dotnet-packages
description: Upgrade ALL NuGet packages to their latest compatible versions.
argument-hint: "[solution-or-project path] [--dry-run]"
---

# Upgrade NuGet Packages

Run the bundled `cpm-update.ps1` to bump every `<PackageVersion>` in `Directory.Packages.props` to the newest compatible version, then build the target solution/project and fix any issues the bumps introduce.

This skill assumes the repo uses **Central Package Management** (`Directory.Packages.props` with `ManagePackageVersionsCentrally=true`) and, typically, lock files (`RestorePackagesWithLockFile=true`).

## Arguments

- **`$1` (optional)** — path to the `.sln`/`.slnf`/`.csproj` to use for post-update build validation. If omitted, locate it: prefer a `.sln` at the repo root, otherwise ask the user which solution/project to validate against.
- **`--dry-run`** — preview the proposed bumps without writing or building.

## Context

- `cpm-update.ps1` (in this skill's `scripts/` folder) is a **PowerShell 7+** script — invoke it with `pwsh`, not `bash`. It probes nuget.org in parallel, filters candidates by TFM compatibility, transitive-dependency (NU1605) constraints, AssemblyVersion regressions, and ABI breaks, then writes the surviving bumps to `Directory.Packages.props`.
- After writing, the script runs `dotnet restore --force-evaluate` (refreshing every `packages.lock.json`, required by Central Package Management) and `dotnet build`, auto-reverting bumps whose errors name a package and retrying until the build is clean.
- You MUST pass `-ValidateTarget <solution-or-project>` explicitly, otherwise restore + build validation is silently skipped and broken bumps land unverified.
- The project TFM auto-detects from any `*.Common.props` next to `Directory.Packages.props`; if none is found, the TFM compatibility check is disabled (the build still validates the bumps).
- `-PropsPath` is auto-located by walking up from the script's directory to the nearest `Directory.Packages.props`; pass it explicitly only if the repo has more than one. Both `-PropsPath` and `-ValidateTarget` accept relative paths (resolved against the current directory) or absolute paths.

## Steps

1. **Locate the props file and validation target.** Find `Directory.Packages.props` (usually the repo root) and the solution/project to validate against (`$1`, or the repo-root `.sln`). If neither props nor a build target can be found, stop and tell the user.

2. **Confirm a clean working tree.** Run `git status`. The only file the script should modify is `Directory.Packages.props` (plus regenerated `packages.lock.json` files). Pre-existing unrelated changes make it hard to tell what the upgrade touched — surface them to the user first.

3. **Run the upgrade with build validation** (substitute your actual paths):

   ```powershell
   pwsh <skill-dir>/scripts/cpm-update.ps1 -ValidateTarget <solution-or-project> [-PropsPath <path-to-Directory.Packages.props>]
   ```

   The script reports `Updated (N)`, anything `Held back by transitive constraints`, and a final `Net updated: X of N proposed bumps survived build validation`. If it auto-reverted bumps, it lists them under `Reverted (N)`.

   Use `-DryRun` first if the user only wants to preview what would change (no writes, no build).

4. **Read the script's final output carefully.**
   - **Exit 0, "Build succeeded"** → the upgrade is complete and verified. Report which packages were bumped (and which were held back / reverted, if any).
   - **Exit 1, "Build still failing after N rounds"** → the script's auto-revert couldn't isolate the offending bump (typically a source-level API break that no error line attributes to a package). Proceed to step 5.

5. **Fix remaining build breakages.** If the build still fails after the script's auto-revert rounds:
   - Run the build yourself to see the full errors: `dotnet build <solution-or-project>`.
   - For each error, decide: **fix the code** to the new API (preferred when the upgrade is intentional and the migration is small), or **revert that single package** in `Directory.Packages.props` to its prior version if the breaking change isn't worth absorbing now.
   - If you revert a package version by hand, regenerate the lock files: `dotnet restore <solution-or-project> --force-evaluate` (never edit `packages.lock.json` by hand).
   - Re-build until clean. Follow the repo's own coding guidelines for any code changes.

6. **Report the result.** Summarize: packages bumped (from → to), packages held back or reverted (with the script's reason), and any code changes you made to absorb breaking API changes. Do **not** commit or push unless the user asks.

## Notes

- **Never edit `packages.lock.json` by hand** — always regenerate via `dotnet restore --force-evaluate`.
- The script caps probing to the newest 25 candidates per package and iterates to a fixed point across rounds; packages held back by transitive constraints are expected, not failures — report them but don't force them.
- If the repo has a frontend/client build coupled to the solution that you don't need for validating backend package bumps, pass the build a skip property (e.g. `dotnet build <sln> --property:SkipClient=true`) when running the build yourself in step 5 — the package upgrade itself is backend-only. Check the repo's build conventions for the right property.
- Prefix the command with `proxy` (e.g. `proxy pwsh <skill-dir>/scripts/cpm-update.ps1 ...`) only if you need the full untruncated build output to diagnose a failure.

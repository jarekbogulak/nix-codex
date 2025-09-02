# nix-codex

A Nix flake that packages the Codex CLI (Node.js wrapper + Rust native binary) so you can build, run, and install it with Nix.

## Overview
- Builds the Codex CLI from the upstream `openai/codex` repo pinned in `flake.lock`.
- Produces a single executable `codex` via a small Node wrapper that delegates to the platform-specific Rust binary.
- Provides a `devShell` with `codex` and build tools on `PATH`.

## Prerequisites
- Nix with flakes enabled
- A supported system: `x86_64-linux`, `aarch64-linux`, `x86_64-darwin`, or `aarch64-darwin`

## Quick Start
- Build: `nix build` (or `nix build .#codex-cli`)
- Run built binary: `./result/bin/codex --help`
- Install to your profile: `nix profile install .#codex-cli`
- Dev shell (adds `codex` to PATH): `nix develop`

## Updating sources
- Update only Codex source: `nix flake lock --update-input codex-src`
- Update all inputs: `nix flake update`
- To pin a specific Codex release, edit the input URL in `flake.nix:10` (e.g., `github:openai/codex?ref=vX.Y.Z`) and re-lock.

## Notes on the build
- This derivation invokes `npm` for the JS wrapper and `cargo` for the Rust CLI.
- The wrapper places the native binary at the path expected by the Node launcher and creates a few compatibility symlinks for common triples.
- For fully hermetic Nix builds, consider vendoring dependencies or moving to a Nix-native Rust/Node builder; this flake intentionally keeps things simple.

## File of interest
- Edit inputs or behavior in `flake.nix:1`.

## Why this flake?
- Avoids manual multi-language setup (Node + Rust) and gives a repeatable, one-command build and install of the Codex CLI.


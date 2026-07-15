# nix-templates

A collection of Nix flake templates for reproducible development environments.

## Prerequisites

- Nix with flakes enabled
- (Optional) direnv for automatic environment activation

## Available templates

### `r-project` — R + Quarto development environment

R environment with R.nvim/Neovim integration and Quarto support.

**Includes:** R, quarto (patched), arf, jarl, nvimcom, httpgd, data.table, rmarkdown, downlit, xml2, sessioninfo

```bash
nix flake init -t github:PMassicotte/nix-templates#r-project
```

The `quarto` CLI is patched for two upstream issues that otherwise break most
renders:

- [NixOS/nixpkgs#519484](https://github.com/NixOS/nixpkgs/issues/519484):
  quarto 1.9.x emits the pandoc defaults key `syntax-highlighting`, but the
  pandoc bundled in nixpkgs only understands `highlight-style`, so any render
  crashes with `Unknown option "syntax-highlighting"`.
- A related `jog.lua` crash (`Don't know how to traverse TableBody`) on any
  page with a `gt()`/`kable()` table, from the same nixpkgs pandoc/quarto
  version mismatch.

`nvimcom` is built and baked directly into `R_LIBS_SITE` rather than left to
R.nvim's own auto-install into `.r-libs/`: that auto-install path is timing
sensitive (R.nvim sets `R_DEFAULT_PACKAGES` before starting R, and that
lookup happens before `R_LIBS_USER` is reliably in effect), so it can
intermittently print `package 'nvimcom' ... was not found` even when
`nvimcom` is present.

If you add the R `quarto` package to your own package list, reference it as
`final.rPackages.quarto` explicitly — the overlay already defines a
top-level `quarto` for the CLI, and Nix's lexical scoping means a bare
`quarto` inside a `with final.rPackages; [...]` list would silently resolve
to the CLI derivation instead of the R package.

---

### `r-package-dev` — R package development

Full-featured environment for developing R packages with Nix reproducibility.

**Includes:** devtools, roxygen2, testthat, usethis, pkgdown, rcmdcheck, urlchecker, arf, jarl, httpgd

```bash
nix flake init -t github:PMassicotte/nix-templates#r-package-dev
```

---

### `rust-cli` — Rust CLI

Rust CLI project using crane (build) and rust-overlay (toolchain).

**Includes:** cargo, clippy, rustfmt, rust-analyzer (stable latest, pinned)

```bash
nix flake init -t github:PMassicotte/nix-templates#rust-cli
```

After init, rename the package in `Cargo.toml` from `my-cli` to your project name.

#### Commands

| Command                  | What it does                          |
| ------------------------ | ------------------------------------- |
| `nix build`              | Compile the project                   |
| `nix run`                | Build and run                         |
| `nix develop`            | Enter dev shell                       |
| `nix profile install .#` | Install binary to your PATH           |
| `nix flake update`       | Update all inputs (Rust, crane, etc.) |

---

### Working on existing (non-flake) Rust projects

If you fork a project that doesn't use Nix, you can still use this template's dev environment without polluting the upstream repo.

1. Copy `flake.nix` and `.envrc` from this template into the project root.
2. Exclude them from git using your local gitignore (so they never appear in your PR):

```bash
echo "flake.nix" >>.git/info/exclude
echo "flake.lock" >>.git/info/exclude
echo ".envrc" >>.git/info/exclude
```

3. Activate the environment:

```bash
direnv allow
# or
nix develop
```

The Rust toolchain is now available and `cargo` will use the project's own `Cargo.toml` as usual.

---

## Common to all templates

After `nix flake init`:

```bash
direnv allow # activate automatically with direnv (recommended)
# or
nix develop # enter the shell manually
```

Run `nix flake update` periodically to update pinned dependencies.

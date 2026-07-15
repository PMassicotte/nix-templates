{
  description = "Nix flake templates";

  outputs =
    { self }:
    {
      templates = {
        r-project = {
          path = ./templates/r-project;
          description = "R + Quarto development environment with R.nvim integration";
          welcomeText = ''
            # R + Quarto Nix Development Environment

            ## Getting started
            - Run `direnv allow` to activate the environment (if using direnv)
            - Enter the shell with `nix develop`

            ## Package layout
            - `ideRPackages`     — editor support (nvimcom, httpgd, data.table); rarely changed
            - `quartoRPackages`  — Quarto integration (rmarkdown, downlit, xml2, sessioninfo, quarto); rarely changed
            - `projectRPackages` — analysis packages (cli, fs); edit per project

            ## What's included
            - R with nvimcom, httpgd, data.table, cli, fs, and Quarto support
            - quarto CLI, patched for https://github.com/NixOS/nixpkgs/issues/519484
              (pandoc "syntax-highlighting"/"highlight-style" mismatch) and a related
              jog.lua table-rendering crash
            - arf (modern Rust-based R console)
            - jarl (fast R linter)
            - nvimcom baked directly into R_LIBS_SITE (not left to R.nvim's
              auto-install into .r-libs/, which is timing-sensitive and can
              intermittently print "package 'nvimcom' ... was not found")
          '';
        };

        r-package-dev = {
          path = ./templates/r-package-dev;
          description = "R package development environment with devtools, nvimcom, and R.nvim integration";
          welcomeText = ''
            # R Package Development Template

            ## Getting started
            1. Edit flake.nix: Add your DESCRIPTION Imports to `runtimeDeps`
            2. Edit flake.nix: Add your DESCRIPTION Suggests to `devPackages`
            3. Run `direnv allow` (if using direnv) or `nix develop`

            ## What's included
            - R with devtools, roxygen2, testthat, usethis, pak, and pkgdown
            - arf (modern Rust-based R console)
            - jarl (fast R linter)
            - R_QPDF set for R CMD check
          '';
        };

        rust-cli = {
          path = ./templates/rust-cli;
          description = "Rust CLI with crane and rust-overlay";
          welcomeText = ''
            # Rust CLI Nix Template

            ## Getting started
            - Edit `Cargo.toml` and rename the package from `my-cli` to your project name
            - Run `nix develop` to enter the dev shell (cargo, clippy, rustfmt, rust-analyzer included)
            - Run `nix build` to compile
            - Run `nix run` to run directly
            - Run `nix profile install .#` to install the binary to your PATH

            ## Updating dependencies
            - Add Cargo deps to `Cargo.toml` as normal
            - Run `nix flake update` to update the Rust toolchain and crane
          '';
        };
      };
    };
}

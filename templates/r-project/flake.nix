{
  description = "A Nix-flake-based R + Quarto development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  inputs.rNvim = {
    url = "github:R-nvim/R.nvim";
    flake = false;
  };

  outputs =
    { self, ... }@inputs:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forEachSupportedSystem =
        f:
        inputs.nixpkgs.lib.genAttrs supportedSystems (
          system:
          f {
            pkgs = import inputs.nixpkgs {
              inherit system;
              overlays = [ inputs.self.overlays.default ];
            };
          }
        );
    in
    {
      overlays.default = final: prev: rec {
        rPackages = prev.rPackages // {
          # rPackages.quarto (the R wrapper around the quarto CLI) propagates a
          # `quarto` build input for its SystemRequirements, whose pname also
          # happens to be "quarto". rWrapper's package-set assembly dedupes by
          # pname, so that propagated CLI copy silently shadows the actual R
          # library and `library(quarto)` fails with "no package called
          # 'quarto'" even though it's listed in quartoRPackages below. Drop
          # the propagated CLI dep — the nixpkgs `quarto` CLI is already put
          # on PATH directly via devShells' `packages`, so nothing is lost.
          quarto = prev.rPackages.quarto.overrideAttrs (old: {
            propagatedBuildInputs = builtins.filter (p: (p.pname or "") != "quarto") (
              old.propagatedBuildInputs or [ ]
            );
          });

          # R.nvim's communication package, baked directly into R_LIBS_SITE.
          # R.nvim sets R_DEFAULT_PACKAGES (including "nvimcom") before
          # starting R; that lookup happens very early in R's startup,
          # before R_LIBS_USER is reliably in effect, so relying on
          # R.nvim's own auto-install into R_LIBS_USER intermittently
          # prints "package 'nvimcom' ... was not found". Baking it into
          # R_LIBS_SITE avoids the timing issue entirely.
          nvimcom = prev.rPackages.buildRPackage {
            pname = "nvimcom";
            version = "unstable";
            src = inputs.rNvim;
            sourceRoot = "source/nvimcom";

            meta = {
              description = "R.nvim communication package";
              homepage = "https://github.com/R-nvim/R.nvim";
              maintainers = [ ];
            };
          };
        };

        # IDE packages — required by R.nvim editor features, stable across projects
        ideRPackages = with final.rPackages; [
          nvimcom # R.nvim <-> Neovim communication
          httpgd # hgd_browse keymap in r.lua
          data_table # view_df save_fun uses data.table::fwrite
        ];

        # Quarto-integration packages — stable across projects.
        quartoRPackages = with final.rPackages; [
          rmarkdown
          downlit # code-link: true support
          xml2 # downlit dependency
          sessioninfo # sessioninfo::session_info() in report footers
          quarto # quarto::quarto_render()/quarto_preview() from an R session
        ];

        # Project packages — specific to this analysis, the reproducible core
        # Edit this list per project
        projectRPackages = with final.rPackages; [
          cli
          fs
        ];

        rPackageList = ideRPackages ++ quartoRPackages ++ projectRPackages;

        # Create rWrapper with packages (for LSP and R.nvim)
        wrappedR = final.rWrapper.override { packages = rPackageList; };

        # arf (modern Rust-based R console, from nixpkgs) wrapped with the same
        # R packages as wrappedR. Named separately: overriding `arf` itself
        # would make arfWrapper wrap itself (infinite recursion).
        wrappedArf = final.arfWrapper.override { packages = rPackageList; };

      };

      devShells = forEachSupportedSystem (
        { pkgs }:
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              wrappedR # R with packages for LSP
              quarto # quarto CLI, for `quarto render`/`quarto preview`/`quarto publish`
              wrappedArf # arf with the same R packages as wrappedR
              jarl # fast R linter (from nixpkgs)
            ];

            # Needed so `quarto render`/`preview` picks up the Nix-provided R
            # with the right packages rather than whatever `R` is on PATH.
            env.QUARTO_R = "${pkgs.wrappedR}/bin/R";

            shellHook = ''
              export R_HOME=$(R RHOME)
              export R_LIBS_SITE=$(strings "$(command -v R)" | grep -oP '/nix/store/[^:]+/library' | sort -u | paste -sd: -)
              export R_LIBS_USER="$PWD/.r-libs"
              mkdir -p "$R_LIBS_USER"
            '';
          };
        }
      );
    };
}

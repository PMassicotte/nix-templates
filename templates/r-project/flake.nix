{
  description = "A Nix-flake-based R + Quarto development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  # Track arf on main; run `nix flake update arf` (or `nix flake update`) to upgrade
  inputs.arf = {
    url = "github:eitsupi/arf";
    flake = false;
  };

  inputs.rNvim = {
    url = "github:R-nvim/R.nvim";
    flake = false;
  };

  outputs =
    { self, ... }@inputs:
    let
      lib = inputs.nixpkgs.lib;
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
              config.allowBroken = true;
              overlays = [ inputs.self.overlays.default ];
            };
          }
        );
    in
    {
      overlays.default = final: prev: rec {
        # https://github.com/NixOS/nixpkgs/issues/519484
        quarto = prev.quarto.overrideAttrs (old: {
          postInstall = (old.postInstall or "") + ''
            # quarto 1.9.x passes "syntax-highlighting" as a pandoc defaults
            # key, but vanilla pandoc 3.x only recognizes "highlight-style".
            # Rename it.
            sed -i 's/kSyntaxHighlighting = "syntax-highlighting"/kSyntaxHighlighting = "highlight-style"/' $out/bin/quarto.js
            sed -i 's/"--syntax-highlighting"/"--highlight-style"/g' $out/bin/quarto.js

            # pandoc's Table AST gained a TableBody case that jog.lua
            # (quarto's filter for shifting Blocks/Inlines around) doesn't
            # know how to traverse, breaking any page with a gt()/kable()
            # table ("Don't know how to traverse TableBody").
            substituteInPlace $out/share/filters/modules/jog.lua \
              --replace-fail "elseif tp == 'pandoc TableHead' or tp == 'pandoc TableFoot' or" \
                "elseif tp == 'pandoc TableBody' or tp == 'TableBody' then
    element.head = jogger(element.head)
    element.body = jogger(element.body)
  elseif tp == 'pandoc TableHead' or tp == 'pandoc TableFoot' or"
          '';
        });

        rPackages = prev.rPackages // {
          # rPackages.quarto (the R wrapper around the quarto CLI) propagates a
          # `quarto` build input for its SystemRequirements, whose pname also
          # happens to be "quarto". rWrapper's package-set assembly dedupes by
          # pname, so that propagated CLI copy silently shadows the actual R
          # library and `library(quarto)` fails with "no package called
          # 'quarto'" even though it's listed in quartoRPackages below. Drop
          # the propagated CLI dep — the patched `quarto` above is already put
          # on PATH directly via devShells' `packages`, so nothing is lost.
          quarto = prev.rPackages.quarto.overrideAttrs (old: {
            propagatedBuildInputs = builtins.filter (
              p: (p.pname or "") != "quarto"
            ) (old.propagatedBuildInputs or [ ]);
          });

          # R.nvim's communication package, baked directly into R_LIBS_SITE.
          # R.nvim sets R_DEFAULT_PACKAGES (including "nvimcom") before
          # starting R; that lookup happens very early in R's startup,
          # before R_LIBS_USER is reliably in effect, so relying on
          # R.nvim's own auto-install into R_LIBS_USER intermittently
          # prints "package 'nvimcom' ... was not found". Baking it into
          # R_LIBS_SITE avoids the timing issue entirely.
          nvimcom = prev.rPackages.buildRPackage {
            name = "nvimcom";
            src = inputs.rNvim;
            sourceRoot = "source/nvimcom";

            buildInputs = with final; [
              R
              gcc
              gnumake
            ];

            meta = {
              description = "R.nvim communication package";
              homepage = "https://github.com/R-nvim/R.nvim";
              maintainers = [ ];
            };
          };
        };

        # Build arf (modern Rust-based R console) from the flake input.
        # To upgrade: run `nix flake update arf` (or `nix flake update`).
        # outputHashes only needs updating if arf changes its crossterm git pin.
        arf = final.rustPlatform.buildRustPackage {
          pname = "arf";
          version = inputs.arf.shortRev or "unstable";

          src = inputs.arf;

          cargoLock = {
            lockFile = "${inputs.arf}/Cargo.lock";
            outputHashes = {
              "crossterm-0.29.0" = "sha256-G57NGBvfZtedKQjwQMoxz1JSVH8LAPlCBeSv+DE8HiM=";
            };
          };

          # Two cd/tilde tests fail in the Nix sandbox (no $HOME), skip them
          doCheck = false;

          buildInputs = with final; lib.optionals stdenv.isDarwin [ darwin.apple_sdk.frameworks.Security ];
          nativeBuildInputs = with final; [ pkg-config ];

          meta = {
            description = "A modern Rust-based R console with fuzzy history, tree-sitter highlighting, and vi/emacs modes";
            homepage = "https://github.com/eitsupi/arf";
            license = lib.licenses.mit;
            mainProgram = "arf";
          };
        };

        # IDE packages — required by R.nvim editor features, stable across projects
        ideRPackages = with final.rPackages; [
          nvimcom # R.nvim <-> Neovim communication
          httpgd # hgd_browse keymap in r.lua
          data_table # view_df save_fun uses data.table::fwrite
        ];

        # Quarto-integration packages — stable across projects.
        #
        # NB: `final.rPackages.quarto` must be referenced explicitly here (not
        # via `with final.rPackages;`) because this `rec` block also defines a
        # sibling `quarto` (the CLI, above). In Nix, a name bound in an
        # enclosing lexical scope always shadows the same name pulled in via
        # `with`, so a bare `quarto` in a `with final.rPackages; [...]` list
        # would silently resolve to the CLI derivation instead of the R
        # package, and `library(quarto)` would fail to find it.
        quartoRPackages = (with final.rPackages; [
          rmarkdown
          downlit # code-link: true support
          xml2 # downlit dependency
          sessioninfo # sessioninfo::session_info() in report footers
        ]) ++ [
          final.rPackages.quarto # quarto::quarto_render()/quarto_preview() from an R session
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

      };

      devShells = forEachSupportedSystem (
        { pkgs }:
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              wrappedR # R with packages for LSP
              quarto # patched quarto CLI, for `quarto render`/`quarto preview`/`quarto publish`
              arf # modern Rust-based R console
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

{
  description = "A Nix-flake-based R development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  # Track arf on main; run `nix flake update arf` (or `nix flake update`) to upgrade
  inputs.arf = {
    url = "github:eitsupi/arf";
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
              "crossterm-0.29.0" = "sha256-vL6xZHyQyQFnDyoQywpeo0q6c0FtDJ59XVmo4vIN5pQ=";
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
          httpgd # hgd_browse keymap in r.lua
          data_table # view_df save_fun uses data.table::fwrite
        ];

        # Project packages — specific to this analysis, the reproducible core
        # Edit this list per project
        projectRPackages = with final.rPackages; [
          cli
          fs
        ];

        rPackageList = ideRPackages ++ projectRPackages;

        # Create rWrapper with packages (for LSP and R.nvim)
        wrappedR = final.rWrapper.override { packages = rPackageList; };

      };

      devShells = forEachSupportedSystem (
        { pkgs }:
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              wrappedR # R with packages for LSP
              arf # modern Rust-based R console
              jarl # fast R linter (from nixpkgs)
            ];

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

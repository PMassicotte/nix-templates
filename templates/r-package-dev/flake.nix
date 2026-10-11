{
  description = "A Nix-flake-based R package development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

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
              config.allowBroken = true;
              overlays = [ inputs.self.overlays.default ];
            };
          }
        );
    in
    {
      overlays.default = final: prev: rec {
        # ==============================================================================
        # YOUR PACKAGE'S DEPENDENCIES (from DESCRIPTION Imports:)
        # ==============================================================================
        runtimeDeps = [
          # Add packages from your DESCRIPTION Imports: section here
          # For example, if your DESCRIPTION has Imports: cli, fs:
          # final.rPackages.cli
          final.rPackages.fs
        ];

        # If you need packages from GitHub (not on CRAN), add them here
        # 1. Add a flake input:  inputs.myPkg = { url = "github:owner/repo"; flake = false; };
        # 2. Build it in the overlay:
        #    myPkg = final.rPackages.buildRPackage {
        #      pname = "myPkg";
        #      version = "unstable";
        #      src = inputs.myPkg;
        #      propagatedBuildInputs = with final.rPackages; [ dep1 dep2 ];
        #    };
        # 3. Reference it here:
        githubDeps = [
          # myPkg
        ];

        # ==============================================================================
        # DEVELOPMENT PACKAGES
        # ==============================================================================
        devPackages = with final.rPackages; [
          # Package development tools
          devtools
          roxygen2
          testthat
          usethis
          pkgdown
          rcmdcheck
          urlchecker

          # IDE support (R.nvim / LSP)
          httpgd
          data_table # view_df save_fun uses data.table::fwrite

          # Uncomment if your package has vignettes
          # knitr
          # rmarkdown
        ];

        # Combine: runtime deps + dev tools
        rPackageList = runtimeDeps ++ githubDeps ++ devPackages;

        # ==============================================================================
        # WRAP R WITH ALL PACKAGES
        # ==============================================================================
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
              wrappedArf # arf with the same R packages as wrappedR
              jarl # fast R linter (from nixpkgs)
              qpdf # PDF compression checks
            ];

            shellHook = ''
              export R_HOME=$(R RHOME)
              export R_LIBS_SITE=$(strings "$(command -v R)" | grep -oP '/nix/store/[^:]+/library' | sort -u | paste -sd: -)
              export R_LIBS_USER="$PWD/.r-libs"
              mkdir -p "$R_LIBS_USER"
              export R_QPDF="${pkgs.qpdf}/bin/qpdf"
            '';
          };
        }
      );
    };
}

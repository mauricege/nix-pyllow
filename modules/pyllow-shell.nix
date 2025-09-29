localFlake: {
  flake-parts-lib,
  lib,
  inputs,
  self,
  ...
}: {
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    {
      config,
      pkgs,
      system,
      ...
    }: let
      cfg = config.pyllow;
    in {
      options.pyllow = {
        wrapMkShell = lib.mkOption {
          type = lib.types.function;
          readOnly = true;
        };
        backend = lib.mkOption {
          type = lib.types.enum ["fhs" "nix-ld"];
          default =
            if builtins.pathExists "/run/current-system/sw/share/nix-ld/lib/ld.so"
            then "nix-ld"
            else "fhs";
          description = ''
            Which backend to use. Default is "nix-ld" if available on the system,
            otherwise "fhs".
          '';
        };

        manylinux = lib.mkOption {
          type = lib.types.nullOr (lib.types.enum ["1" "2010" "2014"]);
          default =
            if pkgs.stdenv.isLinux
            then "2014"
            else null;
          description = ''
            Which manylinux baseline to include in the environment.
            If set, the corresponding pkgs.pythonManylinuxPackages.manylinux* package
            set will be added to the library path (for nix-ld) or to targetPkgs (for FHS).
          '';
        };
        enableHardlinkedCacheWrappers = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Wrap uv and pixi to choose a cache directory on the same filesystem as the venv (for hardlinking).";
        };
        toolsToWrap = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = with pkgs; [uv pixi];
          description = "Tools to wrap in the FHS environment and force precedence in the devshell.";
        };
        shells = lib.mkOption {
          type = lib.types.lazyAttrsOf (lib.types.submoduleWith {
            modules = [
              ({
                config,
                options,
                name,
                ...
              }: {
                options = {
                  name = lib.mkOption {
                    type = lib.types.str;
                    default = "pyllow-devshell";
                    description = "Name of the developer environment.";
                  };

                  packages = lib.mkOption {
                    type = lib.types.listOf lib.types.package;
                    default = [];
                    description = "Packages to include in the environment.";
                  };
                  wrappedPackages = lib.mkOption {
                    type = lib.types.listOf lib.types.package;
                    default = [];
                    internal = true;
                    description = "Wrapped tools.";
                  };
                  finalPackages = lib.mkOption {
                    type = lib.types.listOf lib.types.package;
                    default = [];
                    internal = true;
                    description = "Final set of packages with tools accordingly wrapped and fhs env included.";
                  };
                  env = lib.mkOption {
                    type = lib.types.submodule {
                      freeformType = lib.types.lazyAttrsOf lib.types.anything;
                    };
                    description = "Environment variables to be exposed inside the developer environment.";
                    default = {};
                  };
                  enterShell = lib.mkOption {
                    type = lib.types.lines;
                    description = "Bash code to execute when entering the shell.";
                    default = "";
                  };
                  unsetEnvVars = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    description = "A list of removed environment variables to make the shell/direnv more lean. From devenv";
                    # manually determined with knowledge from https://nixos.wiki/wiki/C
                    default = [
                      "HOST_PATH"
                      "NIX_BUILD_CORES"
                      "__structuredAttrs"
                      "buildInputs"
                      "buildPhase"
                      "builder"
                      "depsBuildBuild"
                      "depsBuildBuildPropagated"
                      "depsBuildTarget"
                      "depsBuildTargetPropagated"
                      "depsHostHost"
                      "depsHostHostPropagated"
                      "depsTargetTarget"
                      "depsTargetTargetPropagated"
                      "dontAddDisableDepTrack"
                      "doCheck"
                      "doInstallCheck"
                      "nativeBuildInputs"
                      "out"
                      "outputs"
                      "patches"
                      "phases"
                      "preferLocalBuild"
                      "propagatedBuildInputs"
                      "propagatedNativeBuildInputs"
                      "shell"
                      "shellHook"
                      "stdenv"
                      "strictDeps"
                    ];
                  };
                };

                config = let
                  wrapped = import ../lib/utils/wrapTools.nix config.packages {
                    inherit pkgs lib;
                    inherit (cfg) toolsToWrap manylinux backend;
                    shellHook = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: value: "export ${name}=${value}") config.env);
                  };
                  inherit (wrapped) wrappedTools fhsEnv packagesWithoutTools libraries;
                in {
                  finalPackages =
                    wrappedTools
                    ++ packagesWithoutTools
                    ++ libraries
                    ++ (
                      if cfg.backend == "fhs"
                      then [fhsEnv]
                      else []
                    );
                  wrappedPackages = wrappedTools;
                  env = lib.mkIf (cfg.backend == "nix-ld") {
                    NIX_LD = lib.fileContents "${pkgs.stdenv.cc}/nix-support/dynamic-linker";
                    NIX_LD_LIBRARY_PATH = lib.makeLibraryPath (config.packages ++ libraries);
                  };
                  enterShell = lib.mkBefore ''
                    export PS1="\[\e[0;34m\](pyllow)\[\e[0m\] ''${PS1-}"
                    ${lib.optionalString (pkgs.stdenv.isLinux && (pkgs.glibcLocalesUtf8 != null)) ''
                      if [ -z "''${LOCALE_ARCHIVE-}" ]; then
                        export LOCALE_ARCHIVE=${pkgs.glibcLocalesUtf8}/lib/locale/locale-archive
                      fi
                    ''}

                    # direnv helper
                    if [ ! type -p direnv &>/dev/null && -f .envrc ]; then
                      echo "An .envrc file was detected, but the direnv command is not installed."
                      echo "To use this configuration, please install direnv: https://direnv.net/docs/installation.html"
                    fi

                    unset ${lib.concatStringsSep " " config.unsetEnvVars}
                  '';
                };
              })
            ];
            shorthandOnlyDefinesConfig = false;
          });
        };
      };
      config = {
        devShells = lib.mapAttrs (_name: cfg:
          pkgs.mkShell ({
              packages = cfg.finalPackages;
              shellHook = ''
                ${cfg.enterShell}
              '';
            }
            // cfg.env))
        cfg.shells;
        pyllow = {
          wrapMkShell = shell:
            import ../lib/wrapShell.nix shell {
              inherit pkgs lib;
              inherit (cfg) backend manylinux toolsToWrap;
            };
        };
      };
    }
  );
}

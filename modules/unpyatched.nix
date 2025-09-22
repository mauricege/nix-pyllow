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
    }: {
      options.unpyatched = {
        enable = lib.mkEnableOption "Make python **just work** with unpyatched. Either through transparent FHS wrapping or nix-ld.";

        name = lib.mkOption {
          type = lib.types.str;
          default = "unpyatched";
          description = "Name of the unpyatched environment.";
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
            then "1"
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
      };

      config = lib.mkIf config.unpyatched.enable (
        let
          # upstream devshell's function https://github.com/numtide/devshell/blob/7c9e793ebe66bcba8292989a68c0419b737a22a0/modules/env.nix#L61C3-L96C72
          envToBash = with lib;
            {
              name,
              value,
              eval,
              prefix,
              unset,
              ...
            } @ args: let
              vals = filter (key: args.${key} != null && args.${key} != false) [
                "eval"
                "prefix"
                "unset"
                "value"
              ];
              valType = head vals;
            in
              assert assertMsg (
                (length vals) > 0
              ) "[[environ]]: ${name} expected one of (value|eval|prefix|unset) to be set.";
              assert assertMsg ((length vals) < 2)
              "[[environ]]: ${name} expected only one of (value|eval|prefix|unset) to be set. Not ${toString vals}";
              assert assertMsg (!(name == "PATH" && valType == "value")) "[[environ]]: ${name} should not override the value. Use 'prefix' instead.";
                if valType == "value"
                then "export ${name}=${escapeShellArg (toString value)}"
                else if valType == "eval"
                then "export ${name}=${eval}"
                else if valType == "prefix"
                then ''export ${name}=$(${pkgs.coreutils}/bin/realpath --canonicalize-missing "${prefix}")''${${name}+:''${${name}}}''
                else if valType == "unset"
                then ''unset ${name}''
                else throw "BUG in the env.nix module. This should never be reached.";

          envExportString = lib.concatStringsSep "\n" (map envToBash (builtins.filter (env: !(lib.elem env.name ["PATH" "NIXPKGS_PATH"])) config.devshells.default.env));

          pnameOf = pkg:
            if pkg ? pname
            then pkg.pname
            else pkg.name;

          cacheWrappers = import ./cacheWrappers.nix {inherit pkgs lib;};

          matchedTools =
            map (pkg:
              if cacheWrappers ? ${pkg.pname}
              then cacheWrappers.${pkg.pname}
              else pkg)
            (builtins.filter (pkg: lib.elem (pnameOf pkg) (map pnameOf config.unpyatched.toolsToWrap))
              (config.devshells.default.packages or []));

          manylinuxLibs =
            if config.unpyatched.manylinux == null
            then []
            else
              {
                "1" = pkgs.pythonManylinuxPackages.manylinux1;
                "2010" = pkgs.pythonManylinuxPackages.manylinux2010;
                "2014" = pkgs.pythonManylinuxPackages.manylinux2014;
              }.${
                config.unpyatched.manylinux
              };
          additionalDefaultLibs = with pkgs; [
            libxcrypt
          ];

          allLibraries = manylinuxLibs ++ additionalDefaultLibs;
          packagesWithoutTools = builtins.filter (pkg: !(lib.elem (pnameOf pkg) (map pnameOf matchedTools))) (config.devshells.default.packages or []);

          wrapToolFHS = pkg: let
            pname = pnameOf pkg;
            fhsTool = pkgs.buildFHSEnvBubblewrap {
              name = pname;
              targetPkgs = pkgs: matchedTools ++ packagesWithoutTools ++ allLibraries;
              runScript = pname;
              profile = envExportString;
            };
          in
            pkgs.symlinkJoin {
              inherit pname;
              version = "${pkg.version}-fhs";
              paths = [fhsTool];
              nativeBuildInputs = [pkgs.makeWrapper];

              postBuild = ''
                for dir in bash_completion.d zsh/site-functions fish/vendor_completions.d; do
                  if [ -d ${pkg}/share/$dir ]; then
                    mkdir -p $out/share/$dir
                    cp -r ${pkg}/share/$dir/* $out/share/$dir/
                  fi
                done
              '';

              meta = {
                mainProgram = "${pname}";
                description = pkg.meta.description or "Wrapped ${pname} for FHS environment";
              };
            };

          wrapToolNixLd = pkg: pkg;

          wrapped = lib.listToAttrs (map (pkg: {
              name = pnameOf pkg;
              value =
                if config.unpyatched.backend == "fhs"
                then wrapToolFHS pkg
                else wrapToolNixLd pkg;
            })
            matchedTools);

          toolCheckString = let
            # Calculate the maximum length of all pnames
            maxPnameLen =
              lib.foldl' (
                acc: pkg: let
                  len = builtins.stringLength pkg.pname;
                in
                  if len > acc
                  then len
                  else acc
              )
              0
              config.unpyatched.toolsToWrap;
          in
            lib.concatMapStringsSep "\n" (
              pkg: ''
                if command -v ${pkg.pname} >/dev/null 2>&1; then
                  printf "  %-${toString maxPnameLen}s - ${pkg.meta.description} \033[32m✔  (available)\033[0m\n" "${pkg.pname}"
                else
                  printf "  %-${toString maxPnameLen}s - ${pkg.meta.description} \033[31m✘ (add it through devshell)\033[0m\n" "${pkg.pname}"
                fi
              ''
            )
            config.unpyatched.toolsToWrap;

          fhsEnv = pkgs.buildFHSEnvBubblewrap {
            name = "fhs";
            targetPkgs = pkgs:
              matchedTools ++ packagesWithoutTools ++ allLibraries;
            profile = "${envExportString}";
          };

          uvConfig =
            if builtins.pathExists "${self}/pyproject.toml"
            then builtins.fromTOML (builtins.readFile "${self}/pyproject.toml")
            else {};
          scripts = uvConfig.project.scripts or {};
          generateApp = name:
            pkgs.runCommand name {
              buildInputs = [wrapped.uv];
            } ''
              mkdir -p $out/bin
              cat > $out/bin/${name} <<'EOF'
              #!/usr/bin/env bash
              REPO_ROOT=${self}
              cd "$REPO_ROOT"
              exec ${wrapped.uv}/bin/uv run --isolated ${name} "$@"
              EOF
              chmod +x $out/bin/${name}
            '';
        in {
          packages =
            wrapped
            // {
              fhs = fhsEnv;
            };

          apps =
            lib.mapAttrs (name: _: {
              type = "app";
              program = lib.getExe (generateApp name);
            })
            scripts;

          devshells.default = {
            name = "unpyatched";

            motd = ''
              {202}🚀 Welcome to ${config.unpyatched.name}{reset}
              $(type -p menu &>/dev/null && menu)

              {226}🐍 Supported Python tooling (via ${config.unpyatched.backend}){reset}

              $(${toolCheckString})

              {226}🛠️  FHS fallback{reset}

                fhs - Enter an FHS-compatible shell with all packages available
            '';
            env =
              [
                {
                  name = "PATH";
                  prefix = lib.concatStringsSep ":" (map (drv: "${drv}/bin") ((lib.attrValues wrapped) ++ [fhsEnv]));
                }
              ]
              ++ (
                if config.unpyatched.backend == "nix-ld"
                then [
                  {
                    name = "NIX_LD";
                    value = lib.fileContents "${pkgs.stdenv.cc}/nix-support/dynamic-linker";
                  }
                  {
                    name = "NIX_LD_LIBRARY_PATH";
                    value =
                      lib.makeLibraryPath (config.devshells.default.packages
                        ++ allLibraries);
                  }
                ]
                else []
              );
          };
        }
      );
    }
  );
}

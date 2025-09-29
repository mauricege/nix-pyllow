packages: {
  toolsToWrap,
  backend ? "fhs",
  manylinux ?
    if pkgs.stdenv.isLinux
    then "2014"
    else null,
  libraries ? import ./libraries.nix {inherit pkgs manylinux;},
  pkgs,
  lib,
  shellHook ? "",
  ...
}: let
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
    (builtins.filter (pkg: lib.elem (pnameOf pkg) (map pnameOf toolsToWrap))
      packages);

  packagesWithoutTools = builtins.filter (pkg: !(lib.elem (pnameOf pkg) (map pnameOf matchedTools))) packages;

  wrapToolFHS = pkg: let
    pname = pnameOf pkg;
    fhsTool = pkgs.buildFHSEnvBubblewrap {
      name = pname;
      targetPkgs = pkgs: matchedTools ++ packagesWithoutTools ++ libraries;
      runScript = pname;
      profile = shellHook;
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

  wrappedTools = map (pkg:
    if backend == "fhs"
    then wrapToolFHS pkg
    else wrapToolNixLd pkg)
  matchedTools;

  fhsEnv = pkgs.buildFHSEnvBubblewrap {
    name = "fhs";
    targetPkgs = pkgs:
      matchedTools ++ packagesWithoutTools ++ libraries;
    profile = shellHook;
  };
in {
  inherit wrappedTools packagesWithoutTools fhsEnv libraries;
}

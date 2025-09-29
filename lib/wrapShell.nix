shell: {
  pkgs,
  lib ? pkgs.lib,
  backend,
  toolsToWrap ? [pkgs.uv pkgs.pixi],
  manylinux,
  ...
}: let
  wrapped = import ../lib/utils/wrapTools.nix shell.nativeBuildInputs {
    inherit pkgs lib;
    toolsToWrap = toolsToWrap;
    inherit backend;
  };
  inherit (wrapped) wrappedTools fhsEnv packagesWithoutTools libraries;
in
  shell.overrideAttrs (oldAttrs: {
    nativeBuildInputs = lib.unique (packagesWithoutTools
      ++ wrappedTools
      ++ (
        if backend == "fhs"
        then [fhsEnv]
        else []
      ));
    shellHook =
      oldAttrs.shellHook
      ++ (
        if backend == "nix-ld"
        then ''
          export NIX_LD=${lib.fileContents "${pkgs.stdenv.cc}/nix-support/dynamic-linker"}
          export NIX_LD_LIBRARY_PATH="${lib.makeLibraryPath (oldAttrs.nativeBuildInputs ++ libraries)}"
        ''
        else ""
      );
  })

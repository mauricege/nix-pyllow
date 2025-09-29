shell: {
  pkgs,
  lib ? pkgs.lib,
  backend,
  toolsToWrap ? [pkgs.uv pkgs.pixi],
  manylinux,
  ...
}: let
  wrapped = import ../lib/utils/wrapTools.nix shell.packages {
    inherit pkgs lib;
    toolsToWrap = toolsToWrap;
    inherit backend;
  };
  inherit (wrapped) wrappedTools fhsEnv packagesWithoutTools libraries;
in
  lib.recursiveUpdate (shell
    // {
      env = lib.mkIf (backend == "nix-ld") {
        NIX_LD = lib.fileContents "${pkgs.stdenv.cc}/nix-support/dynamic-linker";
        NIX_LD_LIBRARY_PATH = lib.makeLibraryPath (shell.packages ++ libraries);
      };
    }) {
    packages = lib.unique (packagesWithoutTools
      ++ wrappedTools
      ++ (
        if backend == "fhs"
        then [fhsEnv]
        else []
      ));
  }

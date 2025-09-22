{
  description = "unpyatched – painless Python tooling on Nix (FHS / nix-ld devshell integration)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    devshell.url = "github:numtide/devshell";
  };

  outputs = {
    self,
    flake-parts,
    devshell,
    ...
  } @ inputs:
    flake-parts.lib.mkFlake {inherit inputs;} ({
      withSystem,
      flake-parts-lib,
      ...
    }: let
      inherit (flake-parts-lib) importApply;
      flakeModules.default = importApply ./modules/unpyatched.nix {inherit withSystem;};
    in {
      imports = [
        inputs.devshell.flakeModule
        flakeModules.default
      ];

      systems = ["x86_64-linux" "aarch64-linux"];
      perSystem = {
        config,
        pkgs,
        ...
      }: {
        devshells.default = {
          packages = with pkgs; [
            uv
            pixi
          ];
          env = [
          ];
        };
        unpyatched = {
          enable = true;
          backend = "fhs"; # or "nix-ld"
        };
      };
      flake = {
        inherit flakeModules;
        templates = rec {
          flake-parts = {
            path = ./templates/flake-parts;
            description = "Example flake suppporting normal numtide devshell workflows with unpyatched enabled";
          };
          default = flake-parts;
        };
      };
    });
}

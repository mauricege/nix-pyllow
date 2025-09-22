{
  description = "Example flake with unpyatched module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    devshell.url = "github:numtide/devshell";
    unpyatched.url = "github:mauricege/unpyatched";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    flake-parts,
    devshell,
    unpyatched,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        inputs.devshell.flakeModule
        inputs.unpyatched.flakeModules.default
      ];

      systems = [
        # systems for which you want to build the `perSystem` attributes
        "x86_64-linux"
        # ...
      ];

      perSystem = {
        config,
        self',
        inputs',
        pkgs,
        system,
        ...
      }: {
        _module.args.pkgs = import self.inputs.nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
          };
        };
        unpyatched = {
          enable = true;
          backend = "nix-ld"; # or "nix-ld"
        };
        devshells.default = {
          packages = with pkgs; [
            uv
            pixi
          ];
          env = [
          ];
        };
      };
    };
}

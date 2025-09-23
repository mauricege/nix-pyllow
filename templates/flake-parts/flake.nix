{
  description = "Example flake with nix-pyllow module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    devshell.url = "github:numtide/devshell";
    pyllow.url = "github:mauricege/nix-pylow";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    flake-parts,
    devshell,
    pyllow,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        inputs.devshell.flakeModule
        inputs.pyllow.flakeModules.default
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

        devshells.default = {
          packages = with pkgs; [
            uv
            pixi
          ];
          env = [
          ];
          pyllow = {
            enable = true;
            backend = "fhs"; # or "nix-ld"
          };
        };
      };
    };
}

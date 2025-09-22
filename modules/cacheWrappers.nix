{
  lib,
  pkgs,
  ...
}: let
  uv = pkgs.stdenv.mkDerivation {
    pname = "uv";
    version = "${pkgs.uv.version}-wrapper";

    buildInputs = [pkgs.makeWrapper];

    unpackPhase = "true"; # no source to unpack

    installPhase = ''
      mkdir -p $out/bin
      makeWrapper ${pkgs.uv}/bin/uv $out/bin/uv \
        --run '
        VENV_DIR="''${VIRTUAL_ENV:-''${UV_PROJECT:-$PWD}}"
        MOUNT_POINT=$(${pkgs.coreutils}/bin/df -P "$VENV_DIR" | tail -1 | ${pkgs.gawk}/bin/awk "{print \$6}")

        # Try a shared cache directory first
        if [ -d "$MOUNT_POINT/.cache" ] && [ -w "$MOUNT_POINT/.cache" ]; then
          UV_CACHE_DIR="$MOUNT_POINT/.cache/uv"
        # Fallback to user-specific cache directory
        elif [ -d "$MOUNT_POINT/$USER/.cache" ] && [ -w "$MOUNT_POINT/$USER/.cache" ]; then
          UV_CACHE_DIR="$MOUNT_POINT/$USER/.cache/uv"
        fi

        export UV_CACHE_DIR
        export UV_MANAGED_PYTHON=1
        '
      makeWrapper ${pkgs.uv}/bin/uvx $out/bin/uvx \
        --run '
        VENV_DIR="''${VIRTUAL_ENV:-''${UV_PROJECT:-$PWD}}"
        MOUNT_POINT=$(${pkgs.coreutils}/bin/df -P "$VENV_DIR" | tail -1 | ${pkgs.gawk}/bin/awk "{print \$6}")

        # Try a shared cache directory first
        if [ -d "$MOUNT_POINT/.cache" ] && [ -w "$MOUNT_POINT/.cache" ]; then
          UV_CACHE_DIR="$MOUNT_POINT/.cache/uv"
        # Fallback to user-specific cache directory
        elif [ -d "$MOUNT_POINT/$USER/.cache" ] && [ -w "$MOUNT_POINT/$USER/.cache" ]; then
          UV_CACHE_DIR="$MOUNT_POINT/$USER/.cache/uv"
        fi

        export UV_CACHE_DIR
        export UV_MANAGED_PYTHON=1
        '
      # Copy uv's completions into $out/share so they are linked into the profile
      mkdir -p $out/share
      cp -r ${pkgs.uv}/share/* $out/share/
    '';
  };
  pixi = pkgs.stdenv.mkDerivation {
    pname = "pixi";
    version = "${pkgs.pixi.version}-wrapper";

    buildInputs = [pkgs.makeWrapper];

    unpackPhase = "true"; # no source to unpack

    installPhase = ''
      mkdir -p $out/bin
      makeWrapper ${pkgs.pixi}/bin/pixi $out/bin/pixi \
        --run '
        VENV_DIR="''${PIXI_PROJECT_MANIFEST:-''${PIXI_PROJECT_ROOT:-$PWD}}"
        MOUNT_POINT=$(${pkgs.coreutils}/bin/df -P "$VENV_DIR" | tail -1 | ${pkgs.gawk}/bin/awk "{print $6}")
        # set the cache directory for pixi to be on the same filesystem as the current working directory
        # This makes sure that cache files are hardlinked to the virtual environment and not copied

        if [ -d "$MOUNT_POINT/$USER/.cache" ] && [ -w "$MOUNT_POINT/$USER/.cache" ]; then
          PIXI_CACHE_DIR="$MOUNT_POINT/$USER/.cache/pixi"
        fi
        export PIXI_CACHE_DIR
        '
      # Copy pixi's completions into $out/share so they are linked into the profile
      mkdir -p $out/share
      cp -r ${pkgs.pixi}/share/* $out/share/
    '';

    # Bring in pixi so its share/ directories (completions for fish/bash/zsh) are exposed
    propagatedBuildInputs = [pkgs.pixi];
  };
in {
  inherit uv pixi;
}

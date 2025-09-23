# 🐍 nix-pyllow - Making Python on NixOS Comfortable

## Python + NixOS = Pain

If you are a python developer on NixOS, you have probably seen this:

```shell
Could not start dynamically linked executable: /home/maurice/.cache/uv/archive-v0/un4lq9QapqWZm9fPXna4G/bin/python
NixOS cannot run dynamically linked executables intended for generic
linux environments out of the box. For more information, see:
https://nix.dev/permalink/stub-ld
```

Or even worse, this:

```shell
libz.so.1: cannot open shared object file: No such file or directory
```

This is a well known issue that comes down to pip pulling in binaries which are dynamically linked to pre-compiled libraries that cannot be resolved on NixOS. Different solutions to this issue have been proposed, such as patching the binaries with patchelf (there's a [tool](https://github.com/GuillaumeDesforges/fix-python) for that), adding the missing libraries to LD_LIBRARY_PATH (in a development shell), or using specialized tooling that generates nix-derivations from .toml and .lock files of python package managers ([uv2nix](https://github.com/pyproject-nix/uv2nix) or [poetry2nix](https://github.com/nix-community/poetry2nix)).

## Unpatched binaries - If you can't beat 'em, embrace 'em

Many scarred NixOS believers have at least considered to (partly) renounce the church's teachings and resort to `steam-run ./my-unpatched-binary` – or finally enable [nix-ld](https://github.com/nix-community/nix-ld), sacrificing purity for their own mental wellbeing.

**nix-pyllow** is a [flake-parts](https://github.com/hercules-ci/flake-parts) module extending [devshell](https://github.com/numtide/devshell) that fully **embraces unpatched binaries** to make Python tooling **just work** on NixOS. It leaves installing the whole Python tool chain to capable package managers ([uv](https://github.com/astral-sh/uv) or [pixi](https://prefix.dev/pixi)). Runtime dependencies are provided either through `nix-ld` or by wrapping the package managers in `buildFHSEnv`. This makes the package managers fully usable from a regular devShell – with support for [direnv](https://direnv.net/). As both pixi and uv encourage a `[pixi|uv] run [executable]` workflow, this also makes your project's python code run seamlessly.

It works by inspecting your devshell's packages attribute and either:

1. Wrapping uv and pixi in `buildFHSEnvBubblewrap` with your packages in `targetPkgs` and prepending those wrappers to your PATH

or

2. Setting NIX_LD_LIBRARY path to include all library directories of your packages list

---

## ✨ Features

- Works with **uv** and **pixi** out of the box
- Integrates with [devshell](https://github.com/numtide/devshell)
- Lets you transparently wrap additional tools via `toolsToWrap`
- Provides good library coverage through configurable **manylinux** compatibility layer (`1`, `2010`, or `2014`)
- Provides an FHS fallback shell via `fhs`
- Automatically generates `nix run` apps for `uv` project scripts (experimental!)

---

## 🚀 Getting Started

### Get the default template

```shell
nix flake init -t github:mauricege/nix-pyllow
```

### Maybe switch the backend

The `nix-pyllow` module supports two backends for providing runtime dependencies to Python tools:

- **"fhs"**: Wraps uv and pixi in an FHS-compatible environment (via `buildFHSEnvBubblewrap`)
- **"nix-ld"**: Uses `nix-ld` to provide dynamic libraries

You can change the backend by editing your `flake.nix` file:

```nix
// filepath: ./flake.nix
nix-pyllow = {
  enable = true;
  backend = "nix-ld"; # or "fhs"
};
```

### Activate the environment

Either `nix develop` or `direnv allow`.

You’ll see a MOTD like:

```shell
🚀 Welcome to nix-pyllow

🐍 Supported Python tooling (via nix-ld)
  uv         - Python package installer ✔ (available)
  pixi       - Environment manager      ✔ (available)

🛠️  FHS fallback
  fhs - Enter an FHS-compatible shell with all packages available
```

---

## ⚙️ Options

| Option                          | Type                              | Default                  | Description                                                   |
| ------------------------------- | --------------------------------- | ------------------------ | ------------------------------------------------------------- |
| `enable`                        | `bool`                            | `false`                  | Enable unpyatched integration                                 |
| `name`                          | `string`                          | `"unpyatched"`           | Name of the environment (shown in MOTD and shell prompt)                       |
| `backend`                       | `"fhs" \| "nix-ld"`               | `"fhs"`                  | Runtime backend (defaults to `"nix-ld"` if available)         |
| `manylinux`                     | `null \| "1" \| "2010" \| "2014"` | `"1"` (Linux)            | Manylinux baseline to include in the environment              |
| `enableHardlinkedCacheWrappers` | `bool`                            | `true`                   | Wrap uv/pixi so they choose a cache dir on the same filesystem as the venv - for hardlinking |
| `toolsToWrap`                   | `list of packages`                | `[ uv pixi ]` | Tools to wrap and expose in the environment                   |

---

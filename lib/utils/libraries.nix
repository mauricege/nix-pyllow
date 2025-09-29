{
  pkgs,
  manylinux ?
    if pkgs.stdenv.isLinux
    then "2014"
    else null,
  ...
}: let
  manylinuxLibs =
    if manylinux == null
    then []
    else
      {
        "1" = pkgs.pythonManylinuxPackages.manylinux1;
        "2010" = pkgs.pythonManylinuxPackages.manylinux2010;
        "2014" = pkgs.pythonManylinuxPackages.manylinux2014;
      }.${
        manylinux
      };
  additionalDefaultLibs = with pkgs; [
    libxcrypt
    openssl.dev
    pkg-config
  ];
in
  manylinuxLibs ++ additionalDefaultLibs

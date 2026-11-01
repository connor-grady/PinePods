{
  perSystem = { pkgs, ... }: {
    devShells.flutter = pkgs.mkShellNoCC {
      name = "pinepods-flutter";
      packages = with pkgs; [
        curl
        fvm
        git
        unzip
        xz
        zip
      ];
      shellHook = ''
        export FVM_CACHE_PATH="''${XDG_CACHE_HOME:-$HOME/.cache}/fvm"
        export PUB_CACHE="''${XDG_CACHE_HOME:-$HOME/.cache}/pub"
      '';
    };
  };
}

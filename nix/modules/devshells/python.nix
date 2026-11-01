{
  perSystem =
    { lib, pkgs, ... }:
    let
      inherit (lib.meta) getExe';
    in
    {
      devShells.python = pkgs.mkShell {
        name = "pinepods-python";
        packages = with pkgs; [
          cmake
          ffmpeg
          mariadb-connector-c.dev
          uv
        ];
        LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib ];
        MARIADB_CONFIG = getExe' pkgs.mariadb-connector-c.dev "mariadb_config";
      };
    };
}

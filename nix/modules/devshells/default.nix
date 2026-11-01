{
  perSystem = { config, pkgs, ... }: {
    devShells.default = pkgs.mkShell {
      inherit (config.devShells.python) LD_LIBRARY_PATH MARIADB_CONFIG;
      name = "pinepods";
      inputsFrom = with config.devShells; [
        flutter
        python
        rust
      ];
    };
  };
}

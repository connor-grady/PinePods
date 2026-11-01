{
  perSystem =
    { config, pkgs, ... }:
    let
      inherit (config.packages) pinepods-api pinepods-db-setup;
    in
    {
      checks.listen = pkgs.testers.runNixOSTest {
        name = "pinepods-listen";

        containers.machine =
          { lib, pkgs, ... }:
          let
            database = {
              DB_TYPE = "postgresql";
              DB_HOST = "/run/postgresql";
              DB_PORT = "5432";
              DB_USER = "pinepods";
              DB_PASSWORD = "";
              DB_NAME = "pinepods";
            };

            api = listen: {
              requires = [
                "pinepods-db-setup.service"
                "redis-pinepods.service"
              ];
              after = [
                "pinepods-db-setup.service"
                "redis-pinepods.service"
              ];
              environment =
                database
                // {
                  VALKEY_HOST = "127.0.0.1";
                  VALKEY_PORT = "6379";
                  SEARCH_API_URL = "http://127.0.0.1:9/api/search";
                  PEOPLE_API_URL = "http://127.0.0.1:9";
                }
                // lib.optionalAttrs (listen != null) { PINEPODS_LISTEN = listen; };
              serviceConfig = {
                Type = "notify";
                ExecStart = lib.getExe pinepods-api;
                User = "pinepods";
                Group = "pinepods";
                WatchdogSec = "2s";
              };
            };

            activated = name: listen: {
              services.${name} = api listen // {
                requires = (api listen).requires ++ [ "${name}.socket" ];
                after = (api listen).after ++ [ "${name}.socket" ];
              };
            };
          in
          {
            environment.systemPackages = [ pkgs.curl ];

            services.postgresql = {
              enable = true;
              ensureDatabases = [ "pinepods" ];
              ensureUsers = [
                {
                  name = "pinepods";
                  ensureDBOwnership = true;
                }
              ];
            };

            services.redis.servers.pinepods = {
              enable = true;
              bind = "127.0.0.1";
              port = 6379;
            };

            users = {
              groups.pinepods = { };
              users.pinepods = {
                isSystemUser = true;
                group = "pinepods";
              };
            };

            systemd = lib.mkMerge [
              {
                services = {
                  pinepods-db-setup = {
                    requires = [ "postgresql.target" ];
                    after = [ "postgresql.target" ];
                    environment = database;
                    serviceConfig = {
                      Type = "oneshot";
                      RemainAfterExit = true;
                      ExecStart = lib.getExe pinepods-db-setup;
                      User = "pinepods";
                      Group = "pinepods";
                    };
                  };
                  pinepods-tcp = api "127.0.0.1:8032";
                  pinepods-unix = api "/run/pinepods/api.sock";
                  pinepods-no-socket = api "systemd";
                };

                sockets = {
                  pinepods-socket-tcp.listenStreams = [ "127.0.0.1:8033" ];
                  pinepods-socket-unix.listenStreams = [ "/run/pinepods-socket/api.sock" ];
                  pinepods-ignored.listenStreams = [ "127.0.0.1:8034" ];
                  pinepods-two.listenStreams = [
                    "127.0.0.1:8036"
                    "127.0.0.1:8037"
                  ];
                };

                tmpfiles.settings.pinepods."/run/pinepods".d = {
                  user = "pinepods";
                  group = "pinepods";
                  mode = "0750";
                };
              }
              (activated "pinepods-socket-tcp" "systemd")
              (activated "pinepods-socket-unix" "systemd")
              (activated "pinepods-ignored" null)
              (activated "pinepods-two" "systemd")
            ];
          };

        testScript = ''
          import json
          import time

          def status(unit):
              return machine.succeed(f"systemctl show -P StatusText {unit}").strip()

          def check(url, unix_socket=None):
              socket = f"--unix-socket {unix_socket} " if unix_socket else ""
              response = json.loads(machine.succeed(f"curl -fsS {socket}{url}/api/pinepods_check"))
              t.assertTrue(response["pinepods_instance"])

          def journal(unit):
              return machine.succeed(f"journalctl -o cat -u {unit}")

          def stop(unit):
              machine.succeed(f"systemctl stop {unit}")
              t.assertEqual(machine.succeed(f"systemctl show -P Result {unit}").strip(), "success")

          machine.wait_for_unit("multi-user.target")

          with subtest("TCP address from PINEPODS_LISTEN, readiness and status"):
              machine.succeed("systemctl start pinepods-tcp.service")
              t.assertEqual(status("pinepods-tcp.service"), "Listening on http://127.0.0.1:8032")
              check("http://127.0.0.1:8032")

          with subtest("Watchdog pings keep the service alive"):
              first = int(machine.succeed("systemctl show -P WatchdogTimestampMonotonic pinepods-tcp.service"))
              time.sleep(6)
              second = int(machine.succeed("systemctl show -P WatchdogTimestampMonotonic pinepods-tcp.service"))
              t.assertGreater(second, first)
              t.assertEqual(machine.succeed("systemctl show -P NRestarts pinepods-tcp.service").strip(), "0")
              machine.succeed("systemctl is-active pinepods-tcp.service")
              stop("pinepods-tcp.service")

          with subtest("Unix socket from PINEPODS_LISTEN is removed on stop and replaced when stale"):
              machine.succeed("systemctl start pinepods-unix.service")
              t.assertEqual(status("pinepods-unix.service"), "Listening on unix:/run/pinepods/api.sock")
              check("http://localhost", "/run/pinepods/api.sock")
              stop("pinepods-unix.service")
              machine.fail("test -e /run/pinepods/api.sock")
              machine.succeed(
                  "runuser -u pinepods -- ${pkgs.python3.interpreter} -c "
                  "'import socket; socket.socket(socket.AF_UNIX).bind(\"/run/pinepods/api.sock\")'"
              )
              machine.succeed("test -S /run/pinepods/api.sock")
              machine.succeed("systemctl start pinepods-unix.service")
              check("http://localhost", "/run/pinepods/api.sock")
              stop("pinepods-unix.service")

          with subtest("TCP socket passed by systemd"):
              machine.succeed("systemctl start pinepods-socket-tcp.service")
              t.assertEqual(status("pinepods-socket-tcp.service"), "Listening on http://127.0.0.1:8033")
              check("http://127.0.0.1:8033")
              stop("pinepods-socket-tcp.service")
              machine.succeed("systemctl is-active pinepods-socket-tcp.socket")
              check("http://127.0.0.1:8033")
              machine.succeed("systemctl is-active pinepods-socket-tcp.service")
              stop("pinepods-socket-tcp.service")
              machine.succeed("systemctl stop pinepods-socket-tcp.socket")

          with subtest("Unix socket passed by systemd is left in place"):
              machine.succeed("systemctl start pinepods-socket-unix.service")
              t.assertEqual(status("pinepods-socket-unix.service"), "Listening on unix:/run/pinepods-socket/api.sock")
              check("http://localhost", "/run/pinepods-socket/api.sock")
              stop("pinepods-socket-unix.service")
              machine.succeed("test -S /run/pinepods-socket/api.sock")
              machine.succeed("systemctl stop pinepods-socket-unix.socket")

          with subtest("A passed socket is ignored unless PINEPODS_LISTEN is systemd"):
              machine.succeed("systemctl start pinepods-ignored.service")
              t.assertEqual(status("pinepods-ignored.service"), "Listening on http://0.0.0.0:8032")
              check("http://127.0.0.1:8032")
              stop("pinepods-ignored.service")
              machine.succeed("systemctl stop pinepods-ignored.socket")

          with subtest("systemd without a passed socket is refused"):
              machine.fail("systemctl start pinepods-no-socket.service")
              t.assertIn("systemd passed 0 sockets", journal("pinepods-no-socket.service"))

          with subtest("More than one passed socket is refused"):
              machine.fail("systemctl start pinepods-two.service")
              t.assertIn("systemd passed 2 sockets", journal("pinepods-two.service"))
        '';
      };
    };
}

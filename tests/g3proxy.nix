# SPDX-FileCopyrightText: 2026 Titouan Heyrendt <t.heyrendt@gmail.com>
#
# SPDX-License-Identifier: MIT

{ pkgs, libSecurix }:
let
  terminal = libSecurix.mkTerminal {
    name = "g3proxy";
    userSpecificModule = { };
    vpnProfiles = { };
    modules = [
      {
        securix = {
          graphical-interface.variant = "sway";
          self = {
            mainDisk = "/dev/nvme0n1";
            machine = {
              hardwareSKU = "x280";
              inventoryId = 0;
            };
          };

          networkmanager.events.enable = true;
        };

        securix.automatic-http-proxy = {
          enable = true;
          implementation = "g3proxy";
          proxies = {
            withssh = {
              vpn = "vpn-a";
              definition = "static";
              remote = {
                address = "1.2.3.4";
                port = 8080;
              };
              auth.sshForward = {
                enable = true;
                target = "bastion.example.com";
              };
            };

            nossh = {
              vpn = "vpn-b";
              definition = "static";
              remote = {
                address = "5.6.7.8";
                port = 8080;
              };
            };
          };

          networkmanager.events.handlers = {
            withssh = {
              matchConnectionId = "vpn-a-id";
              proxyToActuate = "withssh";
            };
            nossh = {
              matchConnectionId = "vpn-b-id";
              proxyToActuate = "nossh";
            };
          };
        };
      }
    ];
  };
in
pkgs.testers.nixosTest {
  name = "g3proxy";
  nodes = {
    securix-unbranded-0 = {
      imports = terminal.modules;
    };
  };
  testScript = ''
    securix = securix_unbranded_0
    securix.wait_for_unit("default.target")
    securix.succeed("cat /etc/os-release | grep securix")
    securix.wait_for_unit("g3proxy.service")

    dispatcher = securix.succeed(
      "grep -rl securix-nm-events-hook /etc/NetworkManager/dispatcher.d/"
    ).strip()
    content = securix.succeed(f"cat {dispatcher}")

    assert "start ssh-tunnel-to-withssh.service" in content, (
      "vpn-up: expected the withssh proxy (auth.sshForward.enable) to manage its ssh-tunnel unit"
    )
    assert 'stop "ssh-tunnel-to-withssh.service"' in content, (
      "vpn-down: expected the withssh proxy (auth.sshForward.enable) to stop its ssh-tunnel unit"
    )
    assert "start ssh-tunnel-to-nossh.service" not in content, (
      "vpn-up: the nossh proxy has no auth.sshForward, it must not try to start a ssh-tunnel unit that is never generated for it"
    )
    assert 'stop "ssh-tunnel-to-nossh.service"' not in content, (
      "vpn-down: the nossh proxy has no auth.sshForward, it must not try to stop a ssh-tunnel unit that is never generated for it"
    )
  '';
}

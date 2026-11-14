{ lib, pkgs, ... }:

let
  testPort = 6807;
  testAuth = "test-access-code";

  lanNode =
    { ... }:
    {
      networking = {
        nftables.enable = true;
        firewall.enable = true;
      };

      services.siyuan = {
        enable = true;
        port = testPort;
        accessAuthCode = testAuth;
        openLANSyncFirewall = true;
      };

      # Seed a complete sync identity so the kernel starts LAN sync during boot.
      # The key only needs to be present for this test; no cloud request is made.
      systemd.services.siyuan.preStart = lib.mkBefore ''
        install -d -m 0700 /var/lib/siyuan/conf
        key="$(${pkgs.coreutils}/bin/printf %s test-repo-key | ${pkgs.coreutils}/bin/base64 -w0)"
        cat > /var/lib/siyuan/conf/conf.json <<EOF
        {
          "repo": {
            "key": "$key"
          },
          "sync": {
            "enabled": true,
            "mode": 1,
            "provider": 2,
            "cloudName": "main",
            "lan": {
              "enabled": true,
              "maxConcurrentReqs": 16
            }
          }
        }
        EOF
      '';
    };
in
{
  name = "siyuan";

  nodes.machine = {
    imports = [ lanNode ];

    environment.etc."siyuan-proxy.env" = {
      text = ''
        HTTP_PROXY=http://127.0.0.1:7890
        HTTPS_PROXY=http://127.0.0.1:7890
        NO_PROXY=localhost,127.0.0.1,::1
      '';
      mode = "0400";
      user = "siyuan";
      group = "siyuan";
    };

    services.siyuan = {
      networkProxy = "system";
      environmentFile = "/etc/siyuan-proxy.env";
    };
  };

  nodes.peer = lanNode;

  testScript = ''
    import datetime

    start_all()

    for node in machines:
        node.wait_for_unit("siyuan.service")
        node.wait_for_open_port(${toString testPort})
        node.succeed("curl --fail --max-time 10 --user siyuan:${testAuth} http://127.0.0.1:${toString testPort}/ >/dev/null")
        node.succeed("curl --fail --max-time 10 --user siyuan:${testAuth} http://127.0.0.1:${toString testPort}/appearance/langs/zh-CN.json >/dev/null")

    # net.Interfaces() uses netlink; without AF_NETLINK the kernel reports no
    # private address and LAN sync remains inactive.
    machine.succeed("systemctl show -P RestrictAddressFamilies siyuan.service | grep -qw AF_NETLINK")
    machine.wait_until_succeeds("journalctl -u siyuan.service --no-pager | grep -F 'LAN sync service started'")

    lanStatus = (
        "curl --fail --silent --show-error --max-time 10 "
        "--user siyuan:${testAuth} -X POST "
        "http://127.0.0.1:${toString testPort}/api/sync/getSyncLANStatus"
    )
    for node in machines:
        node.wait_until_succeeds(
            f"{lanStatus} | ${pkgs.jq}/bin/jq -e "
            "'.code == 0 and .data.enabled == true and .data.active == true'"
        )

    # systemd NFTSet= adds the service cgroup to the dedicated nftables set.
    for node in machines:
        node.succeed("nft list table inet siyuan_lan_sync | grep -F 'socket cgroupv2 level 2 @services'")
        node.wait_until_succeeds(
            "nft list set inet siyuan_lan_sync services "
            "| grep -F 'system.slice/siyuan.service'"
        )

    # The LAN firewall option must not expose the web UI port.
    peer.fail("curl --connect-timeout 3 --silent --show-error http://machine:${toString testPort}/ >/dev/null")

    # Discovery, authentication, and the ephemeral TCP listener all have to
    # cross the firewall for connectedPeers to become non-zero.
    for node in machines:
        node.wait_until_succeeds(
            f"{lanStatus} | ${pkgs.jq}/bin/jq -e '.data.connectedPeers >= 1'",
            timeout=datetime.timedelta(seconds=180),
        )

    peer.wait_until_succeeds(
        "journalctl -u siyuan.service --no-pager | grep -F 'authenticated LAN sync peer'"
    )

    # "system" preserves the proxy environment imported by systemd.
    machine.succeed("${pkgs.jq}/bin/jq -e '.system.networkProxy == {\"scheme\":\"system\",\"host\":\"\",\"port\":\"\"}' /var/lib/siyuan/conf/conf.json")
    machine.succeed("tr '\\0' '\\n' < /proc/$(systemctl show -p MainPID --value siyuan)/environ | grep -Fx 'HTTPS_PROXY=http://127.0.0.1:7890'")

    # A web UI change applies immediately, but a restart restores the module's
    # value.
    machine.succeed("curl --fail --max-time 10 --user siyuan:test-access-code -H 'Content-Type: application/json' -d '{\"scheme\":\"socks5\",\"host\":\"127.0.0.1\",\"port\":\"1080\"}' http://127.0.0.1:6807/api/system/setNetworkProxy >/dev/null")
    machine.wait_until_succeeds("${pkgs.jq}/bin/jq -e '.system.networkProxy.scheme == \"socks5\"' /var/lib/siyuan/conf/conf.json")

    # ExecStartPost waits for appearance/, so a restart only reports success
    # once the UI is servable again.
    machine.succeed("systemctl restart siyuan")
    machine.wait_for_open_port(6807)
    machine.succeed("curl --fail --max-time 10 --user siyuan:test-access-code http://127.0.0.1:6807/appearance/langs/zh-CN.json >/dev/null")
    machine.succeed("${pkgs.jq}/bin/jq -e '.system.networkProxy == {\"scheme\":\"system\",\"host\":\"\",\"port\":\"\"}' /var/lib/siyuan/conf/conf.json")
    machine.fail("ss -ltn | grep -q ':6806 '")
    machine.succeed("test -s /var/lib/siyuan/conf/conf.json")

    # Importing settings or calling /api/system/exit makes the kernel exit with
    # status 0, expecting a desktop client to start it again. The unit has to
    # bring it back on its own.
    machine.execute("curl --max-time 10 --user siyuan:test-access-code -X POST http://127.0.0.1:6807/api/system/exit")
    machine.sleep(datetime.timedelta(seconds=8))
    machine.wait_for_unit("siyuan.service")
    machine.wait_for_open_port(6807)
    machine.succeed("curl --fail --max-time 10 --user siyuan:test-access-code http://127.0.0.1:6807/api/system/version >/dev/null")
  '';
}

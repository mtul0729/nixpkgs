{ pkgs, ... }:

{
  name = "siyuan";

  nodes.machine = {
    services.siyuan = {
      enable = true;
      port = 6807;
      accessAuthCode = "test-access-code";
      networkProxy = {
        scheme = "http";
        host = "127.0.0.1";
        port = 7890;
      };
    };
  };

  testScript = ''
    machine.start()

    machine.wait_for_unit("siyuan.service")
    machine.wait_for_open_port(6807)
    machine.succeed("curl --fail --max-time 10 --user siyuan:test-access-code http://127.0.0.1:6807/ >/dev/null")
    machine.succeed("curl --fail --max-time 10 --user siyuan:test-access-code http://127.0.0.1:6807/appearance/langs/zh-CN.json >/dev/null")

    # The module applies its proxy configuration before starting the kernel.
    machine.succeed("${pkgs.jq}/bin/jq -e '.system.networkProxy == {\"scheme\":\"http\",\"host\":\"127.0.0.1\",\"port\":\"7890\"}' /var/lib/siyuan/conf/conf.json")

    # A web UI change applies immediately, but a restart restores the module's
    # value.
    machine.succeed("curl --fail --max-time 10 --user siyuan:test-access-code -H 'Content-Type: application/json' -d '{\"scheme\":\"socks5\",\"host\":\"127.0.0.1\",\"port\":\"1080\"}' http://127.0.0.1:6807/api/system/setNetworkProxy >/dev/null")
    machine.wait_until_succeeds("${pkgs.jq}/bin/jq -e '.system.networkProxy.scheme == \"socks5\"' /var/lib/siyuan/conf/conf.json")

    # ExecStartPost waits for appearance/, so a restart only reports success
    # once the UI is servable again.
    machine.succeed("systemctl restart siyuan")
    machine.wait_for_open_port(6807)
    machine.succeed("curl --fail --max-time 10 --user siyuan:test-access-code http://127.0.0.1:6807/appearance/langs/zh-CN.json >/dev/null")
    machine.succeed("${pkgs.jq}/bin/jq -e '.system.networkProxy == {\"scheme\":\"http\",\"host\":\"127.0.0.1\",\"port\":\"7890\"}' /var/lib/siyuan/conf/conf.json")
    machine.fail("ss -ltn | grep -q ':6806 '")
    machine.succeed("test -s /var/lib/siyuan/conf/conf.json")

    # Importing settings or calling /api/system/exit makes the kernel exit with
    # status 0, expecting a desktop client to start it again. The unit has to
    # bring it back on its own.
    machine.execute("curl --max-time 10 --user siyuan:test-access-code -X POST http://127.0.0.1:6807/api/system/exit")
    machine.sleep(8)
    machine.wait_for_unit("siyuan.service")
    machine.wait_for_open_port(6807)
    machine.succeed("curl --fail --max-time 10 --user siyuan:test-access-code http://127.0.0.1:6807/api/system/version >/dev/null")

    machine.shutdown()
  '';
}

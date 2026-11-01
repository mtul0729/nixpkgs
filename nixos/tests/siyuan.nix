{
  name = "siyuan";

  nodes.machine = {
    services.siyuan = {
      enable = true;
      port = 6807;
      accessAuthCode = "test-access-code";
    };
  };

  testScript = ''
    machine.start()

    machine.wait_for_unit("siyuan.service")
    machine.wait_for_open_port(6807)
    machine.succeed("curl --fail --max-time 10 --user siyuan:test-access-code http://127.0.0.1:6807/ >/dev/null")
    machine.succeed("curl --fail --max-time 10 --user siyuan:test-access-code http://127.0.0.1:6807/appearance/langs/zh-CN.json >/dev/null")

    # ExecStartPost waits for appearance/, so a restart only reports success
    # once the UI is servable again.
    machine.succeed("systemctl restart siyuan")
    machine.wait_for_open_port(6807)
    machine.succeed("curl --fail --max-time 10 --user siyuan:test-access-code http://127.0.0.1:6807/appearance/langs/zh-CN.json >/dev/null")
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

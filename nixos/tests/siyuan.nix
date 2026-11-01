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
    machine.fail("ss -ltn | grep -q ':6806 '")
    machine.succeed("test -s /var/lib/siyuan/conf/conf.json")

    machine.shutdown()
  '';
}

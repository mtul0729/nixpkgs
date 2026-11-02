{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

let
  cfg = config.services.siyuan;

  workspaceDir = "/var/lib/siyuan";
  workingDir = "${cfg.package}/lib/siyuan";

  args = [
    (lib.getExe' cfg.package "siyuan-kernel")
    "serve"
    "--home-dir"
    workspaceDir
    "--workspace"
    workspaceDir
    "--wd"
    workingDir
    "--port"
    (toString cfg.port)
    "--mode"
    "prod"
  ]
  ++ lib.optionals (cfg.accessAuthCode != "") [
    "--accessAuthCode"
    cfg.accessAuthCode
  ]
  ++ lib.optionals cfg.readOnly [
    "--readonly"
    "true"
  ]
  ++ lib.optionals cfg.ssl [
    "--ssl"
  ]
  ++ lib.optionals (cfg.lang != null) [
    "--lang"
    cfg.lang
  ]
  ++ cfg.extraArgs;

  privilegedPort = cfg.port < 1024;

  networkProxyJSON =
    if cfg.networkProxy == null then
      null
    else
      {
        inherit (cfg.networkProxy) scheme host;
        port = if cfg.networkProxy.port == null then "" else toString cfg.networkProxy.port;
      };
in
{
  meta = {
    maintainers = [ lib.maintainers.myul ];
    doc = ./siyuan.md;
  };

  options.services.siyuan = {
    enable = lib.mkEnableOption "SiYuan note server";

    package = lib.mkPackageOption pkgs "siyuan-server" { };

    user = lib.mkOption {
      type = lib.types.str;
      default = "siyuan";
      description = "User account under which SiYuan runs.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "siyuan";
      description = "Group under which SiYuan runs.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 6806;
      description = "Port on which the SiYuan HTTP server listens.";
    };

    networkServe = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether the kernel should listen on all interfaces instead of only
        `127.0.0.1`. Enable this when exposing SiYuan directly or through a
        reverse proxy on another host.
      '';
    };

    networkProxy = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.submodule {
          options = {
            scheme = lib.mkOption {
              type = lib.types.enum [
                ""
                "system"
                "http"
                "https"
                "socks5"
              ];
              description = ''
                Proxy scheme. An empty string connects directly, while
                `system` asks the kernel to use the system proxy configuration.
              '';
            };

            host = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = ''
                Proxy host for the `http`, `https`, and `socks5` schemes. It may
                include credentials in the form `user:password@host`.
              '';
            };

            port = lib.mkOption {
              type = lib.types.nullOr lib.types.port;
              default = null;
              description = ''
                Proxy port for the `http`, `https`, and `socks5` schemes.
              '';
            };
          };
        }
      );
      default = null;
      example = {
        scheme = "http";
        host = "127.0.0.1";
        port = 7890;
      };
      description = ''
        Network proxy used by the kernel for outbound requests. When unset, the
        value stored in {file}`conf.json` is left under the control of the web
        UI. When set, this module writes it before every service start. Changes
        made through the web UI still take effect immediately, but they are
        overwritten on the next restart.

        Setting `HTTP_PROXY` or `HTTPS_PROXY` in the unit environment is not
        sufficient because the kernel resets those variables from this
        configuration during startup.
      '';
    };

    accessAuthCode = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        Access code used by SiYuan's lock screen. The value is passed on the
        kernel command line and is therefore visible to local users and in the
        Nix store. Prefer {option}`services.siyuan.environmentFile` with
        `SIYUAN_ACCESS_AUTH_CODE` for a secret.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/secrets/siyuan.env";
      description = ''
        Optional environment file read by systemd. It can provide
        `SIYUAN_ACCESS_AUTH_CODE` and other runtime environment variables.
      '';
    };

    lang = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "en_US";
      description = "Kernel UI language. Leave unset to use the browser language.";
    };

    readOnly = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to start the kernel in read-only mode.";
    };

    ssl = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Pass `--ssl` to the kernel. This marks authentication cookies as secure
        and is normally used when SiYuan is served over HTTPS, for example
        behind a TLS-terminating reverse proxy.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to open {option}`services.siyuan.port` in the firewall.";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional arguments passed to `siyuan-kernel serve`.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users = lib.mkIf (cfg.user == "siyuan") {
      siyuan = {
        isSystemUser = true;
        group = cfg.group;
        home = workspaceDir;
      };
    };

    users.groups = lib.mkIf (cfg.group == "siyuan") {
      siyuan = { };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];

    assertions = [
      {
        assertion =
          cfg.networkProxy == null
          || builtins.elem cfg.networkProxy.scheme [
            ""
            "system"
          ]
          || (cfg.networkProxy.host != "" && cfg.networkProxy.port != null && cfg.networkProxy.port > 0);
        message = ''
          services.siyuan.networkProxy requires both host and a non-zero port
          when scheme is http, https, or socks5.
        '';
      }
    ];

    warnings =
      lib.optional (cfg.networkServe && cfg.accessAuthCode == "" && cfg.environmentFile == null)
        ''
          services.siyuan is listening on all interfaces without an access code or
          environment file. Set services.siyuan.accessAuthCode or provide
          SIYUAN_ACCESS_AUTH_CODE through services.siyuan.environmentFile.
        '';

    systemd.services.siyuan = {
      description = "SiYuan note server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        HOME = workspaceDir;
        # A system service must not reserve the desktop client's 6806
        # compatibility port. Set `port = 6806` if that endpoint is wanted.
        SIYUAN_DISABLE_FIXED_PORT = "1";
      };

      preStart = ''
        umask 0077
        conf="${workspaceDir}/conf/conf.json"
        mkdir -p "$(dirname "$conf")"
        if [[ ! -s "$conf" ]]; then
          printf '{}\n' > "$conf"
        fi

        tmp="$(mktemp "$conf.XXXXXX")"
        trap 'rm -f "$tmp"' EXIT
        ${lib.getExe pkgs.jq} \
          --argjson networkServe ${lib.boolToString cfg.networkServe} \
          --argjson networkProxy ${lib.escapeShellArg (builtins.toJSON networkProxyJSON)} \
          '.system.networkServe = $networkServe |
           if $networkProxy == null then . else .system.networkProxy = $networkProxy end' \
          "$conf" > "$tmp"
        mv "$tmp" "$conf"
        trap - EXIT
      '';

      # Restart = "always" restarts a kernel that exits cleanly, so a broken
      # workspace would loop every RestartSec; the default 10s/5 start limit
      # never fills at that spacing. Give the limiter a window that does.
      unitConfig = {
        StartLimitIntervalSec = "5min";
        StartLimitBurst = 5;
      };

      # The kernel starts serving before it copies appearance/ into the
      # workspace, so a client that connects right after start still sees 404s.
      # This runs as ExecStartPost, so `systemctl start` returns only once the
      # UI assets are actually there.
      postStart = ''
        for _ in {1..300}; do
          if [[ -s ${workspaceDir}/conf/appearance/langs/zh-CN.json ]]; then
            exit 0
          fi
          sleep 0.1
        done
        echo "warning: appearance resources did not appear within 30s" >&2
      '';

      serviceConfig = {
        Type = "simple";
        ExecStart = utils.escapeSystemdExecArgs args;
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = workspaceDir;
        StateDirectory = "siyuan";
        StateDirectoryMode = "0700";
        EnvironmentFile = lib.mkIf (cfg.environmentFile != null) cfg.environmentFile;
        # The kernel exits with status 0 when the settings are imported or
        # /api/system/exit is called, expecting its desktop client to start it
        # again; nothing does that here, so restart on clean exits too.
        Restart = "always";
        # Back off instead of hitting a broken workspace every five seconds.
        RestartSec = "2s";
        RestartSteps = 5;
        RestartMaxDelaySec = "1min";

        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectHostname = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        SystemCallArchitectures = "native";
        UMask = "0077";

        AmbientCapabilities = lib.optional privilegedPort "CAP_NET_BIND_SERVICE";
        CapabilityBoundingSet = lib.optional privilegedPort "CAP_NET_BIND_SERVICE";
      };
    };
  };
}

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
  fixedPortFlagSupported =
    cfg.package.passthru.fixedPortFlagSupported or (
      lib.versionAtLeast cfg.package.version "3.8.10"
      || (
        lib.versionOlder cfg.package.version "3.8.10"
        && lib.versionAtLeast cfg.package.version "3.8.10-alpha.3"
      )
    );

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
  ++ lib.optionals fixedPortFlagSupported [
    "--fixed-port=false"
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
    else if cfg.networkProxy == "system" then
      {
        scheme = "system";
        host = "";
        port = "";
      }
    else
      {
        scheme = "";
        host = "";
        port = "";
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
        lib.types.enum [
          "system"
          "direct"
        ]
      );
      default = null;
      example = "system";
      description = ''
        Network proxy mode used by the kernel for outbound requests.

        `null` leaves the value in {file}`conf.json` under the web UI's control.
        `"system"` tells the kernel to retain the environment it inherited from
        systemd, including `HTTP_PROXY`, `HTTPS_PROXY`, and `NO_PROXY`.
        `"direct"` disables proxying.

        This option only controls the proxy mode. Supply proxy URLs through
        {option}`services.siyuan.environmentFile`, not in this Nix expression:
        the kernel clears proxy environment variables unless the mode is
        `"system"`, and credentials in the Nix store are readable by every local
        user.

        When this option is set, the module writes the corresponding value to
        {file}`conf.json` before service start, but only if it differs from the
        current value. Changes made through the web UI remain active until the
        next service restart.
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
      type = lib.types.nullOr lib.types.externalPath;
      default = null;
      example = "/run/secrets/siyuan-proxy.env";
      description = ''
        Optional environment file read by systemd at service start. The file
        must be readable by {option}`services.siyuan.user` and should be
        readable only by that user, for example mode `0600`.

        It can provide `SIYUAN_ACCESS_AUTH_CODE` and other runtime environment
        variables. With {option}`services.siyuan.networkProxy` set to
        `"system"`, it must provide the desired proxy variables, for example:

        ```text
        HTTP_PROXY=http://127.0.0.1:7890
        HTTPS_PROXY=http://127.0.0.1:7890
        NO_PROXY=localhost,127.0.0.1,::1
        ```

        Keep this file outside the Nix store, such as a `sops-nix` template
        under {file}`/run/secrets`. Pass its runtime path as a string so Nix
        does not copy it into the store.
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
        assertion = cfg.networkProxy != "system" || cfg.environmentFile != null;
        message = ''
          services.siyuan.networkProxy = "system" requires
          services.siyuan.environmentFile to provide HTTP_PROXY or HTTPS_PROXY.
        '';
      }
    ];

    warnings = lib.optional (cfg.networkServe && cfg.accessAuthCode == "") ''
      services.siyuan is listening on all interfaces without
      services.siyuan.accessAuthCode. If the access code is supplied by
      services.siyuan.environmentFile, make sure it contains
      SIYUAN_ACCESS_AUTH_CODE.
    '';

    systemd.services.siyuan = {
      description = "SiYuan note server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        HOME = workspaceDir;
      }
      // lib.optionalAttrs (!fixedPortFlagSupported) {
        # A system service must not reserve the desktop client's 6806
        # compatibility port. Older kernels need the environment variable
        # understood by the package's patch.
        SIYUAN_DISABLE_FIXED_PORT = "1";
      };

      preStart = ''
        umask 0077
        conf="${workspaceDir}/conf/conf.json"
        mkdir -p "$(dirname "$conf")"
        if [[ ! -s "$conf" ]]; then
          printf '{}\n' > "$conf"
        fi

        if ${lib.getExe pkgs.jq} -e \
          --argjson networkServe ${lib.boolToString cfg.networkServe} \
          --argjson networkProxy ${lib.escapeShellArg (builtins.toJSON networkProxyJSON)} \
          '(.system.networkServe == $networkServe) and
           ($networkProxy == null or .system.networkProxy == $networkProxy)' \
          "$conf" >/dev/null; then
          exit 0
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

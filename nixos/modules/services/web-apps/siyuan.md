# SiYuan {#module-services-siyuan}

[SiYuan](https://b3log.org/siyuan/) is a privacy-first personal knowledge
management system. This module runs the SiYuan kernel and serves its web UI.

## Quickstart {#module-services-siyuan-quickstart}

The following configuration starts SiYuan on `127.0.0.1:6806` with its data in
`/var/lib/siyuan`:

```nix
{
  services.siyuan = {
    enable = true;
    accessAuthCode = "replace-this";
  };
}
```

To make the instance reachable from other machines, enable
{option}`services.siyuan.networkServe` and optionally open the firewall:

```nix
{
  services.siyuan = {
    enable = true;
    networkServe = true;
    openFirewall = true;
    accessAuthCode = "replace-this";
  };
}
```

The access code is passed on the command line. For a secret that is not visible
in the Nix store, use an environment file instead:

```nix
{
  services.siyuan = {
    enable = true;
    networkServe = true;
    environmentFile = "/run/secrets/siyuan.env";
  };
}
```

The environment file can contain:

```text
SIYUAN_ACCESS_AUTH_CODE=replace-this
```

The kernel's data directory is managed by systemd as
{file}`/var/lib/siyuan`. Configuration written by the web UI is kept in
{file}`/var/lib/siyuan/conf/conf.json`.

## Reverse proxy {#module-services-siyuan-reverse-proxy}

When placing SiYuan behind a TLS-terminating reverse proxy, keep
`networkServe = false` if the proxy connects over loopback, or enable it when
the proxy connects over the network. Set {option}`services.siyuan.ssl` when the
public URL uses HTTPS so authentication cookies are marked secure.

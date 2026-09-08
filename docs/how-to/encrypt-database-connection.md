---
title: Encrypt the database connection
type: how-to
last_reviewed: 2026-09-08
status: current
---

# Encrypt the database connection

By default the container talks to MySQL in plaintext. Mount a certificate under `/deskpro/ssl/mysql/` to encrypt it — the presence of the file is the switch, the same way the [HTTPS certificate](./enable-https.md) works. There is no env var to set.

This matters more than it might look: PHP in this image uses `mysqlnd`, which — unlike `libmysqlclient` — does **not** negotiate TLS opportunistically. With no certificate mounted the connection is plaintext even when the server offers encryption. There is no "encrypted if available" middle ground; you have to ask for it.

## Encrypt the connection

Mount the CA that signed your database server's certificate:

```bash
docker run -d --env-file config.env \
    -v "$PWD/rds-ca.pem:/deskpro/ssl/mysql/ca.pem:ro" \
    deskpro/deskpro-product:$DPVERSION-onprem-$CONTAINER_VERSION
```

That is the equivalent of a `REQUIRE SSL` grant: the connection is encrypted, and the server can enforce it. `ca.crt` works as a filename too.

At boot, `20-certs.sh` copies the file to `/srv/deskpro/INSTANCE_DATA/mysql-ca.crt` and the templates point both PHP and the CLI tools at that path directly.

It is **not** added to the system trust store. Both clients read the path they are given, so the CA never needs to be in `/etc/ssl/certs/ca-certificates.crt` — and putting it there would trust your database's CA for curl, LDAP and every other TLS consumer in the image. If that is what you want, mount it under [`/deskpro/ssl/ca-certificates/`](./enable-https.md) instead, which is the dedicated path for it.

The file must be a parseable PEM certificate. PHP never opens it (see below), but the `mysql` CLI does, and fails with `ERROR 2026 (HY000): TLS/SSL error: no certificate or crl found` if it can't be read.

If the server has TLS disabled, the connection now fails rather than silently falling back to plaintext.

### The server certificate is not verified

Encryption is on, but the server's certificate is **not** checked. That stops passive eavesdropping; it does not stop an attacker who can intercept the connection and present their own certificate.

This is a deliberate limitation of what PDO exposes. `MYSQL_ATTR_SSL_VERIFY_SERVER_CERT` is a single boolean, and when `mysqlnd` honours it, it verifies the CA chain **and** that the certificate's CN or SAN matches the host you connected to — MySQL's `VERIFY_IDENTITY`, with no CA-only step in between.

Because verification is off, `mysqlnd` never opens the CA file at all: its only effect is to switch encryption on. The mounted CA is therefore not checked against what the server presents. Most MySQL servers ship an auto-generated certificate with `CN=MySQL_Server_<version>_Auto_Generated_Server_Certificate`, which matches no hostname, so enabling it would break those deployments outright:

```
SQLSTATE[HY000] [2002] Cannot connect to MySQL using SSL
```

If you need protection against an active man-in-the-middle, secure the network path to the database as well — a private subnet, a peered VPC, or an SSH/WireGuard tunnel.

## Client certificates (`REQUIRE X509`)

A client certificate is how the *server* authenticates *you*. It is a separate concern from encrypting the connection, and most deployments do not need one — only if the MySQL grant says `REQUIRE X509` (or `REQUIRE SUBJECT`/`ISSUER`) rather than plain `REQUIRE SSL`.

Mount both halves:

| Mount target | Format |
| --- | --- |
| `/deskpro/ssl/mysql/client.crt` | PEM |
| `/deskpro/ssl/mysql/client.key` | PEM, unencrypted |

```bash
docker run -d --env-file config.env \
    -v "$PWD/client.crt:/deskpro/ssl/mysql/client.crt:ro" \
    -v "$PWD/client.key:/deskpro/ssl/mysql/client.key:ro" \
    -v "$PWD/ca.pem:/deskpro/ssl/mysql/ca.pem:ro" \
    deskpro/deskpro-product:$DPVERSION-onprem-$CONTAINER_VERSION
```

The pair also encrypts the connection on its own, so the CA is optional here. Mounting the pair alone was the only way to get TLS in older images, and it still works.

The key is copied to `/srv/deskpro/INSTANCE_DATA/mysql-client.key` as `root:dp_app` mode `0640`, so only root and the application user can read it.

## What each mount does

| Mounted under `/deskpro/ssl/mysql/` | Connection encrypted | Client authenticated |
| --- | --- | --- |
| nothing | no | no |
| `ca.pem` | yes | no |
| `client.crt` + `client.key` | yes | yes |
| `ca.pem` + `client.crt` + `client.key` | yes | yes |

## The CLI tools

`mysql-primary`, `mysql-read` and `mysqldump-primary` follow the same mounts, so backups and admin shells are encrypted whenever the application's connection is. The client in this image is MariaDB's, which has no `--ssl-mode`; the generated `~/.my-auto.cnf` uses `ssl`, `ssl-ca` and `ssl-verify-server-cert` instead.

Note that MariaDB's client defaults both `ssl` and `ssl-verify-server-cert` to on, so with nothing mounted the generated config sets `ssl=0` explicitly to keep the CLI in step with the application.

The application's own `mysqldump_path` / `mysql_path` config points at `/usr/bin/mysqldump` and `/usr/bin/mysql` directly, bypassing these wrappers — those invocations are not covered.

## Verifying

Check what the container actually negotiated, not what you mounted:

```bash
docker exec <container> mysql-primary -e "SHOW SESSION STATUS LIKE 'Ssl_cipher'"
```

An empty `Value` means the connection is **not** encrypted.

To check the connection the application itself makes:

```bash
docker exec <container> php -r '
  require "/srv/deskpro/INSTANCE_DATA/config.php";
  $db = $CONFIG["database"];
  $p = new PDO("mysql:host={$db["host"]};port={$db["port"]};dbname={$db["dbname"]}",
               $db["user"], $db["password"], $db["pdo_options"]);
  print_r($p->query("SHOW SESSION STATUS LIKE \"Ssl_cipher\"")->fetchAll(PDO::FETCH_ASSOC));
'
```

Setting `require_secure_transport=ON` on the server is the strongest check of all — it rejects any unencrypted connection, so a misconfigured container fails loudly instead of quietly sending your data in the clear.

## Related

- [Enable HTTPS on the built-in web server](./enable-https.md) — inbound TLS and custom CAs.
- [Ports and mount conventions](../reference/ports-and-mounts.md) — the full `/deskpro/ssl/` layout.

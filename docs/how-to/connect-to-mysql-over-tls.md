---
title: Connect to MySQL over TLS
type: how-to
last_reviewed: 2026-09-09
status: current
---

# Connect to MySQL over TLS

MySQL user accounts can demand TLS at two different strengths, and the container supports both, plus the case where the server offers TLS and you simply want to use it.

| MySQL account grant                                  | What the client must do                                            | What to configure here                                           |
| ---------------------------------------------------- | ------------------------------------------------------------------ | ---------------------------------------------------------------- |
| `REQUIRE SSL`                                        | Encrypt the connection. No certificate needed.                     | `DESKPRO_DB_SSL_ENABLED=true`, or mount a CA.                    |
| `REQUIRE SSL` + you want the server identity checked | Encrypt, and verify the server certificate against a CA you trust. | Mount `ca.pem` and set `DESKPRO_DB_SSL_VERIFY_SERVER_CERT=true`. |
| `REQUIRE X509`                                       | Present a client certificate signed by a CA the server trusts.     | Mount `client.crt` + `client.key`.                               |

These settings apply to **all three** database connections — primary, read replica, and reports.

## Encryption only, no certificates

For an account created with `REQUIRE SSL`:

```bash
docker run -d --env-file config.env \
    -e DESKPRO_DB_SSL_ENABLED=true \
    deskpro/deskpro-product:$DPVERSION-onprem-$CONTAINER_VERSION
```

The connection is encrypted against the system CA path but the server certificate is **not** verified.

## Verifying the server certificate

Mount the CA that signed your database server's certificate:

| Mount target                | Format |
| --------------------------- | ------ |
| `/deskpro/ssl/mysql/ca.pem` | PEM    |

```bash
docker run -d --env-file config.env \
    -v "$PWD/mysql-ca.pem:/deskpro/ssl/mysql/ca.pem:ro" \
    -e DESKPRO_DB_SSL_VERIFY_SERVER_CERT=true \
    deskpro/deskpro-product:$DPVERSION-onprem-$CONTAINER_VERSION
```

Mounting `ca.pem` enables TLS on its own — `DESKPRO_DB_SSL_ENABLED` is not needed as well. What the env var adds is the identity check.

Verification is **off by default** so that existing deployments with self-signed or hostname-mismatched database certificates keep working after an upgrade. Turn it on deliberately.

The CA is used for the database connection only. It is not added to the OS trust store, so it does not widen trust for curl, SMTP, or anything else in the container. To do that, use `/deskpro/ssl/ca-certificates/*.crt` instead — see [Enable HTTPS](./enable-https.md#adding-trusted-cas).

## Client certificate authentication

For an account created with `REQUIRE X509`:

| Mount target                    | Required | Format           |
| ------------------------------- | -------- | ---------------- |
| `/deskpro/ssl/mysql/client.crt` | yes      | PEM              |
| `/deskpro/ssl/mysql/client.key` | yes      | PEM, unencrypted |
| `/deskpro/ssl/mysql/ca.pem`     | no       | PEM              |

```bash
docker run -d --env-file config.env \
    -v "$PWD/client.crt:/deskpro/ssl/mysql/client.crt:ro" \
    -v "$PWD/client.key:/deskpro/ssl/mysql/client.key:ro" \
    -v "$PWD/mysql-ca.pem:/deskpro/ssl/mysql/ca.pem:ro" \
    deskpro/deskpro-product:$DPVERSION-onprem-$CONTAINER_VERSION
```

The pair enables TLS on its own; no env var is needed.

If you want `DESKPRO_DB_SSL_VERIFY_SERVER_CERT=true` alongside a client certificate, you must also mount `ca.pem`. Without it the CA setting stays at the legacy `/etc/ssl/certs` **directory**, which `MYSQL_ATTR_SSL_CA` does not accept as a verification source, and the connection will fail. This path is kept as-is deliberately, so that existing client-certificate deployments render exactly the same configuration they did before these options existed.

## Boot failures

The container refuses to start rather than silently downgrading to an unencrypted connection:

| Boot log error                                                                                                              | Cause                                                                                                                                                             |
| --------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Incomplete MySQL client certificate: both /deskpro/ssl/mysql/client.crt and /deskpro/ssl/mysql/client.key must be mounted` | Only one half of the pair is mounted. Previously this was ignored and the connection ran unencrypted.                                                             |
| `<path> is mounted but is not a readable file`                                                                              | Something exists at a cert path but isn't a readable regular file — usually a dangling symlink, or a directory created by Docker when the host path didn't exist. |
| `Failed to install MySQL CA certificate from /deskpro/ssl/mysql/ca.pem`                                                     | The copy failed. Check the mount is readable by root.                                                                                                             |

The "not a readable file" case is usually the classic Docker mistake: `-v "$PWD/typo.pem:/deskpro/ssl/mysql/ca.pem"` with a source path that doesn't exist. Docker creates a _directory_ at the source and mounts that, so the container sees a directory where a certificate should be. Before this check existed, that scenario disabled TLS without a word.

## Known limitation

The bundled `mysql-primary`, `mysql-read`, and `mysqldump-primary` helper CLIs do **not** use TLS — `user.my.cnf.tmpl` has no `ssl-*` keys. Only the application's PDO connections are covered. If your database enforces `REQUIRE SSL` at the account level, those helpers will be rejected by the server.

## Verifying

Check what was rendered into the app config:

```bash
docker exec <container> grep MYSQL_ATTR /srv/deskpro/INSTANCE_DATA/deskpro-config.php
```

Expected shapes:

```php
// encryption only
$pdo_options[\PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT] = false;
$pdo_options[\PDO::MYSQL_ATTR_SSL_CA] = '/etc/ssl/certs';

// custom CA, server identity verified
$pdo_options[\PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT] = true;
$pdo_options[\PDO::MYSQL_ATTR_SSL_CA] = '/srv/deskpro/INSTANCE_DATA/mysql-ca.pem';

// client certificate
$pdo_options[\PDO::MYSQL_ATTR_SSL_CERT] = "/srv/deskpro/INSTANCE_DATA/mysql-client.crt";
$pdo_options[\PDO::MYSQL_ATTR_SSL_KEY] = "/srv/deskpro/INSTANCE_DATA/mysql-client.key";
```

No output at all means TLS is off.

Confirm the certificates were installed:

```bash
docker exec <container> ls -l /srv/deskpro/INSTANCE_DATA/mysql-*
```

And from the server side, once the app has connected:

```sql
SHOW SESSION STATUS LIKE 'Ssl_cipher';
```

An empty `Ssl_cipher` means that session is not encrypted.

Certificates are copied at boot, so changing a mounted file requires a container restart.

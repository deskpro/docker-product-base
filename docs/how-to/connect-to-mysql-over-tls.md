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

By default these settings apply to all three database connections — primary, read replica, and reports. Each can also be configured on its own; see [Different certificates per connection](#different-certificates-per-connection).

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

If you want `DESKPRO_DB_SSL_VERIFY_SERVER_CERT=true` alongside a client certificate, you must also mount `ca.pem`. Without it the CA setting stays at the legacy `/etc/ssl/certs` **directory**, which `MYSQL_ATTR_SSL_CA` does not accept as a verification source — so the container refuses to boot rather than let you find out at query time. The `/etc/ssl/certs` value is kept as-is deliberately, so that existing client-certificate deployments without verification render exactly the same configuration they did before these options existed.

## Different certificates per connection

The read replica and the reports database may be different servers behind different CAs. Each connection reads its own mount directory and its own pair of environment variables:

| Connection | Mount directory | Environment variables |
| ---------- | --------------- | --------------------- |
| primary | `/deskpro/ssl/mysql/` | `DESKPRO_DB_SSL_ENABLED`, `DESKPRO_DB_SSL_VERIFY_SERVER_CERT` |
| read | `/deskpro/ssl/mysql/read/` | `DESKPRO_DB_READ_SSL_ENABLED`, `DESKPRO_DB_READ_SSL_VERIFY_SERVER_CERT` |
| reports | `/deskpro/ssl/mysql/reports/` | `DESKPRO_DB_REPORTS_SSL_ENABLED`, `DESKPRO_DB_REPORTS_SSL_VERIFY_SERVER_CERT` |

Each directory takes the same three filenames: `ca.pem`, `client.crt`, `client.key`.

**Certificates are directory-scoped.** Mount anything into `read/` and that directory becomes the whole story for the read connection — it takes nothing from the primary. Mount nothing and it uses the primary's set entire. There is no half-way: a replica that mounts only `read/ca.pem` gets that CA and *no client certificate*, even if the primary has one.

The point is that a connection's certificates are always readable off its own mount. Nothing arrives that you didn't put there.

**The environment variables work the other way round.** An absent variable signals nothing, while a placed file signals intent, so the vars cascade: unset takes the primary's value, an explicit value wins. That includes `false` — `DESKPRO_DB_READ_SSL_ENABLED=false` really does leave the replica unencrypted while the primary stays on TLS. Setting it is the only way to get that, and it is a legitimate topology: primary over a WAN, replica on a trusted LAN.

One exception, for backwards compatibility: mounted certificates always enable TLS for their connection, so an explicit `false` alongside a mounted cert does not disable it. Remove the certificates if you want that connection in the clear.

A replica behind its own CA, using a client certificate on both. Note the client pair has to be mounted into `read/` as well — it will not be inherited, because `read/ca.pem` makes that directory self-describing:

```bash
docker run -d --env-file config.env \
    -v "$PWD/client.crt:/deskpro/ssl/mysql/client.crt:ro" \
    -v "$PWD/client.key:/deskpro/ssl/mysql/client.key:ro" \
    -v "$PWD/primary-ca.pem:/deskpro/ssl/mysql/ca.pem:ro" \
    -v "$PWD/replica-ca.pem:/deskpro/ssl/mysql/read/ca.pem:ro" \
    -v "$PWD/client.crt:/deskpro/ssl/mysql/read/client.crt:ro" \
    -v "$PWD/client.key:/deskpro/ssl/mysql/read/client.key:ro" \
    -e DESKPRO_DB_READ_HOST=mysql-replica \
    deskpro/deskpro-product:$DPVERSION-onprem-$CONTAINER_VERSION
```

The rendered config gives each connection its own PDO options array — `$pdo_options`, `$pdo_options_read` and `$pdo_options_reports` — so you can read off exactly what each one will use.

Certificates are copied at boot and the copies are cleared on every boot, so removing a mount and restarting really does remove it. Nothing survives from the previous run.

## Boot failures

The container refuses to start rather than silently downgrading to an unencrypted connection:

| Boot log error                                                                                                              | Cause                                                                                                                                                             |
| --------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Incomplete MySQL client certificate: both <dir>/client.crt and <dir>/client.key must be mounted` | Only one half of the pair is mounted, in whichever directory `<dir>` names. Previously this was ignored and the connection ran unencrypted.                       |
| `<path> is mounted but is not a readable file`                                                                              | Something exists at a cert path but isn't a readable regular file — usually a dangling symlink, or a directory created by Docker when the host path didn't exist. |
| `Failed to install MySQL CA certificate from <dir>/ca.pem`                                                                  | The copy failed. Check the mount is readable by root.                                                                                                             |
| `DESKPRO_DB_..._SSL_VERIFY_SERVER_CERT is set but no CA certificate is available` | Verification was asked for on a connection with no CA file. See below. |

Verification without a CA is refused because it cannot work. `MYSQL_ATTR_SSL_CA` needs a *file*, and the `/etc/ssl/certs` fallback is a directory, which OpenSSL will not load as a CA bundle. Left alone it would surface as a connection error on the first query, long after the container looked healthy. Mount a `ca.pem` for that connection, or turn verification off.

If you are upgrading and the container now refuses to start with this message, the connection it names was already failing at query time — the check moved the error, it did not create it.

The "not a readable file" case is usually the classic Docker mistake: `-v "$PWD/typo.pem:/deskpro/ssl/mysql/ca.pem"` with a source path that doesn't exist. Docker creates a _directory_ at the source and mounts that, so the container sees a directory where a certificate should be. Before this check existed, that scenario disabled TLS without a word.

## The helper CLIs

`mysql-primary`, `mysql-read` and `mysqldump-primary` resolve TLS from the same mounts and variables, so an account with `REQUIRE SSL` or `REQUIRE X509` works from the shell too. `mysql-read` uses the read connection's settings; the other two use the primary's.

The `ssl-mode` they render is the mysql client's equivalent of the PDO attributes:

| Your setting | `ssl-mode` |
| ------------ | ---------- |
| TLS on, verification off | `REQUIRED` |
| TLS on, `..._SSL_VERIFY_SERVER_CERT=true` | `VERIFY_IDENTITY` |

There is no `ssl-capath` fallback: a connection set to verify with no CA file refuses to boot, so `VERIFY_IDENTITY` always has an `ssl-ca` to go with it. The CLIs and PDO see exactly the same configuration, which is what makes them useful for diagnosing it.

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

No output at all means TLS is off. The read and reports connections appear as `$pdo_options_read` and `$pdo_options_reports`.

Confirm the certificates were installed:

```bash
docker exec <container> ls -l /srv/deskpro/INSTANCE_DATA/mysql-*
```

Check what the helper CLIs will use — each one rewrites `~/.my-auto.cnf` when it runs:

```bash
docker exec <container> grep -A2 ssl- ~/.my-auto.cnf
```

And from the server side, once the app has connected:

```sql
SHOW SESSION STATUS LIKE 'Ssl_cipher';
```

An empty `Ssl_cipher` means that session is not encrypted.

Changing a mounted certificate requires a container restart.

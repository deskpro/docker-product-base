---
title: Enable HTTPS on the built-in web server
type: how-to
last_reviewed: 2026-04-17
status: current
---

# Enable HTTPS on the built-in web server

The built-in nginx does not listen on 443 by default. Enable it by mounting a certificate and key — no env var is needed to "turn on" HTTPS; the presence of the cert is the switch.

In most real deployments you should terminate TLS at a reverse proxy instead. This guide is for cases where the container talks directly to the public internet.

## Mount a certificate

| Mount target | Required | Format |
| --- | --- | --- |
| `/deskpro/ssl/certs/deskpro-https.crt` | yes | PEM |
| `/deskpro/ssl/private/deskpro-https.key` | yes | PEM, unencrypted |

Example:

```bash
docker run -d --env-file config.env \
    -v "$PWD/my-cert.crt:/deskpro/ssl/certs/deskpro-https.crt:ro" \
    -v "$PWD/my-cert.key:/deskpro/ssl/private/deskpro-https.key:ro" \
    -p 80:80 -p 443:443 \
    deskpro/deskpro-product:$DPVERSION-onprem-$CONTAINER_VERSION
```

Mount as root-owned with mode `0600` for the key. The entrypoint copies and re-owns these at boot; permissions on the host mount only need to let root read them.

## Testing-only: the bundled self-signed cert

Setting `HTTP_USE_TESTING_CERTIFICATE=true` makes the container listen on 443 using a self-signed cert that ships inside the image.

**This cert is published with the public image — its private key is not secret.** Anyone can decrypt traffic encrypted with it. Use it only for:

- Local development.
- Confirming HTTPS plumbing works before wiring in a real cert.
- Automated tests.

Never use it in production.

## Adding trusted CAs

If your deployment talks to external services (SMTP, API backends) signed by a private CA, drop PEM files into `/deskpro/ssl/ca-certificates/*.crt`. They're rsync'd into `/usr/local/share/ca-certificates/` and `update-ca-certificates` runs at boot, so PHP, curl, and every other TLS consumer in the image trusts them.

## MySQL TLS

To connect to MySQL over TLS, mount:

- `/deskpro/ssl/mysql/client.crt`
- `/deskpro/ssl/mysql/client.key`
- `/deskpro/ssl/mysql/ca.pem` (optional, if the server cert isn't in the system trust store)

The presence of the first two enables TLS automatically — no additional env var needed.

## Verifying

After the container is up:

```bash
docker exec <container> openssl s_client -connect 127.0.0.1:443 -servername your-host </dev/null \
    | openssl x509 -noout -subject -issuer -dates
```

Or from outside the container, just hit `https://your-host/` and check the cert in your browser.

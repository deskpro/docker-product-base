---
title: Configure Deskpro behind a reverse proxy
type: how-to
last_reviewed: 2026-04-17
status: current
---

# Configure Deskpro behind a reverse proxy

Deskpro needs to know the *original* request details — the client's IP, the host they hit, the scheme they used, the port they connected on — in order to generate correct absolute URLs, enforce cookie flags, and rate-limit properly. When a reverse proxy terminates the connection, those details get rewritten. You have to tell Deskpro how to recover them.

There are three ways to do that, in decreasing order of preference:

1. **PROXY protocol** on ports 9080 / 9443 — client IP and port are carried by the protocol itself. Use this when your load balancer supports it.
2. **HTTP headers** on ports 80 / 443 — your proxy sets `X-Forwarded-*` or vendor-specific headers, and you tell Deskpro which to trust.
3. **Static values** — when something is always the same (e.g. the serving hostname never changes), hard-code it.

## Security caveat

**Deskpro trusts any header you tell it to read, unconditionally.** Headers are trivial to spoof. Before enabling proxy headers:

1. Firewall the container so only the reverse proxy can reach ports 80 / 443 / 9080 / 9443.
2. Ensure your proxy strips or overwrites incoming `X-Forwarded-*` headers from clients — otherwise an attacker can claim any IP.

Without both of these, the trust relationship is broken.

## Option 1: PROXY protocol

Your load balancer connects to the container on port `9080` (HTTP + PROXY) or `9443` (HTTPS + PROXY) and sends a PROXY header with the original client's address. Deskpro reads the client IP and port from the PROXY frame — no env vars needed for those.

You may still need `HTTP_USER_REAL_PROTO_HEADER` and `HTTP_USER_REAL_HOST_HEADER` if your LB terminates TLS and forwards over a different scheme or hostname.

## Option 2: Standard proxy headers

A generic load balancer or reverse proxy sending `X-Forwarded-*`:

```env
HTTP_USER_REAL_IP_HEADER=X-Forwarded-For
HTTP_USER_REAL_HOST_HEADER=X-Forwarded-Host
HTTP_USER_REAL_PROTO_HEADER=X-Forwarded-Proto
HTTP_USER_REAL_PORT_HEADER=X-Forwarded-Port
```

## Option 3: Cloudflare

Cloudflare uses its own header for the client IP:

```env
HTTP_USER_REAL_IP_HEADER=CF-Connecting-IP
HTTP_USER_REAL_PROTO_HEADER=X-Forwarded-Proto
```

Cloudflare preserves the `Host` header, so you don't need `HTTP_USER_REAL_HOST_HEADER`. If Cloudflare is configured to connect to the origin over HTTP (Flexible SSL), the `X-Forwarded-Proto` tells Deskpro the user was on HTTPS.

Lock down your host firewall to [Cloudflare IP ranges](https://www.cloudflare.com/ips/). Otherwise, an attacker bypassing Cloudflare can spoof the headers.

## Option 4: Static values

When a value is always the same, skip the header and set it statically:

```env
HTTP_SERVE_HOST=support.example.com       # Instead of HTTP_USER_REAL_HOST_HEADER
HTTP_USER_SET_HTTP_PROTO=http
HTTP_USER_SET_HTTP_PORT=80
HTTP_USER_SET_HTTPS_PROTO=https
HTTP_USER_SET_HTTPS_PORT=443
```

## Port-mapping example

If you're not proxying but instead mapping the container's port to something non-standard (e.g. running Deskpro on `:8080`), tell Deskpro what port the user actually sees:

```bash
docker run --env-file config.env \
    -p 8080:80 -p 8443:443 \
    -e HTTP_USER_SET_HTTP_PORT=8080 \
    -e HTTP_USER_SET_HTTPS_PORT=8443 \
    deskpro/deskpro-product:$DPVERSION-onprem-$CONTAINER_VERSION
```

Without these, Deskpro will generate URLs referring to port 80/443 and your users will get broken links.

## Verifying

Hit your deployment through the proxy and check a rendered page's asset URLs — they should use your public host and the correct scheme. Alternatively:

```bash
docker exec <container> container-var HTTP_USER_REAL_IP_HEADER
docker exec <container> container-var HTTP_SERVE_HOST
```

And inspect an actual request — Deskpro logs include the resolved client IP in access logs.

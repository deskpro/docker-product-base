#!/usr/bin/env bash
#
# Compares the PHP that two images ship -- modules per SAPI, extension
# versions and functions, ini values, load order, linked library versions --
# and prints a unified diff. Used to check PHP_INSTALL_METHOD=source against
# the default deb build:
#
#   docker build -t deskpro/docker-product-base:php-deb .
#   docker build --build-arg PHP_INSTALL_METHOD=source -t deskpro/docker-product-base:php-source .
#   test/compare-php-builds.sh deskpro/docker-product-base:php-deb deskpro/docker-product-base:php-source
#
# Each image boots through the real entrypoint ("none" run mode), so the rendered
# /etc/php/8.3 config is what's compared. Exits 1 if the reports differ;
# the raw reports are kept in the directory printed at the end.
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "usage: $0 <image-a> <image-b>" >&2
  exit 2
fi

work="$(mktemp -d)"

cat > "$work/probe.sh" <<'PROBE'
#!/bin/bash
set -u

section() { printf '\n== %s ==\n' "$1"; }

# phpinfo without the parts that differ per run or per container
phpinfo_stable() {
  sed -e '/^Environment$/,/^PHP License$/d' \
      -e '/^Build date/d' -e '/^System =>/d' -e '/^Build System/d' \
      -e '/^Start time =>/d' -e 's/^Zend Engine v[0-9.]*/Zend Engine v<zend-version>/'
}

section "version"
php -v | head -n1 | sed -E 's/\(built: [^)]*\)//'

section "cli modules"
php -m

section "fpm modules"
php-fpm8.3 -m

section "cli conf.d"
ls -1 /etc/php/8.3/cli/conf.d
section "fpm conf.d"
ls -1 /etc/php/8.3/fpm/conf.d

section "mods-available"
for f in /etc/php/8.3/mods-available/*.ini; do
  printf '%s %s\n' "$(basename "$f" .ini)" "$(grep -m1 -oE 'priority=[0-9]+' "$f")"
done

section "extension dir"
ls -1 "$(php -r 'echo ini_get("extension_dir");')"

section "binaries"
ls -1 /usr/bin/php* /usr/bin/phar* /usr/sbin/php* 2>/dev/null

section "extension versions and functions"
php -r '
$exts = get_loaded_extensions();
sort($exts);
foreach ($exts as $e) {
    echo $e, " ", phpversion($e), "\n";
    $funcs = get_extension_funcs($e) ?: [];
    sort($funcs);
    foreach ($funcs as $f) echo "  ", $f, "\n";
}'

section "runtime capabilities"
php -r '
echo "password_algos: ", implode(",", password_algos()), "\n";
echo "hash_algos: ", implode(",", hash_algos()), "\n";
echo "stream wrappers: ", implode(",", stream_get_wrappers()), "\n";
echo "stream transports: ", implode(",", stream_get_transports()), "\n";
echo "stream filters: ", implode(",", stream_get_filters()), "\n";
echo "timezonedb: ", timezone_version_get(), "\n";
echo "openssl ciphers: ", count(openssl_get_cipher_methods()), "\n";
echo "mb encodings: ", count(mb_list_encodings()), "\n";
echo "gd_info: ", json_encode(gd_info()), "\n";
echo "PHP_OS/INT_SIZE/ZTS/DEBUG: ", PHP_OS, " ", PHP_INT_SIZE, " ", PHP_ZTS, " ", PHP_DEBUG, "\n";
'

section "cli phpinfo"
php -i | phpinfo_stable

section "fpm phpinfo"
php-fpm8.3 -i | phpinfo_stable
PROBE
chmod +x "$work/probe.sh"

# "none" mode runs the full entrypoint (so configs are rendered) but starts no
# app services, which would wait forever for a Deskpro install in a base image
run_probe() {
  local cid i
  cid="$(docker run -d -v "$work/probe.sh:/probe.sh:ro" "$1" none)"
  for i in $(seq 1 60); do
    docker exec "$cid" test -S /run/supervisord.sock 2>/dev/null && break
    sleep 1
  done
  docker exec "$cid" /probe.sh > "$work/raw.txt" || true
  docker rm -f "$cid" >/dev/null
  # the PHP version is reported once in "version"; mask it everywhere else so
  # a version bump doesn't bury the differences that matter
  local version
  version="$(awk '/^== version ==$/ { getline; print $2; exit }' "$work/raw.txt")"
  awk -v v="$version" '
    /^== version ==$/ { print; getline; print; next }
    { while ((i = index($0, v)) > 0) $0 = substr($0, 1, i - 1) "<php-version>" substr($0, i + length(v)); print }
  ' "$work/raw.txt"
}

echo "Probing $1 ..." >&2
run_probe "$1" > "$work/a.txt"
echo "Probing $2 ..." >&2
run_probe "$2" > "$work/b.txt"

status=0
diff -u --label "$1" --label "$2" "$work/a.txt" "$work/b.txt" || status=1
echo >&2
echo "Reports: $work/a.txt $work/b.txt" >&2
exit "$status"

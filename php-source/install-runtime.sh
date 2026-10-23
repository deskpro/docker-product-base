#!/usr/bin/env bash
#
# Finishes installing the source-built PHP (PHP_INSTALL_METHOD=source) on top
# of the files copied in from the builder-php-source stage: installs the
# shared libraries it links against and recreates the Debian package layout
# (mods-available, per-SAPI conf.d symlinks, sapi markers, alternatives) so
# phpenmod/phpdismod and everything under /etc/php/8.3 behave as with debs.
#
# Run from the directory build.sh collect wrote (/out-meta in the builder).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
php_series="8.3"

export DEBIAN_FRONTEND=noninteractive
mapfile -t packages < "$here/runtime-packages.txt"
apt-get update
# php-common here is Debian's, not sury's, and only provides
# phpenmod/phpdismod/phpquery -- no PHP binaries or extensions.
# tzdata: PHP is built --with-system-tzdata and reads /usr/share/zoneinfo.
# systemd: php8.3-fpm depends on it, so on the deb path it is already
# installed (without recommends) before the nginx step runs. Without it here,
# nginx -> logrotate -> cron pulls it in *with* recommends: dbus (and its
# setuid-root launch helper), systemd-timesyncd, systemd-cryptsetup, ...
apt-get install -y --no-install-recommends php-common tzdata systemd "${packages[@]}"
apt-get -y clean
rm -rf /var/lib/apt/lists/*

mkdir -p \
  "/etc/php/${php_series}/mods-available" \
  "/etc/php/${php_series}/cli/conf.d" \
  "/etc/php/${php_series}/fpm/conf.d" \
  "/etc/php/${php_series}/fpm/pool.d" \
  "/usr/lib/php/${php_series}/sapi"
# phpquery discovers a version's SAPIs from these markers, which the
# php8.3-cli and php8.3-fpm packages would otherwise ship
touch "/usr/lib/php/${php_series}/sapi/cli" "/usr/lib/php/${php_series}/sapi/fpm"

enable=()
while read -r module priority kind; do
  case "$module" in ''|'#'*) continue ;; esac
  [ "$priority" = "-" ] && continue
  directive="extension"
  [ "${kind:-}" = "zend" ] && directive="zend_extension"
  printf '; configuration for php %s module\n; priority=%s\n%s=%s.so\n' \
    "$module" "$priority" "$directive" "$module" \
    > "/etc/php/${php_series}/mods-available/${module}.ini"
  enable+=("$module")
done < "$here/modules.txt"
# sury's opcache.ini turns the JIT off; without this, setting
# PHP_OPCACHE_JIT_BUFFER_SIZE would enable the tracing JIT here but not on debs
echo "opcache.jit=off" >> "/etc/php/${php_series}/mods-available/opcache.ini"
phpenmod -v "$php_series" -s ALL "${enable[@]}"

# same alternatives the php8.3-cli package registers
update-alternatives --install /usr/bin/php php "/usr/bin/php${php_series}" 83
update-alternatives --install /usr/bin/phar phar "/usr/bin/phar${php_series}" 83
update-alternatives --install /usr/bin/phar.phar phar.phar "/usr/bin/phar${php_series}.phar" 83
# the package also ships this alias of phar8.3.phar
ln -s "phar${php_series}.phar" "/usr/bin/phar.phar${php_series}"

php -v
php -m
"php-fpm${php_series}" -m

#!/bin/bash
VERSION=${1:-82}

echo "=== Сборка KVAS v$VERSION ==="

cd /home/me/Entware
sed -i "s/^PKG_RELEASE:=.*/PKG_RELEASE:=$VERSION/" /tmp/kvas-ipkg/opt/apps/kvas/Makefile 2>/dev/null || true

rm -rf /tmp/kvas-ipkg
mkdir -p /tmp/kvas-ipkg/opt/etc/init.d /tmp/kvas-ipkg/opt/etc/ndm/fs.d /tmp/kvas-ipkg/opt/etc/ndm/netfilter.d /tmp/kvas-ipkg/CONTROL

cp -a /home/me/kvas/opt/. /tmp/kvas-ipkg/opt/
cp /home/me/kvas/install_hysteria.sh /tmp/kvas-ipkg/opt/apps/kvas/bin/

cp /home/me/kvas/opt/apps/kvas/etc/init.d/S96kvas /tmp/kvas-ipkg/opt/etc/init.d/
cp /home/me/kvas/opt/apps/kvas/etc/init.d/S97xray /tmp/kvas-ipkg/opt/etc/init.d/ 2>/dev/null || true
cp /home/me/kvas/opt/apps/kvas/etc/ndm/fs.d/15-kvas-start.sh /tmp/kvas-ipkg/opt/etc/ndm/fs.d/ 2>/dev/null || true
cp /home/me/kvas/opt/apps/kvas/etc/ndm/netfilter.d/100-dns-local /tmp/kvas-ipkg/opt/etc/ndm/netfilter.d/ 2>/dev/null || true

PKG_VERSION="1.1.9_beta-10"

cat > /tmp/kvas-ipkg/CONTROL/control << EOF
Package: kvas
Version: ${PKG_VERSION}-${VERSION}
Depends: libpcre, jq, curl, knot-dig, nano-full, cron, bind-dig, dnsmasq-full, ipset, dnscrypt-proxy2, iptables, shadowsocks-libev-ss-redir, shadowsocks-libev-config, libmbedtls
Source: https://github.com/qzeleza/kvas
Maintainer: mail@zeleza.ru
Architecture: all
Description: VPN клиент для Keenetic (v${VERSION})
Section: utils
Priority: optional
Installed-Size: 686080
EOF

cat > /tmp/kvas-ipkg/CONTROL/postinst << EOF
#!/bin/sh
if [ "\$1" = "configure" ]; then
    [ ! -d "/opt/etc/ndm/watch.d" ] && mkdir -p "/opt/etc/ndm/watch.d"
    chown root:root /opt/etc/ndm/watch.d

    ln -sf /opt/apps/kvas/bin/kvas /opt/bin/kvas

    mkdir -p /opt/etc/dnsmasq.d
    mkdir -p /opt/etc/adblock
    mkdir -p /opt/etc/ndm/watch.d
    mkdir -p /opt/etc/xray
    mkdir -p /opt/var/log

    chmod -R +x /opt/apps/kvas/bin/* 2>/dev/null
    chmod -R +x /opt/apps/kvas/etc/init.d/* 2>/dev/null
    chmod -R +x /opt/apps/kvas/etc/ndm/* 2>/dev/null
    [ -f /opt/apps/kvas/hysteria/etc/ndm/test_connection.sh ] && chmod +x /opt/apps/kvas/hysteria/etc/ndm/test_connection.sh
    [ -f /opt/apps/kvas/hysteria/etc/ndm/check_space.sh ] && chmod +x /opt/apps/kvas/hysteria/etc/ndm/check_space.sh

    # Версия — создаём kvas.conf и строки если отсутствуют
    kvas_conf="/opt/etc/kvas.conf"
    touch "\${kvas_conf}"
    if grep -q "^APP_VERSION=" "\${kvas_conf}" 2>/dev/null; then
        sed -i "s/^APP_VERSION=.*/APP_VERSION=${PKG_VERSION}/" "\${kvas_conf}"
    else
        echo "APP_VERSION=${PKG_VERSION}" >> "\${kvas_conf}"
    fi
    if grep -q "^APP_RELEASE=" "\${kvas_conf}" 2>/dev/null; then
        sed -i "s/^APP_RELEASE=.*/APP_RELEASE=${VERSION}/" "\${kvas_conf}"
    else
        echo "APP_RELEASE=${VERSION}" >> "\${kvas_conf}"
    fi

    # Run kvas init to set up netfilter/DNS logging (needed for monitoring)
    /opt/apps/kvas/bin/kvas init >/dev/null 2>&1 &
fi
exit 0
EOF
chmod 755 /tmp/kvas-ipkg/CONTROL/postinst

find /tmp/kvas-ipkg/opt -name "*.sh" -exec chmod 755 {} \;
find /tmp/kvas-ipkg/opt -name "S9*" -exec chmod 755 {} \;
chmod 755 /tmp/kvas-ipkg/opt/apps/kvas/bin/kvas
chmod 755 /tmp/kvas-ipkg/opt/apps/kvas/bin/libs/* 2>/dev/null || true

scripts/ipkg-build /tmp/kvas-ipkg /tmp/kvas_output

echo ""
echo "=== Готово: /tmp/kvas_output/kvas_1.1.9_beta-10-${VERSION}_all.ipk ==="
echo "Для копирования на хост выполните:"
echo "  docker cp builder:/tmp/kvas_output/kvas_1.1.9_beta-10-${VERSION}_all.ipk C:\\Users\\Pavel\\kvas\\"

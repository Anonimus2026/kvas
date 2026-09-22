#!/bin/sh
BACKUP=/opt/etc/.kvas_backup
mkdir -p "$BACKUP"
[ -f /opt/etc/kvas.list ] && cp -f /opt/etc/kvas.list "$BACKUP/kvas.list"
[ -f /opt/etc/kvas.conf ] && cp -f /opt/etc/kvas.conf "$BACKUP/kvas.conf"
[ -f /opt/etc/tags.list ] && cp -f /opt/etc/tags.list "$BACKUP/tags.list"

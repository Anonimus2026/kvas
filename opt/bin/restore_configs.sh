#!/bin/sh
BACKUP=/opt/etc/.kvas_backup
if [ -d "$BACKUP" ]; then
    [ -f "$BACKUP/kvas.list" ] && cp -f "$BACKUP/kvas.list" /opt/etc/kvas.list
    [ -f "$BACKUP/kvas.conf" ] && cp -f "$BACKUP/kvas.conf" /opt/etc/kvas.conf
    [ -f "$BACKUP/tags.list" ] && cp -f "$BACKUP/tags.list" /opt/etc/tags.list
    rm -rf "$BACKUP"
    echo 'Configs restored'
fi

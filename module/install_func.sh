initialize() {
    # Cleanup left over
    [ -d "/data/adb/modules/$NEW_MODID" ] && rm -rf "/data/adb/modules/$NEW_MODID"

    # Set permission
    set_perm $COMPATH/get_extra.sh 0 2000 0755
    set_perm $COMPATH/keybox_update.sh 0 2000 0755

    # Keep action.sh for all root managers; only Magisk needs update payload
    if [ "$ACTION" = "false" ]; then
        NEW_MODID="$MODID"
    else
        mkdir -p "$COMPATH/update/common"
        cp "$COMPATH/.default" "$COMPATH/update/common/.default"
        cp "$MODPATH/uninstall.sh" "$COMPATH/update/uninstall.sh"
        cp "$MODPATH/VerifiedBootHash.txt" "$COMPATH/update/VerifiedBootHash.txt" 2>/dev/null || true
        cp "$MODPATH/ExcludeList.txt" "$COMPATH/update/ExcludeList.txt" 2>/dev/null || true
        cp "$COMPATH/keybox_update.sh" "$COMPATH/update/common/keybox_update.sh" 2>/dev/null || true
    fi


    # Create templates for action.sh auto apply
    [ -f "$MODPATH/VerifiedBootHash.txt" ] || touch "$MODPATH/VerifiedBootHash.txt"
    [ -f "$MODPATH/ExcludeList.txt" ] || cat > "$MODPATH/ExcludeList.txt" <<'EOT'
oneplus
coloros
miui
com.android.patch
me.bmax.apatch
me.garfieldhan.apatch.next
EOT
    chmod 0644 "$MODPATH/VerifiedBootHash.txt" "$MODPATH/ExcludeList.txt"

    # Backup module.prop
    cp "$MODPATH/module.prop" "$COMPATH/update/module.prop"
}

find_config() {
    # Remove legacy setup
    [ -f "$SCRIPT_DIR/UpdateTargetList.sh" ] && rm -f "$SCRIPT_DIR/UpdateTargetList.sh"
    [ -d "$CONFIG_DIR" ] && rm -rf "$CONFIG_DIR"
}

migrate_config() {
    # remove empty file
    if [ -f "/data/adb/boot_hash" ]; then
        hash_value=$(grep -v '^#' "/data/adb/boot_hash" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
        [ -z "$hash_value" ] && rm -f /data/adb/boot_hash || echo "$hash_value" > /data/adb/boot_hash
    fi

    # Migrate security_patch config*
    if [ -f "/data/adb/security_patch" ]; then
        if grep -q "^auto_config=1" "/data/adb/security_patch"; then
            touch "/data/adb/tricky_store/security_patch_auto_config"
        fi
        rm -f "/data/adb/security_patch"
    fi

    # Additional system app
    if [ ! -f "/data/adb/tricky_store/system_app" ]; then
        SYSTEM_APP="
        com.google.android.gms
        com.google.android.gsf
        com.android.vending
        com.oplus.deepthinker
        com.heytap.speechassist
        com.coloros.sceneservice"
        touch "/data/adb/tricky_store/system_app"
        for app in $SYSTEM_APP; do
            if pm list packages -s | grep -q "$app"; then
                echo "$app" >> "/data/adb/tricky_store/system_app"
            fi
        done
    fi
}

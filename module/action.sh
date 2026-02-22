#!/system/bin/sh
###########################################
## This file is NOT a part of Tricky Store
###########################################

PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:$PATH
TS_DIR="/data/adb/tricky_store"
TARGET_FILE="$TS_DIR/target.txt"
SYSTEM_APP_FILE="$TS_DIR/system_app"
SECURITY_PATCH_FILE="$TS_DIR/security_patch.txt"
SECURITY_PATCH_AUTO="$TS_DIR/security_patch_auto_config"
DEVCONFIG_FILE="$TS_DIR/devconfig.toml"
BOOT_HASH_FILE="/data/adb/boot_hash"
DEFAULT_KEYBOX_HEX="/data/adb/modules/.TA_utl/common/.default"
[ -f "$DEFAULT_KEYBOX_HEX" ] || DEFAULT_KEYBOX_HEX="/data/adb/modules/TA_utl/common/.default"

MENU_ITEMS="
生成 target.txt（用户应用 + system_app）
合并 Magisk DenyList 到 target.txt
设置 VerifiedBootHash
自动设置 Security Patch
手动设置 Security Patch
写入 AOSP Keybox
导入本地 Keybox
退出"
MENU_SELECTED=1
MENU_USE_KEYS=0

print_header() {
  echo "=========================================="
  echo " Tricky Addon - Action Script"
  echo "=========================================="
}

ensure_tricky_store() {
  [ -d "$TS_DIR" ] || {
    echo "! Tricky Store directory not found: $TS_DIR"
    exit 1
  }
  mkdir -p "$TS_DIR"
  [ -f "$TARGET_FILE" ] || touch "$TARGET_FILE"
}

save_target_from_apps() {
  cat <<'TIP'
- 输入要排除的关键字（正则），用空格分隔。
  直接回车则使用默认值：oneplus coloros miui com.android.patch me.bmax.apatch me.garfieldhan.apatch.next
TIP
  printf "> "
  read -r user_exclude

  [ -n "$user_exclude" ] || user_exclude="oneplus coloros miui com.android.patch me.bmax.apatch me.garfieldhan.apatch.next"
  exclude_pattern=$(echo "$user_exclude" | tr ' ' '|' | sed 's/||*/|/g;s/^|//;s/|$//')

  pm list packages -3 | awk -F: '{print $2}' | grep -Ev "$exclude_pattern" | sort -u > "$TARGET_FILE"

  if [ -f "$SYSTEM_APP_FILE" ]; then
    sed '/^#/d;/^$/d' "$SYSTEM_APP_FILE" | while read -r pkg; do
      pm list packages -s | grep -q "$pkg" && echo "$pkg" >> "$TARGET_FILE"
    done
    sort -u "$TARGET_FILE" -o "$TARGET_FILE"
  fi

  echo "- 已生成 target.txt ($(wc -l < "$TARGET_FILE") 项)"
}

add_denylist_to_target() {
  command -v magisk >/dev/null 2>&1 || {
    echo "! 未检测到 magisk，无法读取 denylist"
    return 1
  }

  exclamation_target=$(grep '!' "$TARGET_FILE" | sed 's/!$//')
  question_target=$(grep '?' "$TARGET_FILE" | sed 's/?$//')
  target=$(sed 's/[!?]$//' "$TARGET_FILE")
  denylist=$(magisk --denylist ls 2>/dev/null | awk -F'|' '{print $1}' | grep -v "isolated")

  printf "%s\n" "$target" "$denylist" | sed '/^$/d' | sort -u > "$TARGET_FILE"

  for t in $exclamation_target; do
    sed -i "s/^$t$/$t!/" "$TARGET_FILE"
  done
  for t in $question_target; do
    sed -i "s/^$t$/$t?/" "$TARGET_FILE"
  done

  touch "$TS_DIR/target_from_denylist"
  echo "- 已合并 denylist 到 target.txt"
}

set_boot_hash() {
  cur_hash=""
  [ -f "$BOOT_HASH_FILE" ] && cur_hash=$(sed '/^#/d;/^$/d' "$BOOT_HASH_FILE")
  echo "当前 boot hash: ${cur_hash:-<空>}"
  echo "输入新的 vbmeta digest（留空则清除）:"
  printf "> "
  read -r hash
  hash=$(echo "$hash" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')

  resetprop -n ro.boot.vbmeta.digest "$hash"
  if [ -z "$hash" ]; then
    rm -f "$BOOT_HASH_FILE"
    echo "- 已清除 boot_hash"
  else
    echo "$hash" > "$BOOT_HASH_FILE"
    chmod 644 "$BOOT_HASH_FILE"
    echo "- 已写入 boot_hash"
  fi
}

set_security_patch_manual() {
  echo "输入 Security Patch 日期(YYYY-MM-DD)，例如 2025-01-05："
  printf "> "
  read -r patch
  if ! echo "$patch" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
    echo "! 格式无效"
    return 1
  fi

  if grep -q "James" "/data/adb/modules/tricky_store/module.prop" && ! grep -q "beakthoven" "/data/adb/modules/tricky_store/module.prop"; then
    cat > "$DEVCONFIG_FILE" <<EOC
securityPatch = "$patch"
EOC
    echo "- 已写入 devconfig.toml"
  else
    cat > "$SECURITY_PATCH_FILE" <<EOC
system=prop
boot=$patch
vendor=$patch
EOC
    chmod 644 "$SECURITY_PATCH_FILE"
    rm -f "$SECURITY_PATCH_AUTO"
    echo "- 已写入 security_patch.txt"
  fi
}

set_security_patch_auto() {
  sh /data/adb/modules/TA_utl/common/get_extra.sh --security-patch >/dev/null 2>&1 || \
  sh /data/adb/modules/.TA_utl/common/get_extra.sh --security-patch >/dev/null 2>&1

  if [ $? -eq 0 ]; then
    touch "$SECURITY_PATCH_AUTO"
    echo "- 已自动配置 security patch"
  else
    echo "! 自动配置失败"
    return 1
  fi
}

set_aosp_keybox() {
  [ -f "$DEFAULT_KEYBOX_HEX" ] || {
    echo "! 找不到默认 keybox 数据"
    return 1
  }

  mv -f "$TS_DIR/keybox.xml" "$TS_DIR/keybox.xml.bak" 2>/dev/null
  xxd -r -p "$DEFAULT_KEYBOX_HEX" | base64 -d > "$TS_DIR/keybox.xml" || {
    echo "! 写入 keybox 失败"
    return 1
  }
  chmod 644 "$TS_DIR/keybox.xml"
  echo "- 已写入 AOSP keybox"
}

import_local_keybox() {
  echo "输入本地 keybox.xml 路径："
  printf "> "
  read -r kb_path
  [ -f "$kb_path" ] || {
    echo "! 文件不存在: $kb_path"
    return 1
  }

  mv -f "$TS_DIR/keybox.xml" "$TS_DIR/keybox.xml.bak" 2>/dev/null
  cp -f "$kb_path" "$TS_DIR/keybox.xml"
  chmod 644 "$TS_DIR/keybox.xml"
  echo "- 已导入 keybox"
}

use_key_menu() {
  command -v getevent >/dev/null 2>&1 || return 1
  getevent -pl 2>/dev/null | grep -q "KEY_VOLUMEUP" || return 1
  getevent -pl 2>/dev/null | grep -q "KEY_VOLUMEDOWN" || return 1
  getevent -pl 2>/dev/null | grep -q "KEY_POWER" || return 1
  return 0
}

render_key_menu() {
  clear 2>/dev/null
  print_header
  echo "音量键控制：音量上=上移，音量下=下移，电源键=确认"
  echo "------------------------------------------"

  idx=1
  echo "$MENU_ITEMS" | sed '/^$/d' | while IFS= read -r item; do
    if [ "$idx" -eq "$MENU_SELECTED" ]; then
      echo "> [$idx] $item"
    else
      echo "  [$idx] $item"
    fi
    idx=$((idx + 1))
  done
}

wait_key_action() {
  while true; do
    event_line=$(getevent -qlc 1 2>/dev/null)
    case "$event_line" in
      *KEY_VOLUMEUP*DOWN*)
        MENU_SELECTED=$((MENU_SELECTED - 1))
        [ "$MENU_SELECTED" -lt 1 ] && MENU_SELECTED=8
        return 1
        ;;
      *KEY_VOLUMEDOWN*DOWN*)
        MENU_SELECTED=$((MENU_SELECTED + 1))
        [ "$MENU_SELECTED" -gt 8 ] && MENU_SELECTED=1
        return 1
        ;;
      *KEY_POWER*DOWN*)
        return 0
        ;;
    esac
  done
}

run_choice() {
  case "$1" in
    1) save_target_from_apps ;;
    2) add_denylist_to_target ;;
    3) set_boot_hash ;;
    4) set_security_patch_auto ;;
    5) set_security_patch_manual ;;
    6) set_aosp_keybox ;;
    7) import_local_keybox ;;
    8) echo "- 退出"; exit 0 ;;
    *) echo "! 无效选项" ;;
  esac
}

main() {
  ensure_tricky_store

  if use_key_menu; then
    MENU_USE_KEYS=1
  fi

  while true; do
    if [ "$MENU_USE_KEYS" -eq 1 ]; then
      render_key_menu
      wait_key_action
      [ $? -eq 0 ] || continue
      clear 2>/dev/null
      print_header
      run_choice "$MENU_SELECTED"
    else
      print_header
      cat <<'MENU'
1) 生成 target.txt（用户应用 + system_app）
2) 合并 Magisk DenyList 到 target.txt
3) 设置 VerifiedBootHash
4) 自动设置 Security Patch
5) 手动设置 Security Patch
6) 写入 AOSP Keybox
7) 导入本地 Keybox
8) 退出
MENU
      printf "请选择操作: "
      read -r choice
      run_choice "$choice"
    fi
    echo ""
    echo "按回车继续..."
    read -r _
  done
}

main "$@"

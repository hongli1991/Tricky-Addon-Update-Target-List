#!/system/bin/sh
###########################################
## This file is NOT a part of Tricky Store
###########################################

PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:$PATH
TS_DIR="/data/adb/tricky_store"
TARGET_FILE="$TS_DIR/target.txt"
SYSTEM_APP_FILE="$TS_DIR/system_app"
SECURITY_PATCH_AUTO="$TS_DIR/security_patch_auto_config"
BOOT_HASH_FILE="/data/adb/boot_hash"

MODDIR=""
ACTION_DIR=""
VBH_TEMPLATE_FILE=""
EXCLUDE_TEMPLATE_FILE=""
KEYBOX_UPDATE_SCRIPT=""
DEFAULT_KEYBOX_HEX=""

MENU_ITEMS="
生成 target.txt（读取 ExcludeList.txt）
合并 Magisk DenyList 到 target.txt
设置 VerifiedBootHash（读取模板）
自动设置 Security Patch
写入 AOSP Keybox
导入本地 Keybox（DocumentsUI）
联网更新 Keybox
退出"
MENU_SELECTED=1
MENU_USE_KEYS=0

print_header() {
  echo "=========================================="
  echo " Tricky Addon - Action Script"
  echo "=========================================="
}

resolve_paths() {
  if [ -d "/data/adb/modules/.TA_utl" ]; then
    MODDIR="/data/adb/modules/.TA_utl"
  elif [ -d "/data/adb/modules/TA_utl" ]; then
    MODDIR="/data/adb/modules/TA_utl"
  else
    MODDIR="${0%/*}"
  fi

  ACTION_DIR="$MODDIR"
  VBH_TEMPLATE_FILE="$ACTION_DIR/VerifiedBootHash.txt"
  EXCLUDE_TEMPLATE_FILE="$ACTION_DIR/ExcludeList.txt"
  KEYBOX_UPDATE_SCRIPT="$ACTION_DIR/common/keybox_update.sh"
  DEFAULT_KEYBOX_HEX="$ACTION_DIR/common/.default"
}

ensure_tricky_store() {
  [ -d "$TS_DIR" ] || {
    echo "! Tricky Store directory not found: $TS_DIR"
    exit 1
  }
  mkdir -p "$TS_DIR"
  [ -f "$TARGET_FILE" ] || touch "$TARGET_FILE"
}

ensure_template_files() {
  [ -f "$VBH_TEMPLATE_FILE" ] || touch "$VBH_TEMPLATE_FILE"
  [ -f "$EXCLUDE_TEMPLATE_FILE" ] || cat > "$EXCLUDE_TEMPLATE_FILE" <<'EOT'
oneplus
coloros
miui
com.android.patch
me.bmax.apatch
me.garfieldhan.apatch.next
EOT
  chmod 644 "$VBH_TEMPLATE_FILE" "$EXCLUDE_TEMPLATE_FILE"
}

save_target_from_apps() {
  exclude_pattern=$(sed '/^#/d;/^$/d' "$EXCLUDE_TEMPLATE_FILE" | tr '\n' '|' | sed 's/|$//')
  [ -n "$exclude_pattern" ] || exclude_pattern='^$'

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
  command -v magisk >/dev/null 2>&1 || { echo "! 未检测到 magisk"; return 1; }
  exclamation_target=$(grep '!' "$TARGET_FILE" | sed 's/!$//')
  question_target=$(grep '?' "$TARGET_FILE" | sed 's/?$//')
  target=$(sed 's/[!?]$//' "$TARGET_FILE")
  denylist=$(magisk --denylist ls 2>/dev/null | awk -F'|' '{print $1}' | grep -v "isolated")
  printf "%s\n" "$target" "$denylist" | sed '/^$/d' | sort -u > "$TARGET_FILE"
  for t in $exclamation_target; do sed -i "s/^$t$/$t!/" "$TARGET_FILE"; done
  for t in $question_target; do sed -i "s/^$t$/$t?/" "$TARGET_FILE"; done
  touch "$TS_DIR/target_from_denylist"
  echo "- 已合并 denylist"
}

set_boot_hash() {
  hash=$(sed '/^#/d;/^$/d' "$VBH_TEMPLATE_FILE" | head -n 1 | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
  [ -n "$hash" ] || { echo "! $VBH_TEMPLATE_FILE 为空"; return 1; }
  resetprop -n ro.boot.vbmeta.digest "$hash"
  echo "$hash" > "$BOOT_HASH_FILE"
  chmod 644 "$BOOT_HASH_FILE"
  echo "- 已写入 boot_hash"
}

set_security_patch_auto() {
  sh "$MODDIR/common/get_extra.sh" --security-patch >/dev/null 2>&1
  [ $? -eq 0 ] && { touch "$SECURITY_PATCH_AUTO"; echo "- 自动配置成功"; } || { echo "! 自动配置失败"; return 1; }
}

set_aosp_keybox() {
  [ -f "$DEFAULT_KEYBOX_HEX" ] || { echo "! 找不到默认 keybox 数据"; return 1; }
  mv -f "$TS_DIR/keybox.xml" "$TS_DIR/keybox.xml.bak" 2>/dev/null
  xxd -r -p "$DEFAULT_KEYBOX_HEX" | base64 -d > "$TS_DIR/keybox.xml" || { echo "! 写入失败"; return 1; }
  chmod 644 "$TS_DIR/keybox.xml"
  echo "- 已写入 AOSP keybox"
}

pick_keybox_path_via_documentsui() {
  am start -a android.intent.action.OPEN_DOCUMENT -t "text/xml" >/dev/null 2>&1 || \
  am start -n com.android.documentsui/.files.FilesActivity >/dev/null 2>&1
  echo "- 已打开 DocumentsUI，请选择 keybox.xml" >&2
  echo "- 返回后按 音量上 继续" >&2
  wait_for_volume_up

  find /sdcard /storage/emulated/0 -type f -name '*.xml' 2>/dev/null | while read -r f; do
    grep -q "AndroidAttestation" "$f" 2>/dev/null || continue
    stat -c '%Y %n' "$f" 2>/dev/null || echo "0 $f"
  done | sort -nr | head -n 1 | cut -d' ' -f2-
}

import_local_keybox() {
  kb_path=$(pick_keybox_path_via_documentsui)
  [ -n "$kb_path" ] && [ -f "$kb_path" ] || { echo "! 无法获取 keybox 路径或文件无效"; return 1; }
  mv -f "$TS_DIR/keybox.xml" "$TS_DIR/keybox.xml.bak" 2>/dev/null
  cp -f "$kb_path" "$TS_DIR/keybox.xml"
  chmod 644 "$TS_DIR/keybox.xml"
  echo "- 已导入 keybox: $kb_path"
}

update_keybox_online() {
  [ -x "$KEYBOX_UPDATE_SCRIPT" ] || chmod 755 "$KEYBOX_UPDATE_SCRIPT" 2>/dev/null
  [ -x "$KEYBOX_UPDATE_SCRIPT" ] || { echo "! 在线更新脚本不存在: $KEYBOX_UPDATE_SCRIPT"; return 1; }
  sh "$KEYBOX_UPDATE_SCRIPT"
}

use_key_menu() {
  command -v getevent >/dev/null 2>&1 || return 1
  getevent -pl 2>/dev/null | grep -q "KEY_VOLUMEUP" || return 1
  getevent -pl 2>/dev/null | grep -q "KEY_VOLUMEDOWN" || return 1
  return 0
}

get_button() {
  local out
  button=""
  while [ -z "$button" ]; do
    out="$(getevent -qlc 1 2>/dev/null | grep -m 1 'KEY_')"
    button="$(echo "$out" | awk '{for (i=1;i<=NF;i++) if ($i ~ /^KEY_/) {print $i; exit}}')"
    sleep 0.15
  done
}

wait_for_volume_up() {
  if [ "$MENU_USE_KEYS" -eq 1 ]; then
    while true; do
      get_button
      [ "$button" = "KEY_VOLUMEUP" ] && break
    done
  else
    echo "按回车继续..."
    read -r _
  fi
}

render_key_menu() {
  clear 2>/dev/null
  print_header
  echo "音量键控制：音量下=下一个（循环），音量上=确认"
  echo "------------------------------------------"
  idx=1
  echo "$MENU_ITEMS" | sed '/^$/d' | while IFS= read -r item; do
    [ "$idx" -eq "$MENU_SELECTED" ] && echo "> [$idx] $item" || echo "  [$idx] $item"
    idx=$((idx + 1))
  done
}

wait_key_action() {
  while true; do
    get_button
    case "$button" in
      KEY_VOLUMEDOWN)
        MENU_SELECTED=$((MENU_SELECTED + 1)); [ "$MENU_SELECTED" -gt 8 ] && MENU_SELECTED=1; return 1 ;;
      KEY_VOLUMEUP)
        return 0 ;;
    esac
  done
}

wait_continue() {
  echo ""
  echo "按 音量上 确认继续..."
  wait_for_volume_up
}

exit_script() {
  echo "- 退出"
  kill -TERM $$ >/dev/null 2>&1
  exit 0
}

run_choice() {
  case "$1" in
    1) save_target_from_apps ;;
    2) add_denylist_to_target ;;
    3) set_boot_hash ;;
    4) set_security_patch_auto ;;
    5) set_aosp_keybox ;;
    6) import_local_keybox ;;
    7) update_keybox_online ;;
    8) exit_script ;;
    *) echo "! 无效选项" ;;
  esac
}

main() {
  resolve_paths
  ensure_tricky_store
  ensure_template_files
  use_key_menu && MENU_USE_KEYS=1

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
1) 生成 target.txt（读取 ExcludeList.txt）
2) 合并 Magisk DenyList 到 target.txt
3) 设置 VerifiedBootHash（读取模板）
4) 自动设置 Security Patch
5) 写入 AOSP Keybox
6) 导入本地 Keybox（DocumentsUI）
7) 联网更新 Keybox
8) 退出
MENU
      printf "请选择操作: "
      read -r choice
      run_choice "$choice"
    fi
    wait_continue
  done
}

main "$@"

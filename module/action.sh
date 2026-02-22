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
ACTION_DIR="${0%/*}"
VBH_TEMPLATE_FILE="$ACTION_DIR/VerifiedBootHash.txt"
DEFAULT_KEYBOX_HEX="/data/adb/modules/.TA_utl/common/.default"
[ -f "$DEFAULT_KEYBOX_HEX" ] || DEFAULT_KEYBOX_HEX="/data/adb/modules/TA_utl/common/.default"

MENU_ITEMS="
生成 target.txt（用户应用 + system_app）
合并 Magisk DenyList 到 target.txt
设置 VerifiedBootHash（读取模块模板）
自动设置 Security Patch
手动设置 Security Patch
写入 AOSP Keybox
导入本地 Keybox（DocumentsUI）
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

ensure_template_files() {
  if [ ! -f "$VBH_TEMPLATE_FILE" ]; then
    touch "$VBH_TEMPLATE_FILE"
    chmod 644 "$VBH_TEMPLATE_FILE"
  fi
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
  ensure_template_files
  hash=$(sed '/^#/d;/^$/d' "$VBH_TEMPLATE_FILE" | head -n 1 | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
  if [ -z "$hash" ]; then
    echo "! $VBH_TEMPLATE_FILE 为空，请先写入 vbmeta digest"
    return 1
  fi

  resetprop -n ro.boot.vbmeta.digest "$hash"
  echo "$hash" > "$BOOT_HASH_FILE"
  chmod 644 "$BOOT_HASH_FILE"
  echo "- 已从 VerifiedBootHash.txt 自动写入 boot_hash"
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

pick_keybox_path_via_documentsui() {
  am start -a android.intent.action.OPEN_DOCUMENT -t "text/xml" >/dev/null 2>&1 || \
  am start -n com.android.documentsui/.files.FilesActivity >/dev/null 2>&1

  echo "- 已打开 DocumentsUI，请选择 keybox.xml"
  echo "- 选完后返回，然后按 音量上 继续"
  wait_for_volume_up

  picked=$(find /sdcard /storage/emulated/0 -type f -name 'keybox.xml' 2>/dev/null | while read -r f; do
    echo "$(stat -c '%Y %n' "$f" 2>/dev/null)"
  done | sort -nr | head -n 1 | cut -d' ' -f2-)

  [ -n "$picked" ] || return 1
  echo "$picked"
  return 0
}

import_local_keybox() {
  kb_path=$(pick_keybox_path_via_documentsui)
  if [ -z "$kb_path" ] || [ ! -f "$kb_path" ]; then
    echo "! 未找到可用 keybox.xml，请确认文件名是 keybox.xml"
    return 1
  fi

  mv -f "$TS_DIR/keybox.xml" "$TS_DIR/keybox.xml.bak" 2>/dev/null
  cp -f "$kb_path" "$TS_DIR/keybox.xml"
  chmod 644 "$TS_DIR/keybox.xml"
  echo "- 已导入 keybox: $kb_path"
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
    get_button
    case "$button" in
      KEY_VOLUMEDOWN)
        MENU_SELECTED=$((MENU_SELECTED + 1))
        [ "$MENU_SELECTED" -gt 8 ] && MENU_SELECTED=1
        return 1
        ;;
      KEY_VOLUMEUP)
        return 0
        ;;
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
    5) set_security_patch_manual ;;
    6) set_aosp_keybox ;;
    7) import_local_keybox ;;
    8) exit_script ;;
    *) echo "! 无效选项" ;;
  esac
}

main() {
  ensure_tricky_store
  ensure_template_files

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
3) 设置 VerifiedBootHash（读取模块模板）
4) 自动设置 Security Patch
5) 手动设置 Security Patch
6) 写入 AOSP Keybox
7) 导入本地 Keybox（DocumentsUI）
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

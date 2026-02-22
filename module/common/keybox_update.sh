#!/system/bin/sh

PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:$PATH
TS_DIR="/data/adb/tricky_store"
TARGET_KEYBOX="$TS_DIR/keybox.xml"
TMP_DIR="/data/local/tmp/keybox_update"
TMP_RAW="$TMP_DIR/raw.tmp"
TMP_KEYBOX="$TMP_DIR/keybox_tmp.xml"

YURIKEY_URL="https://raw.githubusercontent.com/Yurii0307/yurikey/main/key"
TA_UTL_URL="https://raw.githubusercontent.com/KOWX712/Tricky-Addon-Update-Target-List/main/.extra"
INTEGRITYBOX_URL="https://raw.gitmirror.com/MeowDump/MeowDump/refs/heads/main/NullVoid/ShockWave.tar"
INTEGRITYBOX_MIRROR="https://raw.githubusercontent.com/MeowDump/MeowDump/main/NullVoid/ShockWave.tar"

logi(){ echo "[INFO] $1"; }
logw(){ echo "[WARN] $1"; }
loge(){ echo "[ERROR] $1"; }

download_file() {
  url="$1"; dst="$2"
  rm -f "$dst"
  if command -v curl >/dev/null 2>&1; then
    curl --connect-timeout 10 -fLs "$url" -o "$dst"
  else
    busybox wget -T 10 --no-check-certificate -qO "$dst" "$url"
  fi
  [ -s "$dst" ]
}

run_xxd() {
  if command -v xxd >/dev/null 2>&1; then
    xxd "$@"
  elif command -v toybox >/dev/null 2>&1 && toybox xxd --help >/dev/null 2>&1; then
    toybox xxd "$@"
  else
    return 1
  fi
}

run_base64_d() {
  if command -v toybox >/dev/null 2>&1; then
    toybox base64 -d "$@"
  else
    base64 -d "$@"
  fi
}

init_env() {
  rm -rf "$TMP_DIR"
  mkdir -p "$TMP_DIR" "$TS_DIR"
}

fetch_yurikey() {
  logi "下载 Yurikey 源..."
  download_file "$YURIKEY_URL" "$TMP_RAW" || return 1
  run_base64_d "$TMP_RAW" > "$TMP_KEYBOX" 2>/dev/null
}

fetch_ta_utl() {
  logi "下载 Tricky Addon 源..."
  download_file "$TA_UTL_URL" "$TMP_RAW" || return 1
  cat "$TMP_RAW" | run_xxd -r -p | run_base64_d > "$TMP_KEYBOX" 2>/dev/null
}

fetch_integritybox() {
  logi "下载 IntegrityBox 源..."
  download_file "$INTEGRITYBOX_URL" "$TMP_RAW" || download_file "$INTEGRITYBOX_MIRROR" "$TMP_RAW" || return 1
  cp "$TMP_RAW" "$TMP_DIR/process.tmp"
  i=1
  while [ "$i" -le 10 ]; do
    run_base64_d "$TMP_DIR/process.tmp" > "$TMP_DIR/process.next" 2>/dev/null || return 1
    mv -f "$TMP_DIR/process.next" "$TMP_DIR/process.tmp"
    i=$((i+1))
  done
  cat "$TMP_DIR/process.tmp" | run_xxd -r -p | tr 'A-Za-z' 'N-ZA-Mn-za-m' | sed 's/every soul will taste death//g' > "$TMP_KEYBOX"
}

validate_keybox() {
  [ -s "$1" ] || return 1
  grep -q "<?xml" "$1" || return 1
  grep -q "<AndroidAttestation>" "$1" || return 1
  grep -q "BEGIN CERTIFICATE" "$1" || return 1
}

install_keybox() {
  mv -f "$TMP_KEYBOX" "$TARGET_KEYBOX" || return 1
  chmod 644 "$TARGET_KEYBOX"
  logi "Keybox 更新成功"
}

show_current() {
  if [ -f "$TARGET_KEYBOX" ]; then
    echo "$TARGET_KEYBOX"
    ls -lh "$TARGET_KEYBOX"
    head -n 3 "$TARGET_KEYBOX"
  else
    logw "未找到当前 keybox"
  fi
}

get_button() {
  local out button
  button=""
  while [ -z "$button" ]; do
    out="$(getevent -qlc 1 2>/dev/null | grep -m 1 'KEY_')"
    button="$(echo "$out" | awk '{for (i=1;i<=NF;i++) if ($i ~ /^KEY_/) {print $i; exit}}')"
    sleep 0.1
  done
  echo "$button"
}

choose_source_keymode() {
  idx=1
  while true; do
    clear 2>/dev/null
    echo "====== 在线更新 Keybox ======"
    echo "音量下=下一个，音量上=确认"
    echo "----------------------------"
    [ "$idx" -eq 1 ] && echo "> [1] Yurikey" || echo "  [1] Yurikey"
    [ "$idx" -eq 2 ] && echo "> [2] Tricky Addon 源" || echo "  [2] Tricky Addon 源"
    [ "$idx" -eq 3 ] && echo "> [3] IntegrityBox" || echo "  [3] IntegrityBox"
    [ "$idx" -eq 4 ] && echo "> [4] 查看当前状态" || echo "  [4] 查看当前状态"
    [ "$idx" -eq 5 ] && echo "> [5] 返回" || echo "  [5] 返回"

    key=$(get_button)
    case "$key" in
      KEY_VOLUMEDOWN) idx=$((idx+1)); [ "$idx" -gt 5 ] && idx=1 ;;
      KEY_VOLUMEUP) echo "$idx"; return 0 ;;
    esac
  done
}

main() {
  init_env
  if command -v getevent >/dev/null 2>&1 && getevent -pl 2>/dev/null | grep -q "KEY_VOLUME"; then
    while true; do
      choice=$(choose_source_keymode)
      case "$choice" in
        1) fetch_yurikey && validate_keybox "$TMP_KEYBOX" && install_keybox || loge "Yurikey 更新失败" ;;
        2) fetch_ta_utl && validate_keybox "$TMP_KEYBOX" && install_keybox || loge "Tricky Addon 源更新失败" ;;
        3) fetch_integritybox && validate_keybox "$TMP_KEYBOX" && install_keybox || loge "IntegrityBox 更新失败" ;;
        4) show_current ;;
        5) rm -rf "$TMP_DIR"; return 0 ;;
      esac
      echo "按 音量上 继续..."
      while [ "$(get_button)" != "KEY_VOLUMEUP" ]; do :; done
    done
  else
    while true; do
      echo "[1] Yurikey"
      echo "[2] Tricky Addon 源"
      echo "[3] IntegrityBox"
      echo "[4] 查看当前状态"
      echo "[5] 返回"
      printf "请选择: "
      read -r choice
      case "$choice" in
        1) fetch_yurikey && validate_keybox "$TMP_KEYBOX" && install_keybox || loge "Yurikey 更新失败" ;;
        2) fetch_ta_utl && validate_keybox "$TMP_KEYBOX" && install_keybox || loge "Tricky Addon 源更新失败" ;;
        3) fetch_integritybox && validate_keybox "$TMP_KEYBOX" && install_keybox || loge "IntegrityBox 更新失败" ;;
        4) show_current ;;
        5) rm -rf "$TMP_DIR"; return 0 ;;
        *) echo "无效选项" ;;
      esac
      echo "按回车继续..."
      read -r _
    done
  fi
}

main "$@"

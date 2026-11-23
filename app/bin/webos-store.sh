#!/bin/sh
# /var/lib/webosbrew/bin/webos-store.sh
# Root backend helper for Homebrew Store+ (org.webosbrew.storeplus)

LUNA="luna-send -a org.webosbrew.hbchannel -f -n 1"
REPO_URL="https://repo.webosbrew.org/api/apps.json"
CACHE_FILE="/tmp/webosbrew_apps_cache.json"

send_toast() {
  MSG="$1"
  SAFE=$(printf '%s' "$MSG" | sed 's/"/\\"/g')
  $LUNA luna://com.webos.notification/createToast "{\"sourceId\":\"org.webosbrew.hbchannel\",\"message\":\"$SAFE\"}" >/dev/null 2>&1
}

cmd_catalog() {
  TMP="/tmp/webosbrew_apps_new.json"
  if curl -skL --max-time 15 -o "$TMP" "$REPO_URL" 2>/dev/null && [ -s "$TMP" ]; then
    mv "$TMP" "$CACHE_FILE"
    cat "$CACHE_FILE"
  elif [ -s "$CACHE_FILE" ]; then
    cat "$CACHE_FILE"
  else
    echo '{"packages":[],"error":"Failed to fetch repo.webosbrew.org"}'
  fi
}

cmd_installed() {
  $LUNA luna://com.webos.applicationManager/dev/listApps "{}" 2>/dev/null
}

cmd_install() {
  APP_ID="$1"
  IPK_URL="$2"
  TITLE="$3"
  [ -z "$TITLE" ] && TITLE="$APP_ID"

  TMP_IPK="/tmp/storeplus_${APP_ID}.ipk"
  rm -f "$TMP_IPK"

  if ! curl -skL --max-time 180 -o "$TMP_IPK" "$IPK_URL" 2>/dev/null; then
    rm -f "$TMP_IPK"
    echo '{"ok":false,"error":"Download failed"}'
    exit 0
  fi

  SZ=$(wc -c < "$TMP_IPK" 2>/dev/null || echo 0)
  if [ "$SZ" -lt 512 ]; then
    rm -f "$TMP_IPK"
    echo '{"ok":false,"error":"Downloaded IPK is empty or invalid"}'
    exit 0
  fi

  RES=$($LUNA luna://com.webos.appInstallService/dev/install "{\"id\":\"$APP_ID\",\"ipkUrl\":\"$TMP_IPK\",\"subscribe\":false}" 2>/dev/null)
  
  # Wait for installation to complete: poll listApps for up to 30 seconds
  INSTALLED=0
  for i in $(seq 1 15); do
    sleep 2
    if $LUNA luna://com.webos.applicationManager/dev/listApps "{}" 2>/dev/null | grep -q "\"$APP_ID\""; then
      INSTALLED=1
      break
    fi
  done

  rm -f "$TMP_IPK"

  if [ "$INSTALLED" -eq 1 ]; then
    send_toast "Installed $TITLE"
    printf '{"ok":true,"id":"%s","result":%s}\n' "$APP_ID" "${RES:-null}"
  else
    send_toast "Installation failed: $TITLE"
    printf '{"ok":false,"id":"%s","error":"Installation timed out"}\n' "$APP_ID"
  fi
}

cmd_remove() {
  APP_ID="$1"
  TITLE="$2"
  [ -z "$TITLE" ] && TITLE="$APP_ID"

  if [ "$APP_ID" = "org.webosbrew.hbchannel" ] || [ "$APP_ID" = "org.webosbrew.storeplus" ] || [ "$APP_ID" = "com.github.dasilva333.storeplus" ]; then
    echo '{"ok":false,"error":"Protected core app"}'
    exit 0
  fi

  RES=$($LUNA luna://com.webos.appInstallService/dev/remove "{\"id\":\"$APP_ID\",\"subscribe\":false}" 2>/dev/null)
  
  # Wait for removal to complete: poll listApps for up to 10 seconds
  REMOVED=0
  for i in $(seq 1 5); do
    sleep 2
    if ! $LUNA luna://com.webos.applicationManager/dev/listApps "{}" 2>/dev/null | grep -q "\"$APP_ID\""; then
      REMOVED=1
      break
    fi
  done

  if [ "$REMOVED" -eq 1 ]; then
    send_toast "Uninstalled $TITLE"
    printf '{"ok":true,"id":"%s","result":%s}\n' "$APP_ID" "${RES:-null}"
  else
    send_toast "Uninstall failed: $TITLE"
    printf '{"ok":false,"id":"%s","error":"Uninstall timed out"}\n' "$APP_ID"
  fi
}

cmd_launch() {
  APP_ID="$1"
  $LUNA luna://com.webos.applicationManager/launch "{\"id\":\"$APP_ID\"}" 2>/dev/null
}

case "$1" in
  catalog)   cmd_catalog ;;
  installed) cmd_installed ;;
  install)   cmd_install "$2" "$3" "$4" ;;
  remove)    cmd_remove "$2" "$3" ;;
  launch)    cmd_launch "$2" ;;
  *)
    echo "Usage: $0 {catalog|installed|install <id> <url> [title]|remove <id> [title]|launch <id>}"
    exit 1
    ;;
esac

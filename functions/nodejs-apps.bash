#!/usr/bin/env bash
# shellcheck disable=SC2181

nodejs_setup() {
  if [ -x "$(command -v npm)" ]; then return 0; fi

  local myDistro

  if ! [ -x "$(command -v lsb_release)" ]; then
    echo -n "$(timestamp) [openHABian] Installing NodeJS prerequsites (lsb-release)... "
    if cond_redirect apt-get install --yes lsb-release; then echo "OK"; else echo "FAILED"; return 1; fi
  fi

  myDistro="$(lsb_release -sc)"

  if ! add_keys "https://deb.nodesource.com/gpgkey/nodesource.gpg.key"; then return 1; fi

  echo -n "$(timestamp) [openHABian] Adding NodeSource repository to apt... "
  echo "deb https://deb.nodesource.com/node_12.x $myDistro main" > /etc/apt/sources.list.d/nodesource.list
  echo "deb-src https://deb.nodesource.com/node_12.x $myDistro main" >> /etc/apt/sources.list.d/nodesource.list
  if cond_redirect apt-get update; then echo "OK"; else echo "FAILED (update apt lists)"; return 1; fi

  echo -n "$(timestamp) [openHABian] Installing NodeJS... "
  if cond_redirect apt-get install --yes nodejs; then echo "OK"; else echo "FAILED"; return 1; fi
}

frontail_setup() {
  local frontailBase

  if ! [ -x "$(command -v npm)" ]; then
    echo "$(timestamp) [openHABian] Installing Frontail prerequsites (NodeJS)... "
    nodejs_setup
  fi

  frontailBase="$(npm list -g | head -n 1)/node_modules/frontail"

  echo "$(timestamp) [openHABian] Beginning setup of the openHAB Log Viewer (frontail)... "

  if [ -x "$(command -v frontail)" ]; then
    echo -n "$(timestamp) [openHABian] Updating openHAB Log Viewer (frontail)... "
    if cond_redirect npm update --force -g frontail; then echo "OK"; else echo "FAILED"; return 1; fi
  else
    if [ -d "$frontailBase" ]; then
      cond_echo "Removing any old installations..."
      cond_redirect npm uninstall -g frontail
    fi
    echo -n "$(timestamp) [openHABian] Installing openHAB Log Viewer (frontail)... "
    if ! cond_redirect npm install --force -g frontail; then echo "FAILED (install)"; return 1; fi
    if cond_redirect npm update --force -g frontail; then echo "OK"; else echo "FAILED (update)"; return 1; fi
  fi

  echo -n "$(timestamp) [openHABian] Configuring openHAB Log Viewer (frontail)... "
  mkdir -p "$frontailBase"/preset "$frontailBase"/web/assets/styles
  cp "$BASEDIR"/includes/frontail-preset.json "$frontailBase"/preset/openhab.json
  cp "$BASEDIR"/includes/frontail-theme.css "$frontailBase"/web/assets/styles/openhab.css
  if [ $? -eq 0 ]; then echo "OK"; else echo "FAILED"; return 1; fi

  echo -n "$(timestamp) [openHABian] Setting up openHAB Log Viewer (frontail) service... "
  if ! (sed -e "s|%FRONTAILBASE|${frontailBase}|g" "$BASEDIR"/includes/frontail.service > /etc/systemd/system/frontail.service); then echo "FAILED (service file creation)"; fi
  if ! cond_redirect systemctl enable frontail.service; then echo "FAILED (enable service)"; return 1; fi
  if cond_redirect systemctl restart frontail.service; then echo "OK"; else echo "FAILED (restart service)"; return 1; fi

  if [ -z "$BATS_TEST_NAME" ]; then
    dashboard_add_tile frontail
  fi
}

nodered_setup() {
  if [ -z "$INTERACTIVE" ]; then
    echo "$(timestamp) [openHABian] Node-RED setup must be run in interactive mode! Canceling Node-RED setup!"
    echo "CANCELED"
    return 0
  fi

  local temp

  if ! dpkg -s 'build-essential' &> /dev/null; then
    echo -n "$(timestamp) [openHABian] Installing Node-RED required packages (build-essential)... "
    if cond_redirect apt-get install --yes build-essential; then echo "OK"; else echo "FAILED"; return 1; fi
  fi

  temp="$(mktemp "${TMPDIR:-/tmp}"/openhabian.XXXXX)"

  echo "$(timestamp) [openHABian] Beginning setup of Node-RED... "

  echo "$(timestamp) [openHABian] Downloading Node-RED setup script... "
  if cond_redirect wget -qO "$temp" https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered; then
     echo "OK"
  else
    echo "FAILED"
    rm -f "$temp"
    return 1
  fi

  echo -n "$(timestamp) [openHABian] Setting up Node-RED... "
  whiptail --title "Node-RED Setup" --msgbox "The installer is about to ask for information in the command line, please fill out each line." 8 80 3>&1 1>&2 2>&3
  chmod 755 "$temp"
  if sudo -u "${username:-openhabian}" -H bash -c "$temp"; then echo "OK"; rm -f "$temp"; else echo "FAILED"; rm -f "$temp"; return 1; fi

  echo -n "$(timestamp) [openHABian] Installing Node-RED addons... "
  if ! cond_redirect npm install -g node-red-contrib-bigtimer; then echo "FAILED (install bigtimer addon)"; return 1; fi
  if ! cond_redirect npm update -g node-red-contrib-bigtimer; then echo "FAILED (update bigtimer addon)"; return 1; fi
  if ! cond_redirect npm install -g node-red-contrib-openhab2; then echo "FAILED (install openhab2 addon)"; return 1; fi
  if cond_redirect npm update -g node-red-contrib-openhab2; then echo "OK"; else echo "FAILED (update openhab2 addon)"; return 1; fi

  echo -n "$(timestamp) [openHABian] Setting up Node-RED service... "
  if ! cond_redirect systemctl enable nodered.service; then echo "FAILED (enable service)"; return 1; fi
  if cond_redirect systemctl restart nodered.service; then echo "OK"; else echo "FAILED (restart service)"; return 1; fi

  if [ -z "$BATS_TEST_NAME" ]; then
    dashboard_add_tile nodered
  fi
}

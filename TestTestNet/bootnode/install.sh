#!/bin/bash
set -e
set -u
set -x

EXT_IP="$(curl ifconfig.co)"

# Install logentries daemon /*
start_logentries() {
    echo "=====> start_logentries"
    sudo bash -c "echo 'deb http://rep.logentries.com/ trusty main' > /etc/apt/sources.list.d/logentries.list"
    sudo bash -c "gpg --keyserver pgp.mit.edu --recv-keys C43C79AD && gpg -a --export C43C79AD | apt-key add -"
    sudo apt-get update
    sudo apt-get install -y logentries
    sudo le reinit --user-key=0665901a-e843-41c5-82c1-2cc4b39f0b21 --pull-server-side-config=False

    mkdir -p /home/${ADMIN_USERNAME}/logs
    touch /home/${ADMIN_USERNAME}/logs/dashboard.err
    touch /home/${ADMIN_USERNAME}/logs/dashboard.out
    touch /home/${ADMIN_USERNAME}/logs/parity.log
    touch /home/${ADMIN_USERNAME}/logs/netstats_daemon.err
    touch /home/${ADMIN_USERNAME}/logs/netstats_daemon.out
    touch /home/${ADMIN_USERNAME}/logs/explorer.err
    touch /home/${ADMIN_USERNAME}/logs/explorer.out
    touch /home/${ADMIN_USERNAME}/logs/parity.err
    touch /home/${ADMIN_USERNAME}/logs/parity.out

    sudo bash -c "cat >> /etc/le/config << EOF
[install_err]
path = /var/lib/waagent/custom-script/download/0/stderr
destination = dev-mainnet/${EXT_IP}

[install_out]
path = /var/lib/waagent/custom-script/download/0/stdout
destination = dev-mainnet/${EXT_IP}

[dashboard_err]
path = /home/${ADMIN_USERNAME}/logs/dashboard.err
destination = dev-mainnet/${EXT_IP}

[dashboard_out]
path = /home/${ADMIN_USERNAME}/logs/dashboard.out
destination = dev-mainnet/${EXT_IP}

[parity_log]
path = /home/${ADMIN_USERNAME}/logs/parity.log
destination = dev-mainnet/${EXT_IP}

[netstats_daemon_err]
path = /home/${ADMIN_USERNAME}/logs/netstats_daemon.err
destination = dev-mainnet/${EXT_IP}

[netstats_daemon_out]
path = /home/${ADMIN_USERNAME}/logs/netstats_daemon.out
destination = dev-mainnet/${EXT_IP}

[explorer_err]
path = /home/${ADMIN_USERNAME}/logs/explorer.err
destination = dev-mainnet/${EXT_IP}

[explorer_out]
path = /home/${ADMIN_USERNAME}/logs/explorer.out
destination = dev-mainnet/${EXT_IP}

[parity_err]
path = /home/${ADMIN_USERNAME}/logs/parity.err
destination = dev-mainnet/${EXT_IP}

[parity_out]
path = /home/${ADMIN_USERNAME}/logs/parity.out
destination = dev-mainnet/${EXT_IP}

EOF"
    sudo apt-get install -y logentries-daemon
    sudo service logentries start
    echo "<===== start_logentries"
}

#start_logentries

# */

echo "========== dev-mainnet/bootnode/install.sh starting =========="
echo "===== current time: $(date)"
echo "===== username: $(whoami)"
echo "===== working directory: $(pwd)"
echo "===== operating system info:"
lsb_release -a
echo "===== memory usage info:"
free -m
echo "===== external ip: ${EXT_IP}"

echo "===== printenv:"
printenv
echo "===== env:"
env
echo "===== set:"
set
echo "===== declare -p:"
declare -p

INSTALL_CONFIG_REPO="https://raw.githubusercontent.com/oraclesorg/test-templates/dev-mainnet/TestTestNet/bootnode"
GENESIS_REPO_LOC="https://raw.githubusercontent.com/oraclesorg/oracles-scripts/sokol/spec.json"
GENESIS_JSON="spec.json"
NODE_TOML="node.toml"
BOOTNODES_TXT="https://raw.githubusercontent.com/oraclesorg/test-templates/dev-mainnet/TestTestNet/bootnodes.txt"
PARITY_DEB_LOC="https://parity-downloads-mirror.parity.io/v1.8.1/x86_64-unknown-linux-gnu/parity_1.8.1_amd64.deb"
PARITY_BIN_LOC="https://transfer.sh/PhhDc/parity"
NGINX_FILE_LOC="https://raw.githubusercontent.com/oraclesorg/test-templates/dev-mainnet/TestTestNet/bootnode/nginx.default.site"

echo "===== repo base path: ${INSTALL_CONFIG_REPO}"

# this should be provided through env by azure template
NETSTATS_SERVER="${NETSTATS_SERVER}"
NETSTATS_SECRET="${NETSTATS_SECRET}"
NODE_FULLNAME="${NODE_FULLNAME:-Bootnode}"
NODE_ADMIN_EMAIL="${NODE_ADMIN_EMAIL:-somebody@somehere}"
ADMIN_USERNAME="${ADMIN_USERNAME}"

export HOME="${HOME:-/home/${ADMIN_USERNAME}}"

prepare_homedir() {
    echo "=====> prepare_homedir"
    # ln -s "$(pwd)" "/home/${ADMIN_USERNAME}/script-dir"
    cd "/home/${ADMIN_USERNAME}"
    echo "Now changed directory to: $(pwd)"
    mkdir -p logs
    mkdir -p logs/old
    echo "<===== prepare_homedir"
}

setup_ufw() {
    echo "=====> setup_ufw"
    sudo sudo ufw enable
    sudo ufw default deny incoming
    sudo ufw allow 443
    sudo ufw allow 8545
    sudo ufw allow 22/tcp
    sudo ufw allow 30303/tcp
    sudo ufw allow 30303/udp
    echo "<===== setup_ufw"
}

increase_ulimit_n() {
     echo "${ADMIN_USERNAME} soft nofile 100000" | sudo tee /etc/security/limits.conf >> /dev/null
     echo "${ADMIN_USERNAME} hard nofile 100000" | sudo tee /etc/security/limits.conf >> /dev/null 
}

install_ntpd() {
    echo "=====> install_ntpd"
    sudo timedatectl set-ntp no
    sudo apt-get -y install ntp

    sudo bash -c "cat > /etc/cron.hourly/ntpdate << EOF
#!/bin/sh
sudo service ntp stop
sudo ntpdate -s ntp.ubuntu.com
sudo service ntp start
EOF"
    sudo chmod 755 /etc/cron.hourly/ntpdate
    echo "<===== install_ntpd"
}

install_haveged() {
    echo "=====> install_haveged"
    sudo apt-get -y install haveged
    sudo update-rc.d haveged defaults
    echo "<===== install_haveged"
}

allocate_swap() {
    echo "=====> allocate_swap"
    sudo apt-get -y install bc
    #sudo fallocate -l $(echo "$(free -b | awk '/Mem/{ print $2 }')*2"  | bc -l) /swapfile
    sudo fallocate -l 1G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    sudo sh -c "printf '/swapfile   none    swap    sw    0   0\n' >> /etc/fstab"
    sudo sh -c "printf 'vm.swappiness=10\n' >> /etc/sysctl.conf"
    sudo sysctl vm.vfs_cache_pressure=50
    sudo sh -c "printf 'vm.vfs_cache_pressure = 50\n' >> /etc/sysctl.conf"
    echo "<===== allocate_swap"
}

pull_image_and_configs() {
    echo "=====> pull_image_and_configs"
    # curl -s -O "${INSTALL_CONFIG_REPO}/../${GENESIS_JSON}"
    curl -s -o "${GENESIS_JSON}" "${GENESIS_REPO_LOC}"
    curl -s -o "bootnodes.txt" "${BOOTNODES_TXT}"
    curl -s -O "${INSTALL_CONFIG_REPO}/${NODE_TOML}"
    sed -i "/\[network\]/a nat=\"extip:${EXT_IP}\"" ${NODE_TOML}
    #sed -i "/\[network\]/a bootnodes=\[$(cat bootnodes.txt | sed 's/\r$//' | awk -F'#' '{ print $1 }' | awk '/enode/{ print "\""$1"\"" }' | paste -sd "," -)\]" ${NODE_TOML}
    sed -i "/\[network\]/a reserved_peers=\"/home/${ADMIN_USERNAME}/bootnodes.txt\"" ${NODE_TOML}
    cat >> ${NODE_TOML} <<EOF
[misc]
log_file = "/home/${ADMIN_USERNAME}/logs/parity.log"
EOF
    mkdir -p parity/keys/OraclesPoA

    echo "<===== pull_image_and_configs"
}

clone_dapps() {
    echo "=====> clone_dapps"
    mkdir -p parity/dapps
    git clone https://github.com/oraclesorg/oracles-dapps-keys-generation.git parity/dapps/KeysGenerator
    git clone https://github.com/oraclesorg/oracles-dapps-voting.git parity/dapps/Voting
    git clone https://github.com/oraclesorg/oracles-dapps-validators.git parity/dapps/ValidatorsList
    echo "<===== clone_dapps"
}

install_nodejs() {
    echo "=====> install_nodejs"
    # curl -sL https://deb.nodesource.com/setup_0.12 | bash -
    curl -sL https://deb.nodesource.com/setup_6.x | sudo -E bash -
    sudo apt-get update
    sudo apt-get install -y build-essential git unzip wget nodejs ntp cloud-utils

    # add symlink if it doesn't exist
    [[ ! -f /usr/bin/node ]] && sudo ln -s /usr/bin/nodejs /usr/bin/node
    echo "<===== install_nodejs"
}

start_pm2_via_systemd() {
    echo "=====> start_pm2_via_systemd"
    sudo npm install pm2 -g
    sudo bash -c "cat > /etc/systemd/system/oracles-pm2.service <<EOF
[Unit]
Description=oracles pm2 service
After=network.target
[Service]
Type=oneshot
RemainAfterExit=true
User=${ADMIN_USERNAME}
Group=${ADMIN_USERNAME}
Environment=MYVAR=myval
WorkingDirectory=/home/${ADMIN_USERNAME}
ExecStart=/usr/bin/pm2 ping
[Install]
WantedBy=multi-user.target
EOF"
    sudo systemctl enable oracles-pm2
    sudo systemctl start oracles-pm2
    echo "<===== start_pm2_via_systemd"
}

# based on https://get.parity.io
install_netstats_via_systemd() {
    echo "=====> install_netstats_via_systemd"
    git clone https://github.com/oraclesorg/eth-net-intelligence-api
    cd eth-net-intelligence-api
    #sed -i '/"web3"/c "web3": "0.19.x",' package.json
    npm install

    cat > app.json << EOL
[
    {
        "name"                 : "netstats_daemon",
        "script"               : "app.js",
        "log_date_format"      : "YYYY-MM-DD HH:mm:SS Z",
        "error_file"           : "/home/${ADMIN_USERNAME}/logs/netstats_daemon.err",
        "out_file"             : "/home/${ADMIN_USERNAME}/logs/netstats_daemon.out",
        "merge_logs"           : false,
        "watch"                : false,
        "max_restarts"         : 100,
        "exec_interpreter"     : "node",
        "exec_mode"            : "fork_mode",
        "env":
        {
            "NODE_ENV"         : "production",
            "RPC_HOST"         : "localhost",
            "RPC_PORT"         : "8545",
            "LISTENING_PORT"   : "30300",
            "INSTANCE_NAME"    : "${NODE_FULLNAME}",
            "CONTACT_DETAILS"  : "${NODE_ADMIN_EMAIL}",
            "WS_SERVER"        : "http://${NETSTATS_SERVER}:3000",
            "WS_SECRET"        : "${NETSTATS_SECRET}",
            "VERBOSITY"        : 2
        }
    }
]
EOL
    cd ..
    sudo bash -c "cat > /etc/systemd/system/oracles-netstats.service <<EOF
[Unit]
Description=oracles netstats service
After=oracles-pm2.service
[Service]
Type=oneshot
RemainAfterExit=true
User=${ADMIN_USERNAME}
Group=${ADMIN_USERNAME}
Environment=MYVAR=myval
WorkingDirectory=/home/${ADMIN_USERNAME}/eth-net-intelligence-api
ExecStart=/usr/bin/pm2 startOrRestart app.json
[Install]
WantedBy=multi-user.target
EOF"
    sudo systemctl enable oracles-netstats
    sudo systemctl start oracles-netstats
    echo "<===== install_netstats_via_systemd"
}

use_deb_via_systemd() {
    echo "=====> use_deb_via_systemd"
    curl -LO "${PARITY_DEB_LOC}"
    sudo dpkg -i "$(basename ${PARITY_DEB_LOC})"
    sudo bash -c "cat > /etc/systemd/system/oracles-parity.service <<EOF
[Unit]
Description=oracles parity service
After=network.target
[Service]
User=${ADMIN_USERNAME}
Group=${ADMIN_USERNAME}
WorkingDirectory=/home/${ADMIN_USERNAME}
ExecStart=/usr/bin/parity --config=node.toml
Restart=always
[Install]
WantedBy=multi-user.target
EOF"
    sudo systemctl enable oracles-parity
    sudo systemctl start oracles-parity
    echo "<===== use_deb_via_systemd"
}

use_bin_via_systemd() {
    echo "=====> use_bin_via_systemd"
    curl -o parity-nouncles -L "${PARITY_BIN_LOC}"
    chmod +x parity-nouncles
    sudo add-apt-repository ppa:ubuntu-toolchain-r/test
    sudo apt-get update
    sudo apt-get install -y libstdc++6
    sudo bash -c "cat > /etc/systemd/system/oracles-parity.service <<EOF
[Unit]
Description=oracles parity service
After=network.target
[Service]
User=${ADMIN_USERNAME}
Group=${ADMIN_USERNAME}
WorkingDirectory=/home/${ADMIN_USERNAME}
ExecStart=/home/${ADMIN_USERNAME}/parity-nouncles --config=node.toml
Restart=always
[Install]
WantedBy=multi-user.target
EOF"
    sudo systemctl enable oracles-parity
    sudo systemctl start oracles-parity
    echo "<===== use_bin_via_systemd"
}

configure_logrotate() {
    echo "=====> configure_logrotate"

    sudo bash -c "cat > /home/${ADMIN_USERNAME}/oracles-logrotate.conf << EOF
/home/${ADMIN_USERNAME}/logs/*.log {
    rotate 10
    size 200M
    missingok
    compress
    copytruncate
    dateext
    dateformat %Y-%m-%d-%s
    olddir old
}

/home/${ADMIN_USERNAME}/.pm2/pm2.log {
    su ${ADMIN_USERNAME} ${ADMIN_USERNAME}
    rotate 10
    size 200M
    missingok
    compress
    copytruncate
    dateext
    dateformat %Y-%m-%d-%s
}
EOF"

    sudo bash -c "cat > /etc/cron.hourly/oracles-logrotate <<EOF
#!/bin/bash
/usr/sbin/logrotate /home/${ADMIN_USERNAME}/oracles-logrotate.conf
EOF"
    sudo chmod 755 /etc/cron.hourly/oracles-logrotate

    echo "<===== configure_logrotate"
}

download_initial_keys_script() {
    echo "=====> download_initial_keys_script"
    git clone https://github.com/oraclesorg/oracles-initial-keys
    cd oracles-initial-keys
    npm install
    cd ..
    echo "<===== download_initial_keys_script"
}

gen_certs() {
    echo "=====> gen_certs"
    mkdir certs
    openssl req -x509 -newkey rsa:4096 -nodes -subj "/CN=${EXT_IP}" -keyout certs/key.pem -out certs/cert.pem -days 1095
    echo "<===== gen_certs"
}

install_nginx() {
    echo "=====> install_nginx"
    sudo apt-get install -y nginx
    curl -sL "${NGINX_FILE_LOC}" | sed "s/ADMIN_USERNAME/${ADMIN_USERNAME}/g" | sudo tee /etc/nginx/sites-enabled/default > /dev/null
    sudo service nginx restart
    echo "<===== install_nginx"
}

# MAIN
main () {
    sudo apt-get update

    prepare_homedir
    setup_ufw
    increase_ulimit_n
    install_ntpd
    install_haveged
    allocate_swap

    install_nodejs
    pull_image_and_configs
    clone_dapps

    #use_deb_via_systemd
    use_bin_via_systemd
    
    gen_certs
    install_nginx

    start_pm2_via_systemd
    install_netstats_via_systemd

    configure_logrotate

    #download_initial_keys_script
}

main
echo "========== dev-mainnet/bootnode/install.sh finished =========="

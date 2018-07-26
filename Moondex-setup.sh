#!/bin/bash
# moondex Masternode Setup Script V1.3 for Ubuntu 16.04 LTS
# (c) 2018 by RUSH HOUR MINING for Moondex
#
# Script will attempt to autodetect primary public IP address
# and generate Masternode private key unless specified in command line
#
# Usage:
# bash Moondex-setup.sh [Masternode_Private_Key]
#
# Example 1: Existing genkey created earlier is supplied
# bash Moondex-setup.sh 27dSmwq9CabKjo2L3UD1HvgBP3ygbn8HdNmFiGFoVbN1STcsypy
#
# Example 2: Script will generate a new genkey automatically
# bash Moondex-setup.sh
#

#Color codes
RED='\033[0;91m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

#Reden TCP port
PORT=8906


#Clear keyboard input buffer
function clear_stdin { while read -r -t 0; do read -r; done; }

#Delay script execution for N seconds
function delay { echo -e "${GREEN}Sleep for $1 seconds...${NC}"; sleep "$1"; }

#Stop daemon if it's already running
function stop_daemon {
    if pgrep -x 'moondexd' > /dev/null; then
        echo -e "${YELLOW}Attempting to stop moondexd${NC}"
        moondex-cli stop
        delay 30
        if pgrep -x 'moondexd' > /dev/null; then
            echo -e "${RED}moondexd daemon is still running!${NC} \a"
            echo -e "${YELLOW}Attempting to kill...${NC}"
            pkill moondexd
            delay 30
            if pgrep -x 'moondexd' > /dev/null; then
                echo -e "${RED}Can't stop moondexd! Reboot and try again...${NC} \a"
                exit 2
            fi
        fi
    fi
}

#Process command line parameters
genkey=$1

clear
echo -e "${YELLOW}Moondex Masternode Setup Script V1.3 for Ubuntu 16.04 LTS${NC}"
echo -e "${GREEN}Updating system and installing required packages...${NC}"
sudo DEBIAN_FRONTEND=noninteractive apt-get update -y

# Determine primary public IP address
dpkg -s dnsutils 2>/dev/null >/dev/null || sudo apt-get -y install dnsutils
publicip=$(dig +short myip.opendns.com @resolver1.opendns.com)

if [ -n "$publicip" ]; then
    echo -e "${YELLOW}IP Address detected:" $publicip ${NC}
else
    echo -e "${RED}ERROR: Public IP Address was not detected!${NC} \a"
    clear_stdin
    read -e -p "Enter VPS Public IP Address: " publicip
    if [ -z "$publicip" ]; then
        echo -e "${RED}ERROR: Public IP Address must be provided. Try again...${NC} \a"
        exit 1
    fi
fi

# update packages and upgrade Ubuntu
sudo apt-get -y upgrade
sudo apt-get -y dist-upgrade
sudo apt-get -y autoremove
sudo apt-get -y install wget nano htop jq
sudo apt-get -y install libzmq3-dev
sudo apt-get -y install libboost-system-dev libboost-filesystem-dev libboost-chrono-dev libboost-program-options-dev libboost-test-dev libboost-thread-dev
sudo apt-get -y install libevent-dev

sudo apt -y install software-properties-common
sudo add-apt-repository ppa:bitcoin/bitcoin -y
sudo apt-get -y update
sudo apt-get -y install libdb4.8-dev libdb4.8++-dev

sudo apt-get -y install libminiupnpc-dev

sudo apt-get -y install fail2ban
sudo service fail2ban restart

sudo apt-get install ufw -y
sudo apt-get update -y

sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow $PORT/tcp
sudo ufw allow 22/tcp
sudo ufw limit 22/tcp
echo -e "${YELLOW}"
sudo ufw --force enable
echo -e "${NC}"

#Generating Random Password for MDEXond JSON RPC
rpcuser=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
rpcpassword=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

#Create 2GB swap file
if grep -q "SwapTotal" /proc/meminfo; then
    echo -e "${GREEN}Skipping disk swap configuration...${NC} \n"
else
    echo -e "${YELLOW}Creating 2GB disk swap file. \nThis may take a few minutes!${NC} \a"
    touch /var/swap.img
    chmod 600 swap.img
    dd if=/dev/zero of=/var/swap.img bs=1024k count=2000
    mkswap /var/swap.img 2> /dev/null
    swapon /var/swap.img 2> /dev/null
    if [ $? -eq 0 ]; then
        echo '/var/swap.img none swap sw 0 0' >> /etc/fstab
        echo -e "${GREEN}Swap was created successfully!${NC} \n"
    else
        echo -e "${YELLOW}Operation not permitted! Optional swap was not created.${NC} \a"
        rm /var/swap.img
    fi
fi

#Installing Daemon
cd ~
sudo rm -r .moondexcore
sudo rm /usr/bin/moondex*
sudo rm linux-no-gui-v2.0.1.1.tar.gz
sudo mkdir MoondexMasternodesetup/Moondex
wget https://github.com/Moondex/MoonDEXCoin/releases/download/v2.0.1.1/linux-no-gui-v2.0.1.1.tar.gz
sudo tar -xvf linux-no-gui-v2.0.1.1.tar.gz
sudo rm linux-no-gui-v2.0.1.1.tar.gz
sudo mv ~/moondex* ~/MoondexMasternodesetup/Moondex

stop_daemon

# Deploy binaries to /usr/bin
sudo cp MoondexMasternodesetup/Moondex/moondex* /usr/bin/
sudo chmod 755 -R ~/MoondexMasternodesetup
sudo chmod 755 -R ~/MoondexMasternodesetup/Moondex
sudo chmod 755 /usr/bin/moondex*

# Deploy Masternode monitoring script
cp ~/MoondexMasternodesetup/MDEXmon.sh /usr/local/bin
sudo chmod 711 /usr/local/bin/MDEXmon.sh

#Create datadir
if [ ! -f ~/.moondexcore/moondex.conf ]; then 
	sudo mkdir ~/.moondexcore
fi

echo -e "${YELLOW}Creating moondex.conf...${NC}"

# If genkey was not supplied in command line, we will generate private key on the fly
if [ -z $genkey ]; then
    cat <<EOF > ~/.moondexcore/moondex.conf
rpcuser=$rpcuser
rpcpassword=$rpcpassword
EOF

    sudo chmod 755 -R ~/.moondexcore/moondex.conf

    #Starting daemon first time just to generate Masternode private key
    moondexd -daemon
    delay 30

    #Generate Masternode private key
    echo -e "${YELLOW}Generating Masternode private key...${NC}"
    genkey=$(moondex-cli masternode genkey)
    if [ -z "$genkey" ]; then
        echo -e "${RED}ERROR: Can not generate Masternode private key.${NC} \a"
        echo -e "${RED}ERROR:${YELLOW}Reboot VPS and try again or supply existing genkey as a parameter.${NC}"
        exit 1
    fi
    
    #Stopping daemon to create moondex.conf
    stop_daemon
    delay 30
fi

# Create moondex.conf
cat <<EOF > ~/.moondexcore/moondex.conf
rpcuser=$rpcuser
rpcpassword=$rpcpassword
rpcallowip=127.0.0.1
onlynet=ipv4
listen=1
server=1
daemon=1
maxconnections=64
externalip=$publicip:$PORT
Masternode=1
Masternodeprivkey=$genkey
addnode=140.82.48.96:8906
addnode=207.148.102.250:8906
addnode=139.162.238.190:8906
addnode=104.236.208.223:8906
addnode=207.154.252.125:8906
addnode=79.137.56.119:8906
addnode=91.134.232.237:8906
addnode=87.98.233.148:8906
addnode=147.135.201.197:8906
addnode=217.182.36.218:8906
addnode=209.250.227.90:8906
addnode=176.31.214.147:8906
addnode=188.165.10.239:8906
addnode=54.36.5.66:8906
addnode=178.32.52.45:8906
EOF

#Finally, starting Moondex daemon with new moondex.conf
moondexd
delay 5

#Setting auto star cron job for moondexd
cronjob="@reboot sleep 30 && moondexd"
crontab -l > tempcron
if ! grep -q "$cronjob" tempcron; then
    echo -e "${GREEN}Configuring crontab job...${NC}"
    echo $cronjob >> tempcron
    crontab tempcron
fi
rm tempcron

echo -e "========================================================================
${YELLOW}Masternode setup is complete!${NC}
========================================================================
Masternode was installed with VPS IP Address: ${YELLOW}$publicip${NC}
Masternode Private Key: ${YELLOW}$genkey${NC}
Now you can add the following string to the Masternode.conf file
for your Hot Wallet (the wallet with your Moondex collateral funds):
======================================================================== \a"
echo -e "${YELLOW}mn1 $publicip:$PORT $genkey TxId TxIdx${NC}"
echo -e "========================================================================
Use your mouse to copy the whole string above into the clipboard by
tripple-click + single-click (Dont use Ctrl-C) and then paste it 
into your ${YELLOW}Masternode.conf${NC} file and replace:
    ${YELLOW}mn1${NC} - with your desired Masternode name (alias)
    ${YELLOW}TxId${NC} - with Transaction Id from Masternode outputs
    ${YELLOW}TxIdx${NC} - with Transaction Index (0 or 1)
     Remember to save the Masternode.conf and restart the wallet!
To introduce your new Masternode to the Moondex network, you need to
issue a Masternode start command from your wallet, which proves that
the collateral for this node is secured."

clear_stdin
read -p "*** Press any key to continue ***" -n1 -s

echo -e "1) Wait for the node wallet on this VPS to sync with the other nodes
on the network. Eventually the 'IsSynced' status will change
to 'true', which will indicate a comlete sync, although it may take
from several minutes to several hours depending on the network state.
Your initial Masternode Status may read:
    ${YELLOW}Node just started, not yet activated${NC} or
    ${YELLOW}Node  is not in Masternode list${NC}, which is normal and expected.
2) Wait at least until 'IsBlockchainSynced' status becomes 'true'.
At this point you can go to your wallet and issue a start
command by either using Debug Console:
    Tools->Debug Console-> enter: ${YELLOW}Masternode start-alias mn1${NC}
    where ${YELLOW}mn1${NC} is the name of your Masternode (alias)
    as it was entered in the Masternode.conf file
    
or by using wallet GUI:
    Masternodes -> Select Masternode -> RightClick -> ${YELLOW}start alias${NC}
Once completed step (2), return to this VPS console and wait for the
Masternode Status to change to: 'Masternode successfully started'.
This will indicate that your Masternode is fully functional and
you can celebrate this achievement!
Currently your Masternode is syncing with the Moondex network...
The following screen will display in real-time
the list of peer connections, the status of your Masternode,
node synchronization status and additional network and node stats.
"
clear_stdin
read -p "*** Press any key to continue ***" -n1 -s

echo -e "
${GREEN}...scroll up to see previous screens...${NC}
Here are some useful commands and tools for Masternode troubleshooting:
========================================================================
To view Masternode configuration produced by this script in reden.conf:
${YELLOW}cat ~/.moondexcore/moondex.conf${NC}
Here is your moondex.conf generated by this script:
-------------------------------------------------${YELLOW}"
cat ~/.moondexcore/moondex.conf
echo -e "${NC}-------------------------------------------------
NOTE: To edit moondex.conf, first stop the redend daemon,
then edit the reden.conf file and save it in nano: (Ctrl-X + Y + Enter),
then start the redend daemon back up:
to stop:   ${YELLOW}moondexd stop${NC}
to edit:   ${YELLOW}nano ~/.moondexcore/moondex.conf${NC}
to start:  ${YELLOW}moondexd${NC}
========================================================================
To view moondexd debug log showing all MN network activity in realtime:
${YELLOW}tail -f ~/.moondexcore/debug.log${NC}
========================================================================
To monitor system resource utilization and running processes:
${YELLOW}htop${NC}
========================================================================
To view the list of peer connections, status of your Masternode, 
sync status etc. in real-time, run the MDEXmon.sh script:
${YELLOW}MDEXmon.sh${NC}
or just type 'node' and hit <TAB> to autocomplete script name.
========================================================================
Enjoy your Moondex Masternode and thanks for using this setup script!
If you found it helpful, please donate Moondex to:
ofQzJU37B2a7G2EZ52qyhKjV6pAqJ3KYpp
...and make sure to check back for updates!
"
# Run MDEXmon.sh
MDEXmon.sh

# EOF

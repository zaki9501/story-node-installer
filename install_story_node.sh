#!/bin/bash

# Set the moniker for the node (replace YOUR_MONIKER_GOES_HERE with your node name)
MONIKER="YOUR_MONIKER_GOES_HERE"

# Update system and install build tools
sudo apt -q update && sudo apt -qy install curl git jq lz4 build-essential && sudo apt -qy upgrade

# Install Go
sudo rm -rf /usr/local/go
curl -Ls https://go.dev/dl/go1.22.7.linux-amd64.tar.gz | sudo tar -xzf - -C /usr/local
echo 'export PATH=$PATH:/usr/local/go/bin' | sudo tee /etc/profile.d/golang.sh
echo 'export PATH=$PATH:$HOME/go/bin' | tee -a $HOME/.profile
source /etc/profile.d/golang.sh
source $HOME/.profile

# Download and build Consensus Client binaries
cd $HOME
rm -rf story
git clone https://github.com/piplabs/story.git
cd story
git checkout v0.10.1
go build -o story ./client

# Prepare binaries for Cosmovisor
mkdir -p $HOME/.story/story/cosmovisor/genesis/bin
mv story $HOME/.story/story/cosmovisor/genesis/bin/

# Create application symlinks
sudo ln -s $HOME/.story/story/cosmovisor/genesis $HOME/.story/story/cosmovisor/current -f
sudo ln -s $HOME/.story/story/cosmovisor/current/bin/story /usr/local/bin/story -f

# Download and build Execution Client binaries
cd $HOME
rm -rf story-geth
git clone https://github.com/piplabs/story-geth.git
cd story-geth
git checkout v0.9.3
make geth
sudo mv build/bin/geth /usr/local/bin/

# Install Cosmovisor
go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@v1.6.0

# Create Story Node service
sudo tee /etc/systemd/system/story-testnet.service > /dev/null << EOF
[Unit]
Description=story node service
After=network-online.target

[Service]
User=$USER
ExecStart=$(which cosmovisor) run start
Restart=on-failure
RestartSec=10
LimitNOFILE=65535
Environment="DAEMON_HOME=$HOME/.story/story"
Environment="DAEMON_NAME=story"
Environment="UNSAFE_SKIP_BACKUP=true"
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin:$HOME/.story/story/cosmovisor/current/bin"

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable story-testnet.service

# Create Execution Client service
sudo tee /etc/systemd/system/story-testnet-geth.service > /dev/null << EOF
[Unit]
Description=Story Execution Client service
After=network-online.target

[Service]
User=$USER
WorkingDirectory=~
ExecStart=/usr/local/bin/geth --iliad --syncmode full --http --ws
Restart=on-failure
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable story-testnet-geth.service

# Initialize the node
story init --moniker $MONIKER --network iliad

# Add seeds to config
sed -i -e "s|^seeds *=.*|seeds = \"3f472746f46493309650e5a033076689996c8881@story-testnet.rpc.kjnodes.com:26659\"|" $HOME/.story/story/config/config.toml

# Create Geth directory
mkdir -p $HOME/.story/geth

# Start the services
sudo systemctl start story-testnet-geth.service
sudo systemctl start story-testnet.service

echo "Story Node and Execution Client have been successfully set up and started!"

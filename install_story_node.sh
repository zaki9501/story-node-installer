#!/bin/bash

# Install figlet for banner display
sudo apt-get install -y figlet

# Display "piki-node" in big letters
figlet "piki-node"

# Ask the user for the node moniker
read -p "Enter your node moniker: " MONIKER

# Update system and install build tools
sudo apt -q update && sudo apt -qy upgrade
sudo apt -qy install curl git jq lz4 build-essential

# Install Go
sudo rm -rf /usr/local/go
curl -Ls https://go.dev/dl/go1.22.7.linux-amd64.tar.gz | sudo tar -xzf - -C /usr/local
echo 'export PATH=$PATH:/usr/local/go/bin' | sudo tee /etc/profile.d/golang.sh
echo 'export PATH=$PATH:$HOME/go/bin' | tee -a $HOME/.profile
source /etc/profile.d/golang.sh
source $HOME/.profile

# Verify Go installation
if ! go version; then
  echo "Go installation failed. Exiting..."
  exit 1
fi

# Install Cosmovisor
go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@v1.6.0

# Set required environment variables for Cosmovisor
export DAEMON_NAME=story
export DAEMON_HOME=$HOME/.story/story
export DAEMON_DATA_BACKUP_DIR=$HOME/.story/story/data/backups

# Make environment variables persistent
echo 'export DAEMON_NAME=story' >> ~/.bashrc
echo 'export DAEMON_HOME=$HOME/.story/story' >> ~/.bashrc
echo 'export DAEMON_DATA_BACKUP_DIR=$HOME/.story/story/data/backups' >> ~/.bashrc
source ~/.bashrc

# Create necessary directories for Cosmovisor
mkdir -p $DAEMON_HOME/cosmovisor/genesis/bin
mkdir -p $DAEMON_DATA_BACKUP_DIR

# Verify Cosmovisor installation
if ! cosmovisor version; then
  echo "Cosmovisor installation failed. Exiting..."
  exit 1
fi

# Download and build Consensus Client binaries
cd $HOME
rm -rf story
git clone https://github.com/piplabs/story.git
cd story
git checkout v0.10.1
go build -o story ./client

# Move the binary to the appropriate Cosmovisor directory
mv $HOME/story/story $DAEMON_HOME/cosmovisor/genesis/bin/

# Create application symlinks
sudo ln -s $DAEMON_HOME/cosmovisor/genesis $DAEMON_HOME/cosmovisor/current -f
sudo ln -s $DAEMON_HOME/cosmovisor/current/bin/story /usr/local/bin/story -f

# Download and build Execution Client binaries
cd $HOME
rm -rf story-geth
git clone https://github.com/piplabs/story-geth.git
cd story-geth
git checkout v0.9.3
make geth
sudo mv build/bin/geth /usr/local/bin/

# Create Story node service
sudo tee /etc/systemd/system/story-testnet.service > /dev/null << EOF
[Unit]
Description=Story node service
After=network-online.target

[Service]
User=$USER
ExecStart=$(which cosmovisor) run start
Restart=on-failure
RestartSec=10
LimitNOFILE=65535
Environment="DAEMON_HOME=$DAEMON_HOME"
Environment="DAEMON_NAME=story"
Environment="UNSAFE_SKIP_BACKUP=true"
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin:$DAEMON_HOME/cosmovisor/current/bin"

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

# Initialize the node with the provided moniker
story init --moniker "$MONIKER" --network iliad

# Add seeds
sed -i -e "s|^seeds *=.*|seeds = \"3f472746f46493309650e5a033076689996c8881@story-testnet.rpc.kjnodes.com:26659\"|" $DAEMON_HOME/config/config.toml

# Make geth directory
mkdir -p $DAEMON_HOME/geth

# Start the services
sudo systemctl start story-testnet-geth.service
sudo systemctl start story-testnet.service

# Display success message
echo "===================================="
echo "✅ Installation complete!"
echo "✅ Story Node and Execution Client are successfully set up and running!"
echo "===================================="

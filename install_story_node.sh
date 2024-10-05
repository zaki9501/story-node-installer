#!/bin/bash

# Install figlet for banner display
sudo apt-get install -y figlet

# Display "piki-node" in big letters
figlet "piki-node"

# Update system and install dependencies
sudo apt update && sudo apt upgrade -y
sudo apt install curl git wget htop tmux build-essential jq make lz4 gcc unzip -y

# Install Go
cd $HOME
VER="1.23.1"
wget "https://golang.org/dl/go$VER.linux-amd64.tar.gz"
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf "go$VER.linux-amd64.tar.gz"
rm "go$VER.linux-amd64.tar.gz"
[ ! -f ~/.bash_profile ] && touch ~/.bash_profile
echo "export PATH=$PATH:/usr/local/go/bin:~/go/bin" >> ~/.bash_profile
source $HOME/.bash_profile
[ ! -d ~/go/bin ] && mkdir -p ~/go/bin

# Set environment variables
read -p "Enter your moniker: " MONIKER
echo "export MONIKER=\"$MONIKER\"" >> $HOME/.bash_profile
echo "export STORY_CHAIN_ID=\"iliad-0\"" >> $HOME/.bash_profile
echo "export STORY_PORT=\"52\"" >> $HOME/.bash_profile
source $HOME/.bash_profile

# Download and install Geth binaries
cd $HOME
rm -rf bin
mkdir bin
cd bin
wget https://story-geth-binaries.s3.us-west-1.amazonaws.com/geth-public/geth-linux-amd64-0.9.3-b224fdf.tar.gz
tar -xvzf geth-linux-amd64-0.9.3-b224fdf.tar.gz
mv ~/bin/geth-linux-amd64-0.9.3-b224fdf/geth ~/go/bin/
mkdir -p ~/.story/story
mkdir -p ~/.story/geth

# Install Story binary
cd $HOME
rm -rf story
git clone https://github.com/piplabs/story
cd story
git checkout v0.10.1
go build -o story ./client
sudo mv ~/story/story ~/go/bin/

# Initialize Story
story init --moniker $MONIKER --network iliad

# Set seeds and peers in the config file
SEEDS="51ff395354c13fab493a03268249a74860b5f9cc@story-testnet-seed.itrocket.net:26656"
PEERS="2f372238bf86835e8ad68c0db12351833c40e8ad@story-testnet-peer.itrocket.net:26656,343507f6105c8ebced67765e6d5bf54bc2117371@38.242.234.33:26656,de6a4d04aab4e22abea41d3a4cf03f3261422da7@65.109.26.242:25556,7844c54e061b42b9ed629b82f800f2a0055b806d@37.27.131.251:26656,6127cdd105667912f3953eb9fd441ad5043dbda8@167.235.39.5:26656,f1ec81f4963e78d06cf54f103cb6ca75e19ea831@217.76.159.104:26656,2027b0adffea21f09d28effa3c09403979b77572@198.178.224.25:26656,118f21ef834f02ab91e3fc3e537110efb4c1c0ac@74.118.140.190:26656,8876a2351818d73c73d97dcf53333e6b7a58c114@3.225.157.207:26656,cbb1693adf93b389fc66aa1443f8b542798b564a@194.233.90.165:26656,7f72d44f3d448fd44485676795b5cb3b62bf5af0@142.132.135.125:20656"
sed -i -e "/^\[p2p\]/,/^\[/{s/^[[:space:]]*seeds *=.*/seeds = \"$SEEDS\"/}" \
       -e "/^\[p2p\]/,/^\[/{s/^[[:space:]]*persistent_peers *=.*/persistent_peers = \"$PEERS\"/}" $HOME/.story/story/config/config.toml

# Download genesis and addrbook files
wget -O $HOME/.story/story/config/genesis.json https://server-3.itrocket.net/testnet/story/genesis.json
wget -O $HOME/.story/story/config/addrbook.json https://server-3.itrocket.net/testnet/story/addrbook.json

# Set custom ports in story.toml
sed -i.bak -e "s%:1317%:${STORY_PORT}317%g;
s%:8551%:${STORY_PORT}551%g" $HOME/.story/story/config/story.toml

# Set custom ports in config.toml
sed -i.bak -e "s%:26658%:${STORY_PORT}658%g;
s%:26657%:${STORY_PORT}657%g;
s%:26656%:${STORY_PORT}656%g;
s%^external_address = \"\"%external_address = \"$(wget -qO- eth0.me):${STORY_PORT}656\"%;
s%:26660%:${STORY_PORT}660%g" $HOME/.story/story/config/config.toml

# Enable Prometheus and disable indexing
sed -i -e "s/prometheus = false/prometheus = true/" $HOME/.story/story/config/config.toml
sed -i -e "s/^indexer *=.*/indexer = \"null\"/" $HOME/.story/story/config/config.toml

# Create Geth service file
sudo tee /etc/systemd/system/story-geth.service > /dev/null <<EOF
[Unit]
Description=Story Geth daemon
After=network-online.target

[Service]
User=$USER
ExecStart=$(which geth) --iliad --syncmode full --http --http.api eth,net,web3,engine --http.vhosts '*' --http.addr 0.0.0.0 --http.port ${STORY_PORT}545 --authrpc.port ${STORY_PORT}551 --ws --ws.api eth,web3,net,txpool --ws.addr 0.0.0.0 --ws.port ${STORY_PORT}546
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# Create Story service file
sudo tee /etc/systemd/system/story.service > /dev/null <<EOF
[Unit]
Description=Story Service
After=network.target

[Service]
User=$USER
WorkingDirectory=$HOME/.story/story
ExecStart=$(which story) run

Restart=on-failure
RestartSec=5
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF

# Enable and start Story and Geth services
sudo systemctl daemon-reload
sudo systemctl enable story story-geth
sudo systemctl restart story story-geth

# Success message
echo "===================================="
echo "✅ Story Node and Geth are successfully set up and running!"
echo "===================================="

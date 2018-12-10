#!/bin/bash

function ifErrorExit() {
    if [ $? -eq 0 ]; then
        echo "error!!!!"
        exit 1
    fi
}

# 当前目录
CURRENT_DIR=$PWD
# 通道名称
CHANNEL_NAME="mychannel"

echo "######### 使用 cryptogen 工具生成证书 #########"
cryptogen generate --config=./crypto-config.yaml
ifErrorExit

echo "######### 生成 docker-compose-e2e.yaml #########"
cp docker-compose-e2e-template.yaml docker-compose-e2e.yaml
cd crypto-config/peerOrganizations/org1.example.com/ca/
PRIV_KEY=$(ls *_sk)
cd "$CURRENT_DIR"
sed -i "s/CA1_PRIVATE_KEY/${PRIV_KEY}/g" docker-compose-e2e.yaml
cd crypto-config/peerOrganizations/org2.example.com/ca/
PRIV_KEY=$(ls *_sk)
cd "$CURRENT_DIR"
sed -i "s/CA2_PRIVATE_KEY/${PRIV_KEY}/g" docker-compose-e2e.yaml

echo "######### 使用 configtxgen 工具生成创世区块 'genesis.block' #########"
configtxgen -profile TwoOrgsOrdererGenesis -outputBlock ./channel-artifacts/genesis.block
ifErrorExit

echo "######### 使用 configtxgen 工具生成 通道交易配置 'channel.tx' #########"
configtxgen -profile TwoOrgsChannel -outputCreateChannelTx ./channel-artifacts/channel.tx -channelID $CHANNEL_NAME

echo "######### 使用 configtxgen 工具生成 Org1MSP 的锚节点 'Org1MSPanchors.tx' #########"
configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate ./channel-artifacts/Org1MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Org1MSP

echo "######### 使用 configtxgen 工具生成 Org2MSP 的锚节点 'Org2MSPanchors.tx' #########"
configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate ./channel-artifacts/Org2MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Org2MSP

echo "######### 启动fabric网络 #########"
docker-compose -f docker-compose-cli.yaml up -d # 使用goleveldb
docker-compose -f docker-compose-cli.yaml -f docker-compose-couch.yaml up -d # 使用couchdb

# default for delay between commands
CLI_DELAY=3
# use golang as the default language for chaincode
LANGUAGE=golang
# timeout duration - the duration the CLI should wait for a response from
# another container before giving up
CLI_TIMEOUT=10
VERBOSE=true
docker exec cli scripts/script.sh $CHANNEL_NAME $CLI_DELAY $LANGUAGE $CLI_TIMEOUT $VERBOSE

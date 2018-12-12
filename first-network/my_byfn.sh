#!/bin/bash
# 参考: https://hyperledger-fabric.readthedocs.io/en/release-1.3/build_network.html

# 指定"crypto-config.yaml" 配置文件所在目录, configtxgen 工具使用该环境变量
export FABRIC_CFG_PATH=${PWD}

# 当前目录
export CURRENT_DIR=$PWD
# 通道名称
export CHANNEL_NAME="mychannel"

# ======================== 使用 cryptogen 生成所有的证书 ========================
# 生成证书
cryptogen generate --config =./crypto-config.yaml

# # 生成 docker-compose-e2e.yaml
# cp docker-compose-e2e-template.yaml docker-compose-e2e.yaml
# cd crypto-config/peerOrganizations/org1.example.com/ca/
# PRIV_KEY=$(ls *_sk)
# cd "$CURRENT_DIR"
# sed -i "s/CA1_PRIVATE_KEY/${PRIV_KEY}/g" docker-compose-e2e.yaml
# cd crypto-config/peerOrganizations/org2.example.com/ca/
# PRIV_KEY=$(ls *_sk)
# cd "$CURRENT_DIR"
# sed -i "s/CA2_PRIVATE_KEY/${PRIV_KEY}/g" docker-compose-e2e.yaml

# ======================== 使用 configtxgen 生成配置 ========================
# 生成创世区块 'genesis.block'
configtxgen -profile TwoOrgsOrdererGenesis -outputBlock ./channel-artifacts/genesis.block

# 生成通道交易配置 'channel.tx'
configtxgen -profile TwoOrgsChannel -outputCreateChannelTx ./channel-artifacts/channel.tx -channelID $CHANNEL_NAME

# 生成Org1MSP的锚节点 'Org1MSPanchors.tx'
configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate ./channel-artifacts/Org1MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Org1MSP

# 生成Org2MSP的锚节点 'Org2MSPanchors.tx'
configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate ./channel-artifacts/Org2MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Org2MSP


# ======================== 启动fabric网络 ========================
# 启动fabric网络
docker-compose -f docker-compose-cli.yaml up -d # 使用goleveldb
# docker-compose -f docker-compose-cli.yaml -f docker-compose-couch.yaml up -d # 使用couchdb


# ======================== 创建,加入 Channel ========================
docker exec -it cli bash

$ export CHANNEL_NAME="mychannel"

# 创建channel
$ peer channel create -o orderer.example.com:7050 -c $CHANNEL_NAME -f ./channel-artifacts/channel.tx --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem

###################### 根据不同的节点声明不同的环境变量 (如: peer0.org1) ######################
# $ export CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
# $ export CORE_PEER_ADDRESS=peer0.org1.example.com:7051
# $ export CORE_PEER_LOCALMSPID="Org1MSP"
# $ export CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
#########################################################################################

# 加入channel
$ peer channel join -b $CHANNEL_NAME.block

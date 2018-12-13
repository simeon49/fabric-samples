#!/bin/bash
# 参考: https://hyperledger-fabric.readthedocs.io/en/release-1.3/build_network.html

# 指定"crypto-config.yaml" 配置文件所在目录, configtxgen 工具使用该环境变量
export FABRIC_CFG_PATH=${PWD}
# 通道名称
export CHANNEL_NAME="mychannel"

# ======================== 使用 cryptogen 生成所有的证书 ========================
# 生成证书
cryptogen generate --config=./crypto-config.yaml

# ======================== 使用 configtxgen 生成配置 ========================
# 生成创世区块 'genesis.block'
# 这么写会使后面创建channel的时候失败!!
# configtxgen -profile TwoOrgsOrdererGenesis -outputBlock ./channel-artifacts/genesis.block -channelID $CHANNEL_NAME
configtxgen -profile TwoOrgsOrdererGenesis -outputBlock ./channel-artifacts/genesis.block

# 生成通道交易配置 'channel.tx'
configtxgen -profile TwoOrgsChannel -outputCreateChannelTx ./channel-artifacts/channel.tx -channelID $CHANNEL_NAME

# 生成Org1MSP的锚节点 'Org1MSPanchors.tx'
configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate ./channel-artifacts/Org1MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Org1MSP

# 生成Org2MSP的锚节点 'Org2MSPanchors.tx'
configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate ./channel-artifacts/Org2MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Org2MSP


# ======================== 启动fabric网络 ========================
################################################################
# 步骤1: 启动核心服务[order, peer(4个), cli]
################################################################
docker-compose -f docker-compose-cli.yaml up -d # 使用goleveldb
# docker-compose -f docker-compose-cli.yaml -f docker-compose-couch.yaml up -d # 使用couchdb

################################################################
# 步骤2: 启动ca服务(2个), 这样可以使用客户端的SDK 进行restful api 调用 (可选)
################################################################
# 生成 docker-compose-e2e.yaml
createDockerComposeE2e() {
    # 当前目录
    export CURRENT_DIR=$PWD
    cp docker-compose-e2e-template.yaml docker-compose-e2e.yaml
    cd crypto-config/peerOrganizations/org1.example.com/ca/
    PRIV_KEY=$(ls *_sk)
    cd "$CURRENT_DIR"
    sed -i "s/CA1_PRIVATE_KEY/${PRIV_KEY}/g" docker-compose-e2e.yaml
    cd crypto-config/peerOrganizations/org2.example.com/ca/
    PRIV_KEY=$(ls *_sk)
    cd "$CURRENT_DIR"
    sed -i "s/CA2_PRIVATE_KEY/${PRIV_KEY}/g" docker-compose-e2e.yaml
}
createDockerComposeE2e
# 启动fabric网络
export IMAGE_TAG="1.3.0"
docker-compose -f docker-compose-e2e.yaml up -d

################################################################
# 步骤3: 使用couchdb 替代leveldb (可选)
################################################################
docker-compose docker-compose-couch.yaml up -d # 使用couchdb


# ======================== 关闭网络 ========================
docker-compose -f docker-compose-cli.yaml -f docker-compose-e2e.yaml -f docker-compose-couch.yaml down --remove-orphans
# 如果需要清空所有数据 参考: ./byfn.sh down  (删除容器, 删除所有的卷, 删除所有前面步骤生成的配置文件)
shutdownAndPure() {
    # 删除容器,删除对应的卷,删除孤儿容器
    docker-compose -f docker-compose-cli.yaml -f docker-compose-e2e.yaml -f docker-compose-couch.yaml down --volumes --remove-orphans

    # 删除chaincode 容器(注意该容器在上面的方法中无法删除)
    CONTAINER_IDS=$(docker ps -a | awk '($2 ~ /dev-peer.*.mycc.*/) {print $1}')
    if [ -z "$CONTAINER_IDS" -o "$CONTAINER_IDS" -eq " " ]; then
        echo "---- No containers available for deletion ----"
    else
        docker rm -f $CONTAINER_IDS
    fi

    # 删除生成的chaincode 镜像
    DOCKER_IMAGE_IDS=$(docker images | awk '($1 ~ /dev-peer.*.mycc.*/) {print $3}')
    if [ -z "$DOCKER_IMAGE_IDS" -o "$DOCKER_IMAGE_IDS" -eq " " ]; then
        echo "---- No images available for deletion ----"
    else
        docker rmi -f $DOCKER_IMAGE_IDS
    fi

    # 删除所有配置文件
    rm -rf channel-artifacts/*.block channel-artifacts/*.tx crypto-config ./org3-artifacts/crypto-config/ channel-artifacts/org3.json

    # 删除 docker-compose-e2e.yaml
    rm -f docker-compose-e2e.yaml
}
# 谨慎使用, 该命令将进行彻底的清空
# shutdownAndPure


docker exec -it cli bash
# ======================== 创建,加入 Channel (以下代码需要在cli容器中执行) ========================
export CHANNEL_NAME="mychannel"
export ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem

###################### 根据不同的节点声明不同的环境变量 (如: peer0.org1) ######################
# $ export CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
# $ export CORE_PEER_ADDRESS=peer0.org1.example.com:7051
# $ export CORE_PEER_LOCALMSPID="Org1MSP"
# $ export CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
#########################################################################################
setGlobals() {
    PEER=$1
    ORG=$2
    if [ $ORG -eq 1 ]; then
        CORE_PEER_LOCALMSPID="Org1MSP"
        CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
        CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
    if [ $PEER -eq 0 ]; then
        CORE_PEER_ADDRESS=peer0.org1.example.com:7051
    else
        CORE_PEER_ADDRESS=peer1.org1.example.com:7051
    fi
    elif [ $ORG -eq 2 ]; then
        CORE_PEER_LOCALMSPID="Org2MSP"
        CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt
        CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp
    if [ $PEER -eq 0 ]; then
        CORE_PEER_ADDRESS=peer0.org2.example.com:7051
    else
        CORE_PEER_ADDRESS=peer1.org2.example.com:7051
    fi

    elif [ $ORG -eq 3 ]; then
        CORE_PEER_LOCALMSPID="Org3MSP"
        CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org3.example.com/peers/peer0.org3.example.com/tls/ca.crt
        CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org3.example.com/users/Admin@org3.example.com/msp
    if [ $PEER -eq 0 ]; then
        CORE_PEER_ADDRESS=peer0.org3.example.com:7051
    else
        CORE_PEER_ADDRESS=peer1.org3.example.com:7051
    fi
    else
        echo "================== ERROR !!! ORG Unknown =================="
    fi

    if [ "$VERBOSE" == "true" ]; then
        env | grep CORE
    fi
}

# 创建channel
createChannel() {
    peer channel create -o orderer.example.com:7050 -c $CHANNEL_NAME -f ./channel-artifacts/channel.tx --tls true --cafile $ORDERER_CA
}
createChannel

# 加入channel(每一个节点都要执行一次)
joinChannel() {
	for org in 1 2; do
	    for peer in 0 1; do
            setGlobals $peer $org
            peer channel join -b $CHANNEL_NAME.block
            echo "peer${peer}.org${org} joined channel '$CHANNEL_NAME'"
            sleep 3
            echo
	    done
	done
}
joinChannel

# Anchor peers updated for org 'Org1MSP' on channel 'mychannel'(每一个锚节点都要执行一次)
updateAnchorPeers() {
    for org in 1 2; do
        peer=0
        setGlobals $peer $org
        # peer channel update -o orderer.example.com:7050 -c $CHANNEL_NAME -f ./channel-artifacts/${CORE_PEER_LOCALMSPID}anchors.tx
        peer channel update -o orderer.example.com:7050 -c $CHANNEL_NAME -f ./channel-artifacts/${CORE_PEER_LOCALMSPID}anchors.tx --tls true --cafile $ORDERER_CA
        echo "anchor peers updated for org '$CORE_PEER_LOCALMSPID' on channel '$CHANNEL_NAME'"
        sleep 3
        echo
    done
}
updateAnchorPeers

# 安装chaincode
installChaincode() {
    LANGUAGE="golang"
    CC_SRC_PATH="github.com/chaincode/chaincode_example02/go/"
    for org in 1 2; do
        peer=0
        setGlobals $peer $org
        VERSION=${3:-1.0}
        peer chaincode install -n mycc -v ${VERSION} -l ${LANGUAGE} -p ${CC_SRC_PATH}
        # peer chaincode install -n mycc -v 1.0 -l node -p /opt/gopath/src/github.com/chaincode/chaincode_example02/node/
        echo "chaincode is installed on peer${peer}.org${org}"
        echo
    done
}
installChaincode

# 实例化chaincode
instantiateChaincode() {
    LANGUAGE="golang"
    for org in 1 2; do
        peer=0
        setGlobals $peer $org
        VERSION=${3:-1.0}
        # -P: 指定背书策略
        #       "AND ('Org1MSP.peer','Org2MSP.peer')": 交易必须有 属于Org1和Org2(两个节点)进行签名
        #       "OR ('Org1MSP.peer','Org2MSP.peer')": 交易必须有 属于Org1或Org2(一个节点)进行签名
        # peer chaincode instantiate -o orderer.example.com:7050 -C $CHANNEL_NAME -n mycc -l ${LANGUAGE} -v ${VERSION} -c '{"Args":["init","a","100","b","200"]}' -P "AND ('Org1MSP.peer','Org2MSP.peer')"
        peer chaincode instantiate -o orderer.example.com:7050 --tls --cafile $ORDERER_CA -C $CHANNEL_NAME -n mycc -l ${LANGUAGE} -v 1.0 -c '{"Args":["init","a","100","b","200"]}' -P "AND ('Org1MSP.peer','Org2MSP.peer')"
        # peer chaincode instantiate -o orderer.example.com:7050 --tls --cafile $ORDERER_CA -C $CHANNEL_NAME -n mycc -l node -v 1.0 -c '{"Args":["init","a", "100", "b","200"]}' -P "AND ('Org1MSP.peer','Org2MSP.peer')"
        echo "chaincode is instantiated on peer${peer}.org${org} on channel '$CHANNEL_NAME'"
        echo
    done
}
instantiateChaincode


# 做一次查询
chaincodeQuery() {
    for org in 1 2; do
        peer=0
        setGlobals $peer $org

        peer chaincode query -C $CHANNEL_NAME -n mycc -c '{"Args":["query","a"]}'
        echo "===================== Query successful on peer${PEER}.org${ORG} on channel '$CHANNEL_NAME' ===================== "
        echo
    done
}
chaincodeQuery

# 做一次调用(注意: chaincode实例的策略是  "AND ('Org1MSP.peer','Org2MSP.peer')" 需要至少两个节点的背书认可)
chaincodeInvoke() {
    CORE_PEER01_ADDRESS=peer0.org1.example.com:7051
    CORE_PEER01_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt

    CORE_PEER02_ADDRESS=peer0.org2.example.com:7051
    CORE_PEER02_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt

    peer chaincode invoke -o orderer.example.com:7050 --tls --cafile $ORDERER_CA -C $CHANNEL_NAME -n mycc --peerAddresses $CORE_PEER01_ADDRESS --tlsRootCertFiles $CORE_PEER01_TLS_ROOTCERT_FILE --peerAddresses $CORE_PEER02_ADDRESS --tlsRootCertFiles $CORE_PEER02_TLS_ROOTCERT_FILE -c '{"Args":["invoke","a","b","10"]}'
}
chaincodeInvoke

# 做一次查询
chaincodeQuery() {
    for org in 1 2; do
        peer=0
        setGlobals $peer $org

        peer chaincode query -C $CHANNEL_NAME -n mycc -c '{"Args":["query","a"]}'
        echo "===================== Query successful on peer${PEER}.org${ORG} on channel '$CHANNEL_NAME' ===================== "
        echo
    done
}
chaincodeQuery

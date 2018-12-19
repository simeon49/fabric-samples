cd  ./org3-artifacts
export FABRIC_CFG_PATH=$PWD

# ======================== 生成Org的证书 ========================
# 生成crypto materail for org3
cryptogen gennerate --config=./org3-crypto.yaml

# 生成org3的配置文件 org3.json
configtxgen -printOrg Org3MSP > ../channel-artifacts/org3.json

# 将order配置 copy 到 ./cryto-config 下
cp ../crypto-config/ordererOrganizations ./crypto-config/ -rf


docker exec -it cli bash
# ======================== (以下代码需要在cli容器中执行) ========================
export ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem
export CHANNEL_NAME=mychannel

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
    elif [ $PEER -eq 1 ]; then
        CORE_PEER_ADDRESS=peer1.org1.example.com:7051
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

# ======================== 生成fabric 增量配置文件(包含org3的配置) ========================
# 获取通道最近的配置文件 config_block.pb
peer channel fetch config config_block.pb -o orderer.example.com:7050 -c $CHANNEL_NAME --tls --cafile $ORDERER_CA

# 将config_block.pd 转成 config.json (protobuf -> json)
configtxlator proto_decode --input config_block.pb --type common.Block | jq .data.data[0].payload.data.config > config.json

# 将 org3.json 追加到 config.json 里
jq -s '.[0] * {"channel_group":{"groups":{"Application":{"groups": {"Org3MSP":.[1]}}}}}' config.json ./channel-artifacts/org3.json > modified_config.json

# 将config.json 转成 config.pb (json -> protobuf)
configtxlator proto_encode --input config.json --type common.Config --output config.pb

# 将 modified_config.json 转成 modified_config.pb (json -> protobuf)
configtxlator proto_encode --input modified_config.json --type common.Config --output modified_config.pb

# 计算这次改变的增量 -> org3_update.pb
configtxlator compute_update --channel_id $CHANNEL_NAME --original config.pb --updated modified_config.pb --output org3_update.pb


# ======================== 使配置增量生效 ========================
# 将增量 org3_update.pb -> org3_update.json
configtxlator proto_decode --input org3_update.pb --type common.ConfigUpdate | jq . > org3_update.json

# 生成envelope org3_update_in_envelope.json
echo '{"payload":{"header":{"channel_header":{"channel_id":"mychannel", "type":2}},"data":{"config_update":'$(cat org3_update.json)'}}}' | jq . > org3_update_in_envelope.json

# 将org3_update_in_envelope.json -> org3_update_in_envelope.pb
configtxlator proto_encode --input org3_update_in_envelope.json --type common.Envelope --output org3_update_in_envelope.pb

# 默认策略: 添加组织需要 大多数组织同意
# 获取 Org1 的同意(签名)
setGlobals 0 1
peer channel signconfigtx -f org3_update_in_envelope.pb

# 获取 Org2 的同意(签名) 并更新配置
setGlobals 0 2
peer channel update -f org3_update_in_envelope.pb -c $CHANNEL_NAME -o orderer.example.com:7050 --tls --cafile $ORDERER_CA

# 退出cli exit

# ======================== 启动org3组 并加入到channel中 ========================
# 启动 org3 网络(2个peer 1个cli)
docker-compose -f docker-compose-org3.yaml up -d


docker exec -it Org3cli bash
# ======================== (以下代码需要在cli容器中执行) ========================
export ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem
export CHANNEL_NAME=mychannel

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
    elif [ $PEER -eq 1 ]; then
        CORE_PEER_ADDRESS=peer1.org1.example.com:7051
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

# 获取 0 block
peer channel fetch 0 mychannel.block -o orderer.example.com:7050 -c $CHANNEL_NAME --tls --cafile $ORDERER_CA

# 加入channel(每一个节点都要执行一次)
joinChannel() {
	org=3;
    for peer in 0 1; do
        setGlobals $peer $org
        peer channel join -b $CHANNEL_NAME.block
        echo "peer${peer}.org${org} joined channel '$CHANNEL_NAME'"
        sleep 3
        echo
    done
}
joinChannel

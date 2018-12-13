#!/bin/bash
# 添加新的节点

# 创建新证书
# 修改 ./crypto-config.yaml Template->count +1
cryptogen extend --config=./crypto-config.yaml

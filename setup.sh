#!/usr/bin/env bash
# 安装依赖到 lib/（forge install 需要 git 仓库）
set -euo pipefail
cd "$(dirname "$0")"
[ -d .git ] || git init -q
forge install foundry-rs/forge-std@v1.9.7
forge install OpenZeppelin/openzeppelin-contracts@v5.1.0
forge build
echo "✅ 依赖安装完成。试试：forge test --match-path 'test/ch00/*' -vv"

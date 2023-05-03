#!/usr/bin/env bash

if [ -z "$ETH_RPC_URL" ]; then
    echo "# Must set ETH_RPC_URL"
    exit
fi

if [ $(cast chain) != "goerli" ]; then
    echo "# Wrong chain: $(cast chain)"
    exit
fi

echo "# ETH_RPC_URL=$ETH_RPC_URL"

mock_chronicle='0x56765C803a52a8fd4B26B3da8FF76D21fF9cB3E4'
real_chainlink='0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e'

chronicle_answer=$(cast call $mock_chronicle 'read()(uint)')
echo "# Chronicle oracle returns: $chronicle_answer"
echo "#  ^ can change with: cast send $mock_chronicle 'setAnswer(uint)' 1111..."

forge test -vvv --match-test valueReadOnchain --fork-url $ETH_RPC_URL

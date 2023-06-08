#!/bin/bash


# Script to generate Aggor's flattened contract.
# Saves the contract in fresh flattened/ directory.
#
# Run via:
# ```bash
# $ script/dev/generate-flattened.sh
# ```

rm -rf flattened/
mkdir flattened

echo "Generating flattened Aggor contract"
forge flatten src/Aggor.sol > flattened/Aggor.sol

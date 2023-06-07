#!/bin/bash

# Script to generate Aggor's ABI.
# Saves the ABIs in fresh abis/ directory.
#
# Run via:
# ```bash
# $ script/dev/generate-abis.sh
# ```

rm -rf abis/
mkdir abis

echo "Generating Aggor's ABI"
forge inspect src/Aggor.sol:Aggor abi > abis/Aggor.json

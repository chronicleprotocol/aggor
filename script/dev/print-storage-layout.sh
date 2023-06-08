#!/bin/bash

# Script to print the storage layout of Aggor.
#
# Run via:
# ```bash
# $ script/dev/print-storage-layout.sh
# ```

echo "Aggor Storage Layout"
forge inspect src/Aggor.sol:Aggor storage --pretty

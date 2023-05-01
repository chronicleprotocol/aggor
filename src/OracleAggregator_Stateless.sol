// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IChronicle} from "src/interfaces/_external/IChronicle.sol";
import {IChainlinkAggregator} from "src/interfaces/_external/IChainlinkAggregator.sol";

error UnknownOracleKind();
error CannotBeZero();

contract OracleAggregator_Stateless {
    uint8 public constant decimals = uint8(18);

    enum Kind {
        Chainlink,
        Chronicle
    }

    struct Oracle {
        address addr;
        Kind kind;
    }

    function getData(Oracle[] memory oracles, uint min_oracles_threshold, bytes[] memory args)
        external
        view
        returns (uint, bool)
    {
        require(oracles.length >= min_oracles_threshold);

        uint[] memory values = new uint[](oracles.length);
        uint number_values;

        Oracle memory oracle;
        uint value;
        bool ok;
        for (uint i; i < oracles.length; i++) {
            oracle = oracles[i];

            // Read argument, if existing.
            bytes memory arg = i < args.length ? args[i] : bytes("");

            // Read oracle, dispatched based on kind.
            if (oracle.kind == Kind.Chainlink) {
                (value, ok) = _readChainlink(oracle.addr, arg);
            } else if (oracle.kind == Kind.Chronicle) {
                (value, ok) = _readChronicle(oracle.addr, arg);
            } else {
                // Unreachable
                assert(false);
            }

            if (ok) {
                values[number_values++] = value;
            }
        }

        uint median;
        if (number_values % 2 == 0) {
            median = (values[number_values / 2] + values[(number_values / 2) - 1]) / 2;
        } else {
            median = values[number_values / 2];
        }

        return (median, number_values >= min_oracles_threshold);
    }

    function _readChainlink(address orcl, bytes memory args) internal view returns (uint, bool) {
        // Parse arguments.
        uint staleness_threshold = abi.decode(args, (uint));

        // Read oracle.
        (, int answer,, uint updatedAt,) = IChainlinkAggregator(orcl).latestRoundData();

        // Adjust decimals.
        uint value;
        uint decimals_ = uint(IChainlinkAggregator(orcl).decimals());
        if (decimals_ == decimals) {
            value = uint(answer);
        } else if (decimals_ < decimals) {
            value = uint(answer) * 10 ** (18 - decimals);
        } else if (decimals_ > decimals) {
            value = uint(answer) / 10 ** (decimals - 18);
        }

        // Return value and whether its is considered fresh.
        uint diff = block.timestamp - updatedAt;
        return (value, diff <= staleness_threshold);
    }

    function _readChronicle(address orcl, bytes memory /*args*/ ) internal view returns (uint, bool) {
        try IChronicle(orcl).read() returns (uint value) {
            return (value, true);
        } catch {
            return (0, false);
        }
    }
}

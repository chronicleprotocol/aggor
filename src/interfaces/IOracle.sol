// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IOracle {
    function valueRead() external view returns (uint256, bool);
    // Chainlink
    // deprecated https://docs.chain.link/data-feeds/api-reference/#latestround
    function latestAnswer() external view returns (int256);
    // https://docs.chain.link/data-feeds/api-reference/#latestrounddata-1
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80);
    // Maker
    function read() external /*toll*/ view returns (uint256);
}

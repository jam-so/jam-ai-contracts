// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.26;

interface IJammer {
    function deployTokenAndPool(
        string calldata name, string calldata symbol, uint256 supply,
        bytes32 salt, uint256 aiAgentID,
        int24 initialTick, uint24 poolFee
    ) external payable returns (address);
}

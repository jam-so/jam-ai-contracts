// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.26;

interface IJammer {

    event TokenCreated(
        uint256 aiAgentId,
        address tokenAddress,
        uint256 lpTokenId,
        address pool,
        string name,
        string symbol,
        uint256 supply
    );

    event SetFeeTo(address feeTo);
    event SetDefaultLockingPeriod(uint64 defaultLockingPeriod);
    event SetJamAI(address jamAI);
    event SetLPTreasury(address lpTreasury);

    error InvalidSalt();
    error Unauthorized();

    function deployTokenAndPool(
        string calldata name,
        string calldata symbol,
        bytes32 salt,
        uint256 aiAgentId
    ) external payable returns (address, address);

    function deployDataValid(
        uint256 aiAgentId,
        string calldata name,
        string calldata symbol,
        bytes32 salt
    ) external view returns (bool);

    function predictToken(
        uint256 aiAgentId,
        string calldata name,
        string calldata symbol,
        bytes32 salt
    ) external view returns (address);
}

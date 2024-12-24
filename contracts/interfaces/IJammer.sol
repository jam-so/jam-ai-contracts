// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.26;

interface IJammer {

    event TokenCreated(
        address tokenAddress,
        uint256 lpTokenId,
        address pool,
        string name,
        string symbol,
        uint256 supply
    );

    error InvalidSalt();
    error Unauthorized();

    function deployTokenAndPool(
        string calldata name,
        string calldata symbol,
        bytes32 salt,
        uint256 aiAgentId
    ) external payable returns (address);

    function deployDataValid(
        uint256 aiAgentId,
        string calldata name,
        string calldata symbol,
        bytes32 salt
    ) external view returns (bool);

    function predictToken(
        uint256 aiAgentId,
        bytes32 salt,
        string calldata name,
        string calldata symbol
    ) external view returns (address);
}

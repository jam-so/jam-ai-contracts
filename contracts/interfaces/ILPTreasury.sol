// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.26;

interface ILPTreasury {
    event TokenLocked(uint256 tokenId, uint256 duration);
    event FeeCollected(
        uint256 tokenId,
        address indexed token0,
        address indexed token1,
        uint256 amount0,
        uint256 amount1
    );
    event TokenReleased(uint256 tokenId, address tokenRecipient);

    error RescueNotAllowed();
    error InvalidDuration();
    error TokenAlreadyLocked();
    error TokenReleaseProhibited();

    function lock(uint256 tokenId, uint256 duration) external;
}

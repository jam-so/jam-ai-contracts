// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.26;

interface ILPTreasury {
    event TokenLocked(uint256 tokenId, uint256 duration);
    event TokenReleased(uint256 tokenId, address tokenRecipient);
    event FeeCollected(
        uint256 tokenId,
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1
    );

    event TokenRescued(address token, uint256 tokenId, address receiver);
    event SetFeeTo(address feeTo);
    event SetTokenRecipient(address tokenRecipient);

    error RescueNotAllowed();
    error InvalidDuration();
    error TokenAlreadyLocked();
    error TokenReleaseProhibited();

    function lock(uint256 tokenId, uint256 duration) external;
}

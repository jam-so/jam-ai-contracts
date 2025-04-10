
// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.26;

import {ILPTreasury} from "./interfaces/ILPTreasury.sol";
import {Ownable2Step} from "./roles/Ownable2Step.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {INonfungiblePositionManager} from "./interfaces/IPancakeV3.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract LPTreasury is Ownable2Step, ERC721Holder, ILPTreasury {

    address public feeTo;
    address public tokenRecipient;

    // TokenId => Release Deadline
    mapping(uint256 => uint256) public tokenReleases;

    INonfungiblePositionManager public immutable positionManager;

    constructor(
        address feeTo_,
        address positionManager_,
        address tokenRecipient_
    ){
        require(feeTo_ != address(0), "FeeTo cannot be zero address");
        require(positionManager_ != address(0), "PositionManager cannot be zero address");
        require(tokenRecipient_ != address(0), "TokenRecipient cannot be zero address");

        feeTo = feeTo_;
        positionManager = INonfungiblePositionManager(positionManager_);
        tokenRecipient = tokenRecipient_;
    }

    function lock(uint256 tokenId, uint256 duration) external {
        if (duration== 0) revert InvalidDuration();

        address tokenOwner = positionManager.ownerOf(tokenId);
        if (tokenOwner == address(this)) revert TokenAlreadyLocked();

        positionManager.transferFrom(msg.sender, address(this), tokenId);
        tokenReleases[tokenId] = block.timestamp + duration;

        emit TokenLocked(tokenId, duration);
    }

    function claimFees(uint256 tokenId) external {
        _claimFees(tokenId);
    }

    function claimFeesBatch(uint256[] calldata tokenIds) external {
        uint256 len = tokenIds.length;
        for (uint256 i = 0; i < len; ) {
            _claimFees(tokenIds[i]);

            unchecked { ++i; }
        }
    }

    function claimFeesFromRange(
        uint256 batchSize, uint256 batchIndex
    ) external {
        uint256 st = batchSize * batchIndex;
        uint256 ed = batchSize * (batchIndex + 1);

        uint256 balance = positionManager.balanceOf(address(this));
        if (ed > balance) ed = balance;

        for (uint256 i = st; i < ed;) {
            uint256 tokenId = positionManager.tokenOfOwnerByIndex(address(this), i);
            _claimFees(tokenId);

            unchecked { ++i; }
        }
    }

    function _claimFees(uint256 tokenId) internal {
        (uint256 amount0, uint256 amount1) = positionManager.collect(
            INonfungiblePositionManager.CollectParams({
                recipient: feeTo,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max,
                tokenId: tokenId
            })
        );

        (,, address token0, address token1,,,,,,,,) = positionManager.positions(tokenId);

        if (amount0 > 0 || amount1 > 0) {
            emit FeeCollected(tokenId, token0, token1, amount0, amount1);
        }
    }

    function release(uint256 tokenId) external onlyOwner {
        if (tokenReleases[tokenId] > block.timestamp) revert TokenReleaseProhibited();

        positionManager.transferFrom(address(this), tokenRecipient, tokenId);

        emit TokenReleased(tokenId, tokenRecipient);
    }

    function rescueToken(IERC721 token, uint256 tokenId, address receiver) external onlyOwner {
        // Only other NFTs can be rescued.
        if (address(token) == address(positionManager) && tokenReleases[tokenId] > 0)
            revert RescueNotAllowed();

        token.transferFrom(address(this), receiver, tokenId);
        emit TokenRescued(address(token), tokenId, receiver);
    }

    function setFeeTo(address feeTo_) external onlyOwner {
        require(feeTo_ != address(0), "FeeTo cannot be zero address");
        feeTo = feeTo_;
        emit SetFeeTo(feeTo_);
    }

    function setTokenRecipient(address tokenRecipient_) external onlyOwner {
        require(tokenRecipient_ != address(0), "TokenRecipient cannot be zero address");
        tokenRecipient = tokenRecipient_;
        emit SetTokenRecipient(tokenRecipient_);
    }
}

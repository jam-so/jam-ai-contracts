// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.26;

import {Token} from "./Token.sol";
import {IJamAI} from "./interfaces/IJamAI.sol";
import {IJammer} from "./interfaces/IJammer.sol";
import {Ownable2Step} from "./access/Ownable2Step.sol";
import {TickMath} from "./libraries/TickMath.sol";
import {ILPTreasury} from "./interfaces/ILPTreasury.sol";
import {Bytes32AddressLib} from "./libraries/Bytes32AddressLib.sol";
import {
    IUniswapV3Factory,
    IUniswapV3Pool,
    IUniswapV3SwapRouter,
    INonfungiblePositionManager
} from "./interfaces/IUniswapV3.sol";

contract Jammer is Ownable2Step, IJammer {
    using TickMath for int24;
    using Bytes32AddressLib for bytes32;

    address public feeTo;
    uint64 public defaultLockingPeriod = 94608000;

    ILPTreasury public lpTreasury;

    address public immutable WETH;
    IUniswapV3Factory public immutable uniswapV3Factory;
    INonfungiblePositionManager public immutable positionManager;
    address public immutable swapRouter;

    bool public deprecated;

    event TokenCreated(
        address tokenAddress,
        uint256 lpTokenId,
        string name,
        string symbol,
        uint256 supply
    );

    error Deprecated();
    error InvalidTick();
    error InvalidSalt();

    constructor(
        address feeTo_,
        address lpTreasury_,
        address WETH_,
        address uniswapV3Factory_,
        address positionManager_,
        address swapRouter_
    ) {
        require(feeTo_ != address(0), "FeeTo cannot be zero address");
        require(lpTreasury_ != address(0), "LPTreasury cannot be zero address");
        require(WETH_ != address(0), "WETH cannot be zero address");
        require(uniswapV3Factory_ != address(0), "UniswapV3Factory cannot be zero address");
        require(positionManager_ != address(0), "PositionManager cannot be zero address");
        require(swapRouter_ != address(0), "SwapRouter cannot be zero address");

        feeTo = feeTo_;
        lpTreasury = ILPTreasury(lpTreasury_);
        WETH = WETH_;
        uniswapV3Factory = IUniswapV3Factory(uniswapV3Factory_);
        positionManager = INonfungiblePositionManager(positionManager_);
        swapRouter = swapRouter_;
    }

    function deployTokenAndPool(
        string calldata name, string calldata symbol, uint256 supply,
        bytes32 salt, uint256 aiAgentID,
        int24 initialTick, uint24 poolFee
    ) external payable onlyOwner returns (address) {
        if (deprecated) revert Deprecated();

        Token token = new Token{
            salt: keccak256(abi.encode(aiAgentID, salt))
        }(
            name, symbol, supply, IJamAI(msg.sender), aiAgentID
        );

        if (address(token) >= WETH) revert InvalidSalt();

        (address pool, uint256 lpTokenId) = _createPool(initialTick, token, poolFee, supply);

        emit TokenCreated(
            address(token),
            lpTokenId,
            name,
            symbol,
            supply
        );

        return pool;
    }

    function _createPool(
        int24 initialTick, Token token, uint24 poolFee, uint256 supply
    ) internal returns (address, uint256) {
        int24 tickSpacing = uniswapV3Factory.feeAmountTickSpacing(poolFee);
        if (tickSpacing == 0 || initialTick % tickSpacing != 0) revert InvalidTick();

        uint160 sqrtPriceX96 = initialTick.getSqrtRatioAtTick();
        address pool = uniswapV3Factory.createPool(address(token), WETH, poolFee);
        IUniswapV3Pool(pool).initialize(sqrtPriceX96);

        token.approve(address(positionManager), supply);

        (uint256 lpTokenId, , , ) = positionManager.mint(
            INonfungiblePositionManager.MintParams(
                address(token),
                WETH,
                poolFee,
                initialTick,
                maxUsableTick(tickSpacing),
                supply,
                0,
                0,
                0,
                address(this),
                block.timestamp
            )
        );

        positionManager.approve(address(lpTreasury), lpTokenId);
        lpTreasury.lock(lpTokenId, defaultLockingPeriod);

        IUniswapV3SwapRouter(swapRouter).exactInputSingle{value: msg.value}(
            IUniswapV3SwapRouter.ExactInputSingleParams({
                tokenIn: WETH,
                tokenOut: address(token),
                fee: poolFee,
                recipient: address(token),
                amountIn: msg.value,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        token.initialize();

        return (pool, lpTokenId);
    }

    function setFeeTo(address feeTo_) external onlyOwner {
        require(feeTo_ != address(0), "FeeTo cannot be zero address");
        feeTo = feeTo_;
    }

    function setDefaultLockingPeriod(uint64 defaultLockingPeriod_) external onlyOwner {
        defaultLockingPeriod = defaultLockingPeriod_;
    }

    function setLPTreasury(address lpTreasury_) external onlyOwner {
        require(lpTreasury_ != address(0), "LPTreasury cannot be zero address");
        lpTreasury = ILPTreasury(lpTreasury_);
    }

    function setDeprecated(bool deprecated_) external onlyOwner {
        deprecated = deprecated_;
    }

    function maxUsableTick(int24 tickSpacing) internal pure returns (int24) {
        unchecked {
            return (TickMath.MAX_TICK / tickSpacing) * tickSpacing;
        }
    }
}

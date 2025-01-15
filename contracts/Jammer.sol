// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.26;

import {AIAgentToken} from "./AIAgentToken.sol";
import {IJamAI} from "./interfaces/IJamAI.sol";
import {IJammer} from "./interfaces/IJammer.sol";
import {Ownable2Step} from "./roles/Ownable2Step.sol";
import {TickMath} from "./libraries/TickMath.sol";
import {ILPTreasury} from "./interfaces/ILPTreasury.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    IPancakeV3Factory,
    IPancakeV3Pool,
    IPancakeV3SwapRouter,
    INonfungiblePositionManager
} from "./interfaces/IPancakeV3.sol";

contract Jammer is Ownable2Step, IJammer {
    using TickMath for uint160;

    uint64 public defaultLockingPeriod = 31536000;

    IERC20 public immutable jam;
    IJamAI public jamAI;
    ILPTreasury public lpTreasury;

    IPancakeV3Factory public immutable pancakeV3Factory;
    INonfungiblePositionManager public immutable positionManager;
    IPancakeV3SwapRouter public immutable swapRouter;

    uint24 public immutable POOL_FEE = 10000;

    modifier onlyJamAI() {
        if (msg.sender != address(jamAI))
            revert Unauthorized();
        _;
    }

    constructor(
        address jamAI_,
        address lpTreasury_,
        address positionManager_,
        address swapRouter_
    ) {
        require(jamAI_ != address(0), "JamAI cannot be zero address");
        require(lpTreasury_ != address(0), "LPTreasury cannot be zero address");
        require(positionManager_ != address(0), "PositionManager cannot be zero address");
        require(swapRouter_ != address(0), "SwapRouter cannot be zero address");

        jamAI = IJamAI(jamAI_);
        lpTreasury = ILPTreasury(lpTreasury_);
        positionManager = INonfungiblePositionManager(positionManager_);
        swapRouter = IPancakeV3SwapRouter(swapRouter_);
        pancakeV3Factory = IPancakeV3Factory(swapRouter.factory());
        jam = IERC20(jamAI.jam());

        require(
            swapRouter.factory() == positionManager.factory(),
            "SwapRouter and PositionManager factory mismatch"
        );
    }

    function deployTokenAndPool(
        uint256 jamAmountIn,
        string calldata name,
        string calldata symbol,
        bytes32 salt,
        uint256 aiAgentId
    ) external onlyJamAI returns (address, address) {
        AIAgentToken token = _deployToken(name, symbol, salt, aiAgentId);

        (address pool, uint256 lpTokenId) = _createPool(token, jamAmountIn);

        emit TokenCreated(
            aiAgentId,
            address(token),
            lpTokenId,
            pool,
            name,
            symbol,
            token.totalSupply()
        );

        return (address(token), pool);
    }

    function _deployToken(
        string calldata name,
        string calldata symbol,
        bytes32 salt,
        uint256 aiAgentId
    ) internal returns (AIAgentToken token) {
        // Usually, the token will be deployed successfully in the first try
        // using the pre calculated salt.
        for (uint256 i = 0; i < 256;) {
            address tokenAddr = predictToken(aiAgentId, name, symbol, salt);

            if (tokenAddr < address(jam)) {
                address pool = pancakeV3Factory.getPool(tokenAddr, address(jam), POOL_FEE);
                if (pool == address(0)) {
                    token = new AIAgentToken{
                        salt: keccak256(abi.encode(aiAgentId, salt))
                    }(
                        name, symbol, jamAI, aiAgentId
                    );
                    return token;
                }
            }

            salt = keccak256(abi.encode(salt, gasleft()));

            unchecked { i++; }
        }

        revert InvalidSalt();
    }

    function _createPool(
        AIAgentToken token,
        uint256 jamAmountIn
    ) internal returns (address, uint256) {
        address pool = pancakeV3Factory.createPool(address(token), address(jam), POOL_FEE);

        uint256 tokenAmountIn = token.balanceOf(address(this));

        uint256 p = jamAmountIn * 10**18 / tokenAmountIn;
        uint160 sqrtPriceX96 = uint160(Math.sqrt(p) * 2**96 / 10**9);

        int24 initialTick = sqrtPriceX96.getTickAtSqrtRatio();
        int24 tickSpacing = pancakeV3Factory.feeAmountTickSpacing(POOL_FEE);
        initialTick = initialTick / tickSpacing * tickSpacing;

        IPancakeV3Pool(pool).initialize(sqrtPriceX96);

        token.approve(address(positionManager), tokenAmountIn);

        (uint256 lpTokenId, , , ) = positionManager.mint(
            INonfungiblePositionManager.MintParams(
                address(token),
                address(jam),
                POOL_FEE,
                initialTick,
                maxUsableTick(tickSpacing),
                tokenAmountIn,
                0,
                0,
                0,
                address(this),
                block.timestamp
            )
        );

        positionManager.approve(address(lpTreasury), lpTokenId);
        lpTreasury.lock(lpTokenId, defaultLockingPeriod);

        jam.approve(address(swapRouter), jamAmountIn);
        swapRouter.exactInputSingle(
            IPancakeV3SwapRouter.ExactInputSingleParams(
                address(jam),
                address(token),
                POOL_FEE,
                address(this),
                block.timestamp,
                jamAmountIn,
                0,
                0
            )
        );

        token.transfer(address(token), token.balanceOf(address(this)));
        token.initialize();

        return (pool, lpTokenId);
    }

    function deployDataValid(
        uint256 aiAgentID,
        string calldata name,
        string calldata symbol,
        bytes32 salt
    ) external view returns (bool) {
        if (
            aiAgentID == 0 ||
            bytes(name).length == 0 ||
            bytes(symbol).length == 0
        )
            return false;

        address tokenAddr = predictToken(aiAgentID, name, symbol, salt);

        return tokenAddr < address(jam);
    }

    function predictToken(
        uint256 aiAgentId,
        string calldata name,
        string calldata symbol,
        bytes32 salt
    ) public view returns (address) {
        bytes32 create2Salt = keccak256(abi.encode(aiAgentId, salt));

        bytes memory packed = abi.encodePacked(
            type(AIAgentToken).creationCode,
            abi.encode(name, symbol, address(jamAI), aiAgentId)
        );

        bytes32 data = keccak256(
            abi.encodePacked(
                bytes1(0xFF),
                address(this),
                create2Salt,
                keccak256(packed)
            )
        );

        return address(uint160(uint256(data)));
    }

    function setDefaultLockingPeriod(uint64 defaultLockingPeriod_) external onlyOwner {
        defaultLockingPeriod = defaultLockingPeriod_;
        emit SetDefaultLockingPeriod(defaultLockingPeriod_);
    }

    function setJamAI(address jamAI_) external onlyOwner {
        require(jamAI_ != address(0), "JamAI cannot be zero address");
        jamAI = IJamAI(jamAI_);
        emit SetJamAI(jamAI_);
    }

    function setLPTreasury(address lpTreasury_) external onlyOwner {
        require(lpTreasury_ != address(0), "LPTreasury cannot be zero address");
        lpTreasury = ILPTreasury(lpTreasury_);
        emit SetLPTreasury(lpTreasury_);
    }

    function maxUsableTick(int24 tickSpacing) internal pure returns (int24) {
        unchecked {
            return (TickMath.MAX_TICK / tickSpacing) * tickSpacing;
        }
    }
}

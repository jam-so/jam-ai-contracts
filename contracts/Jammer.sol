// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.26;

import {AIAgentToken} from "./AIAgentToken.sol";
import {IJamAI} from "./interfaces/IJamAI.sol";
import {IJammer} from "./interfaces/IJammer.sol";
import {Ownable2Step} from "./access/Ownable2Step.sol";
import {TickMath} from "./libraries/TickMath.sol";
import {ILPTreasury} from "./interfaces/ILPTreasury.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {
    IPancakeV3Factory,
    IPancakeV3Pool,
    IPancakeV3SwapRouter,
    INonfungiblePositionManager
} from "./interfaces/IPancakeV3.sol";

contract Jammer is Ownable2Step, IJammer {
    using TickMath for uint160;

    address public feeTo;
    uint64 public defaultLockingPeriod = 31536000;

    IJamAI public jamAI;
    ILPTreasury public lpTreasury;

    address public immutable WETH;
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
        address feeTo_,
        address jamAI_,
        address lpTreasury_,
        address WETH_,
        address pancakeV3Factory_,
        address positionManager_,
        address swapRouter_
    ) {
        require(feeTo_ != address(0), "FeeTo cannot be zero address");
        require(jamAI_ != address(0), "JamAI cannot be zero address");
        require(lpTreasury_ != address(0), "LPTreasury cannot be zero address");
        require(WETH_ != address(0), "WETH cannot be zero address");
        require(pancakeV3Factory_ != address(0), "PancakeV3Factory cannot be zero address");
        require(positionManager_ != address(0), "PositionManager cannot be zero address");
        require(swapRouter_ != address(0), "SwapRouter cannot be zero address");

        feeTo = feeTo_;
        jamAI = IJamAI(jamAI_);
        lpTreasury = ILPTreasury(lpTreasury_);
        WETH = WETH_;
        pancakeV3Factory = IPancakeV3Factory(pancakeV3Factory_);
        positionManager = INonfungiblePositionManager(positionManager_);
        swapRouter = IPancakeV3SwapRouter(swapRouter_);
    }

    function deployTokenAndPool(
        string calldata name,
        string calldata symbol,
        bytes32 salt,
        uint256 aiAgentId
    ) external payable onlyJamAI returns (address) {
        AIAgentToken token = new AIAgentToken{
            salt: keccak256(abi.encode(aiAgentId, salt))
        }(
            name, symbol, jamAI, aiAgentId
        );

        if (address(token) >= WETH) revert InvalidSalt();

        (address pool, uint256 lpTokenId) = _createPool(token);

        emit TokenCreated(
            address(token),
            lpTokenId,
            pool,
            name,
            symbol,
            token.totalSupply()
        );

        return pool;
    }

    function _createPool(AIAgentToken token) internal returns (address, uint256) {
        address pool = pancakeV3Factory.createPool(address(token), WETH, POOL_FEE);

        uint256 tokenAmountIn = token.balanceOf(address(this));
        uint256 ethAmountIn = msg.value;

        uint256 p = ethAmountIn * 10**18 / tokenAmountIn;
        uint160 sqrtPriceX96 = uint160(Math.sqrt(p) * 2**96 / 10**9);

        int24 initialTick = sqrtPriceX96.getTickAtSqrtRatio();
        int24 tickSpacing = pancakeV3Factory.feeAmountTickSpacing(POOL_FEE);
        initialTick = initialTick / tickSpacing * tickSpacing;

        IPancakeV3Pool(pool).initialize(sqrtPriceX96);

        token.approve(address(positionManager), tokenAmountIn);

        (uint256 lpTokenId, , , ) = positionManager.mint(
            INonfungiblePositionManager.MintParams(
                address(token),
                WETH,
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

        swapRouter.exactInputSingle{value: ethAmountIn}(
            IPancakeV3SwapRouter.ExactInputSingleParams(
                WETH,
                address(token),
                POOL_FEE,
                address(this),
                block.timestamp,
                ethAmountIn,
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

        return tokenAddr < WETH;
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

    function setFeeTo(address feeTo_) external onlyOwner {
        require(feeTo_ != address(0), "FeeTo cannot be zero address");
        feeTo = feeTo_;
    }

    function setDefaultLockingPeriod(uint64 defaultLockingPeriod_) external onlyOwner {
        defaultLockingPeriod = defaultLockingPeriod_;
    }

    function setJamAI(address jamAI_) external onlyOwner {
        require(jamAI_ != address(0), "JamAI cannot be zero address");
        jamAI = IJamAI(jamAI_);
    }

    function setLPTreasury(address lpTreasury_) external onlyOwner {
        require(lpTreasury_ != address(0), "LPTreasury cannot be zero address");
        lpTreasury = ILPTreasury(lpTreasury_);
    }

    function maxUsableTick(int24 tickSpacing) internal pure returns (int24) {
        unchecked {
            return (TickMath.MAX_TICK / tickSpacing) * tickSpacing;
        }
    }
}

// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.26;

import {Token} from "./Token.sol";
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
    using TickMath for int24;

    address public feeTo;
    uint64 public defaultLockingPeriod = 94608000;

    IJamAI public jamAI;
    ILPTreasury public lpTreasury;

    address public immutable WETH;
    IPancakeV3Factory public immutable pancakeV3Factory;
    INonfungiblePositionManager public immutable positionManager;

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
        address positionManager_
    ) {
        require(feeTo_ != address(0), "FeeTo cannot be zero address");
        require(jamAI_ != address(0), "JamAI cannot be zero address");
        require(lpTreasury_ != address(0), "LPTreasury cannot be zero address");
        require(WETH_ != address(0), "WETH cannot be zero address");
        require(pancakeV3Factory_ != address(0), "PancakeV3Factory cannot be zero address");
        require(positionManager_ != address(0), "PositionManager cannot be zero address");

        feeTo = feeTo_;
        jamAI = IJamAI(jamAI_);
        lpTreasury = ILPTreasury(lpTreasury_);
        WETH = WETH_;
        pancakeV3Factory = IPancakeV3Factory(pancakeV3Factory_);
        positionManager = INonfungiblePositionManager(positionManager_);
    }

    function deployTokenAndPool(
        string calldata name,
        string calldata symbol,
        bytes32 salt,
        uint256 aiAgentID
    ) external payable onlyJamAI returns (address) {
        Token token = new Token{
            salt: keccak256(abi.encode(aiAgentID, salt))
        }(
            name, symbol, jamAI, aiAgentID
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

    function _createPool(Token token) internal returns (address, uint256) {
        address pool = pancakeV3Factory.createPool(address(token), WETH, POOL_FEE);

        uint256 tokenAmountIn = token.totalSupply() / 2;
        uint256 ethAmountIn = msg.value;

        uint256 price = tokenAmountIn * 10**18 / ethAmountIn;
        uint160 sqrtPriceX96 = uint160(Math.sqrt(price)) * 2**96 / 10**9;

        IPancakeV3Pool(pool).initialize(sqrtPriceX96);

        token.approve(address(positionManager), tokenAmountIn);

        int24 tickSpacing = pancakeV3Factory.feeAmountTickSpacing(POOL_FEE);

        (uint256 lpTokenId, , , ) = positionManager.mint(
            INonfungiblePositionManager.MintParams(
                address(token),
                WETH,
                POOL_FEE,
                minUsableTick(tickSpacing),
                maxUsableTick(tickSpacing),
                tokenAmountIn,
                ethAmountIn,
                0,
                0,
                address(this),
                block.timestamp
            )
        );

        positionManager.approve(address(lpTreasury), lpTokenId);
        lpTreasury.lock(lpTokenId, defaultLockingPeriod);

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

        address tokenAddr = predictToken(
            aiAgentID, salt, name, symbol
        );

        return tokenAddr < WETH;
    }

     function predictToken(
        uint256 aiAgentId,
        bytes32 salt,
        string calldata name,
        string calldata symbol
    ) public view returns (address) {
        bytes32 create2Salt = keccak256(abi.encode(aiAgentId, salt));

        bytes memory packed = abi.encodePacked(
            type(Token).creationCode,
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

    function minUsableTick(int24 tickSpacing) internal pure returns (int24) {
        unchecked {
            return (TickMath.MIN_TICK / tickSpacing) * tickSpacing;
        }
    }

    function maxUsableTick(int24 tickSpacing) internal pure returns (int24) {
        unchecked {
            return (TickMath.MAX_TICK / tickSpacing) * tickSpacing;
        }
    }
}

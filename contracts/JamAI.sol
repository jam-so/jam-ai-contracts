// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.26;

import { IJamAI } from "./interfaces/IJamAI.sol";
import { IJammer } from "./interfaces/IJammer.sol";
import { Ownable2Step } from "./roles/Ownable2Step.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract JamAI is IJamAI, Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable jam;
    address public feeTo;
    IJammer public jammer;
    address public tradeApprover;
    uint256 public buyFeeRate = 0; // rate / 1000
    uint256 public sellFeeRate = 200; // rate / 1000
    uint256 public threshold = 60;

    // AI Agent ID => Trade Enabled
    mapping(uint256 => bool) public tradeEnabled;
    // AI Agent ID => Supply
    mapping(uint256 => uint256) public ticketsSupply;
    // AI Agent ID => (Holder => Balance)
    mapping(uint256 => mapping(address => uint256)) public ticketsBalance;
    // AI Agent ID => Pool Address
    mapping(uint256 => address) public pools;
    // AI Agent ID => Token Address
    mapping(uint256 => address) public tokens;
    // AI Agent ID => Token Info
    mapping(uint256 => TokenInfo) public preTokenInfo;

    bool public sellEnabled = false;

    constructor(
        address jam_,
        address feeTo_,
        address tradeApprover_
    ) {
        require(jam_ != address(0), "Jam cannot be zero address");
        require(feeTo_ != address(0), "FeeTo cannot be zero address");
        require(tradeApprover_ != address(0), "TradeApprover cannot be zero address");

        feeTo = feeTo_;
        tradeApprover = tradeApprover_;
        jam = IERC20(jam_);
    }

    function getPrice(uint256 supply, uint256 amount) public pure returns (uint256) {
        if (supply == 0) {
            if (amount == 1)
                return 0;
            amount -= 1;
        } else {
            supply -= 1;
        }

        uint256 sum1 = supply == 0 ? 0 : (supply - 1) * supply * (2 * (supply - 1) + 1) / 6;
        uint256 sum2 = supply == 0 && amount == 1 ? 0 : (supply + amount - 1) * (supply + amount) * (2 * (supply + amount - 1) + 1) / 6;
        uint256 summation = sum2 - sum1;

        return summation * 1 ether * 60 + amount * 1 ether * 20000;
    }

    function getBuyPrice(uint256 aiAgentId, uint256 amount) public view returns (uint256) {
        return getPrice(ticketsSupply[aiAgentId], amount);
    }

    function getSellPrice(uint256 aiAgentId, uint256 amount) public view returns (uint256) {
        return getPrice(ticketsSupply[aiAgentId] - amount, amount);
    }

    function getBuyPriceWithFee(uint256 aiAgentId, uint256 amount) external view returns (uint256) {
        uint256 price = getBuyPrice(aiAgentId, amount);
        uint256 protocolFee = price * buyFeeRate / 1000;
        return price + protocolFee;
    }

    function getSellPriceWithFee(uint256 aiAgentId, uint256 amount) external view returns (uint256) {
        uint256 price = getSellPrice(aiAgentId, amount);
        uint256 protocolFee = price * sellFeeRate / 1000;
        return price - protocolFee;
    }

    function startTrading(
        bytes calldata message,
        bytes calldata signature
    ) external {
        if (message.length == 0) revert InvalidMessage();
        if (signature.length != 65) revert InvalidSignature();

        bytes32 digest = keccak256(message);
        address recoveredSigner = ECDSA.recover(digest, signature);
        if (recoveredSigner != tradeApprover) revert InvalidSignature();

        uint256 chainId;
        address contractAddress;
        uint256 aiAgentId;
        string memory name;
        string memory symbol;
        bytes32 salt;
        address creator;
        uint256 amount;
        (chainId, contractAddress, aiAgentId, name, symbol, salt, creator, amount) = abi.decode(
            message, (uint256, address, uint256, string, string, bytes32, address, uint256)
        );

        // Re-encode the decoded variables to check if the message is valid.
        bytes memory message2 = abi.encode(chainId, contractAddress, aiAgentId, name, symbol, salt, creator, amount);
        if (keccak256(message2) != digest) revert InvalidMessage();

        if (chainId != block.chainid) revert InvalidMessage();
        if (contractAddress != address(this)) revert InvalidMessage();
        if (tradeEnabled[aiAgentId]) revert TradeAlreadyEnabled();

        if (!jammer.deployDataValid(aiAgentId, name, symbol, salt)) revert InvalidTokenInfo();

        if (creator == address(0) || amount == 0) revert InvalidMessage();

        preTokenInfo[aiAgentId].name = name;
        preTokenInfo[aiAgentId].symbol = symbol;
        preTokenInfo[aiAgentId].salt = salt;

        tradeEnabled[aiAgentId] = true;
        _buyTickets(creator, aiAgentId, 1);
        _buyTickets(msg.sender, aiAgentId, amount);
    }

    function buyTickets(uint256 aiAgentId, uint256 amount) external {
        _buyTickets(msg.sender, aiAgentId, amount);
    }

    function _buyTickets(address buyer, uint256 aiAgentId, uint256 amount) internal {
        if (!tradeEnabled[aiAgentId]) revert TradeNotEnabled();
        if (pools[aiAgentId] != address(0)) revert PoolLaunched();

        uint256 supply = ticketsSupply[aiAgentId];
        uint256 price = getPrice(supply, amount);
        uint256 protocolFee = price * buyFeeRate / 1000;

        if (price > 0) {
            uint256 balanceBefore = jam.balanceOf(address(this));
            jam.safeTransferFrom(buyer, address(this), price + protocolFee);
            uint256 balanceAfter = jam.balanceOf(address(this));
            if (balanceAfter - balanceBefore != price + protocolFee) revert InsufficientPayment();
        }

        ticketsBalance[aiAgentId][buyer] = ticketsBalance[aiAgentId][buyer] + amount;
        ticketsSupply[aiAgentId] = supply + amount;

        emit Trade(buyer, aiAgentId, true, amount, price, protocolFee, supply + amount);

        if (protocolFee > 0) {
            jam.safeTransfer(feeTo, protocolFee);
        }
    }

    function sellTickets(uint256 aiAgentId, uint256 amount) external nonReentrant {
        if (!tradeEnabled[aiAgentId]) revert TradeNotEnabled();
        if (pools[aiAgentId] != address(0)) revert PoolLaunched();

        if (!sellEnabled) revert SellNotEnabled();

        uint256 supply = ticketsSupply[aiAgentId];
        if(amount == 0 || ticketsBalance[aiAgentId][msg.sender] < amount) revert InsufficientTicketsToSell();
        if (amount >= supply) revert LastTicketNotSellable();

        ticketsBalance[aiAgentId][msg.sender] = ticketsBalance[aiAgentId][msg.sender] - amount;
        ticketsSupply[aiAgentId] = supply - amount;

        uint256 price = getPrice(supply - amount, amount);
        uint256 protocolFee = price * sellFeeRate / 1000;

        emit Trade(msg.sender, aiAgentId, false, amount, price, protocolFee, supply - amount);

        jam.safeTransfer(msg.sender, price - protocolFee);

        if (protocolFee > 0) {
            jam.safeTransfer(feeTo, protocolFee);
        }
    }

    function activatePool(uint256 aiAgentId) external {
        if (pools[aiAgentId] != address(0)) revert PoolAlreadyCreated();
        if (ticketsSupply[aiAgentId] < threshold) revert InsufficientTicketsForPool();

        uint256 jamAmountIn = getPrice(0, ticketsSupply[aiAgentId]);

        TokenInfo memory tokenInfo = preTokenInfo[aiAgentId];

        jam.transfer(address(jammer), jamAmountIn);
        (address token, address pool) = jammer.deployTokenAndPool(
            jamAmountIn,
            tokenInfo.name,
            tokenInfo.symbol,
            tokenInfo.salt,
            aiAgentId
        );

        tokens[aiAgentId] = token;
        pools[aiAgentId] = pool;
    }

    function setFeeTo(address feeTo_) external onlyOwner {
        require(feeTo_ != address(0), "FeeTo cannot be zero address");

        feeTo = feeTo_;
        emit SetFeeTo(feeTo_);
    }

    function setJammer(address jammer_) external onlyOwner {
        require(jammer_ != address(0), "Jammer cannot be zero address");

        jammer = IJammer(jammer_);
        emit SetJammer(jammer_);
    }

    function setTradeApprover(address newApprover) external onlyOwner {
        require(newApprover != address(0), "TradeApprover cannot be zero address");

        tradeApprover = newApprover;
        emit SetTradeApprover(newApprover);
    }

    function setBuyFeeRate(uint256 feeRate) external onlyOwner {
        require(feeRate <= 1000, "Invalid fee rate");

        buyFeeRate = feeRate;
        emit SetBuyFeeRate(feeRate);
    }

    function setSellFeeRate(uint256 feeRate) external onlyOwner {
        require(feeRate <= 1000, "Invalid fee rate");

        sellFeeRate = feeRate;
        emit SetSellFeeRate(feeRate);
    }

    function setThreshold(uint256 newThreshold) external onlyOwner {
        require(newThreshold > 0, "Invalid threshold");

        threshold = newThreshold;
        emit SetThreshold(newThreshold);
    }

    function setSellEnabled(bool enabled) external onlyOwner {
        sellEnabled = enabled;
        emit SetSellEnabled(enabled);
    }

    function updateTokenInfo(
        uint256 aiAgentId,
        string calldata newName,
        string calldata newSymbol,
        bytes32 newSalt
    ) external onlyOwner {
        if (pools[aiAgentId] != address(0))
            revert PoolLaunched();

        if (!jammer.deployDataValid(aiAgentId, newName, newSymbol, newSalt))
            revert InvalidTokenInfo();

        preTokenInfo[aiAgentId].name = newName;
        preTokenInfo[aiAgentId].symbol = newSymbol;
        preTokenInfo[aiAgentId].salt = newSalt;

        emit UpdateTokenInfo(aiAgentId, newName, newSymbol, newSalt);
    }
}

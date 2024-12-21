// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.26;

import { IJamAI } from "./interfaces/IJamAI.sol";
import { IJammer } from "./interfaces/IJammer.sol";
import { Ownable2Step } from "./access/Ownable2Step.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract JamAI is IJamAI, Ownable2Step {

    address public feeTo;
    IJammer public jammer;
    address public tradeActivator;
    uint256 public protocolBuyFeeRate = 0; // rate / 1000
    uint256 public protocolSellFeeRate = 200; // rate / 1000
    uint256 public sharesThreshold = 60;

    // AI Agent ID => Trade Enabled
    mapping(uint256 => bool) public tradeEnabled;
    // AI Agent ID => Supply
    mapping(uint256 => uint256) public sharesSupply;
    // AI Agent ID => (Holder => Balance)
    mapping(uint256 => mapping(address => uint256)) public sharesBalance;
    // AI Agent ID => Pool Address
    mapping(uint256 => address) public createdPools;
    // AI Agent ID => Token Info
    mapping(uint256 => TokenInfo) public agentTokenInfo;

    event Trade(
        address trader,
        uint256 aiAgentID,
        bool isBuy,
        uint256 shareAmount,
        uint256 ethAmount,
        uint256 protocolFeeAmount,
        uint256 supply
    );

    struct TokenInfo {
        string name;
        string symbol;
        uint256 supply;
        bytes32 salt;
        int24 initialTick;
        uint24 poolFee;
    }

    error TradeNotEnabled();
    error PoolLaunched();
    error InvalidMessage();
    error InvalidSignature();
    error TradeAlreadyEnabled();
    error InsufficientPayment();
    error TransferFailed();
    error InsufficientSharesToSell();
    error PoolAlreadyCreated();
    error InsufficientSharesForPool();
    error InvalidTokenInfo();

    constructor(
        address feeTo_,
        address jammer_,
        address tradeActivator_
    ) {
        require(feeTo_ != address(0), "FeeTo cannot be zero address");
        require(jammer_ != address(0), "Jammer cannot be zero address");
        require(tradeActivator_ != address(0), "TradeActivator cannot be zero address");

        feeTo = feeTo_;
        jammer = IJammer(jammer_);
        tradeActivator = tradeActivator_;
    }

    function getPrice(uint256 supply, uint256 amount) public pure returns (uint256) {
        uint256 sum1 = supply == 0 ? 0 : (supply - 1 )* (supply) * (2 * (supply - 1) + 1) / 6;
        uint256 sum2 = supply == 0 && amount == 1 ? 0 : (supply - 1 + amount) * (supply + amount) * (2 * (supply - 1 + amount) + 1) / 6;
        uint256 summation = sum2 - sum1;
        return summation * 1 ether / 16000;
    }

    function getBuyPrice(uint256 aiAgentID, uint256 amount) public view returns (uint256) {
        return getPrice(sharesSupply[aiAgentID], amount);
    }

    function getSellPrice(uint256 aiAgentID, uint256 amount) public view returns (uint256) {
        return getPrice(sharesSupply[aiAgentID] - amount, amount);
    }

    function getBuyPriceWithFee(uint256 aiAgentID, uint256 amount) external view returns (uint256) {
        uint256 price = getBuyPrice(aiAgentID, amount);
        uint256 protocolFee = price * protocolBuyFeeRate / 1000;
        return price + protocolFee;
    }

    function getSellPriceWithFee(uint256 aiAgentID, uint256 amount) external view returns (uint256) {
        uint256 price = getSellPrice(aiAgentID, amount);
        uint256 protocolFee = price * protocolSellFeeRate / 1000;
        return price - protocolFee;
    }

    function enableTrade(
        bytes calldata message,
        bytes calldata signature
    ) external payable {
        if (message.length == 0) revert InvalidMessage();
        if (signature.length != 65) revert InvalidSignature();

        bytes32 digest = keccak256(message);
        address recoveredSigner = ECDSA.recover(digest, signature);
        if (recoveredSigner != tradeActivator) revert InvalidSignature();

        uint256 chainId;
        address contractAddress;
        uint256 aiAgentID;
        string memory name;
        string memory symbol;
        uint256 supply;
        (chainId, contractAddress, aiAgentID, name, symbol, supply) = abi.decode(
            message, (uint256, address, uint256, string, string, uint256)
        );

        if (chainId != block.chainid) revert InvalidMessage();
        if (contractAddress != address(this)) revert InvalidMessage();
        if (tradeEnabled[aiAgentID]) revert TradeAlreadyEnabled();
        if (bytes(name).length == 0 || bytes(symbol).length == 0 || supply == 0)
            revert InvalidTokenInfo();

        agentTokenInfo[aiAgentID].name = name;
        agentTokenInfo[aiAgentID].symbol = symbol;
        agentTokenInfo[aiAgentID].supply = supply;

        tradeEnabled[aiAgentID] = true;
        buyShares(aiAgentID, 1);
    }

    function buyShares(uint256 aiAgentID, uint256 amount) public payable {
        if (!tradeEnabled[aiAgentID]) revert TradeNotEnabled();
        if (createdPools[aiAgentID] != address(0)) revert PoolLaunched();

        uint256 supply = sharesSupply[aiAgentID];
        uint256 price = getPrice(supply, amount);
        uint256 protocolFee = price * protocolBuyFeeRate / 1000;
        if (msg.value < price + protocolFee) revert InsufficientPayment();

        sharesBalance[aiAgentID][msg.sender] = sharesBalance[aiAgentID][msg.sender] + amount;
        sharesSupply[aiAgentID] = supply + amount;

        emit Trade(msg.sender, aiAgentID, true, amount, price, protocolFee, supply + amount);

        if (sharesSupply[aiAgentID] >= sharesThreshold) {
            _activatePool(aiAgentID);
        }

        (bool success, ) = feeTo.call{value: protocolFee}("");
        if(!success) revert TransferFailed();
    }

    function sellShares(uint256 aiAgentID, uint256 amount) public payable {
        if (!tradeEnabled[aiAgentID]) revert TradeNotEnabled();
        if (createdPools[aiAgentID] != address(0)) revert PoolLaunched();

        uint256 supply = sharesSupply[aiAgentID];
        if(sharesBalance[aiAgentID][msg.sender] < amount) revert InsufficientSharesToSell();

        sharesBalance[aiAgentID][msg.sender] = sharesBalance[aiAgentID][msg.sender] - amount;
        sharesSupply[aiAgentID] = supply - amount;

        uint256 price = getPrice(supply - amount, amount);
        uint256 protocolFee = price * protocolSellFeeRate / 1000;

        emit Trade(msg.sender, aiAgentID, false, amount, price, protocolFee, supply - amount);

        (bool success1, ) = msg.sender.call{value: price - protocolFee}("");
        (bool success2, ) = feeTo.call{value: protocolFee}("");
        if(!success1 || !success2) revert TransferFailed();
    }

    function _activatePool(uint256 aiAgentID) internal {
        if (createdPools[aiAgentID] != address(0)) revert PoolAlreadyCreated();
        if (sharesSupply[aiAgentID] < sharesThreshold) revert InsufficientSharesForPool();

        uint256 ethAmountIn = getPrice(0, sharesSupply[aiAgentID]);

        TokenInfo memory tokenInfo = agentTokenInfo[aiAgentID];

        address pool = jammer.deployTokenAndPool{value: ethAmountIn}(
            tokenInfo.name, tokenInfo.symbol, tokenInfo.supply,
            tokenInfo.salt, aiAgentID,
            tokenInfo.initialTick, tokenInfo.poolFee
        );

        createdPools[aiAgentID] = pool;
    }

    function setFeeTo(address feeTo_) external onlyOwner {
        require(feeTo_ != address(0), "FeeTo cannot be zero address");

        feeTo = feeTo_;
    }

    function setTradeActivator(address tradeActivator_) external onlyOwner {
        require(tradeActivator_ != address(0), "TradeActivator cannot be zero address");

        tradeActivator = tradeActivator_;
    }

    function setJammer(address jammer_) external onlyOwner {
        require(jammer_ != address(0), "Jammer cannot be zero address");
        jammer = IJammer(jammer_);
    }

    function setProtocolBuyFeeRate(uint256 feeRate) external onlyOwner {
        require(feeRate <= 1000, "Invalid protocol fee rate");

        protocolBuyFeeRate = feeRate;
    }

    function setProtocolSellFeeRate(uint256 feeRate) external onlyOwner {
        require(feeRate <= 1000, "Invalid protocol fee rate");

        protocolSellFeeRate = feeRate;
    }

    function setSharesThreshold(uint256 sharesThreshold_) external onlyOwner {
        require(sharesThreshold_ > 0, "Invalid shares threshold");
        sharesThreshold = sharesThreshold_;
    }
}

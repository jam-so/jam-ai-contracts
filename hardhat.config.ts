import "@nomicfoundation/hardhat-toolbox";
import { HardhatUserConfig } from "hardhat/config";
import { existsSync, readFileSync } from 'fs';
import { vars } from "hardhat/config";

const privKeyFile = '.private_key'
let privateKey = '';

if (existsSync(privKeyFile)) {
  privateKey = readFileSync(privKeyFile, "utf-8");
  privateKey = privateKey.replace(/\s/g, "");
}

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.26",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },

  networks: {
    "localhost": {
      chainId: 31337,
    },
    "BNBChain": {
      url: vars.get("BNBCHAIN_RPC_URL"),
      chainId: 56,
      gasPrice: 1e9,
    },
    "BNBChainTestnet": {
      url: vars.get("BNBCHAIN_TESTNET_RPC_URL"),
      chainId: 97,
    },
  },

  etherscan: {
    apiKey: {
      bsc: vars.get("BNBCHAIN_API_KEY"),
    },
  },
};

export default config;

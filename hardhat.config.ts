import "@nomicfoundation/hardhat-toolbox";
// import "@nomiclabs/hardhat-ethers";
import { HardhatUserConfig } from "hardhat/config";
import { existsSync, readFileSync } from 'fs';
import { chain, chainID } from "./constants";
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
        version: "0.4.18",
      },
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

  typechain: {
    outDir: "typechain-types",
    target: "ethers-v6",
  },

  networks: {
    [chain.BNBChain]: {
      url: vars.get("BNBChain_RPC_URL"),
    },
  },

  etherscan: {
    apiKey: {
      bsc: vars.get("BNBChain_API_KEY"),
    },
    customChains: [
    ]
  },
};


for (var net in config.networks) {
  if (net == 'hardhat') continue;

  config.networks[net]!.chainId = chainID[net as keyof typeof chainID];

  if (privateKey != '') {
    config.networks[net]!.accounts = [privateKey]
  }
}

export default config;

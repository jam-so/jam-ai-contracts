import { loadBaseUtils } from "./common";
import hre from "hardhat";
import { existsSync } from 'fs';
import { isDefinedNetwork } from '../constants';

async function main() {
    const customLogic = 'readPrivKey.ts';
    if (isDefinedNetwork(hre.network.name) && existsSync(customLogic)) {
        let privateKey = require("../" + customLogic).privateKey;
        hre.network.config.accounts = [privateKey]
    }

    await loadBaseUtils();
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});

import * as hre from "hardhat";
import { existsSync } from 'fs';
import type { REPLServer } from "repl";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { AddressLike } from "ethers";
import { BigNumber } from "bignumber.js";

declare var global: any;
let repl: REPLServer;

let me: HardhatEthersSigner;

async function main() {
    const customLogic = 'importPrivateKey.ts';
    if (existsSync(customLogic)) {
        let privateKey = require("../" + customLogic).privateKey;
        hre.network.config.accounts = [privateKey]
    }

    await setVariables();

    let remoteChainID = (await hre.ethers.provider.getNetwork()).chainId;

    let localChainID = hre.network.config.chainId;
    if (localChainID === undefined || remoteChainID !== BigInt(localChainID)) {
        console.log(`local chainID ${localChainID} != remote chainID ${remoteChainID}`);
        process.exit();
    }

    console.log(`chain: ${hre.network.name}, chainID: ${remoteChainID}`);

    const { addr, balance } = await getNativeTokenBalance();
    console.log(`deployer: ${addr}, native token balance: ${balance}`);

    repl = require("repl").start();
    global = repl.context;
}

async function setVariables() {
    me = (await hre.ethers.getSigners())[0];
    global.me = me;
    global.ONE = BigInt(1e18);

    (global as any)['balance'] = async (addr_?: AddressLike) => {
        let { addr, balance } = await getNativeTokenBalance(addr_);
        console.log(`${addr} native token balance: ${balance}`);
    }

    for (let i = 0; i <= 18; i++) {
        (global as any)[`e${i}`] = (val: any) => {
            let readable = (new BigNumber(val.toString())).shiftedBy(-i).toFixed();
            console.log(readable);
        }
    }
}

async function getNativeTokenBalance(addr?: AddressLike) {
    addr = addr ?? me.address;
    let rawBalance = await hre.ethers.provider.getBalance(addr);
    let readable = (new BigNumber(rawBalance.toString())).shiftedBy(-18).toFixed();

    return {
        addr: addr,
        balance: readable
    };
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
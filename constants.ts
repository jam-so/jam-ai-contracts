export enum chainID {
    // MainNets
    BNBChain = 56,

    // TestNets
    BNBChainTestnet = 97,
}

export enum chain {
    // MainNets
    BNBChain = "BNBChain",

    // TestNets
    BNBChainTestnet = 'BNBChainTestnet',
}
const mainnets = new Set<string>([
    chain.BNBChain,
]);

export function isDefinedNetwork(net: string) {
    return (<any>Object).values(chain).includes(net);
}

export function isMainnet(net: string) {
    return mainnets.has(net);
}

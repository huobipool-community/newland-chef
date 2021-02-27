let Web3 = require('web3');
let web3 = new Web3("https://http-mainnet.hecochain.com");
let mdxChefAddress = '0xFB03e11D93632D97a8981158A632Dd5986F5E909'

async function run() {
    let mdxChef = new web3.eth.Contract(require('../source/abis/mdxChef-abi'), mdxChefAddress)

    let poolLen = await mdxChef.methods['poolLength']().call()
    for(let i = 0; i<poolLen; i++) {
        try {
            let info = await mdxChef.methods['poolInfo'](i).call();
            let mdxPair = new web3.eth.Contract(require('../source/abis/mdxPair-abi'), info.lpToken)

            let token0 = await mdxPair.methods['token0']().call();
            let token1 = await mdxPair.methods['token1']().call();

            let symbol0 = await erc20Query(token0, 'symbol');
            let symbol1 = await erc20Query(token1, 'symbol');

            console.log(`
------ ${i} ${info.lpToken}
${symbol0} ${token0}
${symbol1} ${token1}
        `)
        }catch (e) {}
    }
}

run().catch(e => {
    console.log(e)
})

async function erc20Query(address, method, ...args) {
    try {
        const contract = new web3.eth.Contract(require('../source/abis/erc20-abi'), address);
        return await contract.methods[method](...args).call()
    } catch (e) {
        console.error(e)
        return null;
    }
}
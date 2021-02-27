const Chef = artifacts.require("MasterChef")
const HPTContract = artifacts.require("IERC20")
const USDTContract = artifacts.require("IERC20")
const LP = artifacts.require("IERC20");

const _hptAddress = '0xe499ef4616993730ced0f31fa2703b92b50bb536';
const _usdtAddress = '0xa71EdC38d189767582C38A3145b5873052c3e47a';
const _WHT = '0x5545153ccfca01fbd7dd11c0b23ba694d9509a6f';
const _usdthpt = '0xdE5b574925EE475c41b99a7591EC43E92dCD2fc1';

async function main(){
    const chef = await Chef.at("0x9C5Dd70D98e9B321217e8232235e25E64E78C595");
    let accounts = await web3.eth.getAccounts();
    const hpt = await HPTContract.at(_hptAddress);
    const usdt = await USDTContract.at(_usdtAddress);
    const lp = await LP.at(_usdthpt);


    let ethBalance = await web3.eth.getBalance(accounts[0]) / 1e18;
    console.log('ethBalance:',ethBalance);
    let hptBalance = await hpt.balanceOf(accounts[0]) / 1e18;
    console.log('hptBalance:',hptBalance);
    let usdtBalance = await usdt.balanceOf(accounts[0]) / 1e18;
    console.log('usdtBalance:',usdtBalance);


    await chef.add("10", lp.address, 17, true);
    console.log("start");
    let result = await chef.depositETH("10000000000000000",0, "0xa71EdC38d189767582C38A3145b5873052c3e47a",
          "169050000000000000",
          1,1);
    console.log(JSON.stringify(result));


}

main()
.then(()=>{process.exit()})
.catch((err)=>{
    console.error(err);
    process.exit(1);
});
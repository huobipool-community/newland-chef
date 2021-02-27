const Chef = artifacts.require("MasterChef")
const HPTContract = artifacts.require("IERC20")
const USDTContract = artifacts.require("IERC20")
const LP = artifacts.require("IERC20");

const _mdxFactory = '0xb0b670fc1f7724119963018db0bfa86adb22d941';
const _WHT = '0x5545153ccfca01fbd7dd11c0b23ba694d9509a6f';
const _mdxChef = '0xFB03e11D93632D97a8981158A632Dd5986F5E909';
const _hptAddress = '0xe499ef4616993730ced0f31fa2703b92b50bb536';
const _usdtAddress = '0xa71EdC38d189767582C38A3145b5873052c3e47a';
const _mdx = '0x25d2e80cb6b86881fd7e07dd263fb79f4abe033c';


const _usdthpt = '0xdE5b574925EE475c41b99a7591EC43E92dCD2fc1';

const privateKey = '0x505c97822e0605740d39ab5bb37b1a9f3c9e68dd2f49bdc1ff21b72fbd845987';
const myWalletAddress = '0x124a9013652a6FDB8c7be1C5201850F448aA4Bbf';

web3.eth.accounts.wallet.add(privateKey);

function toH(num){
    return web3.utils.toHex(num);
}

async function main(){
    
    const chef = await Chef.new(_hptAddress, "100000", "0", "1",
                _mdxFactory,
                _WHT,
                _mdxChef,
                1,
                _mdx
            );
    console.log("Contract Chef is deployed at:", chef.address);

    let accounts = await web3.eth.getAccounts();

    const hpt = await HPTContract.at(_hptAddress);
    const usdt = await USDTContract.at(_usdtAddress);

    let ethBalance = await web3.eth.getBalance(accounts[0]) / 1e18;
    console.log('ethBalance:',ethBalance);
    let hptBalance = await hpt.balanceOf(accounts[0]) / 1e18;
    console.log('hptBalance:',hptBalance);
    let usdtBalance = await usdt.balanceOf(accounts[0]) / 1e18;
    console.log('usdtBalance:',usdtBalance);
    
    //approve
    await hpt.approve(chef.address,toH('10000000000000000000000'));
    await usdt.approve(chef.address,toH('10000000000000000000000'));
    console.log('approved');

    let transferResult = await hpt.transfer(
      chef.address,
      toH('100000000000000000'), { from: myWalletAddress } 
    );

    transferResult = await usdt.transfer(
        accounts[0],
        toH('100000000000000000'), { from: myWalletAddress } 
      );


    console.log('tranferred 100 hpt to Chef.');
    hptBalance = await hpt.balanceOf(accounts[0]) / 1e18;
    console.log('hptBalance left:',hptBalance);
}

main()
.then(()=>{process.exit()})
.catch((err)=>{
    console.error(err);
    process.exit(1);
});
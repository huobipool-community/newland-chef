const Chef = artifacts.require("MasterChef");
const HPTContract = artifacts.require("IERC20");

const hptAddress = '0xe499ef4616993730ced0f31fa2703b92b50bb536';
// const daiAbi = require('../source/abis/dai-abi.json');
// const daiContract = new web3.eth.Contract(daiAbi,daiAddress);
function toH(num){
    return web3.utils.toHex(num);
}

async function main(){
    
    const chef = await Chef.new(hptAddress,"1000000000000000000000", "0", "1000000000000000000000");
    console.log("Contract Chef is deployed at:", chef.address);

    let accounts = await web3.eth.getAccounts();
    const hpt = await HPTContract.at(hptAddress);

    let ethBalance = await web3.eth.getBalance(accounts[0]) / 1e18;
    console.log('ethBalance:',ethBalance);
    let hptBalance = await hpt.balanceOf(accounts[0]) / 1e18;
    console.log('hptBalance:',hptBalance);

    //approve
    await hpt.approve(chef.address,toH('10000000000000000000000'));
    console.log('approved');

    let transferResult = await hpt.transfer(
      chef.address,
      toH('10000000000000000000000')  
    );
    console.log('tranferred 10000 hpt to Chef.');
    hptBalance = await hpt.balanceOf(accounts[0]) / 1e18;
    console.log('hptBalance left:',hptBalance);
}

main()
.then(()=>{process.exit()})
.catch((err)=>{
    console.error(err);
    process.exit(1);
});
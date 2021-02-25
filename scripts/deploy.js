const Chef = artifacts.require("MasterChef");
const DaiContract = artifacts.require("IERC20");

const daiAddress = '0x6b175474e89094c44da98b954eedeac495271d0f';
// const daiAbi = require('../source/abis/dai-abi.json');
// const daiContract = new web3.eth.Contract(daiAbi,daiAddress);
function toH(num){
    return web3.utils.toHex(num);
}

async function main(){

    const chef = await Chef.new(daiAddress,"1000000000000000000000", "0", "1000000000000000000000");
    console.log("Contract Chef is deployed at:", chef.address);
    // if(chef.deployed){
    //     console.log("Contract Chef is deployed at:", chef.address);
    // }

    let accounts = await web3.eth.getAccounts();
    const dai = await DaiContract.at(daiAddress);

    let ethBalance = await web3.eth.getBalance(accounts[0]) / 1e18;
    console.log('ethBalance:',ethBalance);
    let daiBalance = await dai.balanceOf(accounts[0]) / 1e18;
    console.log('daiBalance:',daiBalance);

    //approve
    await dai.approve(chef.address,toH('10000000000000000000000'));
    console.log('approved');

    let transferResult = await dai.transfer(
      chef.address,
      toH('10000000000000000000000')  
    );
    console.log('tranferred dai to Chef.');
    daiBalance = await dai.balanceOf(accounts[0]) / 1e18;
    console.log('daiBalance left:',daiBalance);
}

main()
.then(()=>{process.exit()})
.catch((err)=>{
    console.error(err);
    process.exit(1);
});
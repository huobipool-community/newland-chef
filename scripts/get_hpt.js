// First run Ganache locally with `daiMcdJoin` address unlocked
/*

ganache-cli \
  -f https://mainnet.infura.io/v3/$infuraApiKey \
  -m "clutch captain shoe salt awake harvest setup primary inmate ugly among become" \
  -i 1 \
  -u 0x9759A6Ac90977b93B58547b4A71c78317f391A28

*/


const HPTContract = artifacts.require('IERC20');

// Address of DAI contract https://etherscan.io/address/0x6b175474e89094c44da98b954eedeac495271d0f
const hptMainNetAddress = '0xe499ef4616993730ced0f31fa2703b92b50bb536';

// Address of Join (has auth) https://changelog.makerdao.com/ -> releases -> contract addresses -> MCD_JOIN_DAI
const other = '0x124a9013652a6FDB8c7be1C5201850F448aA4Bbf';

function toH(num){
  return web3.utils.toHex(num);
}

async function main(){
  let hpt;
  let accounts = await web3.eth.getAccounts();

  hpt = await HPTContract.at(hptMainNetAddress);
  // 1000 HPT

  console.log(accounts[0]);
  await hpt.transfer(accounts[0], toH('1000000000000000000000'),{ from: other });

  console.log('HPT mint success:');
  console.log((await hpt.balanceOf(accounts[0])/1e18).toString());
}

main()
.then(()=>{process.exit()})
.catch((err)=>{
    console.error(err);
    process.exit(1);
});




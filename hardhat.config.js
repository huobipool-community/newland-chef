require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-truffle5");

require("./scripts/_runUtil.js");

let $keys = []
if (['run', 'compile', 'flatten'].indexOf(process.argv[2]) === -1) {
  let {importKey} = require('./scripts/_keyManager')
  let ownerAddress = '0x276bb442d11b0edb5191bb28b81b6374b187bcc2';
  $keys = [
    importKey(ownerAddress)
  ].filter(i => i)
}
let hardhatAccounts
if ($keys.length > 0) {
  hardhatAccounts = [{
    privateKey: $keys[0],
    balance: '1000000000000000000000'
  }]
}
let gasPrice = 2.3 * 1000000000

module.exports = {
  solidity: {
    version: "0.6.12",
    settings: {
      optimizer: {
        enabled: true,
      }
    }
  },
  networks: {
    hardhat: {
      chainId: 666,
      forking: {
        url: "http://172.18.7.1:8545"
      },
      accounts: hardhatAccounts,
      blockGasLimit: 900000000000000,
      gasPrice,
      allowUnlimitedContractSize: true
    },
    heco: {
      url: "https://http-mainnet-node.huobichain.com",
      accounts: $keys,
      gasPrice,
      allowUnlimitedContractSize: true
    },
    hecoTest: {
      url: "https://http-testnet.hecochain.com",
      accounts: $keys,
      gasPrice,
      allowUnlimitedContractSize: true
    }
  },
  mocha: {
    timeout: 2000000,
  }
};


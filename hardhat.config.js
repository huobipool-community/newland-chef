require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-truffle5");

module.exports = {
  solidity: "0.6.12",

  networks: {
    hardhat: {
      forking: {
        url: "https://http-mainnet.hecochain.com",
      },
      accounts: {
        mnemonic:"clutch captain shoe salt awake harvest setup primary inmate ugly among become"
      }
    }
  }
};


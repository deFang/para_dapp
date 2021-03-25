const NaiveOracle = artifacts.require("NaiveOracle");
const ChainlinkETHPriceOracleProxy = artifacts.require("ChainlinkETHPriceOracleProxy");
const USDT = artifacts.require("ERC20");
const LpToken = artifacts.require("LpToken");
const BigNumber = require("bignumber.js");

function decimalStr(value) {
  return new BigNumber(value).multipliedBy(10 ** 18).toFixed(0, BigNumber.ROUND_DOWN)
}



module.exports = async (deployer, network) => {
    const addresses = await web3.eth.getAccounts();
    await deployer.deploy(NaiveOracle);
    await deployer.deploy(ChainlinkETHPriceOracleProxy);
    await deployer.deploy(USDT, "USDT", "USDT").then(
        (usdt) => {
            var i;
            for (i=0; i<addresses.length; i++ ) {
                usdt.mint(addresses[i], decimalStr("100")); // send 100USDT to test accounts
                }
            }
        );
    // const usdt = await ERC20.deployed();
    // usdt.mint(addresses[0], 1e18);
    // deployer.deploy(LpToken, "FANG");
};

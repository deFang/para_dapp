const fs = require("fs");
const file = fs.createWriteStream("./deploy-logger.txt", { 'flags': 'a' });
let logger = new console.Console(file, file);

function decimalStr(value) {
  return new BigNumber(value).multipliedBy(10 ** 18).toFixed(0, BigNumber.ROUND_DOWN)
}
const BigNumber = require("bignumber.js");
const NaiveOracle = artifacts.require("NaiveOracle");
const ChainlinkETHPriceOracleProxy = artifacts.require("ChainlinkETHPriceOracleProxy");
const TestUSDT = artifacts.require("ERC20");
const ParaPlace = artifacts.require("ParaPlace");
const Para = artifacts.require("Para");
const Admin = artifacts.require("Admin");
const Pricing = artifacts.require("Pricing");
const CloneFactory = artifacts.require("CloneFactory");

module.exports = async (deployer, network, accounts) => {
    const addresses = await web3.eth.getAccounts();
    const owner = accounts[0];
    const supervisor = accounts[0];
    const maintainer = accounts[0];
    const tokenName = "FANG";
    const lpFeeRate = "3000000000000000";
    const mtFeeRate = 0;
    const k = "100000000000000000";
    const gasPriceLimit = 4000000;
    await deployer.deploy(NaiveOracle);
    await deployer.deploy(ChainlinkETHPriceOracleProxy);
    await deployer.deploy(TestUSDT, "TestUSDT", "TestUSDT").then(
        (usdt) => {
            var i;
            for (i=0; i<addresses.length; i++ ) {
                usdt.mint(addresses[i], decimalStr("100")); // send 100USDT to test accounts
                }
            }
        );
    const TestUSDTAddress = TestUSDT.address;
    logger.log("TestUSDTAddress", TestUSDTAddress);
    await deployer.deploy(Admin);
    await deployer.deploy(Pricing);
    await deployer.deploy(Para);
    await deployer.deploy(ParaPlace,
        Para.address, Admin.address, Pricing.address, CloneFactory.address, supervisor
    )
    const ParaPlaceAddress = ParaPlace.address;
    logger.log("ParaPlaceAddress: ", ParaPlaceAddress);
    const ParaPlaceInstance = await ParaPlace.at(ParaPlaceAddress);
    var tx = await ParaPlaceInstance.breedPara(
        maintainer,
        TestUSDT.address,
        NaiveOracle.address,
        tokenName,
        lpFeeRate,
        mtFeeRate,
        k,
        gasPriceLimit
        );
    logger.log("ParaPlace breedPara tx: ", tx.tx);
    // logger.log('para', para);


    const ParaAddress = await ParaPlaceInstance.getPara(NaiveOracle.address);
    const ParaInstance = await Para.at(ParaAddress);
    logger.log("ParaAddress: ", ParaAddress);

    const AdminAddress = await ParaInstance.ADMIN();
    const AdminInstance = await Admin.at(AdminAddress);
    logger.log("AdminAddress: ", AdminAddress);

    const PricingAddress = await ParaInstance.PRICING();
    const PricingInstance = await Pricing.at(PricingAddress);
    logger.log("PricingAddress: ", PricingAddress);

    const LpTokenAddress = await ParaInstance._COLLATERAL_POOL_TOKEN_();
    logger.log('LpTokenAddress', LpTokenAddress);

    await AdminInstance.enableDeposit();
    logger.log('Admin Owner', await AdminInstance._OWNER_());

};

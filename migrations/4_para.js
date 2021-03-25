const Para = artifacts.require("Para");
const Admin = artifacts.require("Admin");
const ERC20 = artifacts.require("ERC20");
const NaiveOracle = artifacts.require("NaiveOracle");

module.exports = async (deployer, network, accounts) => {
    const naiveOracle = await NaiveOracle.deployed();
    const owner = accounts[0];
    const supervisor = accounts[0];
    const maintainer = accounts[0];
    const USDT = await ERC20.deployed();
    const tokenName = "FANG";
    const lpFeeRate = "3000000000000000";
    const mtFeeRate = 0;
    const k = "100000000000000000";
    const gasPriceLimit = 4000000;

    const admin = await deployer.deploy(Admin)
    await admin.init(
        owner,
        supervisor,
        maintainer,
        USDT.address,
        naiveOracle.address,
        lpFeeRate,
        mtFeeRate,
        k,
        gasPriceLimit
    )

    const para = await deployer.deploy(Para);
    // await para.init(admin.address, tokenName);
};

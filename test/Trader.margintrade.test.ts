/*

    Copyright 2020 Para ZOO.
    SPDX-License-Identifier: Apache-2.0

*/

// import * as assert from 'assert';

import { ParaContext, getParaContext } from './utils/Context';
import { decimalStr } from './utils/Converter';
// import { logGas } from './utils/Log';

let lp1: string;
let lp2: string;
let trader1: string;
let trader2: string;
let tempAccount: string;

async function init(ctx: ParaContext): Promise<void> {
  await ctx.setOraclePrice(decimalStr("100"));
  tempAccount = ctx.spareAccounts[5];
  lp1 = ctx.spareAccounts[0];
  lp2 = ctx.spareAccounts[1];
  trader1 = ctx.spareAccounts[2];
  trader2 = ctx.spareAccounts[3];
  await ctx.mintTestToken(lp1, decimalStr("100000"));
  await ctx.mintTestToken(lp2, decimalStr("100000"));
  await ctx.mintTestToken(trader1, decimalStr("1000"));
  await ctx.mintTestToken(trader2, decimalStr("1000"));
  await ctx.mintTestToken(tempAccount, decimalStr("1000"));
  await ctx.approvePara(lp1);
  await ctx.approvePara(lp2);
  await ctx.approvePara(trader1);
  await ctx.approvePara(trader2);

  await ctx.Admin.methods
      .enableDeposit()
      .send(ctx.sendParam(ctx.Deployer));
  await ctx.Admin.methods
      .enableTrading()
      .send(ctx.sendParam(ctx.Deployer));
  await ctx.Para.methods
      .collateralTraderTransferIn(lp1, decimalStr("100000"))
      .send(ctx.sendParam(lp1));
  await ctx.Para.methods
      .collateralTraderTransferIn(trader1, decimalStr("1000"))
      .send(ctx.sendParam(trader1));
  await ctx.Para.methods
      .collateralTraderTransferIn(trader2, decimalStr("1000"))
      .send(ctx.sendParam(trader2));
   await ctx.Admin.methods.setInitialMarginRate(decimalStr("0.2")).send(ctx.sendParam(ctx.Deployer));
   await ctx.Admin.methods.setMaintenanceMarginRate(decimalStr("0.1")).send(ctx.sendParam(ctx.Deployer));
}

describe("Trader", () => {
  let snapshotId: string;
  let ctx: ParaContext;

  before(async () => {
    ctx = await getParaContext();
    await init(ctx);
  });

  beforeEach(async () => {
    snapshotId = await ctx.EVM.snapshot();
  });

  afterEach(async () => {
    await ctx.EVM.reset(snapshotId);
  });

  describe("Trader", () => {
      // it("sell large amount base token when balanced", async () => {
      //     await ctx.Para.methods.depositCollateral(decimalStr("100000")).send(ctx.sendParam(lp1));
      //     await assert.rejects(
      //         ctx.Para.methods.sellBaseToken(decimalStr("100"), decimalStr("10")).send(ctx.sendParam(trader1)), /NOT_SAFE_TO_OPEN/
      //     )
      //     await assert.rejects(
      //         ctx.Para.methods.buyBaseToken(decimalStr("100"), decimalStr("1000000")).send(ctx.sendParam(trader1)), /NOT_SAFE_TO_OPEN/
      //     )
      //     let [side, size, entry_value, cash_balance] = await ctx.Para.methods._MARGIN_ACCOUNT_(trader1).call();
      //     console.log(side, size/10**18, entry_value/10**18, cash_balance/10**18);
      // });

      it("liquidate position when price change", async () => {
          // lp deposit 1000usd to pool
          await ctx.Admin.methods.setLiquidationPenaltyRate(decimalStr("0.01")).send(ctx.sendParam(ctx.Deployer));
          await ctx.Admin.methods.setLiquidationPenaltyPoolRate(decimalStr("0.005")).send(ctx.sendParam(ctx.Deployer))
          await ctx.Para.methods.depositCollateral(decimalStr("100000")).send(ctx.sendParam(lp1));
          // trader1 first to buy 10 base token
          await ctx.Para.methods.buyBaseToken(decimalStr("30"), decimalStr("1000000")).send(ctx.sendParam(trader1)), /NOT_SAFE_TO_OPEN/
          // check trader1 account
          let [side, size, entry_value, cash_balance] = await ctx.Para.methods._MARGIN_ACCOUNT_(trader1).call();
          console.log(side, size/10**18, entry_value/10**18, cash_balance/10**18);
          console.log(await ctx.Para.methods.balanceMargin(await ctx.Para.methods._MARGIN_ACCOUNT_(trader1).call()).call()/10**18)
          await ctx.setOraclePrice(decimalStr("70"));
          console.log(await ctx.Para.methods.balanceMargin(await ctx.Para.methods._MARGIN_ACCOUNT_(trader1).call()).call()/10**18)

          await ctx.Para.methods.liquidate(trader2, trader1).send(ctx.sendParam(trader2));
          [side, size, entry_value, cash_balance] = await ctx.Para.methods._MARGIN_ACCOUNT_(trader1).call();
          console.log('trader1', side, size/10**18, entry_value/10**18, cash_balance/10**18);

          [side, size, entry_value, cash_balance] = await ctx.Para.methods._MARGIN_ACCOUNT_(trader2).call();
          console.log('trader2', side, size/10**18, entry_value/10**18, cash_balance/10**18);

          await ctx.Para.methods.sellBaseToken(decimalStr("30"), decimalStr("100")).send(ctx.sendParam(trader2));
          [side, size, entry_value, cash_balance] = await ctx.Para.methods._MARGIN_ACCOUNT_(trader2).call();
          console.log('trader2 after close', side, size/10**18, entry_value/10**18, cash_balance/10**18);

          [side, size, entry_value, cash_balance] = await ctx.Para.methods._POOL_MARGIN_ACCOUNT_().call();
          console.log('POOL', side, size/10**18, entry_value/10**18, cash_balance/10**18);


      })


  })
})

/*

    Copyright 2020 Para ZOO.
    SPDX-License-Identifier: Apache-2.0

*/

// import * as assert from 'assert';

import { ParaContext, getParaContext } from './utils/Context';
import {decimalStr} from './utils/Converter';
import assert from "assert";
// import { logGas } from './utils/Log';

let lp1: string;
let lp2: string;
let trader1: string;
let trader2: string;
let trader3: string;
let tempAccount: string;
// let poolAccount: string;

async function init(ctx: ParaContext): Promise<void> {
  await ctx.setOraclePrice(decimalStr("100"));
  tempAccount = ctx.spareAccounts[5];
  lp1 = ctx.spareAccounts[0];
  lp2 = ctx.spareAccounts[1];
  trader1 = ctx.spareAccounts[2];
  trader2 = ctx.spareAccounts[3];
  trader3 = ctx.spareAccounts[4];
  // poolAccount = ctx.Para.options.address;
  await ctx.mintTestToken(lp1, decimalStr("100000"));
  await ctx.mintTestToken(lp2, decimalStr("100000"));
  await ctx.mintTestToken(trader1, decimalStr("1000"));
  await ctx.mintTestToken(trader2, decimalStr("1000"));
  await ctx.mintTestToken(trader3, decimalStr("1000"));
  await ctx.mintTestToken(tempAccount, decimalStr("1000"));
  await ctx.approvePara(lp1);
  await ctx.approvePara(lp2);
  await ctx.approvePara(trader1);
  await ctx.approvePara(trader2);
  await ctx.approvePara(trader3);

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
      // it("reject when amount large than maximum", async () => {
      //    await ctx.Para.methods.depositCollateral(decimalStr("100000")).send(ctx.sendParam(lp1));
      //    await assert.rejects(
      //       ctx.Para.methods.buyBaseToken(decimalStr("100"), decimalStr("1000000")).send(ctx.sendParam(trader1)), /NOT_SAFE_TO_OPEN/
      //     )
      //     await assert.rejects(
      //       ctx.Para.methods.sellBaseToken(decimalStr("100"), decimalStr("100")).send(ctx.sendParam(trader1)), /NOT_SAFE_TO_OPEN/
      //     )
      //
      // });

      it("liquidate position when price change", async () => {
          // set penalty rate
          await ctx.Admin.methods.setLiquidationPenaltyRate(decimalStr("0.01")).send(ctx.sendParam(ctx.Deployer));
          await ctx.Admin.methods.setLiquidationPenaltyPoolRate(decimalStr("0.005")).send(ctx.sendParam(ctx.Deployer))
          await ctx.Para.methods.depositCollateral(decimalStr("100000")).send(ctx.sendParam(lp1));
          // a. trader1 first to buy 30 base token, will be liquidated by trader2 when price fall
          await ctx.Para.methods.buyBaseToken(decimalStr("30"), decimalStr("1000000")).send(ctx.sendParam(trader1))
          await ctx.setOraclePrice(decimalStr("70"));
          assert.equal(
              await ctx.Para.methods.isSafeMaintain(trader1).call(),
              false
            );
          await ctx.Para.methods.liquidate(trader2, trader1).send(ctx.sendParam(trader2));
          let [side, size, entry_value, cash_balance, entry_sloss] = await ctx.Para.methods._MARGIN_ACCOUNT_(trader1).call();
          assert.deepEqual(
              [side, size, entry_value, cash_balance, entry_sloss],
              [0,0,0,"63618044538529896861",0]
          );
          [side, size, entry_value, cash_balance, entry_sloss] = await ctx.Para.methods._MARGIN_ACCOUNT_(trader2).call();
          assert.deepEqual(
              [side, size, entry_value, cash_balance, entry_sloss],
              [2, decimalStr("30"),"2104463345232481029300","1021044633452324810293", 0]
          )
          await assert.equal(
              await ctx.Para.methods._POOL_INSURANCE_BALANCE_().call(),
              "10522316726162405146",
          );

          // b. trader2 close long position, open short position, then liquidated by trader3 when price rise
          [side, size, entry_value, cash_balance, entry_sloss] = await ctx.Para.methods._MARGIN_ACCOUNT_(trader2).call();
          console.log('before trader2', side, size/10**18, entry_value/10**18, cash_balance/10**18);
          await ctx.Para.methods.sellBaseToken(decimalStr("20"), decimalStr("100")).send(ctx.sendParam(trader2));
          [side, size, entry_value, cash_balance, entry_sloss] = await ctx.Para.methods._MARGIN_ACCOUNT_(trader2).call();
          console.log('after trader2', side, size/10**18, entry_value/10**18, cash_balance/10**18);
          await ctx.Para.methods.sellBaseToken(decimalStr("10"), decimalStr("100")).send(ctx.sendParam(trader2));
          [side, size, entry_value, cash_balance, entry_sloss] = await ctx.Para.methods._MARGIN_ACCOUNT_(trader2).call();
          console.log('trader2', side, size/10**18, entry_value/10**18, cash_balance/10**18);
          //
          // await ctx.Para.methods.sellBaseToken(decimalStr("30"), decimalStr("100")).send(ctx.sendParam(trader2));
          // [side, size, entry_value, cash_balance] = await ctx.Para.methods._MARGIN_ACCOUNT_(trader2).call();
          // console.log('trader2 after close', side, size/10**18, entry_value/10**18, cash_balance/10**18);
          //
          // [side, size, entry_value, cash_balance] = await ctx.Para.methods._MARGIN_ACCOUNT_(poolAccount).call();
          // console.log('POOL', side, size/10**18, entry_value/10**18, cash_balance/10**18);


      })


  })
})

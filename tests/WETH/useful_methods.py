import brownie
import requests

def genericStateOfStrat(strategy, currency, vault):
    decimals = currency.decimals()
    print(f"\n----state of {strategy.name()}----")

    print("Want:", currency.balanceOf(strategy)/  (1 ** decimals))
    print("Total assets estimate:", strategy.estimatedTotalAssets()/  (10 ** decimals))
    strState = vault.strategies(strategy)
    totalDebt = strState[5]/  (10 ** decimals)
    debtLimit = strState[2]/  (10 ** decimals)
    esassets =strategy.estimatedTotalAssets()+1

    totalReturns = strState[6]/  (10 ** decimals)
    print(f"Total Strategy Debt: {totalDebt:.5f}")
    print(f"Strategy Debt Limit: {debtLimit:.5f}")
    print(f"Total Strategy Returns: {totalReturns:.5f}")
    blocksPerYear = 2628333
    ironapr = strategy.ironBankBorrowRate(0, True)*blocksPerYear/1e18

    apr= strategy.currentSupplyRate()*blocksPerYear/1e18
    irondebt = strategy.ironBankOutstandingDebtStored()
    leverage = (irondebt*(apr-ironapr) + esassets*apr)/esassets

    print('Iron Bank Debt:', irondebt/  (10 ** decimals))  
    print('Basic APR:', {:.2%}.format(apr))
    print('Iron APR:',ironapr)
    print('Full APR:',leverage)
    print("Harvest Trigger:", strategy.harvestTrigger(1000000 * 30 * 1e9))
    print(
        "Tend Trigger:", strategy.tendTrigger(1000000 * 30 * 1e9)
    )  # 1m gas at 30 gwei
    print("Emergency Exit:", strategy.emergencyExit())


def genericStateOfVault(vault, currency):
    decimals = currency.decimals()
    print(f"\n----state of {vault.name()} vault----")
    balance = vault.totalAssets()/  (10 ** decimals)
    print(f"Total Assets: {balance:.5f}")
    balance = vault.totalDebt()/  (10 ** decimals)
    print("Loose balance in vault:", currency.balanceOf(vault)/  (10 ** decimals))
    print(f"Total Debt: {balance:.5f}")

from itertools import count
from brownie import Wei, reverts
from useful_methods import  genericStateOfVault,genericStateOfStrat
import random
import brownie

def test_limit_0(smallrunningstrategy, ironbank,AlphaHomo, ironWeth,Strategy, creamdev,gov, web3,  chain, vault,currency, whale, strategist):
    
    strategy = smallrunningstrategy

   # ironbank._setCreditLimit(strategy, 1_000_000 *1e18, {'from': creamdev})

    #now deposit 
    #deposit = 1000 *1e18
    #dai.approve(vault, 2 ** 256 - 1, {'from': whale})
    #dai.approve(ibdai, 2 ** 256 - 1, {'from': whale})

    #make sure iron bank has enough funds
    #ibdai.mint(deposit*10, {'from': whale})

    #vault.deposit(deposit, {'from': whale})
    #strategy.harvest({'from': strategist})
    #assert strategy.ironBankOutstandingDebtStored() == 0
    #strategy.harvest({'from': strategist})
    assert strategy.ironBankOutstandingDebtStored() > 0
    ironbank._setCreditLimit(strategy2, 0, {'from': creamdev})

    strategy.harvest({'from': strategist})

    strategy2 = strategist.deploy(Strategy,vault, ironWeth)
    alphaHomoPlugin = strategist.deploy(AlphaHomo, strategy2, "Alpha Homo")
    strategy2.addLender(alphaHomoPlugin, {"from": gov})

    ironbank._setCreditLimit(strategy2, 1_000_000 *1e18, {'from': creamdev})
    vault.migrateStrategy(strategy, strategy2, {'from': gov})
    assert strategy.ironBankOutstandingDebtStored() < 10
    genericStateOfStrat(strategy, currency, vault)
    strategy2.harvest({'from': strategist})
    assert strategy2.ironBankOutstandingDebtStored() == 0
    #
    #genericStateOfVault(vault, dai)
   # stateOfStrat(strategy2, dai, comp)

    print(strategy2.tendTrigger(2000000 * 30 * 1e9))
    print(strategy2.tendTrigger(1000000 * 30 * 1e9))
    print(strategy2.internalCreditOfficer())

    strategy2.tend({'from': strategist})
    
    assert strategy2.ironBankOutstandingDebtStored() > 0
    genericStateOfStrat(strategy2, currency, vault)


def test_migrate(smallrunningstrategy, ironbank,AlphaHomo, ironWeth,Strategy, creamdev,gov, web3,  chain, vault,currency, whale, strategist):
    
    strategy = smallrunningstrategy

   # ironbank._setCreditLimit(strategy, 1_000_000 *1e18, {'from': creamdev})

    #now deposit 
    #deposit = 1000 *1e18
    #dai.approve(vault, 2 ** 256 - 1, {'from': whale})
    #dai.approve(ibdai, 2 ** 256 - 1, {'from': whale})

    #make sure iron bank has enough funds
    #ibdai.mint(deposit*10, {'from': whale})

    #vault.deposit(deposit, {'from': whale})
    #strategy.harvest({'from': strategist})
    #assert strategy.ironBankOutstandingDebtStored() == 0
    #strategy.harvest({'from': strategist})
    assert strategy.ironBankOutstandingDebtStored() > 0

    

    strategy2 = strategist.deploy(Strategy,vault, ironWeth)
    alphaHomoPlugin = strategist.deploy(AlphaHomo, strategy2, "Alpha Homo")
    strategy2.addLender(alphaHomoPlugin, {"from": gov})

    ironbank._setCreditLimit(strategy2, 1_000_000 *1e18, {'from': creamdev})
    vault.migrateStrategy(strategy, strategy2, {'from': gov})
    assert strategy.ironBankOutstandingDebtStored() < 10
    genericStateOfStrat(strategy, currency, vault)
    strategy2.harvest({'from': strategist})
    assert strategy2.ironBankOutstandingDebtStored() == 0
    #
    #genericStateOfVault(vault, dai)
   # stateOfStrat(strategy2, dai, comp)

    print(strategy2.tendTrigger(2000000 * 30 * 1e9))
    print(strategy2.tendTrigger(1000000 * 30 * 1e9))
    print(strategy2.internalCreditOfficer())

    strategy2.tend({'from': strategist})
    
    assert strategy2.ironBankOutstandingDebtStored() > 0
    genericStateOfStrat(strategy2, currency, vault)
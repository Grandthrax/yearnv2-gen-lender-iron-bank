import pytest
from brownie import Wei, config


@pytest.fixture
def live_strat_usdc_1(Strategy):
    yield Strategy.at('0xB7e9Bf9De45E1df822E97cA7E0C3D1B62798a4e0')

@pytest.fixture
def live_vault_usdc(pm):
    Vault = pm(config["dependencies"][0]).Vault
    yield Vault.at('0xD6b53d0f3d4e55fbAaADc140C0B0488293a433f8')


@pytest.fixture
def live_GenericCompound_usdc_1(GenericCompound):
    yield GenericCompound.at('0x33D4c129586562adfd993ebb54E830481F31ef37')

@pytest.fixture
def live_GenericCream_usdc_1(GenericCream):
    yield GenericCream.at('0x1bAaCef951d24c5d70a8cA88D89cE16B37472fB3')

@pytest.fixture
def live_GenericDyDx_usdc_1(GenericDyDx):
    yield GenericDyDx.at('0x6C842746F21Ca34542EDC6895dFfc8D4e7D2bC1c')



@pytest.fixture
def live_strat_weth_1(Strategy):
    yield Strategy.at('0x520a45E22B1eB5D7bDe09A445e70708d2957B365')

@pytest.fixture
def live_strat_weth_2(Strategy):
    yield Strategy.at('0x460612682cE6ED51C1A9813F6938671D9D135d6D')

@pytest.fixture
def live_vault_weth_2(pm):
    Vault = pm(config["dependencies"][0]).Vault
    yield Vault.at('0x6392e8fa0588CB2DCb7aF557FdC9D10FDe48A325')

@pytest.fixture
def live_vault_weth(pm):
    Vault = pm(config["dependencies"][0]).Vault
    yield Vault.at('0x18c447b7Ad755379B8800F1Ef5165E8542946Afd')

@pytest.fixture
def live_Alpha_Homo_2(AlphaHomo):
    yield AlphaHomo.at('0x74bE25172F8aFFF92CA6e27418d601D74ACC2525')

@pytest.fixture
def live_Alpha_Homo(AlphaHomo):
    yield AlphaHomo.at('0xd0aC55591F3BFE3F30D0f3A662084d0e28673c47')

@pytest.fixture
def live_EthCompound(EthCompound):
    yield EthCompound.at('0xA8F6263e27d1c9952320A3C0DCBB7ac0eEA99F8D')

@pytest.fixture
def live_dydxweth(GenericDyDx):
    yield GenericDyDx.at('0x1F2699B3aaf3F04b61B99B776b4a21a08502AE73')



@pytest.fixture
def live_guest_list(pm):
    TestGuestList = pm(config["dependencies"][0]).TestGuestList
    yield TestGuestList.at('0x1403EEa5fFF87253658D755030a73dFBCA2993Ab')


#change these fixtures for generic tests
@pytest.fixture
def currency(dai, usdc, weth):
    yield weth

@pytest.fixture(autouse=True)
def carlos(fn_isolation):
    pass
    

@pytest.fixture
def whale(accounts, web3, weth):
    #big binance7 wallet
    #acc = accounts.at('0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8', force=True)
    #big binance8 wallet
    acc = accounts.at('0xf977814e90da44bfa03b6295a0616a897441acec', force=True)

    #lots of weth account
    wethAcc = accounts.at('0x1840c62fD7e2396e470377e6B2a833F3A1E96221', force=True)
    weth.approve(acc, 2 ** 256 - 1, {"from": wethAcc} )
    weth.transfer(acc, weth.balanceOf(wethAcc),{"from": wethAcc} )

    assert  weth.balanceOf(acc) > 0
    yield acc

@pytest.fixture()
def strategist(accounts, whale, currency):
    decimals = currency.decimals()
    currency.transfer(accounts[1], 100 * (10 ** decimals), {'from': whale})
    yield accounts[1]

@pytest.fixture
def samdev(accounts):
    yield accounts.at('0xC3D6880fD95E06C816cB030fAc45b3ffe3651Cb0', force=True)

@pytest.fixture
def devychad(accounts):
    yield accounts.at('0x846e211e8ba920b353fb717631c015cf04061cc9', force=True)

    
@pytest.fixture
def gov(accounts):
    yield accounts[3]

@pytest.fixture
def ychad(accounts):
    yield accounts.at('0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52', force=True)

@pytest.fixture
def rewards(gov):
    yield gov  # TODO: Add rewards contract
@pytest.fixture
def guardian(accounts):
    # YFI Whale, probably
    yield accounts[2]

@pytest.fixture
def keeper(accounts):
    # This is our trusty bot!
    yield accounts[4]

@pytest.fixture
def rando(accounts):
    yield accounts[9]

#specific addresses
@pytest.fixture
def usdc(interface):
    yield interface.ERC20('0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48')

@pytest.fixture
def dai(interface):
    yield interface.ERC20('0x6b175474e89094c44da98b954eedeac495271d0f')

@pytest.fixture
def weth(interface):
    yield interface.IWETH('0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2')


@pytest.fixture
def cdai(interface):
    yield interface.CErc20I('0x5d3a536e4d6dbd6114cc1ead35777bab948e3643')

@pytest.fixture
def cUsdc(interface):
    yield interface.CErc20I('0x39AA39c021dfbaE8faC545936693aC917d5E7563')

@pytest.fixture
def crUsdc(interface):
    yield interface.CErc20I('0x44fbeBd2F576670a6C33f6Fc0B00aA8c5753b322')

@pytest.fixture
def ironWeth(interface):
    yield interface.CErc20I('0x41c84c0e2EE0b740Cf0d31F63f3B6F627DC6b393')

@pytest.fixture
def ironbank(interface):
    yield interface.IronBankControllerI('0xAB1c342C7bf5Ec5F02ADEA1c2270670bCa144CbB')
@pytest.fixture
def creamdev(accounts):
    yield accounts.at('0x6D5a7597896A703Fe8c85775B23395a48f971305', force=True)


#@pytest.fixture(autouse=True)
#def isolation(fn_isolation):
#    pass
@pytest.fixture(scope="module", autouse=True)
def shared_setup(module_isolation):
    pass

@pytest.fixture
def vault(gov, rewards, guardian, currency, pm):
    Vault = pm(config["dependencies"][0]).Vault
    vault = gov.deploy(Vault)
    vault.initialize(currency, gov, rewards, "", "", guardian)
    vault.setDepositLimit(2 ** 256 - 1, {"from": gov})
    yield vault

@pytest.fixture
def Vault(pm):
    yield pm(config["dependencies"][0]).Vault

@pytest.fixture
def strategy(strategist, keeper, vault,crUsdc,cUsdc, ironWeth, gov, Strategy,EthCream, AlphaHomo,EthCompound, GenericDyDx):
    strategy = strategist.deploy(Strategy, vault, ironWeth)
    strategy.setKeeper(keeper)

    ethCreamPlugin = strategist.deploy(EthCream, strategy, "Cream")
    strategy.addLender(ethCreamPlugin, {"from": gov})

    alphaHomoPlugin = strategist.deploy(AlphaHomo, strategy, "Alpha Homo")
    strategy.addLender(alphaHomoPlugin, {"from": gov})

    compoundPlugin = strategist.deploy(EthCompound, strategy, "Compound")
    strategy.addLender(compoundPlugin, {"from": gov})

    dydxPlugin = strategist.deploy(GenericDyDx, strategy, "DyDx")
    strategy.addLender(dydxPlugin, {"from": gov})

    assert strategy.numLenders() == 4
    yield strategy

@pytest.fixture()
def smallrunningstrategy(gov, strategy,ironbank, currency,creamdev, ironWeth, vault, whale):
    rate_limit = 1_000_000_000 *1e18
    
    debt_ratio = 10_000 #100%
    vault.addStrategy(strategy, debt_ratio, rate_limit, 1000, {"from": gov})
    
    ironbank._setCreditLimit(strategy, 1_000_000 *1e18, {'from': creamdev})

    currency.approve(vault, 2 ** 256 - 1, {"from": whale} )

    amount = Wei('100 ether')
    dai.approve(vault, amount, {'from': whale})
    vault.deposit(amount, {'from': whale})    

    strategy.harvest({'from': gov})
    
    #do it again with a smaller amount to replicate being this full for a while
    amount = Wei('10 ether')
    dai.approve(vault, amount, {'from': whale})
    vault.deposit(amount, {'from': whale})   
    strategy.harvest({'from': gov})
    
    yield strategy
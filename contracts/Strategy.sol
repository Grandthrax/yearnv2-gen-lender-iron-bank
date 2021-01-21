// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./GenericLender/IGenericLender.sol";
import "./WantToEthOracle/IWantToEth.sol";

import "@yearnvaults/contracts/BaseStrategy.sol";

import "./Interfaces/Compound/CErc20I.sol";
import "./Interfaces/Compound/ComptrollerI.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

interface IUni{
    function getAmountsOut(
        uint256 amountIn, 
        address[] calldata path
    ) external view returns (uint256[] memory amounts);
}

/********************
 *
 *   A lender optimisation strategy for any erc20 asset
 *   Using iron bank to leverage up
 *   https://github.com/Grandthrax/yearnV2-generic-lender-strat
 *   v0.3.0
 *
 *   This strategy works by taking plugins designed for standard lending platforms
 *   It automatically chooses the best yield generating platform and adjusts accordingly
 *   The adjustment is sub optimal so there is an additional option to manually set position
 *
 ********************* */

contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public constant uniswapRouter = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address public constant weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    uint256 public constant BLOCKSPERYEAR = 2102400; // 12 seconds per block

    //IRON BANK
    ComptrollerI private ironBank = ComptrollerI(address(0xAB1c342C7bf5Ec5F02ADEA1c2270670bCa144CbB));
    CErc20I private ironBankToken;
    uint256 public maxIronBankLeverage = 4; //max leverage we will take from iron bank
    uint256 public step = 10;

    IGenericLender[] public lenders;
    bool public externalOracle = false;
    address public wantToEthOracle;

    constructor(address _vault, address _ironBankToken) public BaseStrategy(_vault) {
        ironBankToken = CErc20I(_ironBankToken);

        debtThreshold = 1e15;
        want.safeApprove(address(ironBankToken), uint256(-1));

        //we do this horrible thing because you can't compare strings in solidity
        require(keccak256(bytes(apiVersion())) == keccak256(bytes(VaultAPI(_vault).apiVersion())), "WRONG VERSION");
    }



    /*****************
     * Iron Bank
     ******************/

    //simple logic. do we get more apr than iron bank charges?
    //if so, is that still true with increased pos?
    //if not, should be reduce?
    //made harder because we can't assume iron bank debt curve. So need to increment
    function internalCreditOfficer() public view returns (bool borrowMore, uint256 amount) {

        if(emergencyExit){
            return(false, ironBankOutstandingDebtStored());
        }

        //how much credit we have
        (, uint256 liquidity, uint256 shortfall) = ironBank.getAccountLiquidity(address(this));
        uint256 underlyingPrice = ironBank.oracle().getUnderlyingPrice(address(ironBankToken));
        
        if(underlyingPrice == 0){
            return (false, 0);
        }

        liquidity = liquidity.mul(1e18).div(underlyingPrice);
        shortfall = shortfall.mul(1e18).div(underlyingPrice);

        //repay debt if iron bank wants its money back
        if(shortfall > 0){
            //note we only borrow 1 asset so can assume all our shortfall is from it
            return(false, shortfall-1); //remove 1 incase of rounding errors
        }
        

        uint256 liquidityAvailable = want.balanceOf(address(ironBankToken));
        uint256 remainingCredit = Math.min(liquidity, liquidityAvailable);

        
        //our current supply rate.
        //we only calculate once because it is expensive
        uint256 currentSR = currentSupplyRate();
        //iron bank borrow rate
        uint256 ironBankBR = ironBankBorrowRate(0, true);

        uint256 outstandingDebt = ironBankOutstandingDebtStored();

        //we have internal credit limit. it is function on our own assets invested
        //this means we can always repay our debt from our capital
        uint256 maxCreditDesired = vault.strategies(address(this)).totalDebt.mul(maxIronBankLeverage);


        //minIncrement must be > 0
        if(maxCreditDesired <= step){
            return (false, 0);
        }

        //we move in 10% increments
        uint256 minIncrement = maxCreditDesired.div(step);

        //we start at 1 to save some gas
        uint256 increment = 1;
  
        // if we have too much debt we return
        //overshoot incase of dust
        if(maxCreditDesired.mul(11).div(10) < outstandingDebt){
            borrowMore = false;
            amount = outstandingDebt - maxCreditDesired;
        }
        //if sr is > iron bank we borrow more. else return
        else if(currentSR > ironBankBR){            
            remainingCredit = Math.min(maxCreditDesired - outstandingDebt, remainingCredit);

            while(minIncrement.mul(increment) <= remainingCredit){
                ironBankBR = ironBankBorrowRate(minIncrement.mul(increment), false);
                if(currentSR <= ironBankBR){
                    break;
                }

                increment++;
            }
            borrowMore = true;
            amount = minIncrement.mul(increment-1);

        }else{

            while(minIncrement.mul(increment) <= outstandingDebt){
                ironBankBR = ironBankBorrowRate(minIncrement.mul(increment), true);

                //we do increment before the if statement here
                increment++;
                if(currentSR > ironBankBR){
                    break;
                }

            }
            borrowMore = false;

            //special case to repay all
            if(increment == 1){
                amount = outstandingDebt;
            }else{
                amount = minIncrement.mul(increment - 1);
            }

        }

        //we dont play with dust:
        if (amount < debtThreshold) { 
            amount = 0;
        }
     }

     function ironBankOutstandingDebtStored() public view returns (uint256 available) {

        return ironBankToken.borrowBalanceStored(address(this));
     }


     function ironBankBorrowRate(uint256 amount, bool repay) public view returns (uint256) {
        uint256 cashPrior = want.balanceOf(address(ironBankToken));

        uint256 borrows = ironBankToken.totalBorrows();
        uint256 reserves = ironBankToken.totalReserves();

        InterestRateModel model = ironBankToken.interestRateModel();
        uint256 cashChange;
        uint256 borrowChange;
        if(repay){
            cashChange = cashPrior.add(amount);
            borrowChange = borrows.sub(amount);
        }else{
            cashChange = cashPrior.sub(amount);
            borrowChange = borrows.add(amount);
        }

        uint256 borrowRate = model.getBorrowRate(cashChange, borrowChange, reserves);

        return borrowRate;
    }

    function setPriceOracle(address _oracle) external onlyAuthorized{
        wantToEthOracle = _oracle;
    }

    function name() external view override returns (string memory) {
        return "StrategyLenderYieldOptimiserIB";
    }

    //management functions
    //add lenders for the strategy to choose between
    // only governance to stop strategist adding dodgy lender
    function addLender(address a) public onlyGovernance {
        IGenericLender n = IGenericLender(a);
        require(n.strategy() == address(this), "Undocked Lender");

        for (uint256 i = 0; i < lenders.length; i++) {
            require(a != address(lenders[i]), "Already Added");
        }
        lenders.push(n);
    }

    //but strategist can remove for safety
    function safeRemoveLender(address a) public onlyAuthorized {
        _removeLender(a, false);
    }

    function forceRemoveLender(address a) public onlyAuthorized {
        _removeLender(a, true);
    }

    //force removes the lender even if it still has a balance
    function _removeLender(address a, bool force) internal {
        for (uint256 i = 0; i < lenders.length; i++) {
            if (a == address(lenders[i])) {
                bool allWithdrawn = lenders[i].withdrawAll();

                if (!force) {
                    require(allWithdrawn, "WITHDRAW FAILED");
                }

                //put the last index here
                //remove last index
                if (i != lenders.length-1) {
                    lenders[i] = lenders[lenders.length - 1];
                }

                //pop shortens array by 1 thereby deleting the last index
                lenders.pop();

                //if balance to spend we might as well put it into the best lender
                if (want.balanceOf(address(this)) > 0) {
                    adjustPosition(0);
                }
                return;
            }
        }
        require(false, "NOT LENDER");
    }

    //we could make this more gas efficient but it is only used by a view function
    struct lendStatus {
        string name;
        uint256 assets;
        uint256 rate;
        address add;
    }

    //Returns the status of all lenders attached the strategy
    function lendStatuses() public view returns (lendStatus[] memory) {
        lendStatus[] memory statuses = new lendStatus[](lenders.length);
        for (uint256 i = 0; i < lenders.length; i++) {
            lendStatus memory s;
            s.name = lenders[i].lenderName();
            s.add = address(lenders[i]);
            s.assets = lenders[i].nav();
            s.rate = lenders[i].apr().mul(BLOCKSPERYEAR);
            statuses[i] = s;
        }

        return statuses;
    }

    // lent assets plus loose assets
    function estimatedTotalAssets() public view override returns (uint256) {
        uint256 nav = lentTotalAssets();
        nav += want.balanceOf(address(this));

        uint256 ironBankDebt = ironBankOutstandingDebtStored();
        if(ironBankDebt > nav) return 0;

        return nav.sub(ironBankDebt);
    }

    function numLenders() public view returns (uint256) {
        return lenders.length;
    }


    //the weighted apr of all lenders. sum(nav * apr)/totalNav
    function currentSupplyRate() public view returns (uint256) {
        uint256 bal = lentTotalAssets();
        bal += want.balanceOf(address(this));


        uint256 weightedAPR = 0;

        for (uint256 i = 0; i < lenders.length; i++) {
            weightedAPR += lenders[i].weightedApr();
        }

        return weightedAPR.div(bal);
    }
    function estimatedAPR() public view returns (uint256){
        uint256 outstandingDebt = ironBankOutstandingDebtStored();
        uint256 ironBankBR = ironBankBorrowRate(0, true);
        uint256 id = outstandingDebt.mul(ironBankBR);

        uint256 currentSR = currentSupplyRate();
        uint256 assets = lentTotalAssets().add(want.balanceOf(address(this)));
        uint256 ti = assets.mul(currentSR);
        if(ti > id && assets > outstandingDebt){
            return ti.sub(id).div(assets.sub(outstandingDebt)).mul(BLOCKSPERYEAR);
        }else{
            return 0;
        }

        

    }

    //Estimates the impact on APR if we add more money. It does not take into account adjusting position
    function _estimateDebtLimitIncrease(uint256 change) internal view returns (uint256) {
        uint256 highestAPR = 0;
        uint256 aprChoice = 0;
        uint256 assets = 0;

        for (uint256 i = 0; i < lenders.length; i++) {
            uint256 apr = lenders[i].aprAfterDeposit(change);
            if (apr > highestAPR) {
                aprChoice = i;
                highestAPR = apr;
                assets = lenders[i].nav();
            }
        }

        uint256 weightedAPR = highestAPR.mul(assets.add(change));

        for (uint256 i = 0; i < lenders.length; i++) {
            if (i != aprChoice) {
                weightedAPR += lenders[i].weightedApr();
            }
        }

        uint256 bal = estimatedTotalAssets().add(change);

        return weightedAPR.div(bal);
    }

    //Estimates debt limit decrease. It is not accurate and should only be used for very broad decision making
    function _estimateDebtLimitDecrease(uint256 change) internal view returns (uint256) {
        uint256 lowestApr = uint256(-1);
        uint256 aprChoice = 0;

        for (uint256 i = 0; i < lenders.length; i++) {
            uint256 apr = lenders[i].aprAfterDeposit(change);
            if (apr < lowestApr) {
                aprChoice = i;
                lowestApr = apr;
            }
        }

        uint256 weightedAPR = 0;

        for (uint256 i = 0; i < lenders.length; i++) {
            if (i != aprChoice) {
                weightedAPR += lenders[i].weightedApr();
            } else {
                uint256 asset = lenders[i].nav();
                if (asset < change) {
                    //simplistic. not accurate
                    change = asset;
                }
                weightedAPR += lowestApr.mul(change);
            }
        }
        uint256 bal = estimatedTotalAssets().add(change);
        return weightedAPR.div(bal);
    }

    //estimates highest and lowest apr lenders. Public for debugging purposes but not much use to general public
    function estimateAdjustPosition()
        public
        view
        returns (
            uint256 _lowest,
            uint256 _lowestApr,
            uint256 _highest,
            uint256 _potential
        )
    {
        //all loose assets are to be invested
        uint256 looseAssets = want.balanceOf(address(this));

        // our simple algo
        // get the lowest apr strat
        // cycle through and see who could take its funds plus want for the highest apr
        _lowestApr = uint256(-1);
        _lowest = 0;
        uint256 lowestNav = 0;
        for (uint256 i = 0; i < lenders.length; i++) {
            if (lenders[i].hasAssets()) {
                uint256 apr = lenders[i].apr();
                if (apr < _lowestApr) {
                    _lowestApr = apr;
                    _lowest = i;
                    lowestNav = lenders[i].nav();
                }
            }
        }

        uint256 toAdd = lowestNav.add(looseAssets);

        uint256 highestApr = 0;
        _highest = 0;

        for (uint256 i = 0; i < lenders.length; i++) {
            uint256 apr;
            apr = lenders[i].aprAfterDeposit(looseAssets);

            if (apr > highestApr) {
                highestApr = apr;
                _highest = i;
            }
        }

        //if we can improve apr by withdrawing we do so
        _potential = lenders[_highest].aprAfterDeposit(toAdd);
    }

    //gives estiomate of future APR with a change of debt limit. Useful for governance to decide debt limits
    function estimatedFutureAPR(uint256 newDebtLimit) public view returns (uint256) {
        uint256 oldDebtLimit = vault.strategies(address(this)).totalDebt;
        uint256 change;
        if (oldDebtLimit < newDebtLimit) {
            change = newDebtLimit - oldDebtLimit;
            return _estimateDebtLimitIncrease(change);
        } else {
            change = oldDebtLimit - newDebtLimit;
            return _estimateDebtLimitDecrease(change);
        }
    }

    //cycle all lenders and collect balances
    function lentTotalAssets() public view returns (uint256) {
        uint256 nav = 0;
        for (uint256 i = 0; i < lenders.length; i++) {
            nav += lenders[i].nav();
        }
        return nav;
    }

    //we need to free up profit plus _debtOutstanding.
    //If _debtOutstanding is more than we can free we get as much as possible
    // should be no way for there to be a loss. we hope...
    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        _profit = 0;
        _loss = 0; //for clarity
        _debtPayment = _debtOutstanding;

        uint256 lentAssets = lentTotalAssets();

        uint256 looseAssets = want.balanceOf(address(this));
        uint256 ironBankDebt = ironBankOutstandingDebtStored();
        uint256 total = looseAssets.add(lentAssets);
        if(ironBankDebt < total){
            total = total.sub(ironBankDebt);
        }else{
            total = 0;
        }

        

        if (lentAssets == 0) {
            //no position to harvest or profit to report
            if (_debtPayment > looseAssets) {
                //we can only return looseAssets
                _debtPayment = looseAssets;
            }

            return (_profit, _loss, _debtPayment);
        }

        uint256 debt = vault.strategies(address(this)).totalDebt;

        if (total > debt) {

            _profit = total - debt;
            uint256 amountToFree = _profit.add(_debtPayment);

            //we need to add outstanding to our profit
            //dont need to do logic if there is nothiing to free
            if (amountToFree > 0 && looseAssets < amountToFree) {
                //withdraw what we can withdraw
                _withdrawSome(amountToFree.sub(looseAssets));
                uint256 newLoose = want.balanceOf(address(this));
                //if we dont have enough money adjust _debtOutstanding and only change profit if needed
                if (newLoose < amountToFree) {
                    if (_profit > newLoose) {
                        _profit = newLoose;
                        _debtPayment = 0;
                    } else {
                        _debtPayment = Math.min(newLoose - _profit, _debtPayment);
                    }
                }
            }

        } else {

            //serious loss should never happen but if it does lets record it accurately
            _loss = debt - total;
            uint256 amountToFree = _loss.add(_debtPayment);

            if (amountToFree > 0 && looseAssets < amountToFree) {
                //withdraw what we can withdraw

                _withdrawSome(amountToFree.sub(looseAssets));
                uint256 newLoose = want.balanceOf(address(this));

                //if we dont have enough money adjust _debtOutstanding and only change profit if needed
                if (newLoose < amountToFree) {
                    if (_loss > newLoose) {
                        _loss = newLoose;
                        _debtPayment = 0;
                    } else {
                        _debtPayment = Math.min(newLoose - _loss, _debtPayment);
                    }
                }
            }
        }
    }

    /*
     * Key logic.
     *   The algorithm moves assets from lowest return to highest
     *   like a very slow idiots bubble sort
     *   we ignore debt outstanding for an easy life
     */
    function adjustPosition(uint256 _debtOutstanding) internal override {

        //start off by borrowing or returning:
        (bool borrowMore, uint256 amount) = internalCreditOfficer();
        
        //do iron bank stuff first
        if(!borrowMore){
            (uint256 _amountFreed,) = liquidatePosition(amount);
            //withdraw and repay
            ironBankToken.repayBorrow(_amountFreed);
            
        }else if(amount > 0){
            //borrow the amount we want
            ironBankToken.borrow(amount);
        }
        
        //emergency exit is dealt with at beginning of harvest
        if (emergencyExit) {
            return;
        }



        //we just keep all money in want if we dont have any lenders
        if(lenders.length == 0){
           return;
        }

        _debtOutstanding; //ignored. we handle it in prepare return


        (uint256 lowest, uint256 lowestApr, uint256 highest, uint256 potential) = estimateAdjustPosition();

        if (potential > lowestApr) {
            //apr should go down after deposit so wont be withdrawing from self
            lenders[lowest].withdrawAll();
        }

        uint256 bal = want.balanceOf(address(this));
        if (bal > 0) {
            want.safeTransfer(address(lenders[highest]), bal);
            lenders[highest].deposit();
        }
    }

    struct lenderRatio {
        address lender;
        //share x 1000
        uint16 share;
    }

    //share must add up to 1000.
    function manualAllocation(lenderRatio[] memory _newPositions) public onlyAuthorized {
        uint256 share = 0;

        for (uint256 i = 0; i < lenders.length; i++) {
            lenders[i].withdrawAll();
        }

        uint256 assets = want.balanceOf(address(this));

        for (uint256 i = 0; i < _newPositions.length; i++) {
            bool found = false;

            //might be annoying and expensive to do this second loop but worth it for safety
            for (uint256 j = 0; j < lenders.length; j++) {
                if (address(lenders[j]) == _newPositions[j].lender) {
                    found = true;
                }
            }
            require(found, "NOT LENDER");

            share += _newPositions[i].share;
            uint256 toSend = assets.mul(_newPositions[i].share).div(1000);
            want.safeTransfer(_newPositions[i].lender, toSend);
            IGenericLender(_newPositions[i].lender).deposit();
        }

        require(share == 1000, "SHARE!=1000");
    }

    //cycle through withdrawing from worst rate first
    function _withdrawSome(uint256 _amount) internal returns (uint256 amountWithdrawn) {
        //dont withdraw dust
        if (_amount < debtThreshold) {
            return 0;
        }

        amountWithdrawn = 0;
        //most situations this will only run once. Only big withdrawals will be a gas guzzler
        uint256 j = 0;
        while (amountWithdrawn < _amount) {
            uint256 lowestApr = uint256(-1);
            uint256 lowest = 0;
            for (uint256 i = 0; i < lenders.length; i++) {
                if (lenders[i].hasAssets()) {
                    uint256 apr = lenders[i].apr();
                    if (apr < lowestApr) {
                        lowestApr = apr;
                        lowest = i;
                    }
                }
            }
            if (!lenders[lowest].hasAssets()) {
                return amountWithdrawn;
            }
            amountWithdrawn += lenders[lowest].withdraw(_amount - amountWithdrawn);
            j++;
            //dont want infinite loop
            if(j >= 6){
                return amountWithdrawn;
            }
        }
    }

    /*
     * Liquidate as many assets as possible to `want`, irregardless of slippage,
     * up to `_amountNeeded`. Any excess should be re-invested here as well.
     */
    function liquidatePosition(uint256 _amountNeeded) internal override returns (uint256 _amountFreed, uint256 _loss) {
        uint256 _balance = want.balanceOf(address(this));

        if (_balance >= _amountNeeded) {
            //if we don't set reserve here withdrawer will be sent our full balance
            return (_amountNeeded,0);
        } else {
            uint256 received = _withdrawSome(_amountNeeded - _balance).add(_balance);
            if (received >= _amountNeeded) {
                return (_amountNeeded,0);
            } else {
               
                return (received,0);
            }
        }
    }

    function harvestTrigger(uint256 callCost) public override view returns (bool) {
        uint256 wantCallCost = _callCostToWant(callCost);

        return super.harvestTrigger(wantCallCost);
    }

    function ethToWant(uint256 _amount) internal view returns (uint256){
       
        address[] memory path = new address[](2);
        path = new address[](2);
        path[0] = weth;
        path[1] = address(want); 
 
        uint256[] memory amounts = IUni(uniswapRouter).getAmountsOut(_amount, path);

        return amounts[amounts.length - 1];
    }

    function _callCostToWant(uint256 callCost) internal view returns (uint256){
        uint256 wantCallCost;

        //three situations
        //1 currency is eth so no change.
        //2 we use uniswap swap price
        //3 we use external oracle
        if(address(want) == weth){
            wantCallCost = callCost;
        }else if(wantToEthOracle == address(0)){
            wantCallCost = ethToWant(callCost);
        }else{
            wantCallCost = IWantToEth(wantToEthOracle).ethToWant(callCost);
        }

        return wantCallCost;
    }

    function tendTrigger(uint256 callCost) public view override returns (bool) {
        // make sure to call tendtrigger with same callcost as harvestTrigger
        if (harvestTrigger(callCost)) {
            return false;
        }
        uint256 wantCallCost = _callCostToWant(callCost);

        //test if we want to change iron bank position
        (,uint256 _amount)= internalCreditOfficer();
        if(profitFactor.mul(wantCallCost) < _amount){
            return true;
        }

        //now let's check if there is better apr somewhere else.
        //If there is and profit potential is worth changing then lets do it
        (uint256 lowest, uint256 lowestApr, , uint256 potential) = estimateAdjustPosition();

        //if protential > lowestApr it means we are changing horses
        if (potential > lowestApr) {
            uint256 nav = lenders[lowest].nav();

            //profit increase is 1 days profit with new apr
            uint256 profitIncrease = (nav.mul(potential) - nav.mul(lowestApr)).div(1e18).div(365);

            

            return (wantCallCost.mul(profitFactor) < profitIncrease);
        }
    }

    /*
     * revert if we can't withdraw full balance
     */
    function prepareMigration(address _newStrategy) internal override {
        uint256 outstanding = vault.strategies(address(this)).totalDebt;
        uint256 ibBorrows = ironBankToken.borrowBalanceCurrent(address(this));
        (,, uint wantBalance) = prepareReturn(outstanding.add(ibBorrows));


        ironBankToken.repayBorrow(Math.min(ibBorrows, wantBalance));
        wantBalance = want.balanceOf(address(this));

       // require(wantBalance.add(loss) >= outstanding, "LIQUIDITY LOCKED");
       //require removed because in 0.3.0 we can still harvest after migrate

    }


    function protectedTokens() internal view override returns (address[] memory) {
        address[] memory protected = new address[](1);
        protected[0] = address(want);
        return protected;
    }

}

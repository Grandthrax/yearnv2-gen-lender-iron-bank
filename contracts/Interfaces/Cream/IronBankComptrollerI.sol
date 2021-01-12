pragma solidity >=0.5.0;

import "../Compound/ComptrollerI.sol";

interface IronBankControllerI is ComptrollerI {


    function creditLimits(address sc)
        external
        view
        returns (
            uint256);


     function _setCreditLimit(address protocol, uint creditLimit) external;
}
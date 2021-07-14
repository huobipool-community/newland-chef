// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

interface IBoosterBank {
    function depositLPToken(uint256 _sid, uint256 _amount, uint256 _bid, uint256 _bAmount, uint256 _desirePrice, uint256 _slippage)
    external returns (uint256 lpAmount);

    function withdrawLPToken(uint256 _sid, uint256 _rate, uint256 _desirePrice, uint256 _slippage) external;

    function claim(uint256 _poolClaimId, uint256[] memory _pidlist) external;

    function emergencyWithdraw(uint256 _sid, uint256 _desirePrice, uint256 _slippage) external;
}
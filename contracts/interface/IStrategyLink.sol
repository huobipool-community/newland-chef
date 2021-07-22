// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IStrategyLink {
    function compActionPool() external view returns(address);
    function getPoolInfo(uint256 _pid) external view  returns(address[] memory collateralToken, address baseToken, address lpToken, uint256 poolId, uint256 totalLPAmount, uint256 totalLPRefund);
    function pendingLPAmount(uint256 _pid, address _account) external view returns (uint256 value);
    function updatePool(uint256 _pid, uint256 _desirePrice, uint256 _slippage) external;
    function sconfig() external view returns(address);
}
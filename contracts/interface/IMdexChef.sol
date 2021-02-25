// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IMdexChef {
    function pending(uint256 _pid, address _user) external view returns (uint256, uint256);
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;

}
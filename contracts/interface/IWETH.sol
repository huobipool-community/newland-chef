// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IWHT {
    function deposit() external payable;

    function transfer(address to, uint value) external returns (bool);

    function withdraw(uint) external;
}
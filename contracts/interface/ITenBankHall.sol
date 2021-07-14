// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface ITenBankHall {
    function strategyInfo(uint _sid) external returns(
        bool isListed,
        address iLink,
        uint256 pid);
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./library/SafeToken.sol";

contract Treasury is Ownable {
    using SafeToken for address;

    mapping(address => mapping(address => uint)) public userTokenAmt;
    mapping(address => uint) public tokenTotalAmt;

    function deposit(address user, address token, uint amt) public payable onlyOwner returns(uint) {
        if (token == address(0)) {
            amt = msg.value;
        }
        if (amt <= 0) {
            return amt;
        }

        if (token != address(0)) {
            token.safeTransferFrom(msg.sender, address(this), amt);
        }

        userTokenAmt[user][token] += amt;
        tokenTotalAmt[token] += amt;
        return amt;
    }

    function withdraw(address user, address token, uint amt, address to) public onlyOwner returns(uint) {
        if (amt <= 0) {
            return amt;
        }
        require(userTokenAmt[user][token] >= amt, "user amt not enough");

        userTokenAmt[user][token] -= amt;
        tokenTotalAmt[token] -= amt;
        uint bal = token.opBalance();

        if (amt > bal) {
            amt = bal;
        }
        if (amt > 0) {
            token.opTransfer(to, amt);
        }
        return amt;
    }
}
pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "../CErc20.sol";
import "../CToken.sol";
import "../PriceOracle.sol";
import "../EIP20Interface.sol";

interface ComptrollerLensInterface {
    function markets(address) external view returns (bool, uint);
    function checkMembership(address account, CToken cToken) external view returns (bool);
    function oracle() external view returns (PriceOracle);
    function getAccountLiquidity(address) external view returns (uint, uint, uint);
    function getAssetsIn(address) external view returns (CToken[] memory);
    function claimComp(address) external;
    function compAccrued(address) external view returns (uint);
    function compSpeeds(address) external view returns (uint256);

}

interface CanLensInterface {
    function markets(address) external view returns (bool, uint);
    function checkMembership(address account, CToken cToken) external view returns (bool);
    function oracle() external view returns (PriceOracle);
    function getAccountLiquidity(address) external view returns (uint, uint, uint);
    function getAssetsIn(address) external view returns (CToken[] memory);
    function claimCan(address) external;
    function canAccrued(address) external view returns (uint);
    function canSpeeds(address _market) external view returns (uint256);

}

contract CompoundLens {

    uint public constant blocksPerYear = 10512000;
    address public usdt = 0xa71edc38d189767582c38a3145b5873052c3e47a;


    struct CTokenMetadata {
        address cToken;
        uint exchangeRateCurrent;
        uint supplyRatePerBlock;
        uint borrowRatePerBlock;
        uint reserveFactorMantissa;
        uint totalBorrows;
        uint totalReserves;
        uint totalSupply;
        uint totalCash;
        bool isListed;
        uint collateralFactorMantissa;
        address underlyingAssetAddress;
        uint cTokenDecimals;
        uint underlyingDecimals;
    }

    function cTokenMetadata(CToken cToken) public returns (CTokenMetadata memory) {
        uint exchangeRateCurrent = cToken.exchangeRateCurrent();
        ComptrollerLensInterface comptroller = ComptrollerLensInterface(address(cToken.comptroller()));
        (bool isListed, uint collateralFactorMantissa) = comptroller.markets(address(cToken));
        address underlyingAssetAddress;
        uint underlyingDecimals;

        if (compareStrings(cToken.symbol(), "cETH")) {
            underlyingAssetAddress = address(0);
            underlyingDecimals = 18;
        } else {
            CErc20 cErc20 = CErc20(address(cToken));
            underlyingAssetAddress = cErc20.underlying();
            underlyingDecimals = EIP20Interface(cErc20.underlying()).decimals();
        }

        return CTokenMetadata({
            cToken: address(cToken),
            exchangeRateCurrent: exchangeRateCurrent,
            supplyRatePerBlock: cToken.supplyRatePerBlock(),
            borrowRatePerBlock: cToken.borrowRatePerBlock(),
            reserveFactorMantissa: cToken.reserveFactorMantissa(),
            totalBorrows: cToken.totalBorrows(),
            totalReserves: cToken.totalReserves(),
            totalSupply: cToken.totalSupply(),
            totalCash: cToken.getCash(),
            isListed: isListed,
            collateralFactorMantissa: collateralFactorMantissa,
            underlyingAssetAddress: underlyingAssetAddress,
            cTokenDecimals: cToken.decimals(),
            underlyingDecimals: underlyingDecimals
        });
    }

    function cTokenMetadataAll(CToken[] calldata cTokens) external returns (CTokenMetadata[] memory) {
        uint cTokenCount = cTokens.length;
        CTokenMetadata[] memory res = new CTokenMetadata[](cTokenCount);
        for (uint i = 0; i < cTokenCount; i++) {
            res[i] = cTokenMetadata(cTokens[i]);
        }
        return res;
    }

    struct CTokenBalances {
        address cToken;
        uint balanceOf;
        uint borrowBalanceCurrent;
        uint balanceOfUnderlying;
        uint tokenBalance;
        uint tokenAllowance;
        bool isMember;
    }

    function cTokenBalances(CToken cToken, address payable account) public returns (CTokenBalances memory) {
        ComptrollerLensInterface comptroller = ComptrollerLensInterface(address(cToken.comptroller()));
        (bool isMember) = comptroller.checkMembership(account,address(cToken));
        
        
        uint balanceOf = cToken.balanceOf(account);
        uint borrowBalanceCurrent = cToken.borrowBalanceCurrent(account);
        uint balanceOfUnderlying = cToken.balanceOfUnderlying(account);
        uint tokenBalance;
        uint tokenAllowance;

        if (compareStrings(cToken.symbol(), "cETH")) {
            tokenBalance = account.balance;
            tokenAllowance = account.balance;
        } else {
            CErc20 cErc20 = CErc20(address(cToken));
            EIP20Interface underlying = EIP20Interface(cErc20.underlying());
            tokenBalance = underlying.balanceOf(account);
            tokenAllowance = underlying.allowance(account, address(cToken));
        }

        return CTokenBalances({
            cToken: address(cToken),
            balanceOf: balanceOf,
            borrowBalanceCurrent: borrowBalanceCurrent,
            balanceOfUnderlying: balanceOfUnderlying,
            tokenBalance: tokenBalance,
            tokenAllowance: tokenAllowance,
            isMember
        });
    }

    function cTokenBalancesAll(CToken[] calldata cTokens, address payable account) external returns (CTokenBalances[] memory) {
        uint cTokenCount = cTokens.length;
        CTokenBalances[] memory res = new CTokenBalances[](cTokenCount);
        for (uint i = 0; i < cTokenCount; i++) {
            res[i] = cTokenBalances(cTokens[i], account);
        }
        return res;
    }

    struct CTokenUnderlyingPrice {
        address cToken;
        uint underlyingPrice;
    }

    function cTokenUnderlyingPrice(CToken cToken) public returns (CTokenUnderlyingPrice memory) {
        ComptrollerLensInterface comptroller = ComptrollerLensInterface(address(cToken.comptroller()));
        PriceOracle priceOracle = comptroller.oracle();

        return CTokenUnderlyingPrice({
            cToken: address(cToken),
            underlyingPrice: priceOracle.getUnderlyingPrice(cToken)
        });
    }

    function cTokenUnderlyingPriceAll(CToken[] calldata cTokens) external returns (CTokenUnderlyingPrice[] memory) {
        uint cTokenCount = cTokens.length;
        CTokenUnderlyingPrice[] memory res = new CTokenUnderlyingPrice[](cTokenCount);
        for (uint i = 0; i < cTokenCount; i++) {
            res[i] = cTokenUnderlyingPrice(cTokens[i]);
        }
        return res;
    }

    struct AccountLimits {
        CToken[] markets;
        uint liquidity;
        uint shortfall;
    }

    function getAccountLimits(ComptrollerLensInterface comptroller, address account) public returns (AccountLimits memory) {
        (uint errorCode, uint liquidity, uint shortfall) = comptroller.getAccountLiquidity(account);
        require(errorCode == 0);

        return AccountLimits({
            markets: comptroller.getAssetsIn(account),
            liquidity: liquidity,
            shortfall: shortfall
        });
    }


    struct CompBalanceMetadataExt {
        uint balance;
        uint allocated;
        uint price;
    }

    function getCompBalanceMetadataExt(EIP20Interface comp, address comptroller, address account) external returns (CompBalanceMetadataExt memory) {
        uint balance = comp.balanceOf(account);
        if (compareStrings(comp.symbol(), "HPT")) {
            ComptrollerLensInterface comptroller = ComptrollerLensInterface(comptroller);
            comptroller.claimComp(account);
            uint newBalance = comp.balanceOf(account);
            uint accrued = comptroller.compAccrued(account);
            uint total = add(accrued, newBalance, "sum comp total");
            uint allocated = sub(total, balance, "sub allocated");

            return CompBalanceMetadataExt({
                balance: balance,
                allocated: allocated,
                price: uint(0)
            });
        } 

        if (compareStrings(comp.symbol(), "CAN")) {
            CanLensInterface comptroller = CanLensInterface(comptroller);
            comptroller.claimCan(account);
            uint newBalance = comp.balanceOf(account);
            uint accrued = comptroller.canAccrued(account);
            uint total = add(accrued, newBalance, "sum comp total");
            uint allocated = sub(total, balance, "sub allocated");

            return CompBalanceMetadataExt({
                balance: balance,
                allocated: allocated,
                price: uint(0)
            });
        } 

        return CompBalanceMetadataExt({
            balance: balance,
            allocated: uint(0),
            price: uint(0)
        });
    }

    struct CTokenRewardApy {
        address cToken;
        uint supplyApy;
        uint borrowApy;
    }

    function cTokenRewardApyAll(CToken[] calldata cTokens,EIP20Interface comp ) external returns (CTokenRewardApy[] memory) {
        uint cTokenCount = cTokens.length;
        CTokenRewardApy[] memory res = new CTokenRewardApy[](cTokenCount);
        uint priceComp = getPrice(address(comp),usdt);
        

        for (uint i = 0; i < cTokenCount; i++) {
            uint speed = getSpeed(cTokens[i],comp);
            uint supplyApy = supplyApy(cTokens[i], priceComp,speed);
            uint borrowApy = borrowApy(cTokens[i], priceComp,speed);
            res[i] = CTokenRewardApy ({
                cToken: cTokens[i], 
                supplyApy: supplyApy,
                borrowApy: borrowApy
            });
        }
        return res;
    }

    function getPrice(address _token, address _base) internal view returns (uint256) {
        return 1e18;
    }

    function getSpeed(address market,EIP20Interface comp) internal view returns (uint256){
        if (compareStrings(comp.symbol(), "HPT")) {
            ComptrollerLensInterface comptroller = ComptrollerLensInterface(address(market.comptroller()));
            return comptroller.compSpeeds(market);
        }
        if (compareStrings(comp.symbol(), "CAN")) {
            CanLensInterface comptroller = CanLensInterface(address(market.comptroller()));
            return comptroller.canSpeeds(market);
        }
        return uint(0);

    }
    function supplyApy(address market, uint priceComp,uint speed) public view returns (uint256) {
        address token = CErc20(market).underlying();
        uint decimals = CErc20(token).decimals();
  
        uint dived = CErc20(market).totalSupply().mul(CErc20(market).exchangeRateStored()).mul(getPrice(token, usdt)).div(1e18);
        if (dived == 0) {
            return 0;
        }
        if (decimals != 18) {
            return speed.mul(priceComp).mul(10512000).mul(1e18).div(dived).div(10 ** (18 - decimals));
        } else {
            return speed.mul(priceComp).mul(10512000).mul(1e18).div(dived);
        }
        
    }

    function borrowApy(address market, uint priceComp,uint speed) public view returns (uint256) {
        address token = CErc20(market).underlying();
        uint decimals = CErc20(token).decimals();
        
        uint borrowIndex = CErc20(market).borrowIndex();
        uint dived = 0;
        if (borrowIndex == 0) {
            dived = CErc20(market).totalBorrows().mul(1e18).mul(getPrice(token, usdt));
        } else {
            dived = CErc20(market).totalBorrows().mul(1e18).div(CErc20(market).borrowIndex()).mul(getPrice(token, usdt));
        }
        if (dived == 0) {
            return 0;
        }
        if (decimals != 18) {
            return speed.mul(priceComp).mul(10512000).mul(1e18).div(dived).div(10 ** (18 - decimals));
        } else {
            return speed.mul(priceComp).mul(10512000).mul(1e18).div(dived);
        }
        
    }
  
    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }

    function add(uint a, uint b, string memory errorMessage) internal pure returns (uint) {
        uint c = a + b;
        require(c >= a, errorMessage);
        return c;
    }

    function sub(uint a, uint b, string memory errorMessage) internal pure returns (uint) {
        require(b <= a, errorMessage);
        uint c = a - b;
        return c;
    }
}

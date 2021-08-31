pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "./CErc20.sol";
import "./CToken.sol";
import "./PriceOracle.sol";
import "./EIP20Interface.sol";
import './SafeMath.sol';
import "./IMdexPair.sol";
import "./IMdexFactory.sol";

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
    function getSupplySpeed(address _market) external view returns (uint256);
    function getBorrowSpeed(address _market) external view returns (uint256);

}

contract CompoundLens {
    using SafeMath for uint;
    uint public constant blocksPerYear = 10512000;
    address public usdt = 0xa71EdC38d189767582C38A3145b5873052c3e47a;
    address public husd = 0x0298c2b32eaE4da002a15f36fdf7615BEa3DA047;
    address public wht = 0x5545153CCFcA01fbd7Dd11C0b23ba694D9509A6F;

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

        if (compareStrings(cToken.symbol(), "cHT")) {
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
        (bool isMember) = comptroller.checkMembership(account, cToken);


        uint balanceOf = cToken.balanceOf(account);
        uint borrowBalanceCurrent = cToken.borrowBalanceCurrent(account);
        uint balanceOfUnderlying = cToken.balanceOfUnderlying(account);
        uint tokenBalance;
        uint tokenAllowance;

        if (compareStrings(cToken.symbol(), "cHT")) {
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
            isMember: isMember
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

    function cTokenUnderlyingPrice(CToken cToken) public view returns (CTokenUnderlyingPrice memory) {
        ComptrollerLensInterface comptroller = ComptrollerLensInterface(address(cToken.comptroller()));
        PriceOracle priceOracle = comptroller.oracle();

        uint decimals;
        if (compareStrings(CErc20(address(cToken)).symbol(), "cHT")) {
            decimals = 18;
        }else{
            decimals = CErc20(CErc20(address(cToken)).underlying()).decimals();
        }

        if (decimals != 18) {
            return CTokenUnderlyingPrice({
                cToken: address(cToken),
                underlyingPrice: priceOracle.getUnderlyingPrice(cToken).div(10 ** (18 - decimals))
                });
        } else {
            return CTokenUnderlyingPrice({
                cToken: address(cToken),
                underlyingPrice: priceOracle.getUnderlyingPrice(cToken)
                });
        }
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

        if (compareStrings(comp.symbol(), "CAN")) {
            CanLensInterface cantroller = CanLensInterface(comptroller);
            cantroller.claimCan(account);
            uint newBalance = comp.balanceOf(account);
            uint accrued = cantroller.canAccrued(account);
            uint total = add(accrued, newBalance, "sum comp total");
            uint allocated = sub(total, balance, "sub allocated");
            return CompBalanceMetadataExt({
                balance: balance,
                allocated: allocated,
                price: getPrice(address(comp))
                });
        }else{
            ComptrollerLensInterface hpttroller = ComptrollerLensInterface(comptroller);
            hpttroller.claimComp(account);
            uint newBalance = comp.balanceOf(account);
            uint accrued = hpttroller.compAccrued(account);
            uint total = add(accrued, newBalance, "sum comp total");
            uint allocated = sub(total, balance, "sub allocated");

            return CompBalanceMetadataExt({
                balance: balance,
                allocated: allocated,
                price: getPrice(address(comp))
                });
        }
    }

    struct CTokenRewardApy {
        address cToken;
        uint supplyApy;
        uint borrowApy;
    }

    function cTokenRewardApyAll(CToken[] calldata cTokens,EIP20Interface comp ) external view returns (CTokenRewardApy[] memory) {
        uint cTokenCount = cTokens.length;
        CTokenRewardApy[] memory res = new CTokenRewardApy[](cTokenCount);
        uint priceComp = getPrice(address(comp));
        for (uint i = 0; i < cTokenCount; i++) {
            uint supplySpeed = getSupplySpeed(cTokens[i],comp);
            uint borrowSpeed = getBorrowSpeed(cTokens[i],comp);
            uint supplyApy = supplyApy(cTokens[i], priceComp, supplySpeed);
            uint borrowApy = borrowApy(cTokens[i], priceComp, borrowSpeed);
            res[i] = CTokenRewardApy ({
                cToken: address(cTokens[i]),
                supplyApy: supplyApy,
                borrowApy: borrowApy
                });
        }
        return res;
    }

    IMdexFactory factory = IMdexFactory(0xb0b670fc1F7724119963018DB0BfA86aDb22d941);
    function getPrice(address _token) internal view returns (uint256) {
        if (_token == address(0)) {
            _token = wht;
        }
        address _base;
        if (compareStrings(CErc20(_token).symbol(), "CAN")) {
            _base = husd;
        }else{
            _base = usdt;
        }

        if (_token == _base) {
            return 10 ** uint(CErc20(_token).decimals());
        }
        IMdexPair lpToken = IMdexPair(factory.getPair(_token, _base));
        (uint256 totalAmount0, uint256 totalAmount1,) = lpToken.getReserves();
        CErc20 token0 = CErc20(lpToken.token0());
        CErc20 token1 = CErc20(lpToken.token1());
        if (address(token0) == _token) {
            return getMktSellAmount(
                10 ** uint(token0.decimals()), totalAmount0, totalAmount1
            );
        } else {
            return getMktSellAmount(
                10 ** uint(token1.decimals()), totalAmount1, totalAmount0
            );
        }
    }

    function getMktSellAmount(uint256 aIn, uint256 rIn, uint256 rOut) public pure returns (uint256) {
        if (aIn == 0) return 0;
        require(rIn > 0 && rOut > 0, "bad reserve values");
        uint256 aInWithFee = aIn.mul(997);
        uint256 numerator = aInWithFee.mul(rOut);
        uint256 denominator = rIn.mul(1000).add(aInWithFee);
        return numerator / denominator;
    }

    function getSupplySpeed(CToken market,EIP20Interface comp) internal view returns (uint256){
        if (compareStrings(comp.symbol(), "CAN")) {
            CanLensInterface comptroller = CanLensInterface(address(market.comptroller()));
            return comptroller.getSupplySpeed(address(market));
        }else{
            ComptrollerLensInterface comptroller = ComptrollerLensInterface(address(market.comptroller()));
            return comptroller.compSpeeds(address(market))/2;
        }
    }

    function getBorrowSpeed(CToken market,EIP20Interface comp) internal view returns (uint256){
        if (compareStrings(comp.symbol(), "CAN")) {
            CanLensInterface comptroller = CanLensInterface(address(market.comptroller()));
            return comptroller.getBorrowSpeed(address(market));
        }else{
            ComptrollerLensInterface comptroller = ComptrollerLensInterface(address(market.comptroller()));
            return comptroller.compSpeeds(address(market))/2;
        }
    }

    function supplyApy(CToken market, uint priceComp,uint speed) public view returns (uint256) {
        uint decimals = 18;
        address token;
        if (compareStrings(market.symbol(), "cHT")) {
            decimals = 18;
        }else{
            token = CErc20(address(market)).underlying();
            decimals = CErc20(token).decimals();
        }
        CTokenUnderlyingPrice memory priceInfo = cTokenUnderlyingPrice(market);
        uint dived = CErc20(address(market)).totalSupply().mul(CErc20(address(market)).exchangeRateStored()).mul(priceInfo.underlyingPrice).div(1e18);
        if (dived == 0) {
            return 0;
        }
        if (decimals != 18) {
            return speed.mul(priceComp).mul(10512000).mul(1e18).div(dived).div(10 ** (18 - decimals));
        } else {
            return speed.mul(priceComp).mul(10512000).mul(1e18).div(dived);
        }

    }

    function borrowApy(CToken market, uint priceComp,uint speed) public view returns (uint256) {
        uint decimals = 18;
        address token;
        if (compareStrings(market.symbol(), "cHT")) {
            decimals = 18;
        }else{
            token = CErc20(address(market)).underlying();
            decimals = CErc20(token).decimals();
        }

        uint dived = 0;
        CTokenUnderlyingPrice memory priceInfo = cTokenUnderlyingPrice(market);
        if (CErc20(address(market)).borrowIndex()  == 0) {
            dived = CErc20(address(market)).totalBorrows().mul(1e18).mul(priceInfo.underlyingPrice);
        } else {
            dived = CErc20(address(market)).totalBorrows().mul(1e18).div(CErc20(address(market)).borrowIndex()).mul(priceInfo.underlyingPrice);
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

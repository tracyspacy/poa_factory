// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

//factory contract creating personl vaults

contract Poa_factory {
    // poa counter
    uint256 public poa_count; //make contract ownable in future
    uint256 public interestRate;
    address public token1 = "<contract address>"; //usdc for ex
    address public token2 = "<contract address>"; //wbtc for ex
    address public tally_minter = "<contract address>"; //minter contract for a native token
    address public ponyswap = "<contract address>"; //dex

    mapping(address => Poa) public whospoa;

    event PoaCreated(Poa newPoa);

    function createNewPoa() public {
        poa_count += 1;
        //only one POA for address
        require(
            address(whospoa[msg.sender]) == address(0),
            "POA already exist"
        );
        Poa newPoa = new Poa(
            address(this),
            tally_minter,
            token1,
            token2,
            ponyswap,
            poa_count,
            msg.sender
        );
        whospoa[msg.sender] = newPoa;
        emit PoaCreated(newPoa);
    }

    function getPoa(address addr) public view returns (Poa) {
        return whospoa[addr];
    }

    function getInterestRate() public view returns (uint256) {
        return interestRate;
    }

    function setInterestRate(uint256 value) public {
        interestRate = value;
    }
}

// poa contract

// set requirement on any action - only owner? - check from factory

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface Tally_minter {
    function mintTally(address to, uint256 amount) external;

    function burnTally(address from, uint256 amount) external;
}

interface Ponyswap {
    function getWBTCprice(uint256 wbtc_amount) external view returns (uint256);

    function getUSDCprice(uint256 usdc_amount) external view returns (uint256);

    function swap(ERC20 _tokenIn, uint256 _amountIn)
        external
        returns (uint256 amountOut);
}

interface Factory {
    function getInterestRate() external view returns (uint256);
}

contract Poa {
    ERC20 public token1;
    ERC20 public token2;
    address public tally_minter;
    address public owner;
    address public factory;
    uint256 public id;
    address public ponyswap;

    constructor(
        address _factory,
        address _tally_minter,
        address _token1,
        address _token2,
        address _ponyswap,
        uint256 _id,
        address _owner
    ) {
        factory = _factory;
        tally_minter = _tally_minter;
        token1 = ERC20(_token1);
        token2 = ERC20(_token2);
        ponyswap = _ponyswap;
        id = _id;
        owner = _owner;
    }

    struct DebtPosition {
        uint256 principal;
        uint256 timestamp;
    }

    DebtPosition[] public debtPositions;

    event TKNdeposit(address from, uint256 amount, ERC20 token);
    event BorrowedAmount(uint256 borrowed, uint256 debttimestamp);
    event RepaidAmount(uint256 toRepay);

    function getinterestrate() public view returns (uint256) {
        return Factory(factory).getInterestRate();
    }

    // deposit acceptable token to POA
    function tknDeposit(uint256 amount, ERC20 token) public {
        //requires to be an owner of POA
        require(owner == msg.sender, "Access denied, create your own POA");
        require(
            address(token) == address(token1) ||
                address(token) == address(token2),
            "This token is not acceptable as deposit"
        );
        SafeERC20.safeTransferFrom(token, msg.sender, address(this), amount);
        emit TKNdeposit(msg.sender, amount, token);
    }

    // cummulative balance of poa, all calculated in USDC considering it's price = 1 USD - add oracle in future
    function getPoaBalance() public view returns (uint256) {
        uint256 wbtc_bal = token2.balanceOf(address(this));
        uint256 wbtcPrice = Ponyswap(ponyswap).getWBTCprice(wbtc_bal);
        uint256 balance = token1.balanceOf(address(this)) + wbtcPrice;
        return balance;
    }

    // function that shows max borrowable amount - 80% could be set as a variable in future to modify
    function maxBorrowable() public view returns (uint256) {
        uint256 balance = getPoaBalance();
        uint256 toRepay = getTotalOutstanding();
        return (balance / 100) * 80 - toRepay;
    }

    // function borrow - requires borrowable amount >= borrowed amount - add interest rate in future
    function borrow(uint256 borrowed) public returns (bool) {
        //requires to be an owner of POA
        require(owner == msg.sender, "Access denied, create your own POA");
        uint256 borrowable = maxBorrowable();
        require(borrowable >= borrowed, "Amount exceeds max borrowable!");
        uint256 debttimestamp = block.timestamp;
        debtPositions.push(DebtPosition(borrowed, debttimestamp));
        // mint tally
        Tally_minter(tally_minter).mintTally(msg.sender, borrowed);
        emit BorrowedAmount(borrowed, debttimestamp);
        return true;
    }

    // function repay - requires borrowed amount >= repayment amount
    function repay() public returns (bool) {
        //requires to be an owner of POA
        require(owner == msg.sender, "Access denied, create your own POA");
        uint256 toRepay = getTotalOutstanding();
        require(toRepay > 0, "Amount exceeds total amount to repay!");
        // burn tally - potentially check if balalnce is >= to repay.
        Tally_minter(tally_minter).burnTally(msg.sender, toRepay);
        delete debtPositions;
        emit RepaidAmount(toRepay);
        return true;
    }

    // withdraw collateral only after repay if needed - add only owner! (otherwise it is liquidation :) )
    function closePoa() public {
        //requires to be an owner of POA
        require(owner == msg.sender, "Access denied, create your own POA");
        uint256 toRepay = getTotalOutstanding();
        uint256 bal1 = token1.balanceOf(address(this));
        uint256 bal2 = token2.balanceOf(address(this));
        if (toRepay > 0) {
            repay();

            if (bal1 > 0) {
                SafeERC20.safeTransfer(token1, msg.sender, bal1);
            }
            if (bal2 > 0) {
                SafeERC20.safeTransfer(token2, msg.sender, bal2);
            }
        } else {
            if (bal1 > 0) {
                SafeERC20.safeTransfer(token1, msg.sender, bal1);
            }
            if (bal2 > 0) {
                SafeERC20.safeTransfer(token2, msg.sender, bal2);
            }
        }
    }

    function trade(ERC20 token, uint256 amount) public {
        //restriction - swap is available for owner only!
        require(owner == msg.sender, "Access denied, create your own POA");
        //uint token_bal = token.balanceOf(address(this));
        //require(token_bal>=amount, "Not enough funds");

        //maybe simple approve is better
        SafeERC20.safeApprove(token, ponyswap, amount);

        Ponyswap(ponyswap).swap(token, amount);
    }

    //total outstanding loan from all positions

    function getTotalOutstanding() public view returns (uint256) {
        uint256 i;
        uint256 totaloutstanding = 0;
        uint256 curtime = block.timestamp;

        if (debtPositions.length > 0) {
            //add to debt positions in borrow function in future as interest rate could change periodically
            uint256 interestRate = getinterestrate();
            for (i = 0; i < debtPositions.length; i++) {
                uint256 delta = curtime - debtPositions[i].timestamp;
                totaloutstanding +=
                    debtPositions[i].principal +
                    (debtPositions[i].principal * delta * interestRate) /
                    31557600;
            }
        }
        return totaloutstanding;
    }

    // loan-to-value to use for liquidations
    function getLTV() public view returns (uint256) {
        uint256 poaBalance = getPoaBalance();
        uint256 ltv = 0;
        if (poaBalance > 0) {
            uint256 ttldebt = getTotalOutstanding();
            ltv = (100 * ttldebt) / poaBalance;
        }
        return ltv;
    }
}

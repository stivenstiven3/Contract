// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title MAC Token
 * @dev ERC20 Token with transfer fee mechanism, freeze functionality and ownership management
 * @author Smart Contract Engineer
 */
contract MyToken is ERC20, Ownable, ReentrancyGuard, Pausable {
    
    // Token decimals
    uint8 private constant DECIMALS = 18;
    
    // Initial supply: 21314 tokens
    uint256 private constant INITIAL_SUPPLY = 21314 * 10**DECIMALS;
    
    // Fee rate: adjustable (initially 3%)
    uint256 public feeRate = 300; // 3% (300 basis points)
    uint256 public constant BASIS_POINTS = 10000; // 100%
    uint256 public constant MAX_FEE_RATE = 1000; // Maximum 10% fee rate
    
    // Mapping to track frozen balances for each address
    mapping(address => uint256) private _frozenBalances;
    
    // Events
    event TransferFeeCharged(address indexed from, uint256 amount);
    event FeeTransferred(address indexed to, uint256 amount);
    event FeeRateChanged(uint256 oldRate, uint256 newRate);
    event AddressFrozen(address indexed account, uint256 amount);
    event AddressUnfrozen(address indexed account, uint256 amount);
    event OwnershipTransferInitiated(address indexed previousOwner, address indexed newOwner);
    
    // Errors
    error InsufficientBalance(uint256 requested, uint256 available);
    error InsufficientUnfrozenBalance(uint256 requested, uint256 available);
    error InvalidAddress();
    error InvalidAmount();
    error SameOwner();
    error ZeroTransfer();
    error FeeRateTooHigh(uint256 requested, uint256 maximum);
    
    /**
     * @dev Constructor that sets initial supply and owner
     * @param initialOwner The address that will be set as the initial owner
     */
    constructor(address initialOwner) 
        ERC20("MAC", "MAC") 
        Ownable(initialOwner)
    {
        if (initialOwner == address(0)) revert InvalidAddress();
        
        // Mint initial supply to the contract deployer
        _mint(msg.sender, INITIAL_SUPPLY);
        
        // Transfer ownership to the specified initial owner
        if (initialOwner != msg.sender) {
            _transferOwnership(initialOwner);
        }
    }
    
    /**
     * @dev Returns the number of decimals used to get its user representation
     */
    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }
    
    /**
     * @dev Set the transfer fee rate
     * @param newRate The new fee rate in basis points (e.g., 300 = 3%)
     */
    function setFeeRate(uint256 newRate) external onlyOwner {
        if (newRate > MAX_FEE_RATE) {
            revert FeeRateTooHigh(newRate, MAX_FEE_RATE);
        }
        
        uint256 oldRate = feeRate;
        feeRate = newRate;
        
        emit FeeRateChanged(oldRate, newRate);
    }
    
    /**
     * @dev Get current fee rate information
     * @return current Current fee rate in basis points
     * @return maximum Maximum allowed fee rate
     */
    function getFeeRateInfo() external view returns (uint256 current, uint256 maximum) {
        return (feeRate, MAX_FEE_RATE);
    }
    
    /**
     * @dev Calculate transfer fee for a given amount
     * @param amount The transfer amount
     * @return feeAmount The fee that would be charged
     * @return netAmount The amount that would reach the recipient
     */
    function calculateTransferFee(uint256 amount) external view returns (uint256 feeAmount, uint256 netAmount) {
        feeAmount = (amount * feeRate) / BASIS_POINTS;
        netAmount = amount - feeAmount;
        return (feeAmount, netAmount);
    }
    
    /**
     * @dev Returns the frozen balance of an account
     * @param account The address to query
     * @return The frozen balance
     */
    function frozenBalanceOf(address account) public view returns (uint256) {
        return _frozenBalances[account];
    }
    
    /**
     * @dev Returns the available (unfrozen) balance of an account
     * @param account The address to query
     * @return The available balance
     */
    function availableBalanceOf(address account) public view returns (uint256) {
        uint256 totalBalance = balanceOf(account);
        uint256 frozenBalance = _frozenBalances[account];
        return totalBalance > frozenBalance ? totalBalance - frozenBalance : 0;
    }
    
    /**
     * @dev Freeze a specific amount of tokens for an address
     * @param account The address to freeze tokens for
     * @param amount The amount of tokens to freeze
     */
    function freezeAddress(address account, uint256 amount) external onlyOwner {
        if (account == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        
        uint256 accountBalance = balanceOf(account);
        uint256 currentFrozen = _frozenBalances[account];
        uint256 newFrozenAmount = currentFrozen + amount;
        
        if (newFrozenAmount > accountBalance) {
            revert InsufficientBalance(newFrozenAmount, accountBalance);
        }
        
        _frozenBalances[account] = newFrozenAmount;
        
        emit AddressFrozen(account, amount);
    }
    
    /**
     * @dev Unfreeze a specific amount of tokens for an address
     * @param account The address to unfreeze tokens for
     * @param amount The amount of tokens to unfreeze
     */
    function unfreezeAddress(address account, uint256 amount) external onlyOwner {
        if (account == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        
        uint256 currentFrozen = _frozenBalances[account];
        if (amount > currentFrozen) {
            revert InsufficientBalance(amount, currentFrozen);
        }
        
        _frozenBalances[account] = currentFrozen - amount;
        
        emit AddressUnfrozen(account, amount);
    }
    
    /**
     * @dev Override transfer to include fee mechanism and frozen balance check
     */
    function transfer(address to, uint256 amount) 
        public 
        override 
        nonReentrant 
        whenNotPaused 
        returns (bool) 
    {
        address from = msg.sender;
        return _transferWithFee(from, to, amount);
    }
    
    /**
     * @dev Override transferFrom to include fee mechanism and frozen balance check
     */
    function transferFrom(address from, address to, uint256 amount) 
        public 
        override 
        nonReentrant 
        whenNotPaused 
        returns (bool) 
    {
        address spender = msg.sender;
        _spendAllowance(from, spender, amount);
        return _transferWithFee(from, to, amount);
    }
    
    /**
     * @dev Internal function to handle transfers with fee mechanism
     * @param from The address sending tokens
     * @param to The address receiving tokens
     * @param amount The total amount of tokens to transfer (including fee)
     */
    function _transferWithFee(address from, address to, uint256 amount) 
        internal 
        returns (bool) 
    {
        if (from == address(0) || to == address(0)) revert InvalidAddress();
        if (amount == 0) revert ZeroTransfer();
        
        // Check if sender has sufficient unfrozen balance
        uint256 availableBalance = availableBalanceOf(from);
        if (amount > availableBalance) {
            revert InsufficientUnfrozenBalance(amount, availableBalance);
        }
        
        // Calculate fee amount (percentage of total transfer)
        uint256 feeAmount = (amount * feeRate) / BASIS_POINTS;
        uint256 transferAmount = amount - feeAmount;
        
        // Perform the transfer to recipient
        _transfer(from, to, transferAmount);
        
        // Handle fee: transfer fee amount to owner
        if (feeAmount > 0 && owner() != address(0)) {
            _transfer(from, owner(), feeAmount);
            emit TransferFeeCharged(from, feeAmount);
            emit FeeTransferred(owner(), feeAmount);
        }
        
        return true;
    }
    
    /**
     * @dev Override _update to include frozen balance checks for all transfer paths
     * FIXED: Now properly checks frozen balances for all transfers
     */
    function _update(address from, address to, uint256 value) 
        internal 
        override 
    {
        // Skip checks for minting and burning
        if (from == address(0) || to == address(0)) {
            super._update(from, to, value);
            return;
        }
        
        // Check frozen balance for all regular transfers
        // This ensures no transfer path can bypass frozen balance restrictions
        uint256 availableBalance = availableBalanceOf(from);
        if (value > availableBalance) {
            revert InsufficientUnfrozenBalance(value, availableBalance);
        }
        
        super._update(from, to, value);
    }
    
    /**
     * @dev Emergency pause function - only owner can pause/unpause
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @dev Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @dev Override renounceOwnership to prevent accidental ownership renouncement
     * This ensures there's always an owner to manage frozen addresses
     */
    function renounceOwnership() public view override onlyOwner {
        revert("MAC: ownership cannot be renounced");
    }
    
    /**
     * @dev Emergency function to recover any ERC20 tokens sent to this contract by mistake
     * @param tokenAddress The address of the token to recover
     * @param tokenAmount The amount of tokens to recover
     */
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner nonReentrant {
        if (tokenAddress == address(0)) revert InvalidAddress();
        if (tokenAddress == address(this)) revert("MAC: cannot recover MAC tokens");
        
        IERC20(tokenAddress).transfer(owner(), tokenAmount);
    }
    
    /**
     * @dev Get contract information
     * @return name_ Token name
     * @return symbol_ Token symbol  
     * @return decimals_ Token decimals
     * @return totalSupply_ Total token supply
     * @return owner_ Current owner address
     * @return feeRate_ Current fee rate in basis points
     */
    function getContractInfo() external view returns (
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 totalSupply_,
        address owner_,
        uint256 feeRate_
    ) {
        return (
            name(),
            symbol(),
            decimals(),
            totalSupply(),
            owner(),
            feeRate
        );
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @dev Interface of the ERC-20 standard
 */
interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

/**
 * @dev Interface for ERC-20 metadata
 */
interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

/**
 * @dev ERC-20 Errors
 */
interface IERC20Errors {
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error ERC20InvalidSender(address sender);
    error ERC20InvalidReceiver(address receiver);
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    error ERC20InvalidApprover(address approver);
    error ERC20InvalidSpender(address spender);
}

/**
 * @dev Simplified Context for msg.sender
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

/**
 * @dev Factory-Deployable ERC-20 Token Implementation
 * This is a concrete implementation that can be deployed by a factory
 */
contract FactoryERC20 is Context, IERC20, IERC20Metadata, IERC20Errors {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    
    uint256 private _totalSupply;
    string private _name;
    string private _symbol;
    uint8 private _decimals;
    address private _creator;
    
    /**
     * @dev Initializes the token with name, symbol, decimals, and initial supply
     * This replaces the constructor for factory deployment
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 initialSupply_,
        address creator_
    ) external {
        require(bytes(_name).length == 0, "Already initialized");
        require(creator_ != address(0), "Invalid creator");
        
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        _creator = creator_;
        
        if (initialSupply_ > 0) {
            _totalSupply = initialSupply_;
            _balances[creator_] = initialSupply_;
            emit Transfer(address(0), creator_, initialSupply_);
        }
    }
    
    function name() public view virtual returns (string memory) {
        return _name;
    }
    
    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }
    
    function decimals() public view virtual returns (uint8) {
        return _decimals;
    }
    
    function totalSupply() public view virtual returns (uint256) {
        return _totalSupply;
    }
    
    function balanceOf(address account) public view virtual returns (uint256) {
        return _balances[account];
    }
    
    function creator() public view returns (address) {
        return _creator;
    }
    
    function transfer(address to, uint256 value) public virtual returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, value);
        return true;
    }
    
    function allowance(address owner, address spender) public view virtual returns (uint256) {
        return _allowances[owner][spender];
    }
    
    function approve(address spender, uint256 value) public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, value);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 value) public virtual returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        return true;
    }
    
    function _transfer(address from, address to, uint256 value) internal {
        if (from == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        if (to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(from, to, value);
    }
    
    function _update(address from, address to, uint256 value) internal virtual {
        if (from == address(0)) {
            _totalSupply += value;
        } else {
            uint256 fromBalance = _balances[from];
            if (fromBalance < value) {
                revert ERC20InsufficientBalance(from, fromBalance, value);
            }
            unchecked {
                _balances[from] = fromBalance - value;
            }
        }
        
        if (to == address(0)) {
            unchecked {
                _totalSupply -= value;
            }
        } else {
            unchecked {
                _balances[to] += value;
            }
        }
        
        emit Transfer(from, to, value);
    }
    
    function _approve(address owner, address spender, uint256 value) internal {
        _approve(owner, spender, value, true);
    }
    
    function _approve(address owner, address spender, uint256 value, bool emitEvent) internal virtual {
        if (owner == address(0)) {
            revert ERC20InvalidApprover(address(0));
        }
        if (spender == address(0)) {
            revert ERC20InvalidSpender(address(0));
        }
        _allowances[owner][spender] = value;
        if (emitEvent) {
            emit Approval(owner, spender, value);
        }
    }
    
    function _spendAllowance(address owner, address spender, uint256 value) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance < type(uint256).max) {
            if (currentAllowance < value) {
                revert ERC20InsufficientAllowance(spender, currentAllowance, value);
            }
            unchecked {
                _approve(owner, spender, currentAllowance - value, false);
            }
        }
    }
}

/**
 * @dev Factory contract for deploying ERC-20 tokens
 */
contract TokenFactory {
    event TokenCreated(
        address indexed tokenAddress,
        address indexed creator,
        string name,
        string symbol,
        uint8 decimals,
        uint256 initialSupply
    );
    
    // Array of all deployed tokens
    address[] public deployedTokens;
    
    // Mapping from creator to their tokens
    mapping(address => address[]) public tokensByCreator;
    
    /**
     * @dev Creates a new ERC-20 token
     * @param name_ Token name
     * @param symbol_ Token symbol
     * @param decimals_ Number of decimals (typically 18)
     * @param initialSupply_ Initial supply (will be minted to creator)
     * @return token Address of the newly created token
     */
    function createToken(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 initialSupply_
    ) external returns (address token) {
        // Deploy new token contract
        FactoryERC20 newToken = new FactoryERC20();
        
        // Initialize the token
        newToken.initialize(name_, symbol_, decimals_, initialSupply_, msg.sender);
        
        token = address(newToken);
        
        // Track the deployed token
        deployedTokens.push(token);
        tokensByCreator[msg.sender].push(token);
        
        emit TokenCreated(token, msg.sender, name_, symbol_, decimals_, initialSupply_);
        
        return token;
    }
    
    /**
     * @dev Get total number of tokens deployed by this factory
     */
    function getTotalTokens() external view returns (uint256) {
        return deployedTokens.length;
    }
    
    /**
     * @dev Get all tokens created by a specific address
     */
    function getTokensByCreator(address creator) external view returns (address[] memory) {
        return tokensByCreator[creator];
    }
    
    /**
     * @dev Get token at specific index
     */
    function getTokenAtIndex(uint256 index) external view returns (address) {
        require(index < deployedTokens.length, "Index out of bounds");
        return deployedTokens[index];
    }
}

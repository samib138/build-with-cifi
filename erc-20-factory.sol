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
 * @dev ERC-20 custom errors for gas efficiency
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
 * @dev Provides msg.sender context
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

/**
 * @dev ReentrancyGuard for protection against reentrant calls
 */
abstract contract ReentrancyGuard {
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;
    uint256 private _status;

    error ReentrancyGuardReentrantCall();

    constructor() {
        _status = NOT_ENTERED;
    }

    modifier nonReentrant() {
        if (_status == ENTERED) {
            revert ReentrancyGuardReentrantCall();
        }
        _status = ENTERED;
        _;
        _status = NOT_ENTERED;
    }
}

/**
 * @title FactoryERC20
 * @dev Improved factory-deployable ERC-20 implementation with security fixes
 * @notice This contract implements a secure, gas-optimized ERC-20 token designed for factory deployment
 */
contract FactoryERC20 is Context, IERC20, IERC20Metadata, IERC20Errors, ReentrancyGuard {
    // Storage layout optimized for gas (packed into fewer slots)
    address private _creator;           // slot 0 (20 bytes)
    uint8 private _decimals;            // slot 0 (1 byte) - PACKED!
    bool private _initialized;          // slot 0 (1 byte) - PACKED!
    
    uint256 private _totalSupply;       // slot 1
    string private _name;               // slot 2+
    string private _symbol;             // slot 3+
    
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    
    // Immutable factory address for access control
    address private immutable FACTORY;
    
    // Events
    event TokenInitialized(
        string name,
        string symbol,
        uint8 decimals,
        uint256 initialSupply,
        address indexed creator
    );
    
    // Custom errors
    error AlreadyInitialized();
    error OnlyFactory();
    error InvalidParameter(string param);
    
    /**
     * @dev Sets the factory address on deployment
     * @notice Only the deployer (factory) can initialize this token
     */
    constructor() {
        FACTORY = msg.sender;
    }
    
    /**
     * @dev Initializes the token with parameters
     * @notice Can only be called once by the factory contract
     * @param name_ Token name (1-32 characters)
     * @param symbol_ Token symbol (1-10 characters)
     * @param decimals_ Decimals (max 18, typically 18)
     * @param initialSupply_ Initial supply in base units
     * @param creator_ Address to receive initial supply
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 initialSupply_,
        address creator_
    ) external nonReentrant {
        // Access control: only factory can initialize
        if (msg.sender != FACTORY) revert OnlyFactory();
        
        // Prevent double initialization
        if (_initialized) revert AlreadyInitialized();
        
        // Input validation
        if (bytes(name_).length == 0 || bytes(name_).length > 32) {
            revert InvalidParameter("name");
        }
        if (bytes(symbol_).length == 0 || bytes(symbol_).length > 10) {
            revert InvalidParameter("symbol");
        }
        if (decimals_ > 18) {
            revert InvalidParameter("decimals");
        }
        if (creator_ == address(0)) {
            revert InvalidParameter("creator");
        }
        if (initialSupply_ == 0) {
            revert InvalidParameter("initialSupply");
        }
        // Prevent overflow issues with extremely large supplies
        if (initialSupply_ > type(uint128).max) {
            revert InvalidParameter("initialSupply too large");
        }
        
        // Initialize state
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        _creator = creator_;
        _initialized = true;
        
        // Mint initial supply
        _totalSupply = initialSupply_;
        _balances[creator_] = initialSupply_;
        
        emit TokenInitialized(name_, symbol_, decimals_, initialSupply_, creator_);
        emit Transfer(address(0), creator_, initialSupply_);
    }
    
    /**
     * @dev Returns the name of the token
     */
    function name() public view virtual returns (string memory) {
        return _name;
    }
    
    /**
     * @dev Returns the symbol of the token
     */
    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }
    
    /**
     * @dev Returns the decimals of the token
     */
    function decimals() public view virtual returns (uint8) {
        return _decimals;
    }
    
    /**
     * @dev Returns the total supply of tokens
     */
    function totalSupply() public view virtual returns (uint256) {
        return _totalSupply;
    }
    
    /**
     * @dev Returns the balance of an account
     */
    function balanceOf(address account) public view virtual returns (uint256) {
        return _balances[account];
    }
    
    /**
     * @dev Returns the creator address
     */
    function creator() public view returns (address) {
        return _creator;
    }
    
    /**
     * @dev Returns the factory address
     */
    function factory() public view returns (address) {
        return FACTORY;
    }
    
    /**
     * @dev Returns whether the token has been initialized
     */
    function initialized() public view returns (bool) {
        return _initialized;
    }
    
    /**
     * @dev Transfers tokens to a recipient
     */
    function transfer(address to, uint256 value) public virtual returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, value);
        return true;
    }
    
    /**
     * @dev Returns the allowance of a spender for an owner
     */
    function allowance(address owner, address spender) public view virtual returns (uint256) {
        return _allowances[owner][spender];
    }
    
    /**
     * @dev Approves a spender to spend tokens
     */
    function approve(address spender, uint256 value) public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, value);
        return true;
    }
    
    /**
     * @dev Transfers tokens from one address to another using allowance
     */
    function transferFrom(address from, address to, uint256 value) public virtual returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        return true;
    }
    
    /**
     * @dev Internal transfer function
     */
    function _transfer(address from, address to, uint256 value) internal {
        if (from == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        if (to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(from, to, value);
    }
    
    /**
     * @dev Updates balances for transfers, mints, and burns
     */
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
    
    /**
     * @dev Internal approve function
     */
    function _approve(address owner, address spender, uint256 value) internal {
        _approve(owner, spender, value, true);
    }
    
    /**
     * @dev Internal approve with optional event emission
     */
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
    
    /**
     * @dev Spends allowance for transferFrom
     */
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
 * @title TokenFactory
 * @dev Improved factory for deploying ERC-20 tokens with security and gas optimizations
 * @notice This factory uses minimal proxy clones for gas-efficient token deployment
 */
contract TokenFactory is ReentrancyGuard {
    // Implementation contract for cloning
    address public immutable implementation;
    
    // Owner for potential future governance
    address public owner;
    
    // Token tracking with pagination support
    address[] private _deployedTokens;
    mapping(address => address[]) private _tokensByCreator;
    mapping(address => bool) private _isDeployedToken;
    
    // Configuration
    uint256 public constant MAX_TOKENS_PER_CREATOR = 100;
    uint256 public deploymentFee;
    
    // Events
    event TokenCreated(
        address indexed tokenAddress,
        address indexed creator,
        string name,
        string symbol,
        uint8 decimals,
        uint256 initialSupply,
        uint256 timestamp
    );
    
    event DeploymentFeeUpdated(uint256 oldFee, uint256 newFee);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    
    // Custom errors
    error MaxTokensReached();
    error InsufficientFee();
    error TransferFailed();
    error OnlyOwner();
    
    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }
    
    /**
     * @dev Deploys the implementation contract and sets up the factory
     */
    constructor() {
        implementation = address(new FactoryERC20());
        owner = msg.sender;
        deploymentFee = 0; // Free deployment by default
    }
    
    /**
     * @dev Creates a new ERC-20 token using minimal proxy pattern
     * @param name_ Token name (1-32 characters)
     * @param symbol_ Token symbol (1-10 characters)  
     * @param decimals_ Number of decimals (max 18, typically 18)
     * @param initialSupply_ Initial supply in base units (must be > 0)
     * @return token Address of the newly created token
     */
    function createToken(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 initialSupply_
    ) external payable nonReentrant returns (address token) {
        // Check deployment fee
        if (msg.value < deploymentFee) revert InsufficientFee();
        
        // Check creator token limit
        if (_tokensByCreator[msg.sender].length >= MAX_TOKENS_PER_CREATOR) {
            revert MaxTokensReached();
        }
        
        // Deploy minimal proxy clone
        token = _clone(implementation);
        
        // Initialize the token (now protected by factory-only access)
        FactoryERC20(token).initialize(
            name_,
            symbol_,
            decimals_,
            initialSupply_,
            msg.sender
        );
        
        // Track the deployed token
        _deployedTokens.push(token);
        _tokensByCreator[msg.sender].push(token);
        _isDeployedToken[token] = true;
        
        emit TokenCreated(
            token,
            msg.sender,
            name_,
            symbol_,
            decimals_,
            initialSupply_,
            block.timestamp
        );
        
        return token;
    }
    
    /**
     * @dev Minimal proxy clone implementation (EIP-1167)
     * @param implementation_ Address of implementation contract
     * @return instance Address of the clone
     */
    function _clone(address implementation_) private returns (address instance) {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(ptr, 0x14), shl(0x60, implementation_))
            mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            instance := create(0, ptr, 0x37)
        }
        require(instance != address(0), "Clone failed");
    }
    
    /**
     * @dev Get total number of tokens deployed by this factory
     */
    function getTotalTokens() external view returns (uint256) {
        return _deployedTokens.length;
    }
    
    /**
     * @dev Get all tokens created by a specific address
     * @param creator Address of the token creator
     */
    function getTokensByCreator(address creator) external view returns (address[] memory) {
        return _tokensByCreator[creator];
    }
    
    /**
     * @dev Get paginated list of deployed tokens
     * @param offset Starting index
     * @param limit Maximum number of tokens to return
     */
    function getTokensPaginated(uint256 offset, uint256 limit) 
        external 
        view 
        returns (address[] memory tokens, uint256 total) 
    {
        total = _deployedTokens.length;
        
        if (offset >= total) {
            return (new address[](0), total);
        }
        
        uint256 end = offset + limit;
        if (end > total) {
            end = total;
        }
        
        uint256 size = end - offset;
        tokens = new address[](size);
        
        for (uint256 i = 0; i < size; i++) {
            tokens[i] = _deployedTokens[offset + i];
        }
        
        return (tokens, total);
    }
    
    /**
     * @dev Check if an address is a token deployed by this factory
     * @param token Address to check
     */
    function isDeployedToken(address token) external view returns (bool) {
        return _isDeployedToken[token];
    }
    
    /**
     * @dev Get token at specific index
     * @param index Index in the deployed tokens array
     */
    function getTokenAtIndex(uint256 index) external view returns (address) {
        require(index < _deployedTokens.length, "Index out of bounds");
        return _deployedTokens[index];
    }
    
    /**
     * @dev Update deployment fee (only owner)
     * @param newFee New fee in wei
     */
    function setDeploymentFee(uint256 newFee) external onlyOwner {
        uint256 oldFee = deploymentFee;
        deploymentFee = newFee;
        emit DeploymentFeeUpdated(oldFee, newFee);
    }
    
    /**
     * @dev Withdraw collected fees (only owner)
     */
    function withdrawFees() external onlyOwner {
        uint256 balance = address(this).balance;
        (bool success, ) = owner.call{value: balance}("");
        if (!success) revert TransferFailed();
    }
    
    /**
     * @dev Transfer ownership (only owner)
     * @param newOwner Address of the new owner
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid address");
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
    
    /**
     * @dev Get number of tokens created by an address
     * @param creator Address of the creator
     */
    function getCreatorTokenCount(address creator) external view returns (uint256) {
        return _tokensByCreator[creator].length;
    }
}

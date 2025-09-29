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
 * @dev Pausable contract for emergency stops
 */
abstract contract Pausable is Context {
    bool private _paused;
    address private _pauser;

    event Paused(address account);
    event Unpaused(address account);
    event PauserTransferred(address indexed previousPauser, address indexed newPauser);

    error EnforcedPause();
    error ExpectedPause();
    error OnlyPauser();

    constructor(address pauser_) {
        _pauser = pauser_;
    }

    modifier onlyPauser() {
        if (_msgSender() != _pauser) revert OnlyPauser();
        _;
    }

    modifier whenNotPaused() {
        if (_paused) revert EnforcedPause();
        _;
    }

    modifier whenPaused() {
        if (!_paused) revert ExpectedPause();
        _;
    }

    function paused() public view virtual returns (bool) {
        return _paused;
    }

    function pauser() public view virtual returns (address) {
        return _pauser;
    }

    function pause() public virtual onlyPauser {
        _paused = true;
        emit Paused(_msgSender());
    }

    function unpause() public virtual onlyPauser {
        _paused = false;
        emit Unpaused(_msgSender());
    }

    function transferPauser(address newPauser) public virtual onlyPauser {
        require(newPauser != address(0), "Invalid pauser address");
        address oldPauser = _pauser;
        _pauser = newPauser;
        emit PauserTransferred(oldPauser, newPauser);
    }
}

/**
 * @title FactoryERC20
 * @dev Factory-deployable ERC-20 with pausable functionality
 */
contract FactoryERC20 is Context, IERC20, IERC20Metadata, IERC20Errors, ReentrancyGuard, Pausable {
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
        address indexed creator,
        address indexed pauser
    );
    
    // Custom errors
    error AlreadyInitialized();
    error OnlyFactory();
    error InvalidParameter(string param);
    
    /**
     * @dev Sets the factory address on deployment
     */
    constructor() Pausable(address(0)) {
        FACTORY = msg.sender;
    }
    
    /**
     * @dev Initializes the token with parameters
     * @param name_ Token name (1-32 characters)
     * @param symbol_ Token symbol (1-10 characters)
     * @param decimals_ Decimals (max 18, typically 18)
     * @param initialSupply_ Initial supply in base units
     * @param creator_ Address to receive initial supply
     * @param pauser_ Address that can pause/unpause the token
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 initialSupply_,
        address creator_,
        address pauser_
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
        if (pauser_ == address(0)) {
            revert InvalidParameter("pauser");
        }
        if (initialSupply_ == 0) {
            revert InvalidParameter("initialSupply");
        }
        if (initialSupply_ > type(uint128).max) {
            revert InvalidParameter("initialSupply too large");
        }
        
        // Initialize state
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        _creator = creator_;
        _initialized = true;
        
        // Set pauser
        _pauser = pauser_;
        
        // Mint initial supply
        _totalSupply = initialSupply_;
        _balances[creator_] = initialSupply_;
        
        emit TokenInitialized(name_, symbol_, decimals_, initialSupply_, creator_, pauser_);
        emit Transfer(address(0), creator_, initialSupply_);
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
    
    function factory() public view returns (address) {
        return FACTORY;
    }
    
    function initialized() public view returns (bool) {
        return _initialized;
    }
    
    /**
     * @dev Transfer tokens - can be paused
     */
    function transfer(address to, uint256 value) public virtual whenNotPaused returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, value);
        return true;
    }
    
    function allowance(address owner, address spender) public view virtual returns (uint256) {
        return _allowances[owner][spender];
    }
    
    /**
     * @dev Approve spender - can be paused
     */
    function approve(address spender, uint256 value) public virtual whenNotPaused returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, value);
        return true;
    }
    
    /**
     * @dev Transfer from - can be paused
     */
    function transferFrom(address from, address to, uint256 value) public virtual whenNotPaused returns (bool) {
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
 * @title TokenFactory
 * @dev Factory for deploying ERC-20 tokens with USDC deployment fee
 * @notice Requires $20 USDC fee to create tokens
 */
contract TokenFactory is ReentrancyGuard, Pausable {
    // USDC token address (Ethereum mainnet)
    // For testing, replace with your testnet USDC address
    IERC20 public immutable USDC;
    
    // Implementation contract for cloning
    address public immutable implementation;
    
    // Owner for governance
    address public owner;
    
    // Fee configuration
    uint256 public constant DEPLOYMENT_FEE = 20 * 10**6; // $20 USDC (6 decimals)
    
    // Token tracking
    address[] private _deployedTokens;
    mapping(address => address[]) private _tokensByCreator;
    mapping(address => bool) private _isDeployedToken;
    
    uint256 public constant MAX_TOKENS_PER_CREATOR = 100;
    
    // Events
    event TokenCreated(
        address indexed tokenAddress,
        address indexed creator,
        address indexed pauser,
        string name,
        string symbol,
        uint8 decimals,
        uint256 initialSupply,
        uint256 timestamp
    );
    
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event USDCWithdrawn(address indexed to, uint256 amount);
    
    // Custom errors
    error MaxTokensReached();
    error InsufficientUSDCAllowance();
    error USDCTransferFailed();
    error TransferFailed();
    error OnlyOwner();
    error InvalidAddress();
    
    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }
    
    /**
     * @dev Deploys the factory with USDC address
     * @param usdc_ Address of USDC token contract
     * @param pauser_ Address that can pause the factory
     */
    constructor(address usdc_, address pauser_) Pausable(pauser_) {
        if (usdc_ == address(0)) revert InvalidAddress();
        
        USDC = IERC20(usdc_);
        implementation = address(new FactoryERC20());
        owner = msg.sender;
    }
    
    /**
     * @dev Creates a new ERC-20 token
     * @notice Requires USDC approval of at least $20 before calling
     * @param name_ Token name (1-32 characters)
     * @param symbol_ Token symbol (1-10 characters)  
     * @param decimals_ Number of decimals (max 18, typically 18)
     * @param initialSupply_ Initial supply in base units
     * @param pauser_ Address that can pause the created token
     * @return token Address of the newly created token
     */
    function createToken(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 initialSupply_,
        address pauser_
    ) external nonReentrant whenNotPaused returns (address token) {
        // Check creator token limit
        if (_tokensByCreator[msg.sender].length >= MAX_TOKENS_PER_CREATOR) {
            revert MaxTokensReached();
        }
        
        // Check USDC allowance
        uint256 allowance = USDC.allowance(msg.sender, address(this));
        if (allowance < DEPLOYMENT_FEE) {
            revert InsufficientUSDCAllowance();
        }
        
        // Collect USDC fee
        bool success = USDC.transferFrom(msg.sender, address(this), DEPLOYMENT_FEE);
        if (!success) {
            revert USDCTransferFailed();
        }
        
        // Deploy minimal proxy clone
        token = _clone(implementation);
        
        // Initialize the token
        FactoryERC20(token).initialize(
            name_,
            symbol_,
            decimals_,
            initialSupply_,
            msg.sender,
            pauser_
        );
        
        // Track the deployed token
        _deployedTokens.push(token);
        _tokensByCreator[msg.sender].push(token);
        _isDeployedToken[token] = true;
        
        emit TokenCreated(
            token,
            msg.sender,
            pauser_,
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
     */
    function _clone(address implementation_) private returns (address instance) {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x3d602d80600a3d3981f3363d3d3d363d73000000000000000000000000000000)
            mstore(add(ptr, 0x14), shl(0x60, implementation_))
            mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            instance := create(0, ptr, 0x37)
        }
        require(instance != address(0), "Clone failed");
    }
    
    /**
     * @dev Get total number of tokens deployed
     */
    function getTotalTokens() external view returns (uint256) {
        return _deployedTokens.length;
    }
    
    /**
     * @dev Get all tokens created by a specific address
     */
    function getTokensByCreator(address creator) external view returns (address[] memory) {
        return _tokensByCreator[creator];
    }
    
    /**
     * @dev Get paginated list of deployed tokens
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
     */
    function isDeployedToken(address token) external view returns (bool) {
        return _isDeployedToken[token];
    }
    
    /**
     * @dev Get token at specific index
     */
    function getTokenAtIndex(uint256 index) external view returns (address) {
        require(index < _deployedTokens.length, "Index out of bounds");
        return _deployedTokens[index];
    }
    
    /**
     * @dev Withdraw collected USDC fees (only owner)
     */
    function withdrawUSDC(address to) external onlyOwner {
        if (to == address(0)) revert InvalidAddress();
        
        uint256 balance = USDC.balanceOf(address(this));
        require(balance > 0, "No USDC to withdraw");
        
        bool success = USDC.transfer(to, balance);
        if (!success) revert USDCTransferFailed();
        
        emit USDCWithdrawn(to, balance);
    }
    
    /**
     * @dev Get current USDC balance in factory
     */
    function getUSDCBalance() external view returns (uint256) {
        return USDC.balanceOf(address(this));
    }
    
    /**
     * @dev Transfer ownership (only owner)
     */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidAddress();
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
    
    /**
     * @dev Get number of tokens created by an address
     */
    function getCreatorTokenCount(address creator) external view returns (uint256) {
        return _tokensByCreator[creator].length;
    }
    
    /**
     * @dev Emergency withdrawal of any ERC20 tokens (only owner)
     * @notice Use for recovering accidentally sent tokens
     */
    function emergencyWithdrawToken(address token, address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert InvalidAddress();
        require(token != address(0), "Invalid token");
        
        bool success = IERC20(token).transfer(to, amount);
        if (!success) revert TransferFailed();
    }
}

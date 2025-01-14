// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import "../../interfaces/IWeweReceiver.sol";
import "../../interfaces/IAMM.sol";

struct Vesting {
    uint256 amount;
    uint256 end;
    uint256 merged;
}

contract DynamicEater is IWeweReceiver, ReentrancyGuard, Pausable, Ownable {
    int256 internal constant RATE_PRECISION = 100_000;
    address internal token;
    address public wewe;
    address public treasury;

    uint256 internal _totalVested;
    uint256 public totalMerged;
    uint256 public maxSupply; // Max supply of tokens to eat
    uint32 public vestingDuration;

    mapping(address => Vesting) public vestings;
    bytes32 public merkleRoot;

    // Initial virtual balances
    uint256 public virtualToken; // Virtual Token balance
    uint256 public virtualWEWE; // WEWE balance

    uint256 constant SCALING_FACTOR = 1_000;
    address public adaptor; // AMM to use for selling

    function name() external view returns (string memory) {
        return string.concat("WeWe: ", IERC20Metadata(token).name());
    }

    function _getWeweBalance() internal view returns (uint256) {
        // Virtual WEWE balance in 10^18 and total vested in 10^18
        require(virtualWEWE >= _totalVested, "_getWeweBalance: virtualWEWE less than total vested");
        return virtualWEWE - _totalVested;
    }

    function getCurrentPrice() public view returns (uint256) {
        // Calculate the price with scaling factor (p = Y / X)
        // Price in percentage, scaled by 1000 (i.e., 1.25% would be 12.5 scaled by 1000)
        uint256 _weweBalance = _getWeweBalance();
        return (_weweBalance * SCALING_FACTOR) / virtualToken;
    }

    function canClaim(address account) external view returns (bool) {
        return vestings[account].end <= block.timestamp;
    }

    function balanceOf(address account) external view returns (uint256) {
        return vestings[account].amount;
    }

    function getToken() external view returns (address) {
        return token;
    }

    function getRate() external view returns (uint256) {
        uint256 decimals = IERC20Metadata(token).decimals();
        return _calculateTokensOut(10 ** decimals);
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    function totalVested() external view returns (uint256) {
        return _totalVested;
    }

    constructor(address _wewe, address _token, uint32 _vestingDuration, uint256 _virtualToken, uint256 _virtualWEWE) {
        require(_wewe != address(0), "DynamicEater: Invalid WEWE address");
        require(_token != address(0), "DynamicEater: Invalid token address");
        wewe = _wewe;
        token = _token;
        vestingDuration = _vestingDuration;

        uint256 decimals = IERC20Metadata(_token).decimals();
        if (decimals < 18) {
            _virtualToken = _virtualToken * (10 ** (18 - decimals));
        }

        // Initial virtual balances in 10^18
        virtualToken = _virtualToken;
        virtualWEWE = _virtualWEWE;
    }

    function setMerkleRoot(bytes32 root) external onlyOwner {
        merkleRoot = root;
    }

    function setAdaptor(address amm) external onlyOwner {
        // Set to address zero to disable selling
        adaptor = amm;

        // Approve the AMM to use the tokens now in this contract
        if (adaptor != address(0)) {
            IERC20(token).approve(adaptor, type(uint256).max);
        }
    }

    function setVirtualWeWEBalance(uint256 value) external onlyOwner {
        virtualWEWE = value;
    }

    function setVirtualTokenBalance(uint256 value) external onlyOwner {
        virtualToken = value;
    }

    function setMaxSupply(uint256 value) external onlyOwner {
        // Set to 0 to disable max supply
        maxSupply = value;
    }

    function calculateTokensOut(uint256 x) public view returns (uint256) {
        // Check casting where x is the token value
        uint256 decimals = IERC20Metadata(token).decimals();
        if (decimals < 18) {
            x = x * (10 ** (18 - IERC20Metadata(token).decimals()));
        }

        return _calculateTokensOut(x);
    }

    function _calculateTokensOut(uint256 x) private view returns (uint256) {
        // Let X be the virtual balance of FOMO.  Leave for readibility
        uint256 X = virtualToken;
        uint256 newTokenBalance = X + x;

        // Let Y be the virtual balance of WEWE. Leave for readibility
        uint256 Y = virtualWEWE;
        Y = _getWeweBalance();

        // y = (x*Y) / (x+X)
        uint256 y = (x * Y) / newTokenBalance;

        return y;
    }

    function _merge(uint256 amount, address from) internal returns (uint256) {
        require(maxSupply >= amount + totalMerged || maxSupply == 0, "_merge: More than max supply");
        
        // x = amount in 10^18 and result is 10^18
        uint256 weweToTransfer = _calculateTokensOut(amount);

        require(
            weweToTransfer <= IERC20(wewe).balanceOf(address(this)),
            "_merge: Insufficient token balance to transfer"
        );

        // If transfer, dont vest
        if (vestingDuration != 0) {
            // Curent vested
            uint256 vestedAmount = vestings[from].amount;
            uint256 merged = vestings[from].merged;
            vestings[from] = Vesting({
                amount: weweToTransfer + vestedAmount,
                end: block.timestamp + vestingDuration * 1 minutes,
                merged: merged + amount
            });

            // 10^18
            _totalVested += weweToTransfer;
        } else {
            // Transfer Wewe tokens to sender in 10^18
            IERC20(wewe).transfer(from, weweToTransfer);
        }

        totalMerged += amount;
        emit Merged(amount, from, weweToTransfer);

        return weweToTransfer;
    }

    function merge(uint256 amount) external virtual whenNotPaused returns (uint256) {
        uint256 balance = IERC20(token).balanceOf(msg.sender);
        require(balance >= amount, "merge: Insufficient balance to eat");
        require(merkleRoot == bytes32(0), "merge: White list is set");

        // Transfer the tokens to this contract in native decimals
        IERC20(token).transferFrom(msg.sender, address(this), amount);

        _dump(amount);

        // Check coins decimals.  Assume the input is in the same decimals as the token
        uint256 decimals = IERC20Metadata(token).decimals();
        if (decimals < 18) {
            amount = amount * (10 ** (18 - decimals));
        }

        return _merge(amount, msg.sender);
    }

    function mergeWithProof(
        uint256 allocation,
        uint256 amount,
        bytes32[] calldata proof
    ) external virtual nonReentrant whenNotPaused returns (uint256) {
        require(merkleRoot != bytes32(0), "mergeWithProof: White list not set");

        // Hash amount and address
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(msg.sender, allocation))));
        require(_validateLeaf(proof, leaf), "mergeWithProof: Invalid proof");

        if (amount > allocation - vestings[msg.sender].merged) {
            // Only merge the delta
            amount = allocation - vestings[msg.sender].merged;
        }

        require(amount > 0, "mergeWithProof: Already merged");
        require(allocation >= amount, "mergeWithProof: Insufficient allocation");
        return _transferAndMerge(amount, msg.sender, address(this));
    }

    function mergeAll() external virtual whenNotPaused returns (uint256) {
        require(merkleRoot == bytes32(0), "merge: White list is set");
        uint256 balance = IERC20(token).balanceOf(msg.sender);
        return _transferAndMerge(balance, msg.sender, address(this));
    }

    function _transferAndMerge(uint256 amount, address from, address recipient) internal returns (uint256) {
        // Transfer the tokens to this contract in native decimals
        IERC20(token).transferFrom(from, recipient, amount);

        _dump(amount);

        // Check coins decimals
        uint256 decimals = IERC20Metadata(token).decimals();
        if (decimals < 18) {
            amount = amount * (10 ** (18 - decimals));
        }

        return _merge(amount, from);
    }

    function claim() external whenNotPaused whenClaimable(msg.sender) {
        uint256 amount = vestings[msg.sender].amount;
        vestings[msg.sender].amount = 0;

        IERC20(wewe).transfer(msg.sender, amount);
    }

    // @notice Fund this contract with wewe token
    function deposit(uint256 amount) external onlyOwner {
        _deposit(amount);
    }

    function dump() external {
        uint256 balance = IERC20(wewe).balanceOf(address(this));
        require(balance > 0, "dump: No balance to dump");
        uint256 sold = _dump(balance);

        emit Dumped(sold);
    }

    function _dump(uint256 amount) internal returns (uint256) {
        if (adaptor == address(0)) {
            return 0;
        }

        if (treasury == address(0)) {
            return 0;
        }

        // Sell the Wewe tokens for the underlying token... This is the sell function
        // function sell(uint256 amount, address token, address recipient, bytes calldata extraData)
        return IAMM(adaptor).sell(amount, token, treasury, "");
    }

    function sweep() external onlyOwner {
        uint256 balance = IERC20(wewe).balanceOf(address(this));
        require(balance > 0, "sweep: No balance to sweep");
        IERC20(wewe).transfer(owner(), balance);
    }

    /// @notice Wewe token approveAndCall function
    function receiveApproval(
        address from,
        uint256 amount,
        address,
        bytes calldata
    ) external nonReentrant whenNotPaused {
        // After wewe approve and call, it will call this function
        require(token != address(0), "receiveApproval: Token address not set");

        // Transfer the tokens to this contract in native decimals
        IERC20(token).transferFrom(msg.sender, address(this), amount);

        // Eat the underlying token "token" with the amount of "amount"
        _merge(amount, from);
    }

    function togglePause() external onlyOwner {
        paused() ? _unpause() : _pause();
    }

    function setVestingDuration(uint32 duration) external onlyOwner {
        vestingDuration = duration;
    }

    function _deposit(uint256 amount) internal {
        IERC20(wewe).transferFrom(msg.sender, address(this), amount);
    }

    function _validateLeaf(bytes32[] memory proof, bytes32 leaf) private view returns (bool) {
        // Verify the Merkle proof
        bool isValid = MerkleProof.verify(proof, merkleRoot, leaf);
        return isValid;
    }

    modifier whenClaimable(address account) {
        // Set to 0 to disable vesting
        if (vestingDuration == 0) {
            _;
        }

        require(vestings[account].end <= block.timestamp, "whenClaimable: Vesting not ended");
        _;
    }

    modifier whenSolvent(uint256 amountToMerge) {
        require(
            IERC20(wewe).balanceOf(address(this)) >= _totalVested + amountToMerge,
            "whenSolvent: Insufficient Wewe balance"
        );
        _;
    }

    event Dumped(uint256 amount);
    event Merged(uint256 amount, address indexed account, uint256 weweAmount);
    event RateChanged(uint256 newRate);
}

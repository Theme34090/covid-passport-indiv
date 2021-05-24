pragma solidity >=0.6.12;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v3.4.0/contracts/math/SafeMath.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v3.4.0/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v3.4.0/contracts/access/Ownable.sol";
import "./SafeToken.sol";

contract Hospital is ERC20, Ownable {
    using SafeMath for uint;
    using SafeToken for address;
    
    event ClaimRequested(address indexed beneficiary, uint indexed amount);
    event ClaimApproval(address indexed approvedBy, address indexed beneficiary);
    event ClaimFinished(address indexed beneficiary, uint indexed amount);
    event PassportIssued(address indexed issuer, address indexed issuedFor);
    event WithdrawRequested(address indexed withdrawer, uint indexed amount);
    event WithdrawFinished(address indexed withdrawer, uint indexed amount);
    
    enum VaccineName { SINOVAC, ASTRAZENECA, PFIZER }
    struct Passport {
        uint issueDate;
        uint expiryDate;
        VaccineName vaccineUsed;
        uint lotNumber;
        bool isValid;
        bool isPaid;
    }
    
    struct Claim {
        uint amount;
        address[] approvedBy;
        uint deadline;
        bool isClaimed;
    }
    
    uint constant DAY = 24*60*60;
    
    mapping(address => Passport) private _passports;
    mapping(address => Claim) private _claims;
    uint public capacity;
    uint public price;
    uint public reserves;
    uint public withdrawCountdown;
    bool public isGoingToWithdraw;
    uint public withdrawAmount;
    
    constructor(address owner, string memory name_, string memory symbol_, uint cap_, uint price_) ERC20(name_, symbol_) public {
        transferOwnership(owner);
        capacity = cap_;
        price = price_;
        reserves = 0;
        isGoingToWithdraw = false;
        withdrawAmount = 0;
    }
    
    function getVaccineName() external view returns (VaccineName, VaccineName, VaccineName) {
        return (VaccineName.SINOVAC, VaccineName.ASTRAZENECA, VaccineName.PFIZER);
    }

    // Passport
    function passportOf(address patient) external view returns (uint issueDate, uint expiryDate, bool isValid) {
        Passport memory passport = _passports[patient];
        return (passport.issueDate, passport.expiryDate, passport.isValid);
    }
    
    function issuePassport(address patient, VaccineName vaccineUsed, uint lotNumber_) external onlyOwner {
        Passport memory newPassport = Passport(block.timestamp, block.timestamp.add(90*DAY), vaccineUsed, lotNumber_, false, false);
        _passports[patient] = newPassport;
        emit PassportIssued(owner(), patient);
    }
    
    function isPassportValid(address patient) external view returns (bool) {
        Passport memory passport = _passports[patient];
        return passport.issueDate > 0 && passport.expiryDate > block.timestamp && passport.isValid;
    }
    
    // Reserves
    function requestWithdrawReserves(uint amount) external onlyOwner {
        require(amount <= reserves, "amount exceeds reserves");
        isGoingToWithdraw = true;
        withdrawCountdown = block.timestamp + 90*DAY;
        withdrawAmount = amount;
        emit WithdrawRequested(owner(), amount);
    }
    
    function withdrawReserves() external onlyOwner {
        require(isGoingToWithdraw == true, "withdrawal request hasn't been made");
        require(withdrawCountdown < block.timestamp, "not ready for withdrawal");
        reserves = reserves.sub(withdrawAmount);
        SafeToken.safeTransferBNB(owner(), withdrawAmount);
        isGoingToWithdraw = false;
        withdrawCountdown = 0;
        withdrawAmount = 0;
        emit WithdrawFinished(owner(), withdrawAmount);
    }
    
    // Claim
    function requestClaim() external {
        require(_passports[msg.sender].issueDate > 0, "passport doesn't exist");
        require(_claims[msg.sender].amount == 0, "claim already exist");
        uint amount = price.mul(2);
        Claim memory newClaim = Claim(amount, new address[](0), block.timestamp.add(30*DAY), false);
        _claims[msg.sender] = newClaim;
        emit ClaimRequested(msg.sender, amount);
    }
    
    function approveClaimFor(address beneficiary) external {
        require(msg.sender != beneficiary, "claimer can't approve for themselves");
        Claim storage claim = _claims[beneficiary];
        require(claim.amount > 0, "claim doesn't exist");
        require(claim.deadline > block.timestamp, "claim expired");
        claim.approvedBy.push(msg.sender);
        emit ClaimApproval(msg.sender, beneficiary);
    }
    
    function claim() external {
        Claim storage claim = _claims[msg.sender];
        require(claim.amount > 0, "claim doesn't exist");
        require(claim.deadline > block.timestamp, "claim expired");
        require(claim.approvedBy.length > 1, "need more approval");
        claim.isClaimed = true;
        Passport storage passport = _passports[msg.sender];
        passport.isValid = false;
        uint fromReserves = price.mul(50).div(100);
        require(fromReserves <= reserves, "insufficient reserves");
        require(claim.amount <= totalBNB(), "insufficient pool value");
        reserves = reserves.sub(fromReserves);
        SafeToken.safeTransferBNB(msg.sender, claim.amount);
        emit ClaimFinished(msg.sender, claim.amount);
    }

    // Payment
    function payFor(address payee) external payable {
        require(msg.value == price, "incorrect value");
        Passport storage passport = _passports[payee];
        require(passport.issueDate > 0, "passport doesn't exist");
        require(passport.isPaid == false, "passport already paid");
        uint toReserves = msg.value.mul(50).div(100);   // 50% goes to hospital, 50% goes to pool
        reserves = reserves.add(toReserves);
        passport.isValid = true;
        passport.isPaid = true;
    }
    
    // Pool
    function totalBNB() public view returns (uint) {
        return address(this).balance.sub(reserves);
    }    

    function deposit() external payable {
        uint total = totalBNB().sub(msg.value);
        uint share = total == 0 ? msg.value : msg.value.mul(totalSupply()).div(total);
        _mint(msg.sender, share);
    }

    function withdraw(uint share) external {
        uint amount = share.mul(totalBNB()).div(totalSupply());
        _burn(msg.sender, share);
        SafeToken.safeTransferBNB(msg.sender, amount);
        uint supply = totalSupply();
    }
}

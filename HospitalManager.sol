pragma solidity >=0.6.12;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v3.4.0/contracts/math/SafeMath.sol";
import "./Hospital.sol";
import "./SafeToken.sol";

contract HospitalManager {
    using SafeMath for uint;
    using SafeToken for address;
    
    uint constant DECIMALS = 10**18;
    
    event HospitalCreated(address indexed hospitalAddress, uint indexed hospitalIndex);
    
    address[] public hospitals;
    mapping (address => address) public hospitalMap;
    uint lastHospitalIndex;

    constructor() public {
        lastHospitalIndex = 0;
    }
    
    function createHospital(string memory name_, string memory symbol_, uint capacity_, uint price_) external payable {
        require(msg.value >= capacity_.mul(price_).mul(2), "insufficient initial fund");
        Hospital newHospital = new Hospital(msg.sender, name_, symbol_, capacity_, price_);
        newHospital.deposit{value: msg.value}();
        SafeToken.safeTransfer(address(newHospital), msg.sender, msg.value);
        hospitals.push(address(newHospital));
        hospitalMap[msg.sender] = address(newHospital);
        emit HospitalCreated(address(newHospital), lastHospitalIndex);
        lastHospitalIndex = lastHospitalIndex + 1;
    }
}

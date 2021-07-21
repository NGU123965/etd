pragma solidity ^0.5.8;

//判断地址类型(合约地址or账号地址)，限定地址调用合约功能(限定余额充足)

library Address {
    function isContract(address account) internal view returns (bool) {
        
        bytes32 codehash;
        
        // 空字符串hash值
        bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;  
        
        //内联编译
        assembly { codehash := extcodehash(account) }
        return (codehash != accountHash && codehash != 0x0);
    }
 
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");
        (bool success, ) = recipient.call.value(amount)("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }
}
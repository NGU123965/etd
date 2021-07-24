pragma solidity 0.5.8;
 
import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./IERC20.sol";
 
contract Pledge {
    using SafeMath for uint256;
    using SafeERC20 for ERC20;
 
    //合约拥有者账号地址
    address private owner;

    //收益分配者账号地址，仅该地址有权进行收益的分配
    address private profitor;

    //抵押合约功能状态，当为true时才可进行抵押
    bool _isDIS = false;
 
    mapping(address => PledgeOrder) _orders;
    mapping(address => uint256) _takeProfitTime;
 
    //用于分配收益的ERC20资产
    ERC20 _Token;

    //用于标记用户地址的抵押状态
    KeyFlag[] keys;
 
    //抵押者地址数量
    uint256 size;

    //最大抵押额度(底层代币)
    uint256 _maxPledgeAmount; 

    //最大挖矿额度(ERC20收益分配)
    uint256 _maxMiningAmount;

    //剩余挖矿额度
    uint256 _leftMiningAmount;

    //单次最少抵押额度
    uint256 _minAmount;

    //已抵押总额度
    uint256 _totalPledegAmount;

    //单次最大分配额度
    uint256 _maxPreMiningAmount;

    //开始时间与结束时间，单位秒
    uint256 _startTime;
    uint256 _endTime;

    //每次收益提取比例
    uint256 _precentUp = 100;
    uint256 _precentDown = 100;
 
    //标记抵押用户状态
    struct PledgeOrder {
        //抵押状态
        bool isExist;

        //抵押额度
        uint256 token;

        //收益额度
        uint256 profitToken;

        //最近一次提取收益时间
        uint256 time;
        
        //抵押地址序号
        uint256 index;
    }

    //标记用户地址的抵押状态
    struct KeyFlag {
        address key;
        bool isExist;
    }
 
    constructor (
        address tokenAddress,
        address paramProfitor,
        uint256 maxPledgeAmount,
        uint256 minAmount,
        uint256 maxMiningAmount,
        uint256 maxPreMiningAmount,
        uint256 startTime,
        uint256 endTime
    ) 
        public 
    {
        _Token = ERC20(tokenAddress);
        owner = msg.sender;
        profitor = paramProfitor;
        _maxPledgeAmount = maxPledgeAmount; 
		_minAmount = minAmount;   
        _maxMiningAmount = maxMiningAmount;
        _maxPreMiningAmount = maxPreMiningAmount;
        _startTime = startTime;
        _endTime = endTime;
        _leftMiningAmount = maxMiningAmount;
    }

    //抵押函数
    function pledgeToken() public payable{
        require(address(msg.sender) == address(tx.origin), "no contract");
        require(_isDIS, "is disable");
        require(_leftMiningAmount > 0, "less token");
        require(msg.value >= _minAmount, "less token");
        require(_totalPledegAmount.add(msg.value) <= _maxPledgeAmount, "more token"); 
        require(block.timestamp >= _startTime&&block.timestamp <= _endTime, "is disable");
 
        if(_orders[msg.sender].isExist == false){
            keys.push(KeyFlag(msg.sender,true));
            size++;
            createOrder(msg.value,keys.length.sub(1));
        }else{
            PledgeOrder storage order = _orders[msg.sender];
            order.token = order.token.add(msg.value);
            keys[order.index].isExist = true;
        }

        _totalPledegAmount = _totalPledegAmount.add(msg.value);
    }

    //检测到未抵押过的用户则进行档案记录   
    function createOrder(uint256 trcAmount,uint256 index) private {
        _orders[msg.sender] = PledgeOrder(
            true,
            trcAmount,
            0,
            block.timestamp,
            index
        );
    }

    //收益分配
    function profit() public onlyProfitor{
        require(_leftMiningAmount > 0, "less token");
        require(_totalPledegAmount > 0, "no pledge");
        uint256 preToken = _maxPreMiningAmount;
        if(_leftMiningAmount < _maxPreMiningAmount){
            preToken = _leftMiningAmount;
        }
        for(uint i = 0; i < keys.length; i++) {
            if(keys[i].isExist == true){
                PledgeOrder storage order = _orders[keys[i].key];
                order.profitToken = order.profitToken.add(order.token.mul(preToken).div(_totalPledegAmount));
            }
        }
        _leftMiningAmount = _leftMiningAmount.sub(preToken);
    }
 
    //收益提取
    function takeProfit() public {
        require(address(msg.sender) == address(tx.origin), "no contract");
        require(_orders[msg.sender].profitToken>0,"less token");
        uint256 time = block.timestamp;
        uint256 diff = time.sub(_takeProfitTime[msg.sender]);
        require(diff > 86400,"less time");
        PledgeOrder storage order = _orders[msg.sender];
        uint256 takeToken = order.profitToken.mul(_precentUp).div(_precentDown);
        order.profitToken = order.profitToken.sub(takeToken);
        _takeProfitTime[msg.sender] = time;
        _Token.safeTransfer(address(msg.sender),takeToken);
    }
 
    //本金提取
    function takeToken(uint256 amount) public {
        require(address(msg.sender) == address(tx.origin), "no contract");
        PledgeOrder storage order = _orders[msg.sender];
        require(order.token>0,"no order");
        require(amount <= order.token,"less token");
        _totalPledegAmount = _totalPledegAmount.sub(amount);
        if(order.token == amount){
            order.token = 0;
            keys[order.index].isExist = false;
        }else{
            order.token = order.token.sub(amount);
        }
        address payable addr = getPayable(msg.sender);
        addr.transfer(amount);
    }
 
    function takeAllToken() public {
        require(address(msg.sender) == address(tx.origin), "no contract");
        PledgeOrder storage order = _orders[msg.sender];
        require(order.token > 0,"no order");
        keys[order.index].isExist = false;
        uint256 takeAmount = order.token;
        order.token = 0;
        _totalPledegAmount = _totalPledegAmount.sub(takeAmount);
        uint256 time = block.timestamp;
        uint256 diff = time.sub(_takeProfitTime[msg.sender]);
        if(diff >= 86400){
            uint256 profitPart = order.profitToken.mul(_precentUp).div(_precentDown);
            keys[order.index].isExist = false;
            order.profitToken = order.profitToken.sub(profitPart);
            _takeProfitTime[msg.sender] = time;
            _Token.safeTransfer(address(msg.sender),profitPart);
        }
        address payable addr = getPayable(msg.sender);
        addr.transfer(takeAmount);
    }
 
    //获取用户抵押本金余额
    function getPledgeToken(address tokenAddress) public view returns(uint256) {
        require(address(msg.sender) == address(tx.origin), "no contract");
        PledgeOrder memory order = _orders[tokenAddress];
        return order.token;
    }
 
    //获取用户收益余额
    function getProfitToken(address tokenAddress) public view returns(uint256) {
        require(address(msg.sender) == address(tx.origin), "no contract");
        PledgeOrder memory order = _orders[tokenAddress];
        return order.profitToken;
    }
 
    //获取当前抵押总额
    function getTotalPledge() public view returns(uint256) {
        require(address(msg.sender) == address(tx.origin), "no contract");
        return _totalPledegAmount;
    }
 
    //转换地址，允许地址接收资产
    function getPayable(address tokenAddress) private pure returns (address payable) {
        return address(uint168(tokenAddress));
    }
 
    function getTakeProfitTime(address tokenAddress) public view returns(uint256) {
        return _takeProfitTime[tokenAddress];
    }
    
    //设置开始状态
    function changeIsDIS(bool flag) public onlyOwner {
        _isDIS = flag;
    }
 
    function changeOwner(address paramOwner) public onlyOwner {
        require(paramOwner != address(0));
		owner = paramOwner;
    }
 
    function changeProfitor(address paramProfitor) public onlyOwner {
        profitor = paramProfitor;
    }
 
    modifier onlyOwner(){
        require(msg.sender == owner);
        _;
    }
 
    modifier onlyProfitor(){
        require(msg.sender == profitor);
    _;
    }
 
    function getOwner() public view returns (address) {
        return owner;
    }
 
    function getProfitor() public view returns (address) {
        return profitor;
    }
 
    function getsize() public view returns (uint256) {
        return size;
    }
 
    function maxPledgeAmount() public view returns (uint256) {
        return _maxPledgeAmount;
    }
 
    function maxMiningAmount() public view returns (uint256) {
        return _maxMiningAmount;
    }
 
    function leftMiningAmount() public view returns (uint256) {
        return _leftMiningAmount;
    }
 
    function minAmount() public view returns (uint256) {
        return _minAmount;
    }
 
    function maxPreMiningAmount() public view returns (uint256) {
        return _maxPreMiningAmount;
    }
 
    function startTime() public view returns (uint256) {
        return _startTime;
    }
 
    function endTime() public view returns (uint256) {
        return _endTime;
    }
 
    function nowTime() public view returns (uint256) {
        return block.timestamp;
    }
 
    function isDIS() public view returns (bool) {
        return _isDIS;
    }
 
}
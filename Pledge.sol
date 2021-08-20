pragma solidity >=0.7.0 <0.9.0;

import "./BalanceMap.sol";

contract Pledge {
    using IterableMapping for itmap;

    //合约拥有者账号地址
    address private owner;
    mapping(address => itmap) balances;
    mapping(address => Ticket[]) orders;
    mapping(address => uint[]) pledgeIndex;
    PledgeOrder[] pledges;

    bool _enabled = true;

    //抵押订单
    struct Ticket {
        //抵押额度(wei)
        uint value;
        //抵押开始时间(s)
        uint64 time;
        //抵押模式
        uint64 mode;
    }

    //标记抵押用户状态
    struct PledgeOrder {
        //转账地址
        address target;
        //抵押者地址
        address pledger;
        //抵押索引
        uint index;
        //抵押额度(wei)
        uint value;
        //剩余额度(wei)
        uint balance;
        //抵押持续时间(s)
        uint64 time;
        //抵押起始时间(s)
        uint64 startTime;
        //最近一次提取时间(s)
        uint64 lastTime;
        //抵押模式
        uint64 mode;
    }

    constructor() {
        owner = msg.sender;
    }

    //创建订单
    function openO(address addr, uint value, uint64 time, uint64 mode) public onlyOwner {
        require(value > 0, "value cannot be zero");
        require(mode == 0 || mode == 1, "wrong mode");
        require(time >= (30 days), "at least 30 days");

        orders[addr].push(Ticket({
        value : value,
        time : time,
        mode : mode
        }));
    }

    function deposit(address pledger, address target, uint value, uint64 time, uint64 mode) private {
        uint64 nowTime = uint64(block.timestamp);
        uint gIndex = pledges.length;
        uint pIndex = pledgeIndex[pledger].length;

        pledges.push(PledgeOrder({
        target : target,
        pledger : pledger,
        index : pIndex,
        value : value,
        balance : value,
        time : time,
        startTime : nowTime,
        lastTime : nowTime,
        mode : mode
        }));

        pledgeIndex[pledger].push(gIndex);
    }

    //直接抵押函数
    function depositLinear(address addr, uint64 time, uint64 mode) public payable {
        require(msg.value > 0, "value cannot be zero");
        require(address(msg.sender) == address(tx.origin), "no contract");
        require(_enabled, "is disabled");
        require(mode == 0 || mode == 1, "wrong mode");
        require(time >= (30 days), "at least 30 days");

        deposit(msg.sender, addr, msg.value, time, mode);
    }

    //订单抵押函数
    function depositLinearO(address addr, uint64 time, uint64 mode) public payable {
        require(msg.value > 0, "value cannot be zero");
        require(address(msg.sender) == address(tx.origin), "no contract");
        require(mode == 0 || mode == 1, "wrong mode");
        require(_enabled, "is disabled");
        require(time >= (30 days), "at least 30 days");

        Ticket[] storage tickets = orders[msg.sender];
        require(tickets.length > 0, "no ticket");

        bool success = false;

        for (uint i = 0; i < tickets.length; i++) {
            if (tickets[i].value == msg.value && tickets[i].time == time && tickets[i].mode == mode) {
                deposit(msg.sender, addr, msg.value, time, mode);
                uint end = tickets.length - 1;
                if (i < end) {
                    tickets[i] = tickets[end];
                }
                tickets.pop();
                success = true;
                break;
            }
        }
        if (success == false) {
            revert("no matched ticket");
        }
    }

    function transfer(address pledger, address target, uint amount) private {
        itmap storage bMap = balances[pledger];
        uint curBalance = bMap.data[target].value;
        bMap.insert(target, amount + curBalance);
    }

    function settleOne(uint index) private returns (bool) {
        PledgeOrder storage curPledge = pledges[index];
        //抵押已到期
        if (block.timestamp >= curPledge.startTime + curPledge.time) {
            uint amount = curPledge.balance;
            curPledge.balance = 0;
            transfer(curPledge.pledger, curPledge.target, amount);
            deletePledge(index);
            return true;
        }

        //按时间释放
        if (curPledge.mode == 1) {
            uint time = block.timestamp;
            uint share = curPledge.time / (30 days);
            uint curShare = (time - uint(curPledge.lastTime)) / (30 days);
            if (curShare > 0) {
                uint amount = curPledge.value * curShare / share;
                curPledge.balance -= amount;
                curPledge.lastTime += uint64(curShare) * (30 days);
                transfer(curPledge.pledger, curPledge.target, amount);
            }
        }
        return false;
    }

    function deletePledge(uint index) private {
        address pledger = pledges[index].pledger;
        uint[] storage allIndex = pledgeIndex[pledger];

        //删除抵押者对该笔抵押的索引
        uint pIndex = pledges[index].index;
        uint end = allIndex.length - 1;
        if (pIndex < end) {
            uint last = allIndex[end];
            allIndex[pIndex] = last;
            pledges[last].index = pIndex;
        }
        allIndex.pop();

        //删除该笔抵押
        end = pledges.length - 1;
        if (index < end) {
            pledges[index] = pledges[end];
            //交换后修正索引记录
            pledger = pledges[index].pledger;
            pIndex = pledges[index].index;
            allIndex = pledgeIndex[pledger];
            allIndex[pIndex] = index;
        }
        pledges.pop();
    }

    //结算指定地址抵押
    function settle(address addr) public {
        require(address(msg.sender) == address(tx.origin), "no contract");

        uint[] storage allIndex = pledgeIndex[addr];
        for (uint i = allIndex.length; i >= 1; i--) {
            settleOne(allIndex[i - 1]);
        }
    }

    //结算全部抵押
    function settleAll() public onlyOwner {
        for (uint i = pledges.length; i >= 1; i--) {
            settleOne(i - 1);
        }
    }

    //获取用户抵押详情
    function checkReceipt(address addr) public view returns (Ticket[] memory) {
        require(address(msg.sender) == address(tx.origin), "no contract");
        uint[] storage curIndex = pledgeIndex[addr];
        Ticket[] memory tics = new Ticket[](curIndex.length);

        for (uint i = 0; i < curIndex.length; i++) {
            tics[i].value = pledges[i].value;
            tics[i].time = pledges[i].time;
            tics[i].mode = pledges[i].mode;
        }
        return tics;
    }

    //提取全部已结算代币
    function withdraw(address addr) public {
        require(address(msg.sender) == addr, "no authority");
        require(address(msg.sender) == address(tx.origin), "no contract");

        itmap storage bMap = balances[addr];

        for (uint i = 1; bMap.iterate_valid(i); i++) {
            address target;
            uint value;
            (target, value) = bMap.iterate_get_and_clear(i);
            payable(target).transfer(value);
        }
        delete balances[addr];
    }

    //设置开始状态
    function changeStatus(bool flag) public onlyOwner {
        _enabled = flag;
    }

    function changeOwner(address paramOwner) public onlyOwner {
        require(paramOwner != address(0));
        owner = paramOwner;
    }

    modifier onlyOwner(){
        require(msg.sender == owner);
        _;
    }

    function getOwner() public view returns (address) {
        return owner;
    }

    function isEnabled() public view returns (bool) {
        return _enabled;
    }
}
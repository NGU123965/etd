pragma solidity >=0.6.0 <0.9.0;

    struct Balance {
        uint keyIndex;
        uint value;
    }

    struct itmap {
        mapping(address => Balance) data;
        address[] keys;
    }

library IterableMapping {
    function insert(itmap storage self, address key, uint value) internal returns (bool replaced) {
        uint keyIndex = self.data[key].keyIndex;
        self.data[key].value = value;
        //keyIndex为0时表NULL
        if (keyIndex > 0)
            return true;
        else {
            self.keys.push(key);
            //keyIndex为keys中下标+1
            self.data[key].keyIndex = self.keys.length;
            return false;
        }
    }

    function remove(itmap storage self, address addr) internal returns (bool success) {
        uint keyIndex = self.data[addr].keyIndex;
        //key不存在
        if (keyIndex == 0)
            return false;

        //交换末尾键值至待删除处
        uint size = self.keys.length;
        require(keyIndex > 0, "wrong index");
        if (keyIndex < size) {
            address lastAddr = self.keys[size - 1];
            self.keys[keyIndex - 1] = lastAddr;
            self.data[lastAddr].keyIndex = keyIndex;
        }
        self.keys.pop();
        delete self.data[addr];

        return true;
    }

    function contains(itmap storage self, address addr) internal view returns (bool) {
        return self.data[addr].keyIndex > 0;
    }

    function iterate_valid(itmap storage self, uint keyIndex) internal view returns (bool) {
        return keyIndex <= self.keys.length;
    }

    function iterate_get_and_clear(itmap storage self, uint keyIndex) internal returns (address key, uint value) {
        require(keyIndex > 0, "wrong index");
        key = self.keys[keyIndex - 1];
        value = self.data[key].value;
        self.data[key].value = 0;
        return (key, value);
    }
}

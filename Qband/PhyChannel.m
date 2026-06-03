classdef PhyChannel <handle
    properties (Access = public)
        bandwith       %信道带宽
        frequency      %主信道频率
        error_module   %误帧率模型
        phy_queue      %物理层发送队列
        usr_num        %一个时隙有多少个用户在发包
    end 
    methods
        function obj = PhyChannel(c1)
            obj.phy_queue = myQueue();
            obj.bandwith = c1;
            obj.usr_num = 0;
        end
    end
end
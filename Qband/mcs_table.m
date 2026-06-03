classdef mcs_table <handle
    properties (Access = public)
        table_elem;     %mcs表的表项
    end 
    methods
        function obj = mcs_table()
            load const_value
            obj.table_elem(1).mcs = 1;
            obj.table_elem(1).nss = 1;
            obj.table_elem(1).constellation_size = 2;
            obj.table_elem(1).code_rate = WIFI_CODE_RATE_1_2;
            obj.table_elem(1).data_rate = 192;
            
            obj.table_elem(2).mcs = 2;
            obj.table_elem(2).nss = 1;
            obj.table_elem(2).constellation_size = 4;
            obj.table_elem(2).code_rate = WIFI_CODE_RATE_1_2;
            obj.table_elem(2).data_rate = 385;
            
            obj.table_elem(3).mcs = 3;
            obj.table_elem(3).nss = 1;
            obj.table_elem(3).constellation_size = 4;
            obj.table_elem(3).code_rate = WIFI_CODE_RATE_3_4;
            obj.table_elem(3).data_rate = 577;
            
            obj.table_elem(4).mcs = 4;
            obj.table_elem(4).nss = 1;
            obj.table_elem(4).constellation_size = 16;
            obj.table_elem(4).code_rate = WIFI_CODE_RATE_1_2;
            obj.table_elem(4).data_rate = 770;
            
            obj.table_elem(5).mcs = 5;
            obj.table_elem(5).nss = 1;
            obj.table_elem(5).constellation_size = 16;
            obj.table_elem(5).code_rate = WIFI_CODE_RATE_3_4;
            obj.table_elem(5).data_rate = 1155;
            
            obj.table_elem(6).mcs = 6;
            obj.table_elem(6).nss = 1;
            obj.table_elem(6).constellation_size = 64;
%             obj.table_elem(6).code_rate = WIFI_CODE_RATE_5_8;
            obj.table_elem(6).code_rate = WIFI_CODE_RATE_1_2;%应该是5/8，但是5/8的pe计算还未得到，先用1/2代替
            obj.table_elem(6).data_rate = 1443;
            
            obj.table_elem(7).mcs = 7;
            obj.table_elem(7).nss = 1;
            obj.table_elem(7).constellation_size = 64;
            obj.table_elem(7).code_rate = WIFI_CODE_RATE_3_4;
            obj.table_elem(7).data_rate = 1732;
            
            obj.table_elem(8).mcs = 8;
            obj.table_elem(8).nss = 1;
            obj.table_elem(8).constellation_size = 64;
%             obj.table_elem(8).code_rate = WIFI_CODE_RATE_13_16;
            obj.table_elem(8).code_rate = WIFI_CODE_RATE_5_6;%应该是13_16，但是13_16的pe计算还未得到，先用1/2代替
            obj.table_elem(8).data_rate = 1876;
        end
    end
end
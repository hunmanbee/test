classdef QbandFrameConfig
    properties
        FrameType = 'Data';
        Tid = 0;
        Uid = 0;
        Seq = 0;
        transId = 0;
        reserved = 0;
        Address1 = 'FFFFFFFFFFFF';
        Address2 = '00123456789B';
        type = '0800';
        MPDUAggregation (1, 1) logical = true;
        ARQConfig;
        BeaconConfig;
        BSRConfig;
        IEConfig;
        AssocReqConfig;
        AssocRspConfig;
        OfflineReqConfig;
        OfflineRspConfig;
        PreConditionConfig;
        PreChannelConfig;
        ChannelReqConfig;
    end

    properties(Hidden,Constant)
        FrameType_Values = {'ChannelReq','Data','ACK','Beacon','DownIE','UpIE1','UpIE2','UpARQ','DownARQ','BSR','PreCon_UpReq','PreCon_UpRsp','PreCon_UpEnd','PreCon_DownReq','PreCon_DownEnd','OfflineReq','OfflineRsp','PreChal_Req','PreChal_Rsp'};
    end

    methods(Access = private)
        function value = validateHex(~, value, length, propertyName)
        % validate format
            validateattributes(value, {'char', 'string'}, {}, mfilename, propertyName);
            if isa(value, 'char')
                validateattributes(value, {'char'}, {'row'}, mfilename, propertyName);
            else % string
                validateattributes(value, {'string'}, {'scalar'}, mfilename, propertyName);
            end
            value = upper(char(value));
            % Validate hex-digits
            wlan.internal.validateHexOctets(value, propertyName, length);
        end
    end
    methods(Hidden)
        function type = getType(obj)
            switch (obj.FrameType)
                case 'Data'
                    type = 'Data';
                case {'ChannelReq','ACK','Beacon','DownIE','UpIE1','UpIE2','UpARQ','DownARQ','AssocReq','AssocRsp','BSR','PreCon_UpReq','PreCon_UpRsp','PreCon_UpEnd','PreCon_DownReq','PreCon_DownEnd','OfflineReq','OfflineRsp','PreChal_Req','PreChal_Rsp'}
                    type = 'Control';
            end
        end
        function subtype = getSubtype(obj)
            subtype = obj.FrameType;
        end
    end
    methods
        function obj = QbandFrameConfig()
        end
        function obj = set.FrameType(obj, value)
            propName = 'FrameType';
            obj.(propName) = '';
            obj.(propName) = value;
        end
        function obj = set.Tid(obj, value)
            propName = 'Tid';
            validateattributes(value, {'numeric'}, {'scalar', 'integer', 'nonnegative', '<=', 15}, mfilename, propName);
            obj.(propName) = double(value);
        end  
        function obj = set.Uid(obj, value)
            propName = 'Uid';
            validateattributes(value, {'numeric'}, {'scalar', 'integer', 'nonnegative', '<=', 255}, mfilename, propName);
            obj.(propName) = double(value);
        end  
        function obj = set.Seq(obj, value)
            propName = 'Seq';
            validateattributes(value, {'numeric'}, {'scalar', 'integer', 'nonnegative', '<=', 65535}, mfilename, propName);
            obj.(propName) = double(value);
        end
        function obj = set.transId(obj, value)
            propName = 'transId';
            validateattributes(value, {'numeric'}, {'scalar', 'integer', 'nonnegative', '<=', 65535}, mfilename, propName);
            obj.(propName) = double(value);
        end
        function obj = set.reserved(obj, value)
            propName = 'reserved';
            validateattributes(value, {'numeric'}, {'scalar', 'integer', 'nonnegative', '<=', 65535}, mfilename, propName);
            obj.(propName) = double(value);
        end
        function obj = set.Address1(obj, value)
            propName = 'Address1';
            value = obj.validateHex(value, 12, propName);
            obj.(propName) = value;
        end
        function obj = set.Address2(obj, value)
            propName = 'Address2';
            value = obj.validateHex(value, 12, propName);
            obj.(propName) = value;
        end          
    end

end

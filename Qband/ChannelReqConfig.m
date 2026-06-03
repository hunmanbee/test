classdef ChannelReqConfig
    properties
        up_channel;
        down_channel;
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
    
    methods
        function obj = ChannelReqConfig()
        end
        function obj = set.up_channel(obj,value)
            propName = 'up_channel';
            obj.(propName) = value;
        end  
        function obj = set.down_channel(obj,value)
            propName = 'down_channel';
            obj.(propName) = value;
        end 
    end
end
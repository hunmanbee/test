classdef AssocRspConfig
    properties
        mac_address;
        uid = 0;
        dl_channel = 0;
        ul_channel = 0;
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
        function obj = AssocRspConfig()
        end
        function obj = set.mac_address(obj, value)
            propName = 'mac_address';
            value = obj.validateHex(value, 12, propName);
            obj.(propName) = value;
        end  
        function obj = set.uid(obj, value)
            propName = 'uid';
            validateattributes(value, {'numeric'}, {'scalar', 'integer', 'nonnegative', '<=', 255}, mfilename, propName);
            obj.(propName) = value;
        end  
    end
end
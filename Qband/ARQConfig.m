classdef ARQConfig
    properties
        tidNum = 0;
        reserved = 0;
        fb_info = {};
    end

    methods
        function obj = ARQConfig()
        end
        function obj = set.tidNum(obj, value)
            propName = 'tidNum';
            obj.(propName) = '';
            obj.(propName) = value;
        end
        function obj = set.reserved(obj, value)
            propName = 'reserved';
            validateattributes(value, {'numeric'}, {'scalar', 'integer', 'nonnegative', '<=', 15}, mfilename, propName);
            obj.(propName) = double(value);
        end  
        function obj = set.fb_info(obj, value)
            propName = 'fb_info';
            obj.(propName) = value;
        end           
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
end
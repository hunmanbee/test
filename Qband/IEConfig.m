classdef IEConfig
    properties
        idx1 = 0;
        dur1 = 0;
        idx2 = 0;
        dur2 = 0; 
        channelNumbers = 0;
        reserved = 0;
    end

    methods
        function obj = IEConfig()
        end
        function obj = set.idx1(obj, value)
            propName = 'idx1';
            validateattributes(value, {'numeric'}, {'scalar', 'integer', 'nonnegative', '<=', 255}, mfilename, propName);
            obj.(propName) = double(value);
        end  
        function obj = set.dur1(obj, value)
            propName = 'dur1';
            validateattributes(value, {'numeric'}, {'scalar', 'integer', 'nonnegative', '<=', 255}, mfilename, propName);
            obj.(propName) = double(value);
        end
        function obj = set.idx2(obj, value)
            propName = 'idx2';
            validateattributes(value, {'numeric'}, {'scalar', 'integer', 'nonnegative', '<=', 255}, mfilename, propName);
            obj.(propName) = double(value);
        end
        function obj = set.dur2(obj, value)
            propName = 'dur2';
            validateattributes(value, {'numeric'}, {'scalar', 'integer', 'nonnegative', '<=', 255}, mfilename, propName);
            obj.(propName) = double(value);
        end
        function obj = set.channelNumbers(obj, value)
            propName = 'channelNumbers';
            validateattributes(value, {'numeric'}, {'scalar', 'integer', 'nonnegative', '<=', 255}, mfilename, propName);
            obj.(propName) = double(value);
        end
        function obj = set.reserved(obj, value)
            propName = 'reserved';
            validateattributes(value, {'numeric'}, {'scalar', 'integer', 'nonnegative', '<=', 255}, mfilename, propName);
            obj.(propName) = double(value);
        end
    end
end
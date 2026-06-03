classdef PreChannelConfig
    properties
        RequestType = 0;
        Status = 0;
        UlChannel = 0;
        DlChannel = 0;
        Reserved = 0;
    end

    methods
        function obj = PreChannelConfig
        end
        function obj = set.RequestType(obj, value)
            propName = 'RequestType';
            validateattributes(value, {'numeric'}, {'scalar', 'integer', 'nonnegative', '<=', 100000000000}, mfilename, propName);
            obj.(propName) = double(value);
        end 
        function obj = set.UlChannel(obj, value)
            propName = 'UlChannel';
            validateattributes(value, {'numeric'}, {'scalar', 'integer', 'nonnegative', '<=', 100000000000}, mfilename, propName);
            obj.(propName) = double(value);
        end 
        function obj = set.Status(obj, value)
            propName = 'Status';
            validateattributes(value, {'numeric'}, {'scalar', 'integer', 'nonnegative', '<=', 100000000000}, mfilename, propName);
            obj.(propName) = double(value);
        end 
        function obj = set.DlChannel(obj, value)
            propName = 'DlChannel';
            validateattributes(value, {'numeric'}, {'scalar', 'integer', 'nonnegative', '<=', 100000000000}, mfilename, propName);
            obj.(propName) = double(value);
        end 
    end
end
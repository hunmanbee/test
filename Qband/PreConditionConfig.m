classdef PreConditionConfig
    properties
        Interval = 0;
        Slot_Num = 0;
        Status = 0;
        Time_Index = 0;
        Slot_Index = 0;
        Cycles_Num = 0;
        Reserved = 0;
    end

    methods
        function obj = PreConditionConfig
        end
        function obj = set.Interval(obj, value)
            propName = 'Interval';
            validateattributes(value, {'numeric'}, {'scalar', 'integer', 'nonnegative', '<=', 100000000000}, mfilename, propName);
            obj.(propName) = double(value);
        end 
        function obj = set.Slot_Num(obj, value)
            propName = 'Slot_Num';
            validateattributes(value, {'numeric'}, {'scalar', 'integer', 'nonnegative', '<=', 100000000000}, mfilename, propName);
            obj.(propName) = double(value);
        end 
        function obj = set.Status(obj, value)
            propName = 'Status';
            validateattributes(value, {'numeric'}, {'scalar', 'integer', 'nonnegative', '<=', 100000000000}, mfilename, propName);
            obj.(propName) = double(value);
        end 
        function obj = set.Time_Index(obj, value)
            propName = 'Time_Index';
            validateattributes(value, {'numeric'}, {'scalar', 'integer', 'nonnegative', '<=', 100000000000}, mfilename, propName);
            obj.(propName) = double(value);
        end 
        function obj = set.Slot_Index(obj, value)
            propName = 'Slot_Index';
            validateattributes(value, {'numeric'}, {'scalar', 'integer', 'nonnegative', '<=', 100000000000}, mfilename, propName);
            obj.(propName) = double(value);
        end 
        function obj = set.Cycles_Num(obj, value)
            propName = 'Cycles_Num';
            validateattributes(value, {'numeric'}, {'scalar', 'integer', 'nonnegative', '<=', 100000000000}, mfilename, propName);
            obj.(propName) = double(value);
        end 
    end
end
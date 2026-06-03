classdef BSRConfig
    properties
        bsrinfo = [];
    end
    methods
        function obj = BSRConfig()
        end
        function obj = set.bsrinfo(obj, value)
            propName = 'bsrinfo';
            obj.(propName) = value;
        end 
    end

end
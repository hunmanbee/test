classdef BeaconConfig
    properties
        timeStamp = 0;
        beaconInterval = 0;
        capabilityInfo = '1 0 0 0 0 0 0';
        pollingBitmap = zeros(1,40);
    end

    methods
        function obj = BeaconConfig()
        end
        function obj = set.timeStamp(obj, value)
            propName = 'timeStamp';
            obj.(propName) = '';
            obj.(propName) = value;
        end
        function obj = set.beaconInterval(obj, value)
            propName = 'beaconInterval';
            validateattributes(value, {'numeric'}, {'scalar', 'integer', 'nonnegative', '<=', 15}, mfilename, propName);
            obj.(propName) = double(value);
        end 
        function obj = set.capabilityInfo(obj, value)
            propName = 'capabilityInfo';
            obj.(propName) = value;
        end
        function obj = set.pollingBitmap(obj, value)
            propName = 'pollingBitmap';
            obj.(propName) = value;
        end
    end
end
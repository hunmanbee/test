function dataFormat = validateMACDecodeInputs(nvPair, isAMPDU)
%validateMACDecodeInputs Validate MAC frame, PHY config and N/V pair inputs
%
%   Note: This is an internal undocumented function and its API and/or
%   functionality may change in subsequent releases.
%
%   DATAFORMAT = validateMACDecodeInputs(DATA, PHYCONFIG, NVPAIR, ISAMPDU)
%   validates the given inputs DATA, PHYCONFIG and NVPAIR for MAC frame
%   decoding functionality. Additional validations for aggregated frames
%   are done if the ISAMPDU flag indicates an aggregated frame. The data
%   format of the input DATA is returned as the output, based on the input
%   NVPAIR.
%
%   DATAFORMAT is the format of the input MAC frame, DATA, returned as one
%   of 'bits' or 'octets'.
%
%   DATA is the input MAC frame specified as either a logical vector,
%   numeric vector, string scalar, character vector or an n-by-2 character
%   array.
%
%   PHYCONFIG is a format configuration object of type <a href="matlab:help('wlanHESUConfig')">wlanHESUConfig</a>,
%   <a href="matlab:help('wlanVHTConfig')">wlanVHTConfig</a>, <a href="matlab:help('wlanHTConfig')">wlanHTConfig</a> or <a href="matlab:help('wlanNonHTConfig')">wlanNonHTConfig</a>.
%
%   NVPAIR is a cell array specifying the (Name, Value) pairs relevant to
%   the MAC frame decoding functionality.
%
%   ISAMPDU is a flag indicating if the given input DATA is an aggregated
%   MPDU specified as a logical or double scalar.

%   Copyright 2018 The MathWorks, Inc.

%#codegen



% Check if the frame is non-aggregated
coder.internal.errorIf(~isAMPDU, ...
    'wlan:wlanAMPDUDeaggregate:NotAnAMPDU');

% Default values
defaultParams = struct('DataFormat', 'bits');
expectedFormatValues = {'bits', 'octets'};

if numel(nvPair) == 0
    useParams = defaultParams;
else
    % Extract each P-V pair
    if isempty(coder.target) % Simulation path
        p = inputParser;
        
        % Get values for the P-V pair or set defaults for the optional arguments
        addParameter(p, 'DataFormat', defaultParams.DataFormat, @(x) any(validatestring(x, expectedFormatValues)));
        % Parse inputs
        parse(p, nvPair{:});
        
        useParams = p.Results;
        
    else % Codegen path
        pvPairs = struct('DataFormat', uint32(0));
        
        % Select parsing options
        popts = struct('PartialMatching', true);
        
        % Parse inputs
        pStruct = coder.internal.parseParameterInputs(pvPairs, popts, nvPair{:});
        
        % Get values for the P-V pair or set defaults for the optional arguments
        useParams = struct;
        useParams.DataFormat = coder.internal.getParameterValue(pStruct.DataFormat, defaultParams.DataFormat, nvPair{:});
    end
end

dataFormat = validatestring(useParams.DataFormat, expectedFormatValues, mfilename);

end
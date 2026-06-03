function validateHexOctets(value, varName, length)
%validateHexOctets Validates hexadecimal format octets
% 
%   Note: This is an internal undocumented function and its API and/or
%   functionality may change in subsequent releases.
%
%   validateHexOctets(VALUE, VARNAME) checks if the given VALUE contains
%   even number of hexadecimal digits. Throws an error if the input
%   contains any characters other than hexadecimal digits or if the input
%   contains odd number of hexadecimal digits.
%
%   VALUE is a string scalar, character vector or an n-by-2 character
%   array.
%
%   VARNAME is the variable name used in the error messages, specified as a
%   character row vector or string scalar.
%
%   validateHexOctets(VALUE, VARNAME, LENGTH) additionally checks if the
%   given VALUE contains the number of hexadecimal digits specified by
%   LENGTH.

%   Copyright 2018 The MathWorks, Inc.

%#codegen

hexValue = upper(reshape(char(value), 1, []));

% Validate hex digits
coder.internal.errorIf(any(~(((hexValue >= '0') & (hexValue <= '9')) | ((hexValue >= 'A') & (hexValue <= 'F')))), ...
    'wlan:shared:InvalidHexDigit', varName);

% Length of hexadecimal data octets must be multiple of 2
coder.internal.errorIf((rem(numel(hexValue), 2) ~= 0), 'wlan:shared:HexNibbleMissing', varName);

% validate length
if (nargin == 3) && ~isempty(length)
    validateattributes(value, {'char'},  {'numel', length}, mfilename, varName);
end
end
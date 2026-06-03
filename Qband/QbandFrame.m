function [frame, frameLength] = QbandFrame(varargin)
    narginchk(1, 3);            %验证当前函数参数数目，若小于1或者大于3则报错。
    inputs = varargin;
    [payload, macConfig] = validateInputs(inputs);      %验证并分离输入参数，将其分离为负载、实例化帧对象
    if ~isempty(payload) % payload非空,则一定是数据帧。默认若负载为至少2个，均汇聚
        if macConfig{1}.MPDUAggregation
            % 产生A-MPDU
            [frameOctets, frameLength] = generateAMPDUData(payload, macConfig);
        else    % 产生单个mpdu
            data = [];
            if ~isempty(payload)
                data = payload{1};
            end
            frameOctets = QbandGenerateMPDU(data, macConfig{1});
            frameLength = numel(frameOctets);  
        end
    else    % 控制帧/无负载数据帧
        if strcmp(macConfig{1}.getType,'Data')  % 无负载数据帧（单个）
            frameOctets = QbandGenerateMPDU([], macConfig);
            frameLength = numel(frameOctets);  
        else    % 控制帧。为规范使用，输入的帧对象要么默认汇聚，要么均不汇聚
            if macConfig{1}.MPDUAggregation
                [frameOctets, frameLength] = generateAMPDUControl(macConfig);
            end
        end

    end
    frame = dec2hex(frameOctets, 2);
end


















% 产生AMPDU-Data
function [ampdu, frameLength] = generateAMPDUData(payload, macConfig)
  % payload中msdu数量
  numMPDUs = numel(payload);
  numConfig = numel(macConfig);
  if numConfig == numMPDUs  % 确保负载和帧对象数量一致
    % 初始化元胞数组，用于提供qbandGenerateAMPDU的输入
    mpduList = cell(1, numMPDUs);
    % 产生MPDU，存入mpduList
    for i = 1:numMPDUs
      msdu = payload{i};
      mpduList{i} = QbandGenerateMPDU(msdu, macConfig{i});
      % 逐次增加Seq
      if i < numMPDUs
        macConfig{i+1}.Seq = mod((macConfig{i}.Seq + 1), 4096);
      end
    end
    [ampdu, frameLength] = qbandGenerateAMPDU(mpduList);
  end
end

% 产生AMPDU-Control
function [ampdu, frameLength] = generateAMPDUControl(macConfig)
    numConfig = numel(macConfig);
    mpduList = cell(1, numConfig);
    for i = 1:numConfig
        mpduList{i} = QbandGenerateMPDU([], macConfig{i});
    end
    [ampdu, frameLength] = qbandGenerateAMPDU(mpduList);
end

% 验证并分离输入参数，将其分离为负载、实例化帧对象以及HTConfig（关于带宽分配的部分，目前没有用到。）
function [payload, macConfig] = validateInputs(inputs)
  % 初始化负载长度、输入参数数量、MSDU最大长度（暂时不用）
  payloadLength = 0;
  nInputs = numel(inputs);
  maxMSDULength = 2304;

  % 如果输入参数为1，则它为实例化帧对象，直接赋值。
  if nInputs == 1
    macConfig = inputs{1};
    payload = {};
    

  %如果输入参数为2/3，则它为（负载、实例化对象（、HTConfig））。
  else
    % 对输入的实例化帧对象检验，如果不符合格式则报错（目前未完成）
    %coder.internal.errorIf(~isa(inputs{2}, 'wlanMACFrameConfig') || (numel(inputs{2}) > 1), 'wlan:wlanMACFrame:InvalidArgument2');
    macConfig = inputs{2};

    % 将第一个输入参数传递给payloadInput，即负载传递以便后续处理。
    payloadInput = inputs{1};
    % 如果输入的负载个数不止一个，则将负载转化为一个数组储存，进制为10进制。
    if iscell(payloadInput) || isstring(payloadInput)
      % 统计负载个数
      numMSDUs = numel(payloadInput);

      % 检验输入负载，并将其转换为十进制，同时更新负载长度。
      payload = cell(1, numMSDUs);
      for i = 1:numMSDUs
        if iscell(payloadInput)
          msdu = payloadInput{i};
          %coder.internal.errorIf(isstring(msdu), 'wlan:wlanMACFrame:StringInCellNotAccepted');
        else % string
          msdu = payloadInput(i);
        end
        msduOctets = validatePayloadFormat(msdu);
        %coder.internal.errorIf(numel(msduOctets) > maxMSDULength, 'wlan:wlanMACFrame:MSDUSizeExceededMultiple', i);
        payloadLength = payloadLength + numel(msduOctets);
        payload{i} = msduOctets;
      end
    %如果输入负载只有一个，则直接转存至payload{1}。
    else
      payload = cell(1, 1);
      payload{1} = validatePayloadFormat(payloadInput);
      payloadLength = numel(payload{1});
      coder.internal.errorIf(payloadLength > maxMSDULength, 'wlan:wlanMACFrame:MSDUSizeExceededSingle');
    end

%     如果有三个输入参数，则涉及到HT、VHT等格式，此处忽略。
%         if (nInputs == 3)
%           phyConfig = inputs{3};
%     
%           % Validate phyConfig object
%           validateattributes(phyConfig, {'wlanHTConfig', 'wlanVHTConfig', 'wlanHESUConfig'}, {'scalar'}, mfilename, 'phyConfig');
%     
%           % Validate wlanHTConfig object for HT format
%           coder.internal.errorIf(strcmp(macConfig.FrameType, 'QoS Data') && (macConfig.MSDUAggregation || macConfig.MPDUAggregation) && ...
%             strcmp(macConfig.FrameFormat, 'HT-Mixed') && ~isa(inputs{3}, 'wlanHTConfig'), 'wlan:wlanMACFrame:InvalidPHYConfig', ...
%             'HT-Mixed', 'wlanHTConfig');
%     
%           % Validate wlanVHTConfig object for VHT format
%           coder.internal.errorIf(strcmp(macConfig.FrameType, 'QoS Data') && strcmp(macConfig.FrameFormat, 'VHT') && ...
%             ~isa(inputs{3}, 'wlanVHTConfig'), 'wlan:wlanMACFrame:InvalidPHYConfig', 'VHT', 'wlanVHTConfig');
%           
%           % Validate wlanHESUConfig object for HE format
%           coder.internal.errorIf(strcmp(macConfig.FrameType, 'QoS Data') && any(strcmp(macConfig.FrameFormat, {'HE-SU', 'HE-EXT-SU'})) && ...
%             ~isa(inputs{3}, 'wlanHESUConfig'), 'wlan:wlanMACFrame:InvalidPHYConfig', 'HE', 'wlanHESUConfig');
%     
%           % Validate HE-SU and HE-EXT-SU formats
%           coder.internal.errorIf(isa(inputs{3}, 'wlanHESUConfig') && ~strcmp(phyConfig.packetFormat, macConfig.FrameFormat), 'wlan:wlanMACFrame:HEFormatMismatch');
%         else
%           coder.internal.errorIf(strcmp(macConfig.FrameType, 'QoS Data') && (any(strcmp(macConfig.FrameFormat, {'VHT', 'HE-SU', 'HE-EXT-SU'})) || ...
%             (strcmp(macConfig.FrameFormat, 'HT-Mixed') && (macConfig.MSDUAggregation || macConfig.MPDUAggregation))), ...
%             'wlan:wlanMACFrame:PHYConfigRequired');
%     
%           if coder.target('MATLAB')
%             phyConfig = [];
%           else % Codegen path
%             % For codegen: assign default PHY configuration
%             phyConfig = wlanVHTConfig;
%           end
%         end

  end

  % 根据帧类型更新帧MPDUAggregation与HTControlPresent等属性，这里先忽略，后续实现汇聚功能时再引入MPDUAggregation属性。
    %   if any(strcmp(macConfig.FrameFormat, {'VHT', 'HE-SU', 'HE-EXT-SU'})) && strcmp(macConfig.FrameType, 'QoS Data')
    %     % HE and VHT format data frames are always sent as A-MPDUs
    %     macConfig.MPDUAggregation = true;
    %   elseif strcmp(macConfig.FrameFormat, 'Non-HT')
    %     % Non-HT format frame cannot be an A-MPDU
    %     macConfig.MPDUAggregation = false;
    %     % Non-HT format frames do not contain HT-Control field
    %     macConfig.HTControlPresent = false;
    %   end

end

% 检验负载格式是否正确，并将字符串16进制转为10进制数组输出。
function decOctets = validatePayloadFormat(payload)
  if isempty(payload)
    decOctets = [];
    return;
  end

  % Validate payload format
  validateattributes(payload, {'char', 'numeric', 'string'}, {}, mfilename, 'payload')

  if ischar(payload)    
    % Validate hex-digits
    validateHexOctets(payload, 'payload');
    
    if isvector(payload)
      validateattributes(payload, {'char'}, {'row'}, 'validatePayloadFormat', 'payload', 1);
      % Convert row vector to column of octets.
      columnOctets = reshape(payload, 2, [])';
    else
      validateattributes(payload, {'char'}, {'2d', 'ncols', 2}, 'validatePayloadFormat', 'payload', 1);
      columnOctets = payload;
    end
    
    % Converting hexadecimal format octets to integer format
    decOctets = hex2dec(columnOctets);

  elseif isstring(payload)
    if payload == ""
      decOctets = [];
      return;
    end
    validateattributes(payload, {'string'}, {'scalar'}, mfilename, 'payload');
    
    % Convert octets to char type
    hexOctets = char(payload);
    
    % Validate hex-digits
    wlan.internal.validateHexOctets(hexOctets, 'payload');

    % Converting hexadecimal format octets to decimal format
    decOctets = hex2dec(reshape(hexOctets, 2, [])');
    
  else % numeric
    if iscolumn(payload)
      payloadRow = payload;
    else
      % Convert row vector to column vector
      payloadRow = payload';
    end
    % Payload byte values should be a non-negative number <= 255
    validateattributes(payloadRow, {'numeric'}, {'vector', 'integer', 'nonnegative', '<=', 255}, mfilename, 'payload octets');

    decOctets = double(payloadRow);
  end
end
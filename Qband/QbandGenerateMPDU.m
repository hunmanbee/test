function mpdu = QbandGenerateMPDU(payload, macConfig)
    switch(macConfig.getType)
      case 'Control'
        mpduBits = generateControlFrame(macConfig);
      otherwise % Data
        mpduBits = generateDataFrame(payload, macConfig);
    end
    mpdu = uint8(bi2deOptimized(reshape(mpduBits, 8, [])'));
end

%产生数字帧完整比特（不含分隔符）
function frame = generateDataFrame(payload, macConfig)
    frameControlData = prepareFrameControl1(macConfig);
    address = prepareAddress(macConfig);
    %此处type为以太帧类型，固定0800。
    type = decOctetVector('0800',2,false);
    frameHeader = [frameControlData,address,type]';
    frame = [frameHeader;payload];
    frame = appendFCS(frame);
end

% 产生控制帧完整比特（不含分隔符）
function frame = generateControlFrame(macConfig)
    % 控制帧分情况讨论
    if strcmp(macConfig.FrameType,'UpIE1')||strcmp(macConfig.FrameType,'UpIE2')||strcmp(macConfig.FrameType,'DownIE')
        frameControlControl = prepareFrameControl2(macConfig);
        frameControlElement = prepareControlElement(macConfig);
        frame = [frameControlControl,frameControlElement]';
        frame = appendFCS(frame);
    elseif strcmp(macConfig.FrameType,'BSR')
        frameControlControl = prepareFrameControl2(macConfig);
%         frameControlElement = bi2deOptimized(reshape(de2biOptimized(macConfig.BSRConfig.bsrinfo,32),8,[])')';
        frameControlElement = prepareControlElement(macConfig);
        frame = [frameControlControl,frameControlElement]';
        frame = appendFCS(frame);
    elseif strcmp(macConfig.FrameType,'PreCon_UpReq')||strcmp(macConfig.FrameType,'PreCon_UpRsp')||strcmp(macConfig.FrameType,'PreCon_UpEnd')||strcmp(macConfig.FrameType,'PreCon_DownReq')||strcmp(macConfig.FrameType,'PreCon_DownEnd')
        frameControlControl = prepareFrameControl2(macConfig);
        frameControlElement = prepareControlElement(macConfig);
        frame = [frameControlControl,frameControlElement]';
        frame = appendFCS(frame);
    elseif strcmp(macConfig.FrameType,'PreChal_Req')||strcmp(macConfig.FrameType,'PreChal_Rsp')
        frameControlControl = prepareFrameControl2(macConfig);
        frameControlElement = prepareControlElement(macConfig);
        frame = [frameControlControl,frameControlElement]';
        frame = appendFCS(frame);        
    elseif strcmp(macConfig.FrameType,'Beacon')
        frameControlControl = prepareFrameControl2(macConfig);
        frameControlElement = prepareControlElement(macConfig);
        frame = [frameControlControl,frameControlElement]';
        frame = appendFCS(frame);
    elseif strcmp(macConfig.FrameType,'AssocReq')
        frameControlControl = prepareFrameControl2(macConfig);
        frameControlElement = prepareControlElement(macConfig);
        frame = [frameControlControl,frameControlElement]';
        frame = appendFCS(frame);
    elseif strcmp(macConfig.FrameType,'ChannelReq')
        frameControlControl = prepareFrameControl2(macConfig);
        frameControlElement = prepareControlElement(macConfig);
        frame = [frameControlControl,frameControlElement]';
        frame = appendFCS(frame);
    else    % DownARQ、UpAQR
        frameControlControl = prepareFrameControl2(macConfig);
        frameControlElement = prepareControlElement(macConfig);
        frame = [frameControlControl,frameControlElement]';
        frame = appendFCS(frame);
    end
end
% 添加FCS校验码至最后。
function codedframe = appendFCS(frame)
  persistent gen
  if isempty(gen)
    gen = comm.CRCGenerator([32 26 23 22 16 12 11 10 8 7 5 4 2 1 0], 'InitialConditions', 1, 'DirectMethod', true, 'FinalXOR', 1);
  end

  % 1 octet = 8 bits
  octetLength = 8;

  % Convert octets to bits to add FCS
  frameBits = de2bi(frame, octetLength);
  frameBitsColVector = reshape(frameBits', numel(frameBits), 1);

  % Append FCS to the frame bits
  codedframe = gen(double(frameBitsColVector));
end
% 从实例化对象中获取源和目的地址
function add = prepareAddress(cfg)
    DestinationAdress = decOctetVector(cfg.Address1, 6, false);
    SourceAddress = decOctetVector(cfg.Address2, 6, false);
    add = [DestinationAdress,SourceAddress];
end
% 获取数据帧的控制字段
function frameControlData = prepareFrameControl1(cfg)
    type = getTypeCode(cfg.getType);
    subType = getSubtypeCode(cfg.getSubtype);
    tid = de2biOptimized(cfg.Tid,4);
    uid = de2biOptimized(cfg.Uid,8);
    seq = de2biOptimized(cfg.Seq,16);
    seq = reshape(seq,8,[])';
    frameControlData = uint8(bi2deOptimized([type,subType,tid;uid;seq])');
end
% 获取控制帧的控制字段
function frameControlControl = prepareFrameControl2(cfg)
    type = getTypeCode(cfg.getType);
    subType = getSubtypeCode(cfg.getSubtype);
    uid = de2biOptimized(cfg.Uid,8);
    transId = de2biOptimized(cfg.transId,8);
    reserved = de2biOptimized(cfg.reserved,8);
    frameControlControl = uint8(bi2deOptimized([type,subType;uid;transId;reserved])');
end
% 获取控制内容
function frameControlElement = prepareControlElement(cfg)
    if strcmp(cfg.FrameType,'UpIE1')||strcmp(cfg.FrameType,'UpIE2')||strcmp(cfg.FrameType,'DownIE')
        idx1 = de2biOptimized(cfg.IEConfig.idx1,5);
        dur1 = de2biOptimized(cfg.IEConfig.dur1,5);
        idx2 = de2biOptimized(cfg.IEConfig.idx2,5);
        dur2 = de2biOptimized(cfg.IEConfig.dur2,5);
        if strcmp(cfg.FrameType,'DownIE')
            channelNumbers = de2biOptimized(cfg.IEConfig.channelNumbers,2);
            reserved = de2biOptimized(cfg.IEConfig.reserved,2);
        else
            channelNumbers = de2biOptimized(cfg.IEConfig.channelNumbers,1);
            reserved = de2biOptimized(cfg.IEConfig.reserved,3);
        end
        frameControlElement = uint8(bi2deOptimized(reshape([idx1,dur1,idx2,dur2,channelNumbers,reserved],8,[])'))';
    elseif strcmp(cfg.FrameType,'UpARQ')||strcmp(cfg.FrameType,'DownARQ')
        tidNum = de2biOptimized(cfg.ARQConfig.tidNum,4);
        reserved = de2biOptimized(cfg.ARQConfig.reserved,4);
        fb_info = [];
        for i = 1 : cfg.ARQConfig.tidNum
            decOctets = validatePayloadFormat(cfg.ARQConfig.fb_info{i});
            fb_info = [fb_info;decOctets];
        end
        frameControlElement = uint8([bi2deOptimized([tidNum,reserved]);fb_info])';
    elseif strcmp(cfg.FrameType,'BSR')
        bsrbits = reshape(de2bi(cfg.BSRConfig.bsrinfo, 32)',1,[]);
        bsrinfo = bi2deOptimized(reshape(bsrbits,8,[])')';
        frameControlElement = bsrinfo;
    elseif strcmp(cfg.FrameType,'AssocReq')
        address = decOctetVector(cfg.Address2, 6, false);
        frameControlElement = address;
%         pos = 1;
%         address = dec2hex(bi2deOptimized(reshape(mpduBits(pos : pos+47), 8, [])'), 2);
%         frameControlElement = address;
    elseif strcmp(cfg.FrameType,'AssocRsp')   
         address = decOctetVector(cfg.Address1, 6, false);
         uid = cfg.AssocRspConfig.uid;
         dl_channel = cfg.AssocRspConfig.dl_channel;
         ul_channel = cfg.AssocRspConfig.ul_channel;
         frameControlElement = [address,uid,dl_channel,ul_channel];
%         pos = 1;
%         address = dec2hex(bi2deOptimized(reshape(mpduBits(pos : pos+47), 8, [])'), 2);
%         pos  = pos + 48;
%         uid = de2biOptimized(cfg.IEConfig.idx1,5);
%         frameControlElement = address;
    elseif strcmp(cfg.FrameType,'OfflineReq')
        address = decOctetVector(cfg.Address2, 6, false);
        frameControlElement = address;
    elseif strcmp(cfg.FrameType,'OfflineRsp')
        address = decOctetVector(cfg.Address1, 6, false);
        uid = cfg.OfflineRspConfig.uid;
        frameControlElement = [address,uid];
    elseif strcmp(cfg.FrameType,'PreCon_UpReq')
        Interval = de2biOptimized(cfg.PreConditionConfig.Interval,4);
        Slot_Num = de2biOptimized(cfg.PreConditionConfig.Slot_Num,4);
        frameControlElement = uint8(bi2deOptimized([Interval,Slot_Num]));
    elseif strcmp(cfg.FrameType,'PreCon_UpRsp')
        if cfg.PreConditionConfig.Status == 0
            Time_Index = de2biOptimized(cfg.PreConditionConfig.Time_Index,5);
            Interval = de2biOptimized(cfg.PreConditionConfig.Interval,5);
            Slot_Index = de2biOptimized(cfg.PreConditionConfig.Slot_Index,5);
            Slot_Num = de2biOptimized(cfg.PreConditionConfig.Slot_Num,4);
            Cycles_Num = de2biOptimized(cfg.PreConditionConfig.Cycles_Num,10);
            Reserved = de2biOptimized(cfg.PreConditionConfig.Reserved,2);
            frameControlElement = uint8(bi2deOptimized(reshape([cfg.PreConditionConfig.Status,Time_Index,Interval,Slot_Index,Slot_Num,Cycles_Num,Reserved],8,[])'))';
        else
            Interval = de2biOptimized(cfg.PreConditionConfig.Interval,5);
            Slot_Num = de2biOptimized(cfg.PreConditionConfig.Slot_Num,4);
            Reserved = de2biOptimized(cfg.PreConditionConfig.Reserved,6);
            frameControlElement = uint8(bi2deOptimized(reshape([cfg.PreConditionConfig.Status,Interval,Slot_Num,Reserved],8,[])'))';
        end
    elseif strcmp(cfg.FrameType,'PreCon_UpEnd')
        % 无控制内容，SubType为21
    elseif strcmp(cfg.FrameType,'PreCon_DownReq')
        Time_Index = de2biOptimized(cfg.PreConditionConfig.Time_Index,5);
        Interval = de2biOptimized(cfg.PreConditionConfig.Interval,5);
        Slot_Index = de2biOptimized(cfg.PreConditionConfig.Slot_Index,5);
        Slot_Num = de2biOptimized(cfg.PreConditionConfig.Slot_Num,4);
        Cycles_Num = de2biOptimized(cfg.PreConditionConfig.Cycles_Num,10);
        Reserved = de2biOptimized(cfg.PreConditionConfig.Reserved,3);
        frameControlElement = uint8(bi2deOptimized(reshape([Time_Index,Interval,Slot_Index,Slot_Num,Cycles_Num,Reserved],8,[])'))';
    elseif strcmp(cfg.FrameType,'PreCon_DownEnd')
        %无控制内容，SubType为23
    elseif strcmp(cfg.FrameType,'PreChal_Req')
        RequestType = de2biOptimized(cfg.PreChannelConfig.RequestType,2);
        Reserved = de2biOptimized(cfg.PreChannelConfig.Reserved,6);
        frameControlElement = uint8(bi2deOptimized(reshape([RequestType,Reserved],8,[])'))';
    elseif strcmp(cfg.FrameType,'PreChal_Rsp')
        if cfg.PreChannelConfig.Status == 1
            Reserved = de2biOptimized(cfg.PreChannelConfig.Reserved,7);
            UlChannel = de2biOptimized(cfg.PreChannelConfig.UlChannel,4);
            DlChannel = de2biOptimized(cfg.PreChannelConfig.DlChannel,4);
            frameControlElement = uint8(bi2deOptimized(reshape([cfg.PreChannelConfig.Status,Reserved,UlChannel,DlChannel],8,[])'))';
        elseif cfg.PreChannelConfig.Status == 0
            Reserved = de2biOptimized(cfg.PreChannelConfig.Reserved,7);
            frameControlElement = uint8(bi2deOptimized(reshape([cfg.PreChannelConfig.Status,Reserved],8,[])'))';
        end
    elseif strcmp(cfg.FrameType,'ChannelReq')
        up_channel = de2biOptimized(cfg.ChannelReqConfig.up_channel,4);
        down_channel = de2biOptimized(cfg.ChannelReqConfig.down_channel,4);
        frameControlElement = uint8(bi2deOptimized([up_channel,down_channel]));
    elseif strcmp(cfg.FrameType,'ACK')
        %无控制内容，SubType为16
        frameControlElement = [];
        frameControlElement = uint8(frameControlElement);
    else    % Beacon
        timeStamp = de2biOptimized(cfg.BeaconConfig.timeStamp,64);
        beaconInterval = de2biOptimized(cfg.BeaconConfig.beaconInterval,16);
        capabilityInfo = str2num(cfg.BeaconConfig.capabilityInfo);
        capabilityInfo = [capabilityInfo,zeros(1,9)];
        pollingBitmap = [0,42,cfg.BeaconConfig.pollingBitmap];
        frameControlElement = uint8(bi2deOptimized(reshape([timeStamp,beaconInterval,capabilityInfo],8,[])'))';
        frameControlElement = [frameControlElement,pollingBitmap];
    end
end
% 获取帧类型字段
function code = getTypeCode(type)
  switch(type)
    case 'Control'
      code = 1;
    otherwise % Data
      code = 0;
  end
end
% 获取帧子类型字段
function code = getSubtypeCode(type)
switch(type)        % MSB格式！！
  case 'Beacon'
    code = [0 0 0 0 0 0 0];
  case 'DownIE'
    code = [1 0 1 0 0 0 0];
  case 'UpIE1'
    code = [0 1 1 0 0 0 0];
  case 'UpIE2'
    code = [1 1 1 0 0 0 0];
  case 'UpARQ'
    code = [0 0 0 1 0 0 0];
  case 'DownARQ'
    code = [1 0 0 1 0 0 0];
  case 'BSR'
    code = [0 1 0 1 0 0 0];
  case 'AssocReq'
    code = [1 0 0 0 0 0 0];
  case 'AssocRsp'
    code = [0 1 0 0 0 0 0];
  case 'OfflineReq'
    code = [1 1 0 0 0 0 0];
  case 'OfflineRsp'
    code = [0 0 1 0 0 0 0];
  case 'PreCon_UpReq'
    code = [1 1 0 0 1 0 0];
  case 'PreCon_UpRsp'
    code = [0 0 1 0 1 0 0];
  case 'PreCon_UpEnd'
    code = [1 0 1 0 1 0 0];
  case 'PreCon_DownReq'
    code = [0 1 1 0 1 0 0];
  case 'PreCon_DownEnd'
    code = [1 1 1 0 1 0 0]; 
  case 'PreChal_Req'
    code = [1 0 0 0 1 0 0];
  case 'PreChal_Rsp'
    code = [0 1 0 0 1 0 0];  
  case 'ChannelReq'
    code = [0 0 0 1 1 0 0];
  case 'ACK'
    code = [0 0 0 0 1 0 0];
  otherwise % Data
    code = [0 0 0];
end
end
% 输入字符、字符串或者整数，输出uint8形式数组，需指定字节数和大小端格式
function octetVector = decOctetVector(value, numOctets, isLittleEndian)
  octetLen = 8;
  % 输入16进制字符（串）
  if isa(value, 'char') || isa(value, 'string')
    hexOctets = reshape(char(value), 2, [])';
    octetVector = uint8(hex2dec(hexOctets)');
    if isLittleEndian
      octetVector(1:end) = octetVector(end:-1:1);
    end
  else % 输入数字
    bits = de2biOptimized(value, octetLen*numOctets);
    bits = reshape(bits, octetLen, [])';
    octetVector = bi2deOptimized(bits)';
    octetVector = [octetVector zeros(1, numOctets-numel(octetVector))];
  end
  octetVector = uint8(octetVector);
end
% 二进制转十进制
function dec = bi2deOptimized(bin)
    dec = comm.internal.utilities.bi2deRightMSB(double(bin), 2);
end
% 将十进制数转化为二进制，需提供比特位数n
function bin = de2biOptimized(dec, n)
    bin = comm.internal.utilities.de2biBase2RightMSB(double(dec), n);
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
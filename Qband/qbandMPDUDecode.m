function [macConfig, payload, status] = qbandMPDUDecode(mpdu, varargin)

    % 检测输入参数个数，最多4个
    narginchk(2, 4);

    % 初始化帧对象、负载，接受varargin参数用于检测数据类型
    macConfig = QbandFrameConfig;
    payload = cell(1, 0);
    nvPair = varargin;
    % 暂定长度最大2304字节
    maxMPDULength = 2304;

    % 校验输入参数并返回状态与bit形式的mpdu（mpduColVector）
    [status, mpduColVector] = validateInputs(mpdu, nvPair);
    if status ~= wlanMACDecodeStatus.Success
        return;
    end

    % 检验 FCS（crc32）
    [status, mpdu] = checkFCS(mpduColVector);
    if status ~= wlanMACDecodeStatus.Success
        macConfig.DecodeFailed = true;
        return;
    end

    % 初始化数据指针
    pos = 1;

    % 提取Frame control (32-bits)中信息，存入macConfig，并更新状态
    frameControl = mpdu(pos : pos+31);
    [macConfig, status] = decodeFrameControl(macConfig, frameControl, status);
    if status ~= wlanMACDecodeStatus.Success
        macConfig.DecodeFailed = true;
        return;
    end
    pos = pos + 32;

    % 检查mpdu长度是否超出规定
    mpduLength = numel(mpdu)/8;
    if mpduLength > maxMPDULength
        status = wlanMACDecodeStatus.MaxMPDULengthExceeded;
        return;
    end

    % 解封装剩下的内容（add1、add2、type、payload或者控制帧的字段），控制帧之后写
    switch macConfig.getType
        case 'Control'
            [macConfig, status] = decodeControlFrame(macConfig, mpdu(pos:end), status);            
        otherwise % Data
            [macConfig, payload, status] = decodeDataFrame(macConfig, mpdu(pos:end), status);
    end

    if status ~= wlanMACDecodeStatus.Success
        macConfig.DecodeFailed = true;
        return;
    end
end

% 提取Frame control (32-bits)中信息，存入macConfig，并更新状态
function [macConfig, status] = decodeFrameControl(macConfig, frameControl, status)
    % 初始化指针（函数内部）
    pos = 1;
    
    % 获取Type (1-bits)
    [type, status] = getType(frameControl(pos), status);
    if status ~= wlanMACDecodeStatus.Success
        return;
    end
    pos = pos + 1;

    % D/C位之后数据帧和控制帧的Frame Control字段存在差别，需要分开提取信息
    if  strcmp(type, 'Data')    % 数据帧
        % 获取Subtype (3-bits)，存入macConfig.FrameType
        [subtype, status]= getSubtype(frameControl(pos : pos+2), type, status);
        if status ~= wlanMACDecodeStatus.Success
            return;
        end
        macConfig.FrameType = subtype;
        pos = pos + 3;

        % 获取Tid
        macConfig.Tid = bi2deOptimized(frameControl(pos : pos+3)');
        pos = pos + 4;

        % 获取Uid
        macConfig.Uid = bi2deOptimized(frameControl(pos : pos+7)');
        pos = pos + 8;

        % 获取Seq
        macConfig.Seq = bi2deOptimized(frameControl(pos : pos+15)');
        
    else
        % 获取Subtype (7-bits)，存入macConfig.FrameType
        [subtype, status]= getSubtype(frameControl(pos : pos+6), type, status);
        if status ~= wlanMACDecodeStatus.Success
            return;
        end
        macConfig.FrameType = subtype;
        pos = pos + 7;

        % 获取Uid
        macConfig.Uid = bi2deOptimized(frameControl(pos : pos+7)');
        pos = pos + 8;

        % 获取 transId
        macConfig.transId = bi2deOptimized(frameControl(pos : pos+7)');
        pos = pos + 8;

        % 获取reserved
        macConfig.reserved = bi2deOptimized(frameControl(pos : pos+7)');

    end



end

% 返回Type类型，更新状态
function [type, status] = getType(typeCode, status)
code = bi2deOptimized(typeCode');
switch code
    case 0
        type = 'Data';
    case 1
        type = 'Control';
    otherwise
        type = '';
        % 抛出错误
        coder.internal.warning('wlan:wlanMPDUDecode:UnsupportedFrameType', code);
        status = wlanMACDecodeStatus.UnsupportedFrameType;
end
end

% 返回subtype code，更新状态
function [subtype, status] = getSubtype(subtypeCode, type, status)
code = bi2deOptimized(subtypeCode');

if strcmp(type, 'Data')
    switch code
        case 0
            subtype = 'Data';
        otherwise
            subtype = '';
            % 抛出错误
            coder.internal.warning('wlan:wlanMPDUDecode:UnsupportedFrameSubtype', code, ...
                'data', '0, 4, 8, and 12');
            status = wlanMACDecodeStatus.UnsupportedFrameSubtype;
    end
else % Control
    switch code
        case 0
            subtype = 'Beacon';
        case 1
            subtype = 'AssocReq';
        case 2
            subtype = 'AssocRsp';
        case 3
            subtype = 'OfflineReq';
        case 4
            subtype = 'OfflineRsp';
        case 5
            subtype = 'DownIE';
        case 6
            subtype = 'UpIE1';
        case 7
            subtype = 'UpIE2';
        case 8
            subtype = 'UpARQ';
        case 9
            subtype = 'DownARQ';
        case 10
            subtype = 'BSR';
        case 16
            subtype = 'ACK';
        case 17
            subtype = 'PreChal_Req';
        case 18
            subtype = 'PreChal_Rsp';
        case 19
            subtype = 'PreCon_UpReq';
        case 20
            subtype = 'PreCon_UpRsp';
        case 21
            subtype = 'PreCon_UpEnd';
        case 22
            subtype = 'PreCon_DownReq';
        case 23
            subtype = 'PreCon_DownEnd';
        case 24
            subtype = 'ChannelReq';
        otherwise
            subtype = '';
            % 抛出错误
            coder.internal.warning('wlan:wlanMPDUDecode:UnsupportedFrameSubtype', ...
                code, 'control', '9, 11, 12, and 13');
            status = wlanMACDecodeStatus.UnsupportedFrameSubtype;
    end
end
end

% 二进制转十进制
function dec = bi2deOptimized(bin)
    dec = comm.internal.utilities.bi2deRightMSB(double(bin), 2);
end

% 校验 FCS
function [status, mpdu] = checkFCS(mpduWithFCS)
persistent detect

% CRC校验器
if isempty(detect)
    detect = comm.CRCDetector([32 26 23 22 16 12 11 10 8 7 5 4 2 1 0], 'InitialConditions', 1, 'DirectMethod', true, 'FinalXOR', 1);
end

% 校验 FCS，返回对错状态err
[mpdu, err] = detect(double(mpduWithFCS));
mpdu = reshape(mpdu, [], 1);

% 根据err更新状态
if err
    status = wlanMACDecodeStatus.FCSFailed;
else
    status = wlanMACDecodeStatus.Success;
end
end

% 检验输入参数
function [status, mpduBits] = validateInputs(mpdu, nvPair)

% 初始化
status = wlanMACDecodeStatus.Success;
mpduLength = numel(mpdu);
isAMPDU = 1;

% 从nvPair中得到输入数据类型
dataFormat = validateMACDecodeInputs(nvPair, isAMPDU);

if strcmpi(dataFormat, 'bits')
    validateattributes(mpdu, {'logical', 'numeric'}, {'binary', 'vector'}, '', 'MPDU');
    coder.internal.errorIf((rem(mpduLength, 8) ~= 0), 'wlan:shared:InvalidDataSize');
    mpduBits = double(reshape(mpdu, [], 1));
    
else % 数据为字节形式存储
    % 检验是否为hex形式或者dec形式
    validateattributes(mpdu, {'char', 'numeric', 'string'}, {}, mfilename, 'MPDU')
    
    if isnumeric(mpdu)
        validateattributes(mpdu, {'numeric'}, {'vector', 'integer', 'nonnegative', '<=', 255}, mfilename, 'MPDU');
        mpduBits = double(reshape(de2bi(mpdu, 8)', [], 1));
        
    else % hex形式的char或者string
        if ischar(mpdu)
            if isvector(mpdu)
                % Convert row vector to column of octets.
                columnOctets = reshape(mpdu, 2, [])';
            else
                validateattributes(mpdu, {'char'}, {'2d', 'ncols', 2}, mfilename, 'MPDU', 1);
                columnOctets = mpdu;
            end
        else % string
            validateattributes(mpdu, {'string'}, {'scalar'}, mfilename, 'MPDU')
            
            % 转化成char
            columnOctets = reshape(char(mpdu), 2, [])';
        end
        
        % 检验hex数据是否为偶数个
        validateHexOctets(columnOctets, 'MPDU');
        
        % 将hex转化成dec
        decOctets = hex2dec(columnOctets);
        % 转化成1列bit数据
        mpduBits = reshape(de2bi(decOctets, 8)', [], 1);
    end
end

% 检验最小mpdu长度. FCS和Frame Control总共8字节
if (numel(mpduBits)/8 < 8)
    status = wlanMACDecodeStatus.NotEnoughData;
    coder.internal.warning('wlan:wlanMPDUDecode:NotEnoughDataToParseMPDU');
end

end

% 解封装数据帧的address、type、payload
function [macConfig, payload, status] = decodeDataFrame(macConfig, mpduBits, status)
    % 初始化
    pos = 1;
    minOctets = 26;     
    payload = cell(1, 0);
    numDataBits = numel(mpduBits);

    % mpdu最小26字节，扣除FCS和FrameControl的8字节，最小大于18字节
%     if (numDataBits < 18*8)
    if (numDataBits < 8*8)
        coder.internal.warning('wlan:wlanMPDUDecode:NotEnoughDataToParseFrame', minOctets, 'Data');
        status = wlanMACDecodeStatus.NotEnoughData;
        return;
    end

    % Address1 (48 bits)
    address = dec2hex(bi2deOptimized(reshape(mpduBits(pos : pos+47), 8, [])'), 2);
    macConfig.Address1 = reshape(address', 1, []);
    pos = pos + 48;

    % Address2 (48 bits)
    address = dec2hex(bi2deOptimized(reshape(mpduBits(pos : pos+47), 8, [])'), 2);
    macConfig.Address2 = reshape(address', 1, []);
    pos = pos + 48;

    % type (16 bits,默认0800，直接跳过)
    pos = pos + 16;

    % payload
    msduLength = numel(mpduBits(pos:end))/8;
    
    % payload长度小于1500比特，大于则更新状态
    if msduLength > 1500
        status = wlanMACDecodeStatus.MaxMSDULengthExceeded;
        return;
    end
    
    % 存入payload，hex形式
    if (numDataBits >= pos)
        payload{end + 1} = dec2hex(bi2deOptimized(reshape(mpduBits(pos:end), 8, [])'), 2);
    end
end

% 解封装控制帧字段
function [macConfig, status] = decodeControlFrame(macConfig, mpduBits, status)
    % 每种控制帧字段均不同，需分类解封装
    if strcmp(macConfig.FrameType,'DownIE')||strcmp(macConfig.FrameType,'UpIE1')||strcmp(macConfig.FrameType,'UpIE2')
        % 初始化
        pos = 1;
        numDataBits = numel(mpduBits);

        % 长度应该为24bit，否则报错，更新status。


        % idx1
        idx1 = bi2deOptimized(mpduBits(pos : pos+4)');
        macConfig.IEConfig.idx1 = idx1;
        pos = pos + 5;

        % dur1
        dur1 = bi2deOptimized(mpduBits(pos : pos+4)');
        macConfig.IEConfig.dur1 = dur1;
        pos = pos + 5;

        % idx2
        idx2 = bi2deOptimized(mpduBits(pos : pos+4)');
        macConfig.IEConfig.idx2 = idx2;
        pos = pos + 5; 

        % dur2
        dur2 = bi2deOptimized(mpduBits(pos : pos+4)');
        macConfig.IEConfig.dur2 = dur2;
        pos = pos + 5;  

        % channelNumbers 和 reserved
        if strcmp(macConfig.IEConfig,'DownIE')
            channelNumbers = bi2deOptimized(mpduBits(pos : pos+1)');
            macConfig.IEConfig.channelNumbers = channelNumbers;
            pos = pos + 2;

            reserved = bi2deOptimized(mpduBits(pos : pos+1)');
            macConfig.IEConfig.reserved = reserved;
        else
            channelNumbers = bi2deOptimized(mpduBits(pos));
            macConfig.IEConfig.channelNumbers = channelNumbers;
            pos = pos + 1;

            reserved = bi2deOptimized(mpduBits(pos : pos+2)');
            macConfig.IEConfig.reserved = reserved;
        end

    elseif strcmp(macConfig.FrameType,'UpARQ')||strcmp(macConfig.FrameType,'DownARQ')
        pos = 1;
        tidNum = bi2deOptimized(mpduBits(pos : pos+3)');
        macConfig.ARQConfig.tidNum = tidNum;
        pos = pos + 4;

        reserved = bi2deOptimized(mpduBits(pos : pos+3)');
        macConfig.ARQConfig.reserved = reserved;
        pos = pos + 4;
        for i = 1:tidNum
            fb_infoNum = 4*bi2deOptimized(mpduBits(pos : pos + 11)') + 8;     %获取该单元字节数
            macConfig.ARQConfig.fb_info{i} = dec2hex(bi2deOptimized(reshape(mpduBits(pos : pos + fb_infoNum*8 - 1),8,[])'),2);
%             macConfig.ARQConfig.fb_info{i} = dec2hex(bi2deOptimized(reshape(mpduBits(pos:pos-1+fb_infoNum/tidNum),8,[])'),2);
            pos = pos + fb_infoNum*8;
        end

    elseif strcmp(macConfig.FrameType,'Beacon')
        pos = 1;
        timeStamp = bi2deOptimized(mpduBits(pos : pos + 63)');
        macConfig.BeaconConfig.timeStamp = timeStamp;
        pos = pos + 64;

        beaconInterval = bi2deOptimized(mpduBits(pos : pos + 15)');
        macConfig.BeaconConfig.beaconInterval = beaconInterval;
        pos = pos + 16;

        macConfig.BeaconConfig.capabilityInfo = num2str(mpduBits(pos : pos+6)');
        pos = pos + 16;
        pollingBitmap = bi2deOptimized(reshape(mpduBits(pos : pos + 42*8-1)',8,[])')';
        macConfig.BeaconConfig.pollingBitmap = pollingBitmap;

    elseif strcmp(macConfig.FrameType,'AssocReq')
        pos = 1;
        address = dec2hex(bi2deOptimized(reshape(mpduBits(pos : pos+47), 8, [])'), 2);
        macConfig.AssocReqConfig.mac_address = reshape(address', 1, []);
    elseif strcmp(macConfig.FrameType,'AssocRsp')
        pos = 1;
        address = dec2hex(bi2deOptimized(reshape(mpduBits(pos : pos+47), 8, [])'), 2);
        macConfig.AssocRspConfig.address = reshape(address', 1, []);
        pos = pos + 48;
        macConfig.AssocRspConfig.uid = bi2deOptimized(mpduBits(pos : pos+7)');
        pos = pos + 8;
        macConfig.AssocRspConfig.dl_channel = bi2deOptimized(mpduBits(pos : pos+7)');
        pos = pos + 8;
        macConfig.AssocRspConfig.ul_channel = bi2deOptimized(mpduBits(pos : pos+7)');
    elseif strcmp(macConfig.FrameType,'OfflineReq')
        pos = 1;
        address = dec2hex(bi2deOptimized(reshape(mpduBits(pos : pos+47), 8, [])'), 2);
        macConfig.OfflineReqConfig.mac_address = reshape(address', 1, []);
    elseif strcmp(macConfig.FrameType,'OfflineRsp')
        pos = 1;
        address = dec2hex(bi2deOptimized(reshape(mpduBits(pos : pos+47), 8, [])'), 2);
        macConfig.OfflineRspConfig.address = reshape(address', 1, []);
        pos = pos + 48;
        macConfig.OfflineRspConfig.uid = bi2deOptimized(mpduBits(pos : pos+7)');
    elseif strcmp(macConfig.FrameType,'PreCon_UpReq')
        pos = 1;
        Interval = bi2deOptimized(mpduBits(pos:pos+3)');
        macConfig.PreConditionConfig.Interval = Interval;
        pos = pos + 4;

        Slot_Num = bi2deOptimized(mpduBits(pos:pos+3)');
        macConfig.PreConditionConfig.Slot_Num = Slot_Num;
    elseif strcmp(macConfig.FrameType,'PreCon_UpRsp')
        pos = 1;
        Status = mpduBits(pos);
        macConfig.PreConditionConfig.Status = Status;
        pos = pos + 1;

        Time_Index = bi2deOptimized(mpduBits(pos:pos+4)');
        macConfig.PreConditionConfig.Time_Index = Time_Index;
        pos = pos + 5;

        Interval = bi2deOptimized(mpduBits(pos:pos+4)');
        macConfig.PreConditionConfig.Interval = Interval;
        pos = pos + 5;

        Slot_Index = bi2deOptimized(mpduBits(pos:pos+4)');
        macConfig.PreConditionConfig.Slot_Index = Slot_Index;
        pos = pos + 5;

        Slot_Num = bi2deOptimized(mpduBits(pos:pos+3)');
        macConfig.PreConditionConfig.Slot_Num = Slot_Num;
        pos = pos + 4;

        Cycles_Num = bi2deOptimized(mpduBits(pos:pos+9)');
        macConfig.PreConditionConfig.Cycles_Num = Cycles_Num;
        pos = pos + 10;

        Reserved = bi2deOptimized(mpduBits(pos:pos+1)');
        macConfig.PreConditionConfig.Reserved = Reserved;
    elseif strcmp(macConfig.FrameType,'PreCon_DownReq')
        pos = 1;
        Time_Index = bi2deOptimized(mpduBits(pos:pos+4)');
        macConfig.PreConditionConfig.Time_Index = Time_Index;
        pos = pos + 5;

        Interval = bi2deOptimized(mpduBits(pos:pos+4)');
        macConfig.PreConditionConfig.Interval = Interval;
        pos = pos + 5;

        Slot_Index = bi2deOptimized(mpduBits(pos:pos+4)');
        macConfig.PreConditionConfig.Slot_Index = Slot_Index;
        pos = pos + 5;

        Slot_Num = bi2deOptimized(mpduBits(pos:pos+3)');
        macConfig.PreConditionConfig.Slot_Num = Slot_Num;
        pos = pos + 4;

        Cycles_Num = bi2deOptimized(mpduBits(pos:pos+9)');
        macConfig.PreConditionConfig.Cycles_Num = Cycles_Num;
        pos = pos + 10;

        Reserved = bi2deOptimized(mpduBits(pos:pos+2)');
        macConfig.PreConditionConfig.Reserved = Reserved;
    elseif strcmp(macConfig.FrameType,'PreChal_Req')
        pos = 1;
        RequestType = bi2deOptimized(mpduBits(pos:pos+1)');
        macConfig.PreChannelConfig.RequestType = RequestType;
        pos = pos + 2;

        Reserved = bi2deOptimized(mpduBits(pos:pos+5)');
        macConfig.PreChannelConfig.Reserved = Reserved;
    elseif strcmp(macConfig.FrameType,'PreChal_Rsp')
        pos = 1;
        Status = mpduBits(pos);
        macConfig.PreChannelConfig.Status = Status;
        pos = pos + 1;

        Reserved = bi2deOptimized(mpduBits(pos:pos+6)');
        macConfig.PreChannelConfig.Reserved = Reserved;
        pos = pos + 7;

        UlChannel = bi2deOptimized(mpduBits(pos:pos+3)');
        macConfig.PreChannelConfig.UlChannel = UlChannel;
        pos = pos + 4;

        DlChannel = bi2deOptimized(mpduBits(pos:pos+3)');
        macConfig.PreChannelConfig.DlChannel = DlChannel;     
    elseif strcmp(macConfig.FrameType,'PreCon_DownEnd')||strcmp(macConfig.FrameType,'PreCon_UpEnd')||strcmp(macConfig.FrameType,'ACK')
        % 结束帧和ACK无控制信息
    elseif strcmp(macConfig.FrameType,'ChannelReq')
        pos = 1;
        up_channel =  bi2deOptimized(mpduBits(pos : pos + 3)');
        macConfig.ChannelReqConfig.up_channel = up_channel;
        pos = pos + 4;

        down_channel = bi2deOptimized(mpduBits(pos : pos + 3)');
        macConfig.ChannelReqConfig.down_channel = down_channel;
        
    else    % BSR
        pos = 1;
        bsrinfo = bi2deOptimized(reshape(mpduBits(pos : end),32,[])')';
        macConfig.BSRConfig.bsrinfo = bsrinfo;
    end
end

function [mpduList, delimiterCRCFails, status,Length] = AMPDUDeaggregate(ampdu, varargin)
    % 初始化子帧计数器、CRC错误列表、mpduList
    subframeCount = 0;
    failedIdx = cell(1, 0);
    mpduList = cell(1, 0);
    delimiterCRCFails = false(1, 0);
    Length = [];    %记录每个帧的长度
    % 接收额外输入参数
    nvPair = varargin;

    % 校验输入参数
    [status, ampdu] = validateInputs(ampdu, nvPair);
    if status ~= wlanMACDecodeStatus.Success
        return;
    end

    % 初始化汇聚后帧总长度
    i = 1;
    ampduLength = numel(ampdu);
    
    % 循环探测汇聚帧的各个帧头（分隔符），帧头固定4byte，且signature固定78
    while (i + 3) <= ampduLength
        % Signature在分隔符第一位
        if ampdu(i) == 78
            % 取出分隔符，以bit为单位
            delimiterWithCRC = reshape(de2bi(ampdu(i : i+3), 8)', [], 1);
            % 核查CRC,传回的delimiter为十进制，单行
            [delimiter, err] = checkDelimiterCRC(delimiterWithCRC);
            i = i+4;

            % 如果crc错误
            if err
                % 如果错误，则尽最大可能保全数据：如果监测到数据总量大于14字节，则接受为payload
                % 定义发生错误的长度
                failedMPDULength = 0;
                j = i;
                while (j + 3) <= ampduLength
                    % 如果找到下一个分隔符，则直接跳出循环
                    if (ampdu(j) == 78)
                        break;
                    end
                    % 否则移动4字节继续寻找
                    j = j + 4;
                    % 不断增加的错误字段长度
                    failedMPDULength = failedMPDULength + 4;
                end
                if (j + 3) >= ampduLength   % 超出ampdu总长度。一般长度都是4整数倍，这里以防万一取4的模
                    failedMPDULength = failedMPDULength + rem(ampduLength, 4);
                end
                % 最大MPDU长度（不包含分隔符，此处待商榷）
                maxMPDULength = 4095;              
                if failedMPDULength > maxMPDULength
                    failedMPDULength = maxMPDULength;
                end
                % 如果长度大于14字节，则存入mpduList
                if (failedMPDULength >= 14) && ((i + failedMPDULength - 1) <= ampduLength)
                    subframeCount = subframeCount + 1;
                    failedIdx{end + 1} = subframeCount;
                    mpduList{end+1} = dec2hex(ampdu(i : i+failedMPDULength-1), 2);
                    i = i + failedMPDULength;
                end
                continue;  
            else % crc检测通过
                % 提取mpdu长度
                mpduLength = bi2deOptimized(delimiter(17:28));
                % If zero delimiters are encountered, continue searching for a
                % non-zero delimiter.
                if (mpduLength == 0)
                    continue;
                end
            end

            % 给mpdu子帧计数
            subframeCount = subframeCount + 1;
            
            % 将每个mpdu按照hex格式存入mpduList（元胞数组）
            if (i + mpduLength - 1) <= ampduLength
                mpduList{end + 1} = dec2hex(ampdu(i : i+mpduLength-1), 2);
                Length(end + 1) = mpduLength; 
            else
                mpduList{end + 1} = dec2hex(ampdu(i : end), 2);
                status = wlanMACDecodeStatus.InvalidDelimiterLength;
                break;
            end
            i = i + mpduLength;
            % 检测padding并跳过它
            pad = abs(mod(mpduLength, -4));
            if pad
                i = i + pad;
            end
        else    % 如果不是signature，则直接向后移动4比特
            i = i+4;
        end
    end

    % 如果子帧个数为0，则修改状态为没有找到任何MPDU
    if subframeCount == 0
        status = wlanMACDecodeStatus.NoMPDUFound;
    % 统计分隔符crc错误个数，并生成错误/成功向量
    else
        delimiterCRCFails = false(1, subframeCount);
        
        % 在创造的bitmap中指定出错误mpdu的位置
        for i = 1:numel(failedIdx)
            delimiterCRCFails(failedIdx{i}) = 1;
        end
        
        % 如果全错，则修改状态
        if all(delimiterCRCFails)
            status = wlanMACDecodeStatus.CorruptedAMPDU;
        end
    end

end


function [delimiter, err] = checkDelimiterCRC(delimiterWithCRC)
% 产生CRC8序列，用于检验
persistent gen
if isempty(gen)
    gen = comm.CRCGenerator([8 2 1 0], 'InitialConditions', [1 1 1 1 1 1 1 1], 'DirectMethod', true, 'FinalXOR', 1);
end

% 提取分隔符中的crc，再将其赋0以计算新的crc进行对比
crcReceive = bi2deOptimized(delimiterWithCRC(9:16)');
delimiterWithCRC(9:16) = 0;

% 比较CRC8，更新err，不相等置1
delimiterWithCRC = gen(delimiterWithCRC);
delimiterWithCRC = bi2deOptimized(reshape(delimiterWithCRC, 8, [])');
delimiterWithCRC(2) = delimiterWithCRC(end);
delimiterWithCRC(end) = [];
err = ~isequal(crcReceive,delimiterWithCRC(2));

delimiter = reshape(de2biOptimized(delimiterWithCRC,8)',1,[]);

end

%二进制转十进制
function dec = bi2deOptimized(bin)
    dec = comm.internal.utilities.bi2deRightMSB(double(bin), 2);
end

% 将十进制数转化为二进制，需提供比特位数n
function bin = de2biOptimized(dec, n)
    bin = comm.internal.utilities.de2biBase2RightMSB(double(dec), n);
end

function [status, decOctets] = validateInputs(ampdu, nvPair)
    % 初始化
    status = wlanMACDecodeStatus.Success;
    ampduLength = numel(ampdu);
    isAMPDU = true;

    % 检查输入的格式、返回bits、octets
    dataFormat = validateMACDecodeInputs(nvPair, isAMPDU);

    %若是bits格式，则转化为8bits一单位的decimal格式
    if strcmpi(dataFormat, 'bits')
        validateattributes(ampdu, {'logical', 'numeric'}, {'binary', 'vector'}, '', 'A-MPDU');
        coder.internal.errorIf((rem(ampduLength, 8) ~= 0), 'wlan:shared:InvalidDataSize');
        ampduColVector = reshape(ampdu, 1, []);
        decOctets = bi2deOptimized(reshape(ampduColVector, 8, [])')';
    else
        % 检查格式是否为hex或者decimal，如果不是则报错
        validateattributes(ampdu, {'char', 'numeric', 'string'}, {}, mfilename, 'payload');
        % 若格式为demical数字，则直接存入decOctets
        if isnumeric(ampdu)
            validateattributes(ampdu, {'numeric'}, {'vector', 'integer', 'nonnegative', '<=', 255}, mfilename, 'A-MPDU');
            decOctets = reshape(ampdu, 1, []);
            decOctets = double(decOctets);
        % 若为hex，则进行转换
        else 
            if ischar(ampdu)
                if isvector(ampdu)
                    % 如果为单字符，则转换为n*2的矩阵，因为1byte是两个16hex字符
                    hexOctets = reshape(ampdu, 2, [])';
                else
                    validateattributes(ampdu, {'char'}, {'2d', 'ncols', 2}, mfilename, 'A-MPDU', 1);
                    hexOctets = ampdu;
                end
                
            else % string
                validateattributes(ampdu, {'string'}, {'scalar'}, mfilename, 'A-MPDU')
                
                % 字符串需要转为字符后再重组
                hexOctets = reshape(char(ampdu), 2, [])';
            end
            % 将hex转为dec
            decOctets = hex2dec(hexOctets)';
        end
    end
    % 校验长度，如果不合规定则修改状态status
%     if (numel(decOctets) < 18)  %zhao 此处18修改为12
    if (numel(decOctets) < 12)  %zhao 此处18修改为12
        status = wlanMACDecodeStatus.NotEnoughData;
        coder.internal.warning('wlan:wlanAMPDUDeaggregate:NotEnoughDataToParseAMPDU');
    end
end
function [AmpduList,MUList,delimiterCRCFails] = qbandBaledFrameDecode(baledframe, varargin)
    % 初始化子帧计数器、CRC错误列表、AmpduList、MUList
    subframeCount = 0;
    failedIdx = cell(1, 0);
    AmpduList = cell(1, 0);
    MUList = cell(1, 0);
    delimiterCRCFails = false(1, 0);
    % 接收额外输入参数,用于判断输入格式
    nvPair = varargin;

    % 校验输入参数，输出1行
    baledframe = validateInputs(baledframe, nvPair);

    % 初始化汇聚后帧总长度
    i = 1;
    baledframeLength = numel(baledframe);

    % 循环探测打捆帧的各个帧头（分隔符），帧头固定8byte，且signature固定78,wang:将签名字段暂时改为49381
    while (i+7) <= baledframeLength
        % Signature在分隔符第一位,占16bit
        if isequal(baledframe(i:i+1),bi2deOptimized(reshape(de2biOptimized(49381,16)',8,[])')')
            % 取出分隔符，以bit为单位,单列
            delimiterWithCRC = reshape(de2bi(baledframe(i : i+7), 8)', [], 1);

            % 核查CRC,传回的delimiter为十进制，单行
            subframeLength = bi2deOptimized(delimiterWithCRC(29:44)');   % 获取子帧长度
            if i + 8 > numel(baledframe) || i+8+subframeLength-1 > numel(baledframe)
                fprintf('error\n');
            end
            subframeforcrcVerify = baledframe(i+8:i+8+subframeLength-1);    % 获取该子帧（crc校验正确未知）
            err = checkDelimiterCRC(delimiterWithCRC,subframeforcrcVerify);     % 获取crc标志

            % 获取MUList
            MCS = bi2deOptimized(delimiterWithCRC(17:20)');
            Uid = bi2deOptimized(delimiterWithCRC(21:28)');
            MUList{end + 1} = [MCS;Uid];

            i = i+8;

            % 如果crc错误
            if err
                % 如果错误，则尽最大可能保全数据：如果监测到数据总量大于14字节，则接受
                % 定义发生错误的长度
                failedMPDULength = 0;
                j = i;

                while (j + 7) <= baledframeLength
                    % 如果找到下一个分隔符，则直接跳出循环
                    if isequal(baledframe(j:j+1),bi2deOptimized(reshape(de2biOptimized(78,16)',8,[])')')
                        break;
                    end
                    
                    % 否则移动4字节继续寻找
                    j = j + 4;
                    
                    % 不断增加的错误字段长度
                    failedMPDULength = failedMPDULength + 4;
                end
                
                if (j + 7) >= baledframeLength   % 超出总长度。一般长度都是4整数倍，这里以防万一取4的模
                    failedMPDULength = failedMPDULength + rem(baledframeLength, 4);
                end
                
                % 最大长度（不包含分隔符，此处待商榷）
                maxLength = 4095;              
                if failedMPDULength > maxLength
                    failedMPDULength = maxLength;
                end
                
                % 如果长度大于14字节，则存入AmpduList
                if (failedMPDULength >= 14) && ((i + failedMPDULength - 1) <= baledframeLength)
                    subframeCount = subframeCount + 1;
                    failedIdx{end + 1} = subframeCount;
                    AmpduList{end + 1} = dec2hex(baledframe(i : i+failedMPDULength-1), 2);
                    i = i + failedMPDULength;
                end
                
                continue;
                
            else % crc检测通过
                % 提取Ampdu长度
                AmpduLength = bi2deOptimized(delimiterWithCRC(29:44)');
                
                % If zero delimiters are encountered, continue searching for a
                % non-zero delimiter.
                if (AmpduLength == 0)
                    continue;
                end
            end

            % 给mpdu子帧计数
            subframeCount = subframeCount + 1;

            % 将每个Ampdu按照hex格式存入AmpduList（元胞数组）
            if (i + AmpduLength - 1) <= baledframeLength
                AmpduList{end + 1} = dec2hex(baledframe(i : i+AmpduLength-1), 2);
            else
                AmpduList{end + 1} = dec2hex(baledframe(i : end), 2);
                break;
            end
            i = i + AmpduLength;

            % 此处没有padding
        else
            i = i+4;% 如果不是signature，则直接向后移动4比特
        end
    end

    % 统计分隔符crc错误个数，并生成错误/成功向量
    delimiterCRCFails = false(1, subframeCount);    
    % 在创造的bitmap中指定出错误mpdu的位置
    for i = 1:numel(failedIdx)
        delimiterCRCFails(failedIdx{i}) = 1;
    end
end

function decOctets = validateInputs(ampdu, nvPair)
    % 初始化
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
end


function err = checkDelimiterCRC(delimiterWithCRC,subframeforcrcVerify)
% 产生CRC16序列，用于检验
persistent gen
if isempty(gen)
    gen = comm.CRCGenerator([16 15 2 0], 'InitialConditions', 1, 'DirectMethod', true, 'FinalXOR', 1);
end

% 提取分隔符中的crc，与计算的crc进行对比
crcReceive = delimiterWithCRC(45:60);
subframeforcrcVerifyBits = reshape(de2bi(subframeforcrcVerify, 8)', [], 1);
subframeforcrcVerifyBits = double(subframeforcrcVerifyBits);
subframeforcrcVerifyBits = gen(subframeforcrcVerifyBits);
crcNew = subframeforcrcVerifyBits(end-15:end);
err = ~isequal(crcReceive,crcNew);

end


%二进制转十进制
function dec = bi2deOptimized(bin)
    dec = comm.internal.utilities.bi2deRightMSB(double(bin), 2);
end

% 将十进制数转化为二进制，需提供比特位数n
function bin = de2biOptimized(dec, n)
    bin = comm.internal.utilities.de2biBase2RightMSB(double(dec), n);
end
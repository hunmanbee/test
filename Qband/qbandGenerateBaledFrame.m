function [BaledFrame,frameLength] = qbandGenerateBaledFrame(AmpduList,MUList,varargin)
    % 函数输入多个汇聚帧以及它们各自MCS和Uid信息用于打捆，输出打捆帧和帧长度(输入输出格式均为10进制)
    
    % 获取输入的AMPDU帧个数,定义最大个数(后续定义)
    numAMPDUs = numel(AmpduList);

    % 接收额外输入参数
    nvPair = varargin;

    % 构建元胞数组，存放加了连接符的子帧
    subFrame = cell(1, numAMPDUs);
    psduLengthCounter = 0;  %计数器

    % 循环添加分隔符
    for i = 1 : numAMPDUs
        decOctets = validateInputs(AmpduList{i}, nvPair);   % 统一输入格式为decmical,decOctets为单行
        Delimiter = generateDelimiter(decOctets',MUList{i});
        BaledSubFrame = [Delimiter;decOctets'];
        psduLengthCounter = psduLengthCounter + numel(BaledSubFrame);
        subFrame{i} = BaledSubFrame;
    end
    
    % 将subFrame的所有元素连接起来
    frameLength = psduLengthCounter;
    BaledFrame = uint8(zeros(psduLengthCounter, 1));
    pos = 1;
    for i = 1:numAMPDUs
      % Add each subframe to the A-MPDU buffer
      BaledFrame(pos : pos+numel(subFrame{i})-1) = subFrame{i};
      pos = pos + numel(subFrame{i});
    end
end

% 产生分隔符
function Delimiter = generateDelimiter(Ampdu,MU)
    % 生成CRC16序列
    persistent gen 
    if isempty(gen)
        gen = comm.CRCGenerator([16 15 2 0], 'InitialConditions', 1, 'DirectMethod', true, 'FinalXOR', 1);
    end

    % Signature默认78，占16bit,wang:暂时改为12345
    delimiterSignature = 49381;
    delimiterSignature = de2biOptimized(delimiterSignature,16)';

    % MCS,Uid从MU数组中提取,分别占4bit和8bit
    MCS = de2biOptimized(MU(1),4)';
    Uid = de2biOptimized(MU(2),8)';

    % 子帧长度，占16bit
    dataLength = de2biOptimized(numel(Ampdu),16)';

    % 获取子帧CRC16，占16bit
    AmpduBits = de2biOptimized(Ampdu,8);
    Crc = gen(reshape(AmpduBits',numel(AmpduBits),1));
    CrcBits = Crc(end-15:end);  % 最后16位为crc
    
    % reserved为0，占4bit
    reserved = zeros(4,1);

    Delimiter = [delimiterSignature;MCS;Uid;dataLength;CrcBits;reserved];
    Delimiter = bi2deOptimized(reshape(Delimiter,8,[])');
    Delimiter = uint8(Delimiter);
end

%二进制转十进制
function dec = bi2deOptimized(bin)
    dec = comm.internal.utilities.bi2deRightMSB(double(bin), 2);
end
% 将十进制数转化为二进制，需提供比特位数n
function bin = de2biOptimized(dec, n)
    bin = comm.internal.utilities.de2biBase2RightMSB(double(dec), n);
end
% 检验输入格式并转换为统一格式
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
    % 校验长度，如果不合规定则修改状态status
    if (numel(decOctets) < 18)
        coder.internal.warning('wlan:wlanAMPDUDeaggregate:NotEnoughDataToParseAMPDU');
    end
end

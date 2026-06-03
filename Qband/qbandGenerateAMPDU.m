function [ampdu, frameLength] = qbandGenerateAMPDU(mpduList)
    %函数输入mpdu的元胞数组，每个元素即一个mpdu，输出汇聚的ampdu，均为uint8格式，同时给出ampdu长度。

    % 获取输入的MPDU帧个数,定义最大个数
    numMPDUs = numel(mpduList);
    maxMPDUs = 1024;

    %构建元胞数组，存放加了连接符和padding的帧
    subFrame = cell(1, numMPDUs);
    psduLengthCounter = 0;  %计数器
    if numMPDUs <= maxMPDUs
        %循环给每个MPDU加连接符和padding
        for i = 1:numMPDUs
            % 产生连接符
            mpduDelimiter = generateMPDUDelimiter(numel(mpduList{i}));
            % 加入padding
            ampduSubFrame = addSubframePadding([mpduDelimiter; mpduList{i}]);
            psduLengthCounter = psduLengthCounter + numel(ampduSubFrame);
            % 将ampduSubFrame填入subFrame元胞数组
            subFrame{i} = ampduSubFrame;
        end
    end
    % 将subFrame的所有元素连接起来
    frameLength = psduLengthCounter;
    ampdu = uint8(zeros(psduLengthCounter, 1));
    pos = 1;
    for i = 1:numMPDUs
      % Add each subframe to the A-MPDU buffer
      % Note: Last subframe includes EOF padding in case of VHT A-MPDU
      ampdu(pos : pos+numel(subFrame{i})-1) = subFrame{i};
      pos = pos + numel(subFrame{i});
    end
end



%产生连接符，包含signature、crc8、length、reserved四个字段
function mpduDelimiter = generateMPDUDelimiter(mpduLength)

  % 产生CRC8序列
  persistent gen
  if isempty(gen)
    gen = comm.CRCGenerator([8 2 1 0], 'InitialConditions', [1 1 1 1 1 1 1 1], 'DirectMethod', true, 'FinalXOR', 1);
  end

  % Signature默认78，占8bit
  delimiterSignature = 78;

  % 先默认CRC为0，占8bit
  crc = zeros(8, 1);

  % 子帧长度（不含连接符），占12bit
  mpduLength = de2biOptimized(mpduLength, 12)';

  % reserved部分，4bit
  reserved = zeros(4, 1);

  % 更新CRC8
  mpduDelimiter = gen([de2bi(delimiterSignature, 8)';crc;mpduLength;reserved]);
  mpduDelimiter = bi2deOptimized(reshape(mpduDelimiter, 8, [])');
  mpduDelimiter(2) = mpduDelimiter(end);
  mpduDelimiter(end) = [];
  mpduDelimiter = uint8(mpduDelimiter);

end

%二进制转十进制
function dec = bi2deOptimized(bin)
    dec = comm.internal.utilities.bi2deRightMSB(double(bin), 2);
end
% 将十进制数转化为二进制，需提供比特位数n
function bin = de2biOptimized(dec, n)
    bin = comm.internal.utilities.de2biBase2RightMSB(double(dec), n);
end

% 加入padding
function paddedFrame = addSubframePadding(frame)
  numOctets = numel(frame);
  if mod(numOctets, 4)
    bytePadding = 4 - mod(numOctets, 4);
    paddedFrame = [frame; uint8(zeros(bytePadding, 1))];
  else
    paddedFrame = frame;
  end
end
function [bonding_Ampdu,outputArg2] = qbandBondingAMPDU(Ampdu_list,uid,data_len,MCS_list)  
%函数输入A-mpdu的元胞数组，每个元素即一个A-mpdu，输出打捆的ampdu，均为uint8格式，wang:拟定输入的时候附带一个mcs表，表示每个子帧用哪个MCS等级

    % 获取输入的MPDU帧个数,定义最大个数
    numA_MPDUs = numel(Ampdu_list);
    maxA_MPDUs = 1024;

    %构建元胞数组，存放加了连接符和padding的帧
    subFrame = cell(1, numA_MPDUs);
    psduLengthCounter = 0;  %计数器
    if numA_MPDUs <= maxA_MPDUs
        %循环给每个MPDU加连接符和padding
        for i = 1:numA_MPDUs
            % 产生连接符
            BondingDelimiter = generateBondingDelimiter(Ampdu_list{i},uid,data_len,MCS_list(i));
            % 加入padding
            ampduSubFrame = addSubframePadding([BondingDelimiter; Ampdu_list{i}]);
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
function BondingDelimiter = generateBondingDelimiter(A_mpdu,uid,data_len,mcs)

  % 产生CRC8序列
  persistent gen
  if isempty(gen)
    gen = comm.CRCGenerator([16 15 2 0], 'InitialConditions', [1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1], 'DirectMethod', true, 'FinalXOR', 1);
  end

  % Signature取为81，占16bit,wang:这个特征签名字段随便赋的值
  delimiterSignature = 81;

  % 先默认CRC为0，占16bit
  crc = zeros(16, 1);
  
  
  
  % 子帧帧体转换
  mpduColVector = FCS16(A_mpdu);

  % reserved部分，4bit
  reserved = zeros(4, 1);
  
  %汇聚帧帧体部分

  % 更新CRC8
  BondingDelimiter = gen([de2bi(delimiterSignature, 16)';de2bi(mcs, 4)';de2bi(uid, 8)';de2bi(data_len, 16)';crc;reserved;mpduColVector]);
  BondingDelimiter = bi2deOptimized(reshape(BondingDelimiter, 8, [])');
  BondingDelimiter(2) = BondingDelimiter(end);
  BondingDelimiter(end) = [];
  BondingDelimiter = uint8(BondingDelimiter);

end
function dec = bi2deOptimized(bin)
    dec = comm.internal.utilities.bi2deRightMSB(double(bin), 2);
end
% 将十进制数转化为二进制，需提供比特位数n
function bin = de2biOptimized(dec, n)
    bin = comm.internal.utilities.de2biBase2RightMSB(double(dec), n);
end
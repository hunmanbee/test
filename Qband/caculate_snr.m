function snrW = caculate_snr(channel_width, dist, fc, powerLevel, txGain,F)
lambda = 3e8/fc;
%1）	根据中心频率和距离计算路径衰减
pathLoss = fspl(dist, lambda);
%2）	计算接收功率
rxPowerdBm = powerLevel + txGain - pathLoss;
rxPowermW = 10^(rxPowerdBm/10);
signal = (rxPowermW / 1000)*F;      %由AOA误差造成的损失
%3）	根据信道带宽计算计算噪声功率
noise = caculate_noise(channel_width);
%4）	计算SNR
snrW = double(signal/noise);
end

function noise = caculate_noise(channel_width)
    % thermal noise at 290K in J/s = W
    BOLTZMANN = 1.3803e-23;
    % Nt is the power of thermal noise in W at 290K
    Nt = BOLTZMANN * 290 * double(channel_width) * 1000000;
    rxNoiseFigure = 7;
    noiseFigure = 10^(rxNoiseFigure/10);
    noiseFloor = noiseFigure * Nt;
    noise = noiseFloor;
end

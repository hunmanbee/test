load const_value
fc = 42e9;
nbits = 1000;
mcs_idx = 8;
dist = 5;
mcs_ss = mcs_table().table_elem;
channel_width = 1080;
powerLevel = 15;
txGain = 10;
snr = caculate_snr(channel_width, dist, fc, powerLevel, txGain);
fprintf('snr = %d\n',snr);
for mcs_idx = 1 : 8
    csr = GetChunkSuccessRate (mcs_ss(mcs_idx),snr, nbits);
    fprintf('csr = %d\n',csr);
end

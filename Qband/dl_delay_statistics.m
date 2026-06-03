function dl_avg_delay = dl_delay_statistics(handle, aver_dl_tx, sta_id,k)
    AP_mac = handle.ap;
    sta = handle.stas;
    sta_num = numel(sta);
    
    % 初始化输出
    sta_dl_delay = zeros(1, sta_num);
    
    % 配置参数
    min_samples = 0;        % 最小样本数要求
    
    % 统计下行时延 (AP发送 -> STA接收)
    dl_tx_samples = 0;
     
    total_dl_tx_delay = 0;
    total_dl_tx_packets = 0;
    
    for tid = 1:8
        tx_bagnum = AP_mac.stas_info(k).dl_tx_info(tid).tot_tx_bagnum;
        tx_delay = AP_mac.stas_info(k).dl_tx_info(tid).tot_tx_delay;
        
        if tx_bagnum >= min_samples
            avg_delay = tx_delay / tx_bagnum ;  % 转换为ms
            
            total_dl_tx_delay = total_dl_tx_delay + avg_delay;
            total_dl_tx_packets = total_dl_tx_packets + 1;
            dl_tx_samples = dl_tx_samples + tx_bagnum;
            
            fprintf('  STA%d TID%d: 下行发送时延=%.3fms (%d个包)\n',sta_id, tid-1, avg_delay, tx_bagnum);
            
            % 重置计数器
            AP_mac.stas_info(k).dl_tx_info(tid).tot_tx_delay = 0;
            AP_mac.stas_info(k).dl_tx_info(tid).tot_tx_bagnum = 0;
        % elseif tx_bagnum > 0
        %     fprintf('  STA%d TID%d: 样本不足 (%d < %d)，跳过统计\n', sta_id, tid-1, tx_bagnum, min_samples);
        end
    end
    
    if total_dl_tx_packets > 0
        sta_dl_delay(sta_id) = total_dl_tx_delay / total_dl_tx_packets;
        dl_avg_delay = [aver_dl_tx, sta_dl_delay(sta_id)];
    end
      
end
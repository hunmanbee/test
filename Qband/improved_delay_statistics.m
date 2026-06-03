function [handle, aver_dl_tx, aver_dl_rx, aver_ul_tx, aver_ul_rx, sta_ul_delay, sta_dl_delay, sta_dl_pkt_count, sta_ul_pkt_count] = improved_delay_statistics(handle, fid, aver_dl_tx, aver_dl_rx, aver_ul_tx, aver_ul_rx)

    AP_mac = handle.ap;
    sta = handle.stas;
    sta_num = numel(sta);
    
    % 初始化输出
    sta_ul_delay = zeros(1, sta_num);
    sta_dl_delay = zeros(1, sta_num);
    sta_dl_pkt_count = zeros(1, sta_num);   % 新增：下行精确包数
    sta_ul_pkt_count = zeros(1, sta_num);   % 新增：上行精确包数

    min_samples = 10;
    slot_time_ms = 0.05;

    % ==================== 下行发送时延（AP -> STA）====================
    for k = 1:numel(AP_mac.stas_info)
        sta_id = AP_mac.stas_info(k).sta_id;
        if sta_id < 1 || sta_id > sta_num, continue; end

        total_dl_tx_delay = 0;
        total_dl_tx_packets = 0;

        for tid = 1:8
            tx_bagnum = AP_mac.stas_info(k).dl_tx_info(tid).tot_tx_bagnum;
            tx_delay = AP_mac.stas_info(k).dl_tx_info(tid).tot_tx_delay;

            if tx_bagnum >= min_samples
                avg_delay = tx_delay / tx_bagnum;
                total_dl_tx_delay = total_dl_tx_delay + avg_delay;
                total_dl_tx_packets = total_dl_tx_packets + tx_bagnum;

                % 重置
                AP_mac.stas_info(k).dl_tx_info(tid).tot_tx_delay = 0;
                AP_mac.stas_info(k).dl_tx_info(tid).tot_tx_bagnum = 0;
            end
        end

        if total_dl_tx_packets > 0
            sta_dl_delay(sta_id) = total_dl_tx_delay / total_dl_tx_packets;
            sta_dl_pkt_count(sta_id) = total_dl_tx_packets;   % 精确包数
            aver_dl_tx = [aver_dl_tx, sta_dl_delay(sta_id)];
        end
    end

    % ==================== 上行发送时延（STA -> AP）====================
    for k = 1:sta_num
        if sta{k}.offline_req == 2, continue; end

        total_ul_tx_delay = 0;
        total_ul_tx_packets = 0;

        for tid = 1:8
            tx_bagnum = sta{k}.ul_tx_bagnum(tid);
            tx_delay = sta{k}.ul_tx_delay(tid);

            if tx_bagnum >= min_samples
                avg_delay = tx_delay / tx_bagnum * slot_time_ms;
                total_ul_tx_delay = total_ul_tx_delay + avg_delay;
                total_ul_tx_packets = total_ul_tx_packets + tx_bagnum;

                sta{k}.ul_tx_delay(tid) = 0;
                sta{k}.ul_tx_bagnum(tid) = 0;
            end
        end

        if total_ul_tx_packets > 0
            sta_ul_delay(k) = total_ul_tx_delay / total_ul_tx_packets;
            sta_ul_pkt_count(k) = total_ul_tx_packets;
            aver_ul_tx = [aver_ul_tx, sta_ul_delay(k)];
        end
    end

    % ==================== 下行接收时延（STA侧）====================
    for k = 1:sta_num
        if sta{k}.offline_req == 2, continue; end

        total_dl_rx_delay = 0;
        total_dl_rx_packets = 0;

        for tid = 1:8
            rx_bagnum = sta{k}.dl_rx_bagnum(tid);
            rx_delay = sta{k}.dl_rx_delay(tid);

            if rx_bagnum >= min_samples
                avg_delay = rx_delay / rx_bagnum;
                total_dl_rx_delay = total_dl_rx_delay + avg_delay;
                total_dl_rx_packets = total_dl_rx_packets + rx_bagnum;

                sta{k}.dl_rx_delay(tid) = 0;
                sta{k}.dl_rx_bagnum(tid) = 0;
            end
        end

        if total_dl_rx_packets > 0
            aver_dl_rx = [aver_dl_rx, total_dl_rx_delay / total_dl_rx_packets];
        end
    end

    % ==================== 上行接收时延（AP侧）====================
    for k = 1:numel(AP_mac.stas_info)
        sta_id = AP_mac.stas_info(k).sta_id;
        if sta_id < 1 || sta_id > sta_num, continue; end

        total_ul_rx_delay = 0;
        total_ul_rx_packets = 0;

        for tid = 1:8
            rx_bagnum = AP_mac.stas_info(k).ul_rx_bagnum(tid);
            rx_delay = AP_mac.stas_info(k).ul_rx_delay(tid);

            if rx_bagnum >= min_samples
                avg_delay = rx_delay / rx_bagnum;
                total_ul_rx_delay = total_ul_rx_delay + avg_delay;
                total_ul_rx_packets = total_ul_rx_packets + rx_bagnum;

                AP_mac.stas_info(k).ul_rx_delay(tid) = 0;
                AP_mac.stas_info(k).ul_rx_bagnum(tid) = 0;
            end
        end

        if total_ul_rx_packets > 0
            aver_ul_rx = [aver_ul_rx, total_ul_rx_delay / total_ul_rx_packets];
        end
    end

    handle.ap = AP_mac;
    handle.stas = sta;
end
function handles = data_input(handles)
% On-Off + Poisson 下行流量生成器（完整安全版）
% 已修复初始化 bug + 结构体一致性问题

    persistent traffic_cfg;

    tot_size = 2^16;
    slot_idx = handles.slot_idx;
    APmac = handles.ap;
    sta = handles.stas;

    if mod(slot_idx, 20) == 1   % 每 1ms 生成一次流量
        % ==================== On-Off 参数安全初始化 ====================
        num_sta = numel(APmac.stas_info);  
        need_init = isempty(traffic_cfg) || ...
                    ~isfield(traffic_cfg, 'is_on') || ...
                    length(traffic_cfg.is_on) ~= num_sta;

        if need_init
            traffic_cfg = struct(...
                'DataRate_Mbps',  [120, 110, 100, 90], ...     % On 期峰值速率（高负载突发）
                'OnTime_sec',     [0.005, 0.005, 0.006, 0.007], ...  % 严格对标论文思路
                'OffTime_sec',    [0.010, 0.010, 0.009, 0.008], ...  % 理论使用率 ≈ 33%~47%
                'PacketSize',     [1500, 1500, 1500, 1500], ...      % 严格对标 Nunez 2025
                'is_on',          false(1, num_sta), ...
                'next_switch_tick', zeros(1, num_sta));

            % 随机决定每个 STA 初始是 On 还是 Off
            for i = 1:num_sta
                if rand < 0.5
                    traffic_cfg.is_on(i) = true;
                    traffic_cfg.next_switch_tick(i) = slot_idx + round(traffic_cfg.OnTime_sec(i) / 0.001);
                else
                    traffic_cfg.is_on(i) = false;
                    traffic_cfg.next_switch_tick(i) = slot_idx + round(traffic_cfg.OffTime_sec(i) / 0.001);
                end
            end
            fprintf('【Traffic】On-Off + Poisson 模型已启动\n');

        elseif length(traffic_cfg.is_on) ~= num_sta
            % STA 数量变化时重新初始化
            traffic_cfg = struct(...
                'DataRate_Mbps',  [100, 90, 80, 70], ...
                'OnTime_sec',     [0.04, 0.04, 0.045, 0.05], ...
                'OffTime_sec',    [0.06, 0.06, 0.055, 0.05], ...
                'PacketSize',     [1200, 1200, 1100, 1000], ...
                'is_on',          false(1, num_sta), ...
                'next_switch_tick', zeros(1, num_sta));

            for i = 1:num_sta
                if rand < 0.5
                    traffic_cfg.is_on(i) = true;
                    traffic_cfg.next_switch_tick(i) = slot_idx + round(traffic_cfg.OnTime_sec(i) / 0.001);
                else
                    traffic_cfg.is_on(i) = false;
                    traffic_cfg.next_switch_tick(i) = slot_idx + round(traffic_cfg.OffTime_sec(i) / 0.001);
                end
            end
            fprintf('【Traffic】STA 数量变化，重新初始化 On-Off 模型\n');
        end
        % =====================================================================

        % ==================== AP 下行 On-Off 流量生成 ====================
        for k = 1:num_sta
            if ~logical(APmac.stas_info(k).status)
                continue;
            end

            % 判断是否需要切换 On/Off 状态
            if slot_idx >= traffic_cfg.next_switch_tick(k)
                if traffic_cfg.is_on(k)
                    traffic_cfg.is_on(k) = false;
                    traffic_cfg.next_switch_tick(k) = slot_idx + round(traffic_cfg.OffTime_sec(k) / 0.001);
                else
                    traffic_cfg.is_on(k) = true;
                    traffic_cfg.next_switch_tick(k) = slot_idx + round(traffic_cfg.OnTime_sec(k) / 0.001);
                end
            end

            % 只在 On 期间产生包（泊松分布）
            if traffic_cfg.is_on(k)
                pkt_rate = traffic_cfg.DataRate_Mbps(k) * 1e6 / 8 / traffic_cfg.PacketSize(k);
                expected_pkts = pkt_rate * 0.001;
                bag_num = poissrnd(expected_pkts);

                for n = 1:bag_num
                    data = randi(2,1,traffic_cfg.PacketSize(k)*8) - 1;
                    data = uint8(comm.internal.utilities.bi2deRightMSB(double(reshape(data, 8, [])'), 2));

                    mac_cfg = QbandFrameConfig();
                    mac_cfg.FrameType = 'Data';
                    mac_cfg.Tid = 0;
                    mac_cfg.Uid = APmac.stas_info(k).sta_id;
                    mac_cfg.Seq = APmac.stas_info(k).seq(1);

                    APmac.stas_info(k).seq(1) = mod(APmac.stas_info(k).seq(1) + 1, tot_size);

                    tx_mpdu = QbandGenerateMPDU(data, mac_cfg);
                    time_stamp = APmac.slot_idx;

                    tx_info.frame = tx_mpdu;
                    tx_info.time_stamp = time_stamp;
                    APmac.stas_info(k).tx_queue(1).push(tx_info);

                    APmac.stas_info(k).dl_tx_info(1).pkt_bytes = ...
                        APmac.stas_info(k).dl_tx_info(1).pkt_bytes + size(tx_mpdu, 1);
                    APmac.stas_info(k).dl_tx_info(1).pkt_num = ...
                        APmac.stas_info(k).dl_tx_info(1).pkt_num + 1;
                end
            end

            % 必须更新：本 ms 新增字节数
            current_total_bytes = sum([APmac.stas_info(k).dl_tx_info.pkt_bytes]);
            new_bytes_this_ms = current_total_bytes - APmac.stas_info(k).prev_dl_bytes;
            APmac.stas_info(k).dl_byte_this_ms = new_bytes_this_ms;
            APmac.stas_info(k).prev_dl_bytes = current_total_bytes;
        end

        % ==================== STA 上行流量（暂时保留原模型） ====================
        for k = 1:numel(sta)
            if isempty(sta{k}) || ~logical(sta{k}.status)
                continue;
            end

            length_val = (sta{k}.tx_rate) * 5e-5 * 20;
            bag_num = max(1, round(length_val / 1000));

            for tid = 0:7
                for n = 1:bag_num
                    data = randi(2,1,1000) - 1;
                    data = uint8(comm.internal.utilities.bi2deRightMSB(double(reshape(data, 8, [])'), 2));

                    mac_cfg = QbandFrameConfig();
                    mac_cfg.FrameType = 'Data';
                    mac_cfg.Tid = tid;
                    mac_cfg.Uid = sta{k}.uid;
                    mac_cfg.Seq = sta{k}.seq(tid + 1);
                    sta{k}.seq(tid + 1) = mod(sta{k}.seq(tid + 1) + 1, tot_size);

                    tx_mpdu = QbandGenerateMPDU(data, mac_cfg);
                    UL_tx_info.frame = tx_mpdu;
                    UL_tx_info.time_stamp = sta{k}.slot_idx;

                    if sta{k}.qos_enabled
                        sta{k} = sta{k}.enqueue_edca_frame(tx_mpdu, tid, sta{k}.slot_idx);
                    else
                        sta{k}.tx_queue(tid + 1).push(UL_tx_info);
                    end
                    sta{k}.pkt_bytes(tid + 1) = sta{k}.pkt_bytes(tid + 1) + size(tx_mpdu, 1);
                end
            end
        end
    end

    handles.ap = APmac;
    handles.stas = sta;
end
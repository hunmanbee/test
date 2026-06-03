function handles = edca_contention_access(handles)
    % EDCA竞争接入处理
    sta = handles.stas;
    channel = handles.ul_channel;
    slot_idx = handles.slot_idx;
    % mcs_table = handles.mcs_table;
    
    channel_busy = false(length(channel), 1);

    for k = 1 : numel(sta)
        if  sta{k}.offline_req == 2
            continue;
        end
        
        % 更新信道状态
        current_channel_busy = channel_busy(sta{k}.ul_channel);
        sta{k} = sta{k}.update_channel_state(current_channel_busy, slot_idx);
        
        % 检查EDCA信道接入
        [access_granted, ac_index] = sta{k}.edca_channel_access(slot_idx);
        
        if access_granted
            [frame_info, ac_name] = sta{k}.dequeue_edca_frame(ac_index);
            
            if ~isempty(frame_info)

                % 记录发送时间用于重传超时检测
                if ~isfield(sta{k}.edca_state, 'last_tx_time')
                    sta{k}.edca_state.last_tx_time = struct();
                end
                sta{k}.edca_state.last_tx_time.(ac_name) = slot_idx;

                % 估算信道质量
                channel_quality = sta{k}.estimate_channel_quality();
                packet_size = size(frame_info.frame, 1);
                
                % 使用EDCA MCS选择
                mcs_val = sta{k}.get_mcs_for_edca(ac_index, 'channel_quality', channel_quality, 'packet_size', packet_size);
                
                % % 根据MCS获取发送成功率
                current_csr = handles.ul_csr(mcs_val);
                success = rand() < current_csr;

                if success
                    % 构造发送帧
                    packet = {};
                    packet{1} = frame_info.frame;
                    aggregate_frame = dec2hex(qbandGenerateAMPDU(packet), 2);
                    
                   
                    % 发送
                    A_mpdu_list = {};
                    MU_list = {};
                    A_mpdu_list{1} = aggregate_frame;
                    MU_list{1} = [mcs_val, sta{k}.uid];
                    [baled_frame,~] = qbandGenerateBaledFrame(A_mpdu_list, MU_list, 'DataFormat', 'Octets');
                    
                    channel{sta{k}.ul_channel}.phy_queue.push(baled_frame);
                    channel_busy(sta{k}.ul_channel) = true;
                    
                    % 更新统计信息
                    tid = frame_info.tid;
                    time_stamp = frame_info.time_stamp;
                    % sta{k}.ul_tx_delay(tid + 1) = sta{k}.ul_tx_delay(tid + 1) + (sta{k}.slot_idx - time_stamp) * 0.05;



                     %新增：计算退避等待时间
                    backoff_wait_slots = 0;
                    for ac_idx=1:4
                        ac_n = sta{k}.get_ac_name(ac_idx);
                        if sta{k}.edca_backoff.(ac_n).backoff_active
                            backoff_wait_slots = backoff_wait_slots + sta{k}.edca_backoff.(ac_n).backoff_counter;
                        end
                    end
                    
                    % 新增：计算传输时间
                    tx_time_ms = (packet_size * 8) / (handles.mcs_table.table_elem(mcs_val).data_rate * 1e6 * channel{sta{k}.ul_channel}.bandwith / 540) * 1000;
                    
                    % 综合时延：队列等待 + 退避等待 + 传输时间
                    sta{k}.ul_tx_delay(tid + 1) = sta{k}.ul_tx_delay(tid + 1) + (sta{k}.slot_idx - time_stamp) * 0.05 + backoff_wait_slots * 0.05 + tx_time_ms;
                    
                    sta{k}.ul_tx_bagnum(tid + 1) = sta{k}.ul_tx_bagnum(tid + 1) + 1;                    
                  
                    % 重置退避参数
                    sta{k} = sta{k}.reset_edca_backoff(ac_name);
                    
                    % 更新重传统计
                    sta{k} = sta{k}.update_retransmission_stats(ac_name, 'success');
                    
                    fprintf('STA %d EDCA %s 发送成功, MCS=%d\n', sta{k}.uid, ac_name, mcs_val);

                    % 放入备份队列
                    pkt_info.frame = frame_info.frame;
                    pkt_info.time_stamp = sta{k}.slot_idx;
                    sta{k}.backup_queue(tid + 1).push(pkt_info);
                else
                    sta{k} = sta{k}.handle_edca_retransmission(ac_name, frame_info);
                    fprintf('STA %d EDCA %s 发送失败，触发重传\n', sta{k}.uid, ac_name);
                end
            end
        else
            % 更新退避计数器
            for ac_idx = 1:4
                ac_name = sta{k}.get_ac_name(ac_idx);
                if ~sta{k}.edca_queues.(ac_name).isempty()
                    sta{k} = sta{k}.update_edca_backoff(ac_name);
                end
            end
        end
        
        handles.stas{k} = sta{k};
    end
end
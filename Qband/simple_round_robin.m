function allocated_slots = simple_round_robin(sta_data, valid_stas, available_slots, m, channel_width, mcs_table, ap_mac)
    allocated_slots = struct('uid', {}, 'start_slot', {}, 'slot_num', {});
    
    if isempty(valid_stas)
        return;
    end
    
    % 持久变量用于轮询记录
    persistent last_scheduled_idx
    if isempty(last_scheduled_idx)
        last_scheduled_idx = zeros(1, 4);  % 每个信道一个记录
    end
    
    % 从上次调度的下一个STA开始
    start_idx = mod(last_scheduled_idx(m), length(valid_stas)) + 1;
    
    % 简单轮询分配
    remaining_slots = available_slots;
    current_idx = start_idx;
    
    while remaining_slots > 0
        i = valid_stas(current_idx);
        
        if sta_data(i).total_bytes > 0
            % 计算这个STA需要的时隙数
            index = ap_mac.get_index(sta_data(i).uid);
            needed_slots = 0;
            
            if index > 0
                % 基于数据量和MCS计算所需时隙
                for tid = 0 : 7
                    speed = mcs_table.table_elem(ap_mac.stas_info(index).ul_mcs_info(tid + 1)).data_rate * 1e6 * channel_width / 540 / 8 * 5e-5;
                    needed_slots = needed_slots + ceil(ap_mac.stas_info(index).buffer_len(tid + 1) / speed);
                end
            else
                % 如果找不到索引，使用简单估计
                needed_slots = ceil(sta_data(i).total_bytes / 1000);  % 简单估计
            end
            
            % 确保不超过剩余时隙
            alloc_slots = min(needed_slots, remaining_slots);
            
            if alloc_slots > 0
                % 创建分配记录
                schedule.uid = sta_data(i).uid;
                schedule.start_slot = 0;  % 将在主函数中设置
                schedule.slot_num = alloc_slots;
                
                allocated_slots(end+1) = schedule;
                remaining_slots = remaining_slots - alloc_slots;
                
                fprintf('轮询分配: STA%d -> %d时隙 (需要%d)\n', sta_data(i).uid, alloc_slots, needed_slots);
            end
        end
        
        % 移动到下一个STA
        current_idx = mod(current_idx, length(valid_stas)) + 1;
        
        % 如果已经遍历了一圈，且没有可分配时隙，退出
        if current_idx == start_idx && remaining_slots == available_slots
            break;
        end
    end
    
    % 更新轮询索引
    if ~isempty(allocated_slots)
        last_scheduled_idx(m) = current_idx;
    end
end
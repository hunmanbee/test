function [start_slot, available_slots] = calculate_available_slots(ap_mac, m)
    % 基本参数
    total_slots = 20;  % 每毫秒总时隙数
    
    % 计算轮询时隙
    slot_idx = mod(ceil(mod(ap_mac.slot_idx, 200) / 20), 10);
    polling_slots = 4;
    
    if ~isempty(ap_mac.polling_result{m})
        for i = 1:4
            if ap_mac.polling_result{m}(i + 4 * slot_idx) == 256
                polling_slots = i - 1;
                break;
            end
        end
    end
    
    % 计算预留时隙
    reserved_slots = 0;
    temp_ms = mod(mod(ceil(ap_mac.slot_idx / 20) - 1, 10) + 2, 10);
    
    for i = 1:numel(ap_mac.ul_channel_info{m})
        sta_id = ap_mac.ul_channel_info{m}(i);
        sta_idx = ap_mac.get_index(sta_id);
        
        if sta_idx > 0
            if ap_mac.stas_info(sta_idx).control_flags == 2
                if mod(temp_ms - ap_mac.stas_info(sta_idx).ul_resv_info.Time_Index, ...
                      ap_mac.stas_info(sta_idx).ul_resv_info.Interval) == 0
                    reserved_slots = reserved_slots + ap_mac.stas_info(sta_idx).ul_resv_info.Slot_Num;
                end
            end
        end
    end
    
    % 控制时隙预留
    control_slots = 2;
    
    % 计算可用时隙
    start_slot = 1 + polling_slots;  % 从轮询时隙后开始
    available_slots = total_slots - polling_slots - reserved_slots - control_slots;
    
    fprintf('时隙分配: 总%d, 轮询%d, 预留%d, 控制%d, 可用%d\n', total_slots, polling_slots, reserved_slots, control_slots, available_slots);
end
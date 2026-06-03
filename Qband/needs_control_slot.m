function need = needs_control_slot(sta_info, slot_idx)
    % 检查STA是否需要控制时隙
    need = false;
    
    % 条件1: 有下行数据要发送
    temp_ms = mod(mod(ceil(slot_idx / 20) - 1, 10) + 2, 10);
    if sta_info.dl_send_state(temp_ms + 1) == 1
        need = true;
        sta_info.dl_send_state(temp_ms + 1) = 0;  % 重置标志
        return;
    end
    
    % 条件2: 有下行预留请求
    if sta_info.dl_resv_info.Slot_Num ~= 0
        need = true;
        return;
    end
end
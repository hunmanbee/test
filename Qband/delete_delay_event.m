function obj = delete_delay_event(obj, aid, mac_addr, fun_code)
    event_num = size(obj, 2);
    old_idx = [];
    for event_idx = 1 : event_num
        if (obj(event_idx).aid == aid || strcmp(obj(event_idx).mac_addr, mac_addr)) && obj(event_idx).fun_code == fun_code
            old_idx = [old_idx, event_idx];
        end
    end
    obj(old_idx) = [];
end
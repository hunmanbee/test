function obj = add_delay_event(obj, aid, mac_addr, end_tick, fun_code, varargin)
    new_obj.aid = aid;
    new_obj.mac_addr = mac_addr;
    new_obj.end_tick = end_tick;
    new_obj.fun_code = fun_code;
    new_obj.input = varargin;
    obj = [obj, new_obj];
end

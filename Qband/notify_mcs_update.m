function [mcs_update_info,mcs_flag] = notify_mcs_update(mcs_update_info, tmp_tick)
%     load const_value;
    MAX_MCS_VALUE = 7;
    MCS_DECREASE_TIME_TICK = 60;
    MCS_DECREASE_PACKET_NUM_THRESHOLD = 200;
    PER_HIGH = 0.1000;
    PER_LOW = 0.0300;
    if mcs_update_info.time_lock > 0 && tmp_tick - mcs_update_info.time_lock > 1000
        mcs_update_info.time_lock = -1;
        mcs_update_info.restricted_mcs = MAX_MCS_VALUE + 1;  %解锁
    end
    ploss = mcs_update_info.failed_num / mcs_update_info.count;
    if((tmp_tick - mcs_update_info.start_time_tick > MCS_DECREASE_TIME_TICK) && ...,
        mcs_update_info.count > MCS_DECREASE_PACKET_NUM_THRESHOLD && ...,
        ploss > PER_HIGH)
            if(mcs_update_info.mcs_val > 1)
                if ploss > 0.15  %该阈值可调整
                    mcs_update_info.restricted_mcs = mcs_update_info.mcs_val;
                    mcs_update_info.time_lock = tmp_tick + 1000; %time_lock的时间可调整
                end
                mcs_update_info.mcs_val = mcs_update_info.mcs_val - 1;
            end
            mcs_update_info.failed_num = 0;
            mcs_update_info.count = 0;
            mcs_update_info.start_time_tick = tmp_tick;
            return;
    end
    if(tmp_tick - mcs_update_info.start_time_tick > MCS_DECREASE_TIME_TICK)
%         if(ploss > PER_HIGH && mcs_update_info.mcs_val > 1)
%             mcs_update_info.mcs_val = mcs_update_info.mcs_val - 1;
        if(ploss < PER_LOW && mcs_update_info.mcs_val < MAX_MCS_VALUE && mcs_update_info.mcs_val + 1 < mcs_update_info.restricted_mcs)
            mcs_update_info.mcs_val = mcs_update_info.mcs_val + 1;
        end
        mcs_update_info.failed_num = 0;
        mcs_update_info.count = 0;
        mcs_update_info.start_time_tick = tmp_tick;
        return;
    end
end


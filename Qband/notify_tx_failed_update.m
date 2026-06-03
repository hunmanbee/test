function mcs_update_info = notify_tx_failed_update(mcs_update_info)
    mcs_update_info.count = mcs_update_info.count + 1;
    mcs_update_info.failed_num = mcs_update_info.failed_num + 1;
end
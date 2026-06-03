function sta = access_timeout_process(sta)
    %backoff_info的loop轮次增加
    sta.backoff_info.loop = sta.backoff_info.loop + 1;
    %重新开始退避
    sta.backoff_info.val = round(rand(1) * 20 * power(2, sta.backoff_info.loop - 1)) + 1;
end
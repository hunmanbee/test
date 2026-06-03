function [sent, received, failed, success_rate] = improved_precon_statistics(handle, sent, received, failed, fid)
% improved_precon_statistics  - PreCon 帧真实统计（仿 improved_delay_statistics.m）
% 自动清零计数器，支持日志记录

persistent precon_stats;  % 持久化统计

if isempty(precon_stats)
    precon_stats = struct('sent',0, 'received',0, 'failed',0);
end

% 更新全局计数
precon_stats.sent = precon_stats.sent + sent;
precon_stats.received = precon_stats.received + received;
precon_stats.failed = precon_stats.failed + failed;

sent = precon_stats.sent;
received = precon_stats.received;
failed = precon_stats.failed;

if sent > 0
    success_rate = received / sent;
else
    success_rate = 0;
end

% 写入日志
fprintf(fid, 'PreCon统计 [%d] sent=%d received=%d failed=%d success=%.2f%%\n', ...
    handle.slot_idx, sent, received, failed, success_rate*100);

% 清零本周期计数（供下次调用）
sent = 0; received = 0; failed = 0;

% 可选：存入 handle 供绘图使用
handle.precon_stats = precon_stats;  % 如果 ap_mac 有对应属性可扩展

end
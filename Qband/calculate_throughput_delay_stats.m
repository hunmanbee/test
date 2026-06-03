function [throughput_stats, delay_stats] = calculate_throughput_delay_stats(stas_dl_throughput, stas_ul_delay, stas_dl_delay, time, time_dl)
    % 计算吞吐量统计
    throughput_stats = struct();
    throughput_stats.avg_throughputs = zeros(1, length(stas_dl_throughput));
    throughput_stats.max_throughputs = zeros(1, length(stas_dl_throughput));
    throughput_stats.min_throughputs = zeros(1, length(stas_dl_throughput));
    
    for i = 1:length(stas_dl_throughput)
        if ~isempty(stas_dl_throughput{i})
            throughput_gbps = stas_dl_throughput{i} / 1e9;
            throughput_stats.avg_throughputs(i) = mean(throughput_gbps);
            throughput_stats.max_throughputs(i) = max(throughput_gbps);
            throughput_stats.min_throughputs(i) = min(throughput_gbps);
        end
    end
    
    % 计算时延统计
    delay_stats = struct();
    delay_stats.avg_ul_delays = zeros(1, length(stas_ul_delay));
    delay_stats.avg_dl_delays = zeros(1, length(stas_dl_delay));
    delay_stats.max_ul_delays = zeros(1, length(stas_ul_delay));
    delay_stats.max_dl_delays = zeros(1, length(stas_dl_delay));
    
    for i = 1:length(stas_ul_delay)
        if ~isempty(stas_ul_delay{i})
            delay_stats.avg_ul_delays(i) = mean(stas_ul_delay{i});
            delay_stats.max_ul_delays(i) = max(stas_ul_delay{i});
        end
    end
    
    for i = 1:length(stas_dl_delay)
        if ~isempty(stas_dl_delay{i})
            delay_stats.avg_dl_delays(i) = mean(stas_dl_delay{i});
            delay_stats.max_dl_delays(i) = max(stas_dl_delay{i});
        end
    end
end
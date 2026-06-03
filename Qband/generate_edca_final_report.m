function generate_edca_final_report(overall_stats, handle, stas_dl_throughput, stas_ul_delay, stas_dl_delay, time, time_dl)
    ac_names = {'AC_VO', 'AC_VI', 'AC_BE', 'AC_BK'};
    ac_colors = {[1 0.2 0.2], [0.2 0.8 0.2], [0.2 0.4 1], [0.5 0.5 0.5]};
    ac_labels = {'Voice', 'Video', 'Best Effort', 'Background'};
    
    final_stats = struct();
    for i = 1:length(ac_names)
        ac_name = ac_names{i};
        if ~isempty(overall_stats.avg_retry_rates.(ac_name))
            retry_data = overall_stats.avg_retry_rates.(ac_name);
            final_stats.(ac_name).avg_retry_rate = mean(retry_data);
            final_stats.(ac_name).max_retry_rate = max(retry_data);
            final_stats.(ac_name).min_retry_rate = min(retry_data);
            final_stats.(ac_name).std_retry_rate = std(retry_data);
            final_stats.(ac_name).jitter = std(diff(retry_data)); % 抖动
        else
            final_stats.(ac_name).avg_retry_rate = 0;
            final_stats.(ac_name).max_retry_rate = 0;
            final_stats.(ac_name).min_retry_rate = 0;
            final_stats.(ac_name).std_retry_rate = 0;
            final_stats.(ac_name).jitter = 0;
        end
    end
    % 计算吞吐量和时延统计
    [throughput_stats, delay_stats] = calculate_throughput_delay_stats(stas_dl_throughput, stas_ul_delay, stas_dl_delay, time, time_dl);
    
    % 1. 各AC重传率对比
    fig1 = figure('Name', '各AC类别平均内部碰撞率', 'Position', [100, 100, 800, 600], 'Color', 'white');
    retry_rates = [final_stats.AC_VO.avg_retry_rate, final_stats.AC_VI.avg_retry_rate, final_stats.AC_BE.avg_retry_rate, final_stats.AC_BK.avg_retry_rate];

    h_bar = bar(retry_rates * 100, 'FaceColor', 'flat');  
    for i = 1:4
        h_bar.CData(i,:) = ac_colors{i};
    end 
    
    for i = 1:length(retry_rates)
        text(i, retry_rates(i)*100 + 0.5, sprintf('%.2f%%', retry_rates(i)*100), 'HorizontalAlignment', 'center', 'FontWeight', 'bold', 'FontSize', 12);
    end
        
    set(gca, 'XTickLabel', ac_labels, 'FontSize', 11);
    title('各AC类别平均内部碰撞率', 'FontSize', 14, 'FontWeight', 'bold');
    ylabel('碰撞率 (%)', 'FontSize', 12);
    ylim([0, max(retry_rates)*100 + 8]);
    grid on;

    saveas(fig1, '1_AC_碰撞率对比.png');
    saveas(fig1, '1_AC_碰撞率对比.svg');
    
    % 2. 重传率时间序列
    fig2 = figure('Name', '各AC类别碰撞率时间序列', 'Position', [100, 100, 800, 600], 'Color', 'white');
    hold on;
    for i = 1:length(ac_names)
        if ~isempty(overall_stats.avg_retry_rates.(ac_names{i}))
            time_points = overall_stats.time_points / 1000;
            plot(time_points, overall_stats.avg_retry_rates.(ac_names{i}) * 100, 'Color', ac_colors{i}, 'LineWidth', 2, 'DisplayName', ac_labels{i});
        end
    end
    xlabel('时间 (秒)', 'FontSize', 12);
    ylabel('碰撞率 (%)', 'FontSize', 12);
    title('各AC类别碰撞率时间序列', 'FontSize', 14, 'FontWeight', 'bold');
    legend('show', 'Location', 'best', 'FontSize', 10);
    grid on;
    
    saveas(fig2, '2_AC_碰撞率时间序列.png');
    saveas(fig2, '2_AC_碰撞率时间序列.svg');
    
    % 3. 下行吞吐量分析
    fig3 = figure('Name', '各STA下行吞吐量变化', 'Position', [100, 100, 1500, 1300], 'Color', 'white');
    hold on;
    sta_colors = lines(length(stas_dl_throughput));
    for i = 1:length(stas_dl_throughput)
        if ~isempty(stas_dl_throughput{i})
            throughput_gbps = stas_dl_throughput{i} / 1e9;
            plot(1:length(throughput_gbps), throughput_gbps, 'Color', sta_colors(i,:), 'LineWidth', 1.5, 'DisplayName', sprintf('STA%d', i));
        end
    end
    xlabel('采样点', 'FontSize', 12);
    ylabel('吞吐量 (Gbps)', 'FontSize', 12);
    title('各STA下行吞吐量变化', 'FontSize', 14, 'FontWeight', 'bold');
    legend('show', 'Location', 'best', 'FontSize', 10);
    grid on;
    
    saveas(fig3, '3_各STA下行吞吐量变化.png');
    saveas(fig3, '3_各STA下行吞吐量变化.svg');
    
    % 4. 平均吞吐量对比
    fig4 = figure('Name', '各STA平均下行吞吐量', 'Position', [100, 100, 800, 600], 'Color', 'white');
    avg_throughputs = throughput_stats.avg_throughputs;
    sta_indices = 1:length(avg_throughputs);
    
    bar(sta_indices, avg_throughputs, 'FaceColor', [0.3 0.6 0.9]);
    for i = 1:length(avg_throughputs)
        text(i, avg_throughputs(i) + 0.05, sprintf('%.2f', avg_throughputs(i)), 'HorizontalAlignment', 'center', 'FontSize', 10);
    end
    
    set(gca, 'XTick', sta_indices);
    xlabel('STA索引', 'FontSize', 12);
    ylabel('平均吞吐量 (Gbps)', 'FontSize', 12);
    title('各STA平均下行吞吐量', 'FontSize', 14, 'FontWeight', 'bold');
    grid on;
    
    saveas(fig4, '4_各STA平均下行吞吐量.png');
    saveas(fig4, '4_各STA平均下行吞吐量.svg');
    
    % 5. 上行时延分析
    fig5 = figure('Name', '各STA上行时延变化', 'Position', [100, 100, 800, 600], 'Color', 'white');
    hold on;
    for i = 1:length(stas_ul_delay)
        if ~isempty(stas_ul_delay{i}) && ~isempty(time{i})
            plot(time{i}, stas_ul_delay{i}, 'Color', sta_colors(i,:), 'LineWidth', 1.5, 'DisplayName', sprintf('STA%d', i));
        end
    end
    xlabel('时间 (秒)', 'FontSize', 12);
    ylabel('上行时延 (ms)', 'FontSize', 12);
    title('各STA上行时延变化', 'FontSize', 14, 'FontWeight', 'bold');
    legend('show', 'Location', 'best', 'FontSize', 10);
    grid on;
    
    % 设置合适的Y轴范围
    non_empty_ul = find(~cellfun(@isempty, stas_ul_delay));
    if ~isempty(non_empty_ul)
        % 只对非空数据计算最大值
        ul_delay_max_vals = cellfun(@(x) max(x), stas_ul_delay(non_empty_ul), 'UniformOutput', false);
        % 过滤掉任何可能为空的结果
        ul_delay_max_vals = ul_delay_max_vals(~cellfun(@isempty, ul_delay_max_vals));
        if ~isempty(ul_delay_max_vals)
            ul_delay_max = max(cell2mat(ul_delay_max_vals));
        else
            ul_delay_max = 10; % 默认值
        end
    else
        ul_delay_max = 10; % 默认值
    end

    ylim([0, ul_delay_max * 1.1]);
    
    saveas(fig5, '5_各STA上行时延变化.png');
    saveas(fig5, '5_各STA上行时延变化.svg');
    
    % 6. 下行时延分析
    fig6 = figure('Name', '各STA下行时延变化', 'Position', [100, 100, 800, 600], 'Color', 'white');
    hold on;
    for i = 1:length(stas_dl_delay)
        if ~isempty(stas_dl_delay{i}) && ~isempty(time_dl{i})
            plot(time_dl{i}, stas_dl_delay{i}, 'Color', sta_colors(i,:), 'LineWidth', 1.5, 'DisplayName', sprintf('STA%d', i));
        end
    end
    xlabel('时间 (秒)', 'FontSize', 12);
    ylabel('下行时延 (ms)', 'FontSize', 12);
    title('各STA下行时延变化', 'FontSize', 14, 'FontWeight', 'bold');
    legend('show', 'Location', 'best', 'FontSize', 10);
    grid on;
    
    % 设置合适的Y轴范围
    non_empty_dl = find(~cellfun(@isempty, stas_dl_delay));
    if ~isempty(non_empty_dl)
        % 只对非空数据计算最大值
        dl_delay_max_vals = cellfun(@(x) max(x), stas_dl_delay(non_empty_dl), 'UniformOutput', false);
        % 过滤掉任何可能为空的结果
        dl_delay_max_vals = dl_delay_max_vals(~cellfun(@isempty, dl_delay_max_vals));
        if ~isempty(dl_delay_max_vals)
            dl_delay_max = max(cell2mat(dl_delay_max_vals));
        else
            dl_delay_max = 10; % 默认值
        end
    else
        dl_delay_max = 10; % 默认值
    end    
   
    ylim([0, dl_delay_max * 1.1]);
    
    saveas(fig6, '6_各STA下行时延变化.png');
    saveas(fig6, '6_各STA下行时延变化.svg');
    
    % 7. 平均时延对比
    fig7 = figure('Name', '各STA平均上下行时延对比', 'Position', [100, 100, 800, 600], 'Color', 'white');
    ul_delays = delay_stats.avg_ul_delays;
    dl_delays = delay_stats.avg_dl_delays;
    sta_indices = 1:length(ul_delays);
    
    bar_data = [ul_delays; dl_delays]';
    h = bar(sta_indices, bar_data, 'grouped');
    h(1).FaceColor = [0.9 0.4 0.4];
    h(2).FaceColor = [0.4 0.4 0.9];
    
    xlabel('STA索引', 'FontSize', 12);
    ylabel('平均时延 (ms)', 'FontSize', 12);
    title('各STA平均上下行时延对比', 'FontSize', 14, 'FontWeight', 'bold');
    legend('上行时延', '下行时延', 'Location', 'best', 'FontSize', 11);
    grid on;
    
    saveas(fig7, '7_各STA平均上下行时延对比.png');
    saveas(fig7, '7_各STA平均上下行时延对比.svg'); 
end

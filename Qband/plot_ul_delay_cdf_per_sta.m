function plot_ul_delay_cdf_per_sta(stas_ul_delay)
    % 绘制各STA独立的上行时延CDF图
    % 输入：
    %   stas_ul_delay: 各STA上行时延数据（cell数组）
    
    % 创建图形窗口
    figure('Position', [100, 100, 1200, 800], 'Name', '上行时延CDF - 各STA独立', 'Color', 'white', 'NumberTitle', 'off');
    
    % ============ 辅助函数定义 ============
    
    % CDF计算函数
    function [cdf_vals, x_vals] = calculate_cdf(data)
        if isempty(data)
            cdf_vals = [];
            x_vals = [];
            return;
        end
        
        sorted_data = sort(data(:));
        n = length(sorted_data);
        cdf_vals = (1:n)' / n;
        x_vals = sorted_data;
        
        if x_vals(1) > 0
            x_vals = [0; x_vals];
            cdf_vals = [0; cdf_vals];
        end
        
        if cdf_vals(end) < 1
            x_vals = [x_vals; x_vals(end)];
            cdf_vals = [cdf_vals; 1];
        end
    end
    
    % 收集所有STA的时延数据
    function all_delays = collect_all_delays(delay_cell)
        all_delays = [];
        for k = 1:length(delay_cell)
            if ~isempty(delay_cell{k})
                valid_delays = delay_cell{k}(delay_cell{k} > 0);
                all_delays = [all_delays; valid_delays(:)];
            end
        end
    end
    
    % ============ 主绘图逻辑 ============
    
    % 获取STA数量
    num_stas = length(stas_ul_delay);
    
    % 确定子图布局
    if num_stas <= 4
        rows = 2;
        cols = 2;
    elseif num_stas <= 6
        rows = 2;
        cols = 3;
    elseif num_stas <= 9
        rows = 3;
        cols = 3;
    else
        rows = ceil(sqrt(num_stas));
        cols = ceil(num_stas / rows);
    end
    
    % 创建颜色映射
    colors = lines(num_stas);
    
    % 初始化统计数据存储
    sta_stats = struct();
    
    % 绘制每个STA的CDF
    for sta_idx = 1:num_stas
        subplot(rows, cols, sta_idx);
        
        if ~isempty(stas_ul_delay{sta_idx})
            % 获取时延数据
            delays = stas_ul_delay{sta_idx}(stas_ul_delay{sta_idx} > 0);
            
            if ~isempty(delays)
                % 计算CDF
                [cdf_vals, delay_vals] = calculate_cdf(delays);
                
                % 绘制CDF曲线
                plot(delay_vals, cdf_vals, '-', 'LineWidth', 2, 'Color', colors(sta_idx, :));
                hold on;
                
                % 标记关键百分位点
                percentiles = [50, 95];
                for p = percentiles
                    target_cdf = p/100;
                    idx = find(cdf_vals >= target_cdf, 1);
                    if ~isempty(idx)
                        plot(delay_vals(idx), cdf_vals(idx), 'o', 'MarkerSize', 6, 'MarkerFaceColor', 'r');
                    end
                end
                
                % 计算统计信息
                mean_delay = mean(delays);
                median_delay = median(delays);
                p95_delay = prctile(delays, 95);
                
                % 保存统计信息
                sta_stats(sta_idx).mean = mean_delay;
                sta_stats(sta_idx).median = median_delay;
                sta_stats(sta_idx).p95 = p95_delay;
                sta_stats(sta_idx).samples = length(delays);
                
                % 添加统计信息文本
                text_str = {
                    sprintf('样本数: %d', length(delays)),
                    sprintf('均值: %.2f ms', mean_delay),
                    sprintf('中值: %.2f ms', median_delay),
                    sprintf('P95: %.2f ms', p95_delay)
                };
                
                text(0.02, 0.98, text_str, 'Units', 'normalized', 'VerticalAlignment', 'top', 'FontSize', 8, 'BackgroundColor', [1, 1, 1, 0.8]);
                
                % 设置子图属性
                xlabel('时延 (ms)', 'FontSize', 9);
                ylabel('累积概率', 'FontSize', 9);
                title(sprintf('STA %d', sta_idx), 'FontSize', 11, 'FontWeight', 'bold');
                grid on;
                box on;
                
                % 设置坐标轴范围
                xlim([0, max(delay_vals) * 1.1]);
                ylim([0, 1.05]);
                
                hold off;
            else
                % 无数据时显示提示
                text(0.5, 0.5, '无时延数据', 'HorizontalAlignment', 'center');
                title(sprintf('STA %d', sta_idx), 'FontSize', 11, 'FontWeight', 'bold');
            end
        else
            % 空数据时显示提示
            text(0.5, 0.5, '无数据', 'HorizontalAlignment', 'center');
            title(sprintf('STA %d', sta_idx), 'FontSize', 11, 'FontWeight', 'bold');
        end
    end
    
    % 添加总标题
    sgtitle('各STA独立上行时延CDF分布', 'FontSize', 14, 'FontWeight', 'bold');
    
    % 保存图形
    try
        saveas(gcf, 'ul_delay_cdf_per_sta.png');
        fprintf('图表已保存: ul_delay_cdf_per_sta.png\n');
    catch
        warning('无法保存图表文件');
    end
end
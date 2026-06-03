function plot_dl_delay_cdf_all_stas(stas_dl_delay)
    % 绘制所有STA合并的下行时延CDF图

    
    % 创建图形窗口
    figure('Position', [100, 100, 900, 700], 'Name', '下行时延CDF - 所有STA平均', 'Color', 'white', 'NumberTitle', 'off');
    
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
    
    % 百分位标记函数
    function mark_percentiles(x_vals, cdf_vals)
        hold on;
        
        percentiles = [50, 90, 95, 99];
        colors = {'r', 'g', 'b', 'm'};
        markers = {'o', 's', 'd', '^'};
        
        for i = 1:length(percentiles)
            p = percentiles(i);
            target_cdf = p/100;
            idx = find(cdf_vals >= target_cdf, 1);
            
            if ~isempty(idx)
                x_p = x_vals(idx);
                y_p = cdf_vals(idx);
                
                plot(x_p, y_p, markers{i}, 'Color', colors{i}, 'MarkerFaceColor', colors{i}, 'MarkerSize', 10, 'DisplayName', sprintf('P%d (%.3f ms)', p, x_p));
                
                % plot([x_p, x_p], [0, y_p], '--', 'Color', colors{i}, 'LineWidth', 1.5);
                % plot([0, x_p], [y_p, y_p], '--', 'Color', colors{i}, 'LineWidth', 1.5);
            end
        end
        hold off;
    end
    
    % 收集所有时延数据
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
    
    % 收集所有STA的下行时延数据
    all_dl_delays = collect_all_delays(stas_dl_delay);
    
    if isempty(all_dl_delays)
        text(0.5, 0.5, '无下行时延数据', 'HorizontalAlignment', 'center', 'FontSize', 14, 'FontWeight', 'bold');
        title('下行时延CDF (所有STA)', 'FontSize', 16, 'FontWeight', 'bold');
        return;
    end
    
    % 计算CDF
    [cdf_vals, delay_vals] = calculate_cdf(all_dl_delays);
    
    % 绘制CDF曲线（使用红色）
    plot(delay_vals, cdf_vals, 'r-', 'LineWidth', 3, 'DisplayName', '下行时延CDF');
    hold on;
    
    % 标记百分位点
    mark_percentiles(delay_vals, cdf_vals);
    
    
    %  根据数据范围确定文本位置
    x_max = max(delay_vals);
    
    % text(0.02, 0.98, text_str, 'Units', 'normalized', 'VerticalAlignment', 'top', 'FontSize', 10, 'BackgroundColor', [1, 1, 1, 0.8], 'EdgeColor', 'red', 'LineWidth', 1);
    
    % 设置图形属性
    xlabel('时延 (ms)', 'FontSize', 12, 'FontWeight', 'bold');
    ylabel('累积概率', 'FontSize', 12, 'FontWeight', 'bold');
    title('下行时延累积分布函数 ', 'FontSize', 14, 'FontWeight', 'bold');
    grid on;
    box on;
    
    % 设置坐标轴范围
    xlim([0, x_max * 1.1]);
    ylim([0, 1.05]);
    
    % 添加图例
    legend('Location', 'southeast', 'FontSize', 10, 'Box', 'off');
    
    % hold on;
    % percentiles = [50, 90, 95, 99];
    % colors = {'r', 'g', 'm', 'k'};

    % 保存图形
    try
        saveas(gcf, 'dl_delay_cdf_all_stas.png');
        fprintf('图表已保存: dl_delay_cdf_all_stas.png\n');
    catch
        warning('无法保存图表文件');
    end
    
    hold off;
end
function plot_all_cdf_figures(handles, stas_ul_delay, stas_dl_delay, overall_stats)
    % 主函数：调用所有CDF绘图函数
    % 输入：
    %   handles
    %   stas_ul_delay: 各STA上行时延数据
    %   stas_dl_delay: 各STA下行时延数据
    %   overall_stats: EDCA统计数据
    
    
    % 1. 上行时延CDF（所有STA合并）
    plot_ul_delay_cdf_all_stas(stas_ul_delay, overall_stats);
    
    % 2. 各STA独立的上行时延CDF
    plot_ul_delay_cdf_per_sta(stas_ul_delay);
    
    % 4. 下行时延CDF（所有STA合并）
    plot_dl_delay_cdf_all_stas(stas_dl_delay);
 
    fprintf('所有CDF分析图表生成完成！\n');
end
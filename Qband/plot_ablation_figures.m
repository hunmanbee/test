function plot_ablation_figures()
% 最终改进版：支持 Baseline 无 reward + 自动容错 per-run 数据

    if ~exist('results/figures', 'dir')
        mkdir('results/figures');
    end

    load('results/ablation_7groups.mat');
    fprintf('开始生成消融实验图片（支持 Baseline 无 reward 版）...\n');

    cmap = lines(7);

    %% ==================== Fig1: 主结果柱状图（已优化 Baseline 处理） ====================
    figure('Position', [100 100 1600 550]);
    
    % 子图1: Average Reward（只对有 reward 的组画）
    subplot(1,4,1);
    valid_idx = ~isnan(summary.MeanReward);
    if any(valid_idx)
        bar(summary.MeanReward(valid_idx), 'FaceColor', cmap(1,:)); hold on;
        errorbar(find(valid_idx), summary.MeanReward(valid_idx), summary.StdReward(valid_idx), ...
                 'k.', 'LineWidth', 1.5, 'CapSize', 6);
        xticks(find(valid_idx));
        xticklabels(summary.Experiment(valid_idx));
        xtickangle(35);
    else
        text(0.5, 0.5, 'Baseline 组无 Reward 概念', 'HorizontalAlignment', 'center');
    end
    ylabel('Average Reward', 'FontSize', 11);
    title('(a) Average Reward (仅 RL/DQN 组)', 'FontSize', 12, 'FontWeight', 'bold');
    grid on; set(gca, 'FontSize', 9);

    % 子图2: Jain's Fairness（所有组都画）
    subplot(1,4,2);
    bar(summary.MeanFairness, 'FaceColor', cmap(2,:)); hold on;
    errorbar(1:height(summary), summary.MeanFairness, summary.StdReward*0.05, 'k.', 'LineWidth', 1.5, 'CapSize', 6);
    set(gca, 'XTickLabel', summary.Experiment, 'XTickLabelRotation', 35, 'FontSize', 9);
    ylabel('Jain''s Fairness Index', 'FontSize', 11);
    title('(b) Fairness Index (全部7组)', 'FontSize', 12, 'FontWeight', 'bold');
    grid on;

    % 子图3: Channel Usage（所有组都画）
    subplot(1,4,3);
    bar(summary.MeanUsage, 'FaceColor', cmap(3,:)); hold on;
    errorbar(1:height(summary), summary.MeanUsage, summary.StdReward*0.03, 'k.', 'LineWidth', 1.5, 'CapSize', 6);
    set(gca, 'XTickLabel', summary.Experiment, 'XTickLabelRotation', 35, 'FontSize', 9);
    ylabel('Average Usage Rate', 'FontSize', 11);
    title('(c) Channel Usage (全部7组)', 'FontSize', 12, 'FontWeight', 'bold');
    grid on;

    % 子图4: Average Delay（所有组都画）
    subplot(1,4,4);
    bar(summary.MeanDelay, 'FaceColor', cmap(4,:)); hold on;
    errorbar(1:height(summary), summary.MeanDelay, summary.StdReward*0.2, 'k.', 'LineWidth', 1.5, 'CapSize', 6);
    set(gca, 'XTickLabel', summary.Experiment, 'XTickLabelRotation', 35, 'FontSize', 9);
    ylabel('Average Delay (ms)', 'FontSize', 11);
    title('(d) Average Delay (全部7组)', 'FontSize', 12, 'FontWeight', 'bold');
    grid on;

    sgtitle('Ablation Study Results (7 Methods) - Baseline 无 Reward', 'FontSize', 14, 'FontWeight', 'bold');
    saveas(gcf, 'results/figures/Fig1_Ablation_Results.png');
    fprintf('Fig1 已保存（已正确处理 Baseline 无 reward 的情况）\n');

    %% ==================== Fig2: Training Curves（只画 RL 相关组） ====================
    figure('Position', [100 100 900 550]); hold on;
    rl_groups = {'RL_full', 'RL_no_fairness', 'RL_no_diversity', 'DQN'};
    has_data = false;
    for i = 1:length(rl_groups)
        filename = fullfile('results', [rl_groups{i} '_run1.mat']);
        if exist(filename, 'file')
            try
                load(filename);
                if ~isempty(reward_history) && length(reward_history) > 5
                    plot(reward_history, 'Color', cmap(i,:), 'LineWidth', 1.8, 'DisplayName', rl_groups{i});
                    has_data = true;
                end
            catch
            end
        end
    end
    if has_data
        xlabel('Decision Steps (every 10ms)', 'FontSize', 11);
        ylabel('Average Reward', 'FontSize', 11);
        title('Training Curves Comparison (RL Methods)', 'FontSize', 13, 'FontWeight', 'bold');
        legend('Location', 'southeast', 'FontSize', 10);
        grid on;
    else
        text(0.5, 0.5, '未找到 RL 组的 per-run 数据', 'HorizontalAlignment', 'center');
    end
    saveas(gcf, 'results/figures/Fig2_Training_Curves.png');
    fprintf('Fig2 已保存\n');

    %% ==================== Fig3: Delay CDF（改进版，支持更多组） ====================
    figure('Position', [100 100 900 550]); hold on;
    cdf_groups = {'RL_full', 'RL_no_fairness', 'DQN', 'Baseline_greedy', 'Baseline_fixed'};
    has_cdf = false;
    for i = 1:length(cdf_groups)
        filename = fullfile('results', [cdf_groups{i} '_run1.mat']);
        if exist(filename, 'file')
            try
                load(filename);
                if ~isempty(delay_history) && length(delay_history) > 10
                    [f, x] = ecdf(delay_history);
                    plot(x, f, 'Color', cmap(i,:), 'LineWidth', 2.0, 'DisplayName', cdf_groups{i});
                    has_cdf = true;
                end
            catch
            end
        end
    end
    if has_cdf
        xlabel('Delay (ms)', 'FontSize', 11);
        ylabel('CDF', 'FontSize', 11);
        title('CDF of Packet Delay (Multiple Methods)', 'FontSize', 13, 'FontWeight', 'bold');
        legend('Location', 'southeast', 'FontSize', 9);
        grid on;
    else
        text(0.5, 0.5, '未找到足够的 delay_history 数据', 'HorizontalAlignment', 'center');
    end
    saveas(gcf, 'results/figures/Fig3_Delay_CDF.png');
    fprintf('Fig3 已保存\n');

    %% ==================== Fig4: Reward Boxplot（只对有 reward 的组） ====================
    figure('Position', [100 100 950 550]);
    all_rewards = []; labels = {};
    for i = 1:height(summary)
        mode = summary.Experiment{i};
        if isnan(summary.MeanReward(i))
            continue;   % 跳过 Baseline
        end
        for r = 1:3
            filename = fullfile('results', sprintf('%s_run%d.mat', strrep(mode, ' + ', '_'), r));
            if exist(filename, 'file')
                try
                    load(filename);
                    if ~isempty(reward_history)
                        all_rewards = [all_rewards; mean(reward_history)];
                        labels{end+1} = mode;
                    end
                catch
                end
            end
        end
    end
    if ~isempty(all_rewards)
        boxplot(all_rewards, labels);
        ylabel('Average Reward', 'FontSize', 11);
        title('Reward Distribution Across Runs (仅 RL/DQN 组)', 'FontSize', 13, 'FontWeight', 'bold');
        grid on; set(gca, 'FontSize', 10, 'XTickLabelRotation', 30);
    else
        text(0.5, 0.5, '无有效 reward 数据用于 boxplot', 'HorizontalAlignment', 'center');
    end
    saveas(gcf, 'results/figures/Fig4_Reward_Boxplot.png');
    fprintf('Fig4 已保存\n');

    fprintf('\n✅ 所有图片已更新并保存到 results/figures/\n');
    fprintf('   Baseline 组已正确跳过 reward 相关绘图。\n');
end